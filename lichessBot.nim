import
    lichessNetUtils,
    log,
    historyOfGameResults

import std/[
    strutils,
    strformat,
    json,
    tables,
    os,
    osproc,
    posix,
    options,
    times
]

let configJsonNode = readFile("config.json").parseJson

proc absolutePath(path: string): string =
        result = path
        if result.len > 0 and result[0] != '/':
            result = getCurrentDir() & "/" & result
let
    token = configJsonNode["lichessToken"].getStr
    historyOfGameResultsFileName = configJsonNode["historyOfGameResultsFileName"].getStr.absolutePath
    anarchyCommentsFileName = configJsonNode["anarchyCommentsFileName"].getStr.absolutePath
    hashSizeMegaByte = configJsonNode["hashSizeMegaByte"].getInt
    maxConcurrentGames = configJsonNode["concurrentGames"].getInt
    maxFrequencyBotGames = initDuration(minutes = configJsonNode["maxFrequencyBotGamesMinutes"].getInt)
    blockedPlayers = block:
        var blockedPlayers: seq[string]
        if "blockedPlayers" in configJsonNode:
            for blockedPlayerNode in configJsonNode["blockedPlayers"]:
                blockedPlayers.add blockedPlayerNode.getStr
        blockedPlayers

doAssert maxConcurrentGames in 1..50, "At least one and at most 50 concurrent games allowed"
doAssert historyOfGameResultsFileName.len > 0 and historyOfGameResultsFileName[0] == '/', "Should be an absolute path"
doAssert hashSizeMegaByte > 0, "Hash size should be at least 1 MB"

logInfo &"Arguments:\n{token = }\n{historyOfGameResultsFileName = }\n{anarchyCommentsFileName = }\n{hashSizeMegaByte = }\n{maxConcurrentGames = }\n{maxFrequencyBotGames.inMinutes = }"

historyOfGameResultsResetAllLockFiles historyOfGameResultsFileName

type LichessBotState = object
    gameProcesses: Table[string, Process]
    numReservedProcesses: int = 0
    lastBotGame: DateTime

proc tryReserveGameProcess(lbs: var LichessBotState): bool =
    if lbs.gameProcesses.len + lbs.numReservedProcesses < maxConcurrentGames:
        lbs.numReservedProcesses += 1
        return true
    false

proc garbageCollectGameProcesses(lbs: var LichessBotState, ignoreKilledGameId: string = "") =

    var finishedProcessGameIds: seq[string]
    for gameId, process in lbs.gameProcesses:
        let exitCode = process.peekExitCode
        if exitCode != -1:
            # process finished
            if exitCode == 0:
                logInfo "Process playing game ", gameId, " finished successfully"
            elif gameId == ignoreKilledGameId and exitCode - 128 == 9: # exit code -9 means programm got killed
                logWarn "Process playing game ", gameId, " got killed. Not trying to restart it."
            else:
                let msg = fmt"Process playing game {gameId} finished with potential error. Exit code: {exitCode} (minus 128: {exitCode - 128})"
                logError msg
                raise newException(CatchableError, msg)

            finishedProcessGameIds.add gameId

    for gameId in finishedProcessGameIds:
        doAssert gameId in lbs.gameProcesses
        lbs.gameProcesses[gameId].close
        lbs.gameProcesses.del gameId

proc handleGameStart(lbs: var LichessBotState, jsonNode: JsonNode) =
    doAssert jsonNode{"type"}.getStr == "gameStart", jsonNode.pretty
    
    let
        gameNode = jsonNode{"game"}
        gameId = gameNode{"gameId"}.getStr
        opponentName = gameNode{"opponent"}{"username"}.getStr

    let gameDir = "./game_directories/game_directory_" & gameId

    if dirExists gameDir:
        var backupGameDir = gameDir & "_backup"
        while dirExists backupGameDir:
            backupGameDir &= "_backup"
        logWarn "Game directory \"", gameDir, "\" already exists, backing it up to \"", backupGameDir, "\""
        moveDir gameDir, backupGameDir

    doAssert not dirExists gameDir
    createDir gameDir

    if gameId in lbs.gameProcesses:
        logError fmt"A single game should not be played by two processes at the same time (gameId: {gameId})"
        lbs.gameProcesses[gameId].kill
        sleep 1000
        lbs.garbageCollectGameProcesses(ignoreKilledGameId = gameId)

    doAssert gameId notin lbs.gameProcesses, "It shouldn't be there by anymore by now ..."

    lbs.gameProcesses[gameId] = startProcess(
        command = getCurrentDir() & "/playLichessGame",
        workingDir = gameDir,
        args = [
            $getpid(), # parend PID
            gameId, # lichess gameId
            token, # lichess token
            historyOfGameResultsFileName, # historyOfGameResultsFileName
            anarchyCommentsFileName, # anarchyCommentsFileName
            $hashSizeMegaByte, # hashSizeMegaByte
        ],
        options = {poParentStreams}
    )

    echoLog fmt"Launched process for game https://lichess.org/{gameId} against {opponentName}"
    echoLog "Games running: ", lbs.gameProcesses.len

    if lbs.numReservedProcesses >= 1:
        lbs.numReservedProcesses -= 1


    if lbs.gameProcesses.len + lbs.numReservedProcesses > maxConcurrentGames:
        logWarn fmt"Sum of running ({lbs.gameProcesses.len}) and reserved processes ({lbs.numReservedProcesses}) larger than maximum number of allowed games ({maxConcurrentGames})"


    


proc handleGameFinish(lbs: var LichessBotState, jsonNode: JsonNode) =
    doAssert jsonNode{"type"}.getStr == "gameFinish", jsonNode.pretty
    let gameId = jsonNode{"game"}{"id"}.getStr
    echoLog "Game officially finished: ", gameId
    var numActiveGames = lbs.gameProcesses.len
    if gameId in lbs.gameProcesses:
        numActiveGames -= 1
    echoLog "Games running: ", numActiveGames

proc handleChallenge(lbs: var LichessBotState, jsonNode: JsonNode) =
    doAssert jsonNode{"type"}.getStr == "challenge", jsonNode.pretty

    let
        challengeNode = jsonNode{"challenge"}
        challengeId = challengeNode{"id"}.getStr
        opponentId = challengeNode{"challenger"}{"id"}.getStr
        opponentName = challengeNode{"challenger"}{"name"}.getStr
        isBot = challengeNode{"challenger"}{"title"}.getStr == "BOT"

    template decline(reason: string) =
        discard jsonResponse(HttpPost, fmt"https://lichess.org/api/challenge/{challengeId}/decline", token, {"reason": reason}.toTable)
        logInfo fmt"Declined challenge {challengeId} by {opponentId} because of ", reason

    # decline challenge if needed
    if opponentName in blockedPlayers or opponentId in blockedPlayers:
        decline(reason = "noBot")
        logInfo fmt"Additional Info: Declined challenge {challengeId} because {opponentId} is in block list"
        return

    if isBot and lbs.lastBotGame + maxFrequencyBotGames >= now():
        decline(reason = "noBot")
        return

    if challengeNode{"timeControl"}{"increment"}.getInt <= 0:
        decline(reason = "timeControl")
        return

    if challengeNode{"variant"}{"key"}.getStr notin ["standard", "chess960"]:#, "fromPosition"]:
        decline(reason = "variant")
        return

    if challengeNode{"rated"}.getBool:
        decline(reason = "casual")
        return

    if challengeNode{"speed"}.getStr == "ultraBullet":
        decline(reason = "tooFast")
        return

    if challengeNode{"speed"}.getStr in ["correspondence", "classical"]:
        decline(reason = "tooSlow")
        return

    if not lbs.tryReserveGameProcess():
        decline(reason = "later")
        return

    # accept challenge
    discard jsonResponse(HttpPost, fmt"https://lichess.org/api/challenge/{challengeId}/accept", token)
    if isBot:
        lbs.lastBotGame = now()
    logInfo fmt"Accepted challenge {challengeId}"

proc handleChallengeCanceled(lbs: var LichessBotState, jsonNode: JsonNode) =
    doAssert jsonNode{"type"}.getStr == "challengeCanceled", jsonNode.pretty
    logInfo "Opponent cancelled challenge ", jsonNode{"challenge"}{"id"}.getStr

proc handleChallengeDeclined(lbs: var LichessBotState, jsonNode: JsonNode) =
    doAssert jsonNode{"type"}.getStr == "challengeDeclined", jsonNode.pretty
    logInfo "Challenge from ", jsonNode{"challenge"}{"challenger"}{"name"}.getStr, " got cancelled: ", jsonNode{"challenge"}{"id"}.getStr


proc listenToIncomingEvents(lbs: var LichessBotState) =
    for jsonNode in streamEvents("lichess.org", "/api/stream/event", token):

        if jsonNode.isNone:
            continue

        let jsonNode = jsonNode.get

        lbs.garbageCollectGameProcesses

        logInfo "Got event: ", jsonNode.pretty

        case jsonNode{"type"}.getStr:
        of "gameStart":
            lbs.handleGameStart jsonNode
        of "gameFinish":
            lbs.handleGameFinish jsonNode
        of "challenge":
            lbs.handleChallenge jsonNode
        of "challengeCanceled":
            lbs.handleChallengeCanceled jsonNode
        of "challengeDeclined":
            lbs.handleChallengeDeclined jsonNode
        else:
            logWarn "stream response doesn't contain expected type value: ", jsonNode.pretty
    
    logWarn "Event stream finished"

proc main() =
    var lbs: LichessBotState
    lbs.lastBotGame = dateTime(2000, mJan, 01, 00, 00, 00, 00, utc())
    while true:        
        try:
            let userName = jsonResponse(HttpGet, "https://lichess.org/api/account", token){"id"}.getStr
            echoLog "Playing as ", userName
            lbs.listenToIncomingEvents
            break
        except CatchableError:
            logError "Encountered exception while listening to events: ", getCurrentExceptionMsg(), "\n", getCurrentException().getStackTrace()
            let cooldownMilliseconds = 10_000
            logInfo "Trying again listening to event stream in ", cooldownMilliseconds, " ms"
            sleep cooldownMilliseconds

main()