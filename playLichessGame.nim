import std/[
    os,
    posix,
    strutils,
    json,
    strformat,
    options,
    times,
    random
]

import
    lichessNetUtils,
    log,
    lichessGame,
    anarchyParameters,
    historyOfGameResults,
    positionUtils,
    position,
    timeManagedSearch,
    types,
    hashTable,
    utils,
    move,
    anarchyConditions,
    anarchyComments,
    search,
    evaluation

randomize(epochTime().int64 mod 500_000)

doAssert commandLineParams().len == 6, "Need following arguments: <parent PID> <lichess gameId> <lichess token> <historyOfGameResultsFileName> <anarchyCommentsFileName> <hashSizeMegaByte>"

let
    parentPID = commandLineParams()[0].parseInt.Pid
    gameId = commandLineParams()[1]
    token = commandLineParams()[2]
    historyOfGameResultsFileName = commandLineParams()[3]
    anarchyCommentsFileName = commandLineParams()[4]
    hashSizeMegaByte = commandLineParams()[5].parseInt

loadAnarchyComments anarchyCommentsFileName

logInfo &"Arguments:\n{parentPID = }\n{gameId = }\n{token = }\n{historyOfGameResultsFileName = }\n{hashSizeMegaByte = }"


proc lastEnemyMoveWasKingCloudMove(gameState: LichessGameState, botColor: Color): bool =
    doAssert gameState.currentPosition.us == botColor, "Can only be called if next move is a bot move"
    if gameState.positionMoveHistory.len == 0:
        return false
    return gameState.positionMoveHistory[^1].position.isCloudKingMove(gameState.positionMoveHistory[^1].move)

func getCloudKingMove(position: Position): Move =

    for move in position.legalMoves:
        if position.isCloudKingMove(move):
            return move
    noMove

var sentGreetingMessage = false

const maxWaitTimeBeforeStarted = initDuration(seconds = 60)
let startTime = now()

proc abortGame(bgs: var BotGameState) =
    let query = fmt"https://lichess.org/api/bot/game/{gameId}/abort"
    discard bgs.requestsSession.jsonResponse(httpPost, query, token)
    logInfo "Aborted game"

proc main() =

    var bgs = BotGameState(
        requestsSession: getRequestsSession(),
        gameId: gameId,
        token: token
    )

    if sentGreetingMessage:
        bgs.sendMessage "Sorry, I had some stupid technical difficulties."
    
    let (botUserId, botUserName) = block:
        let b = bgs.requestsSession.jsonResponse(httpGet, "https://lichess.org/api/account", token)
        if b{"id"}.getStr == "":
            logError b.pretty
            quit QuitFailure
        (b{"id"}.getStr, b{"username"}.getStr)

    logInfo "Bot user ID: ", botUserId
    logInfo "Bot username: ", botUserName

    doAssert getCurrentDir().lastPathPart == "game_directory_" & gameId, "This executable must be run in a directory named \"game_directory_{gameId}\""
    doAssert historyOfGameResultsFileName.len > 0 and historyOfGameResultsFileName[0] == '/', "historyOfGameResultsFileName must be an absolute path"

    bgs.difficultyLevel = 1.DifficultyLevel
    let lichessGame = block:
        var
            lichessGame = none LichessGame
            difficultyLevelOpt = none DifficultyLevel

        for gameFullNode in streamEvents(fmt"https://lichess.org/api/bot/game/stream/{gameId}", token):

            if gameFullNode.isNone:
                continue

            let gameFullNode = gameFullNode.get

            if gameFullNode{"type"}.getStr != "gameFull":
                logWarn &"Didn't receive expected \"gameFull\" JSON type: {gameFullNode}"
                continue

            lichessGame = some newLichessGame(gameFullNode, botUserId)
            difficultyLevelOpt = some historyOfGameResultsFileName.getDifficultyLevel(lichessGame.get.opponentElo)
            break # only the first event (initial gamestate) is important

        if lichessGame.isNone or difficultyLevelOpt.isNone:
            let msg = fmt"Didn't manage to initialize lichessGame and/or difficultyLevel (maybe event stream ended before first json result?)"
            logError msg
            raise newException(IOError, msg)
        
        bgs.difficultyLevel = difficultyLevelOpt.get
        let lg = lichessGame.get
        lg # this is a hack, because weirdly when I return lichessGame.get it doesn't work out
        # lichessGame.get
    
    doAssert lichessGame.gameId == gameId
    doAssert bgs.gameId == gameId
    logInfo "Difficulty: ", bgs.difficultyLevel

    var
        hashTable = newHashTable()
        weOfferedDrawAlready = false
        weDeclinedDrawAlready = false
        consideredRageQuitting = false
        canChangeDifficulty = true
    hashTable.setSize(sizeInBytes = hashSizeMegaByte * megaByteToByte)

    for jsonNode in streamEvents(fmt"https://lichess.org/api/bot/game/stream/{gameId}", token):    
        if parentPID != getppid(): # parent process stopped
            logError "Parent process (", parentPID, ") doesn't exist anymore"
            quit QuitFailure

        if jsonNode.isNone:

            if bgs.lastLichessGameState.positionMoveHistory.len <= 1 and now() - startTime >= maxWaitTimeBeforeStarted:
                bgs.abortGame()

            continue

        let jsonNode = jsonNode.get

        logInfo "Received event: ", jsonNode.pretty

        let nodeType = jsonNode{"type"}.getStr
        
        let gameStateNode = if nodeType != "gameState":
            if nodeType == "chatLine":
                if jsonNode{"room"}.getStr == "spectator" and
                jsonNode{"username"}.getStr == "lichess":
                    if (jsonNode{"text"}.getStr == "White offers draw" and lichessGame.botColor == black) or
                    (jsonNode{"text"}.getStr == "Black offers draw" and lichessGame.botColor == white):
                        if (not weDeclinedDrawAlready) or rand(1.0) < 0.2:
                            sleep 300
                            discard bgs.sendComment enemyOffersDraw
                            weDeclinedDrawAlready = true

                if jsonNode{"room"}.getStr == "player" and jsonNode{"username"}.getStr != botUserName:

                    func normalize(s: string): string =
                        s.toLowerAscii.multiReplace(
                            (",", ""),
                            (".", ""),
                            ("!", ""),
                            ("?", ""),
                            ("-", ""),
                            ("_", ""),
                            ("\"", ""),
                            ("'", "")
                        )

                    let text = jsonNode{"text"}.getStr.normalize

                    if commandHigherDiffculty.normalize in text:
                        if not canChangeDifficulty:
                            bgs.sendMessage messageCanOnlyChangeDifficultyAtBeginOfGame
                        else:
                            if bgs.difficultyLevel == DifficultyLevel.high:
                                bgs.sendMessage messageAlreadyAtHighestDifficulty
                            else:
                                inc bgs.difficultyLevel
                                bgs.sendMessage messageNewDifficultyLevel(bgs.difficultyLevel)
                        logInfo "Difficulty: ", bgs.difficultyLevel
                    
                    elif commandLowerDiffculty.normalize in text:
                        if not canChangeDifficulty:
                            bgs.sendMessage messageCanOnlyChangeDifficultyAtBeginOfGame
                        else:
                            if bgs.difficultyLevel == DifficultyLevel.low:
                                bgs.sendMessage messageAlreadyAtLowestDifficulty
                            else:
                                inc bgs.difficultyLevel, -1
                                bgs.sendMessage messageNewDifficultyLevel(bgs.difficultyLevel)
                        logInfo "Difficulty: ", bgs.difficultyLevel
                    elif text.len > commandSetDiffculty.len and text[0..<commandSetDiffculty.len] == commandSetDiffculty.normalize:
                        let words = text[commandSetDiffculty.len..^1].splitWhitespace
                        if words.len >= 1:
                            let dl = words[0].toDifficultyLevel
                            if dl.isSome:
                                bgs.difficultyLevel = dl.get
                                bgs.sendMessage messageDirectlySetDifficultyLevel(bgs.difficultyLevel)
                            else:
                                bgs.sendMessage "Don't know what you mean with " & words[0]
                    else:
                        if text.toDifficultyLevel.isSome:
                            bgs.difficultyLevel = text.toDifficultyLevel.get
                            bgs.sendMessage messageDirectlySetDifficultyLevel(bgs.difficultyLevel)

                continue

            if nodeType == "opponentGone":
                # if jsonNode{"gone"}.getBool:
                #     TODO leave game
                # ignore for now
                continue

            if nodeType != "gameFull":
                logWarn &"Didn't receive expected \"gameState\" JSON type: {jsonNode}"                
                continue

            jsonNode{"state"}
        else:
            jsonNode

        let gameState = lichessGame.getCurrentState(gameStateNode)

        bgs.lastLichessGameState = gameState


        if not sentGreetingMessage:
            if gameState.positionMoveHistory.len <= 1:
                sleep 500
                doAssert bgs.sendComment greeting
                bgs.sendMessage messageStartingDifficultyLevel(bgs.difficultyLevel)
            else:
                bgs.sendMessage "Sorry, I crashed."
            sentGreetingMessage = true



        if gameState.currentPosition.fen in bgs.sentMovesForPositions:
            logWarn "Skipping. Already sent move for position: ", gameState.currentPosition.fen
            continue

        logInfo "Current position: ", gameState.currentPosition.fen
        
        let gameStateStatus = gameStateNode{"status"}.getStr

        if gameStateStatus notin ["started", "created"]:
            logInfo "Game finished (", gameStateStatus, ")"
            if gameStateStatus in ["mate", "resign", "stalemate", "timeout", "draw", "outoftime"]:
                if gameStateStatus in ["draw", "stalemate"]:
                    logInfo "Draw"
                else:
                    logInfo "Winner is ",  gameStateNode{"winner"}.getStr
                var outcome = 0.5
                if gameStateNode{"winner"}.getStr == "white":
                    outcome = 1.0
                if gameStateNode{"winner"}.getStr == "black":
                    outcome = 0.0
                if outcome != 0.5 and lichessGame.botColor == black:
                    outcome = 1.0 - outcome

                sleep 800
                if outcome == 1.0:
                    case gameStateStatus:
                    of "resign":
                        doAssert bgs.sendComment(enemyResigns)
                    of "mate":
                        doAssert bgs.sendComment(enemyGetsMated)
                    of "outoftime":
                        doAssert bgs.sendComment(enemyRunsOutOfTime)
                    else:
                        logError "Unsupported game state status: ", gameStateStatus
                elif outcome == 0.0:
                    case gameStateStatus:
                    of "resign":
                        doAssert bgs.sendComment(weResign)
                    of "mate":
                        doAssert bgs.sendComment(weGetMated)
                    of "outoftime":
                        doAssert bgs.sendComment(weRunOutOfTime)
                    else:
                        logError "Unsupported game state status: ", gameStateStatus
                elif outcome == 0.5:
                    case gameStateStatus:
                    of "stalemate":
                        doAssert bgs.sendComment(stalemate)
                    of "draw":
                        doAssert bgs.sendComment(draw)
                    else:
                        logError "Unsupported game state status: ", gameStateStatus
                else:
                    doAssert false, fmt"{outcome = }"


                historyOfGameResultsFileName.updateHistoryOfGameResults(
                    difficultyLevel = bgs.difficultyLevel,
                    opponentElo = lichessGame.opponentElo,
                    score = outcome
                )
            return
        
        doAssert gameState.currentPosition.legalMoves.len >= 1

        if gameState.positionMoveHistory.len >= 4:
            canChangeDifficulty = false

        if gameState.currentPosition.us == lichessGame.botColor:
            bgs.beforeBotMove(gameState)

        if gameState.currentPosition.us == lichessGame.botColor:
            # we have to do a move
            logInfo "Game ", gameId, ": Starting search on ", gameState.currentPosition.fen

            let # we want to do the very first move a bit quicker
                moveTimeDivider = if gameState.positionMoveHistory.len <= 1: 5 else: 1
                wtime = gameState.wtime div moveTimeDivider
                btime = gameState.btime div moveTimeDivider

            # if enemy does king cloud move we will also make a king cloud move if possible
            let suggestedMove = if gameState.lastEnemyMoveWasKingCloudMove(gameState.lichessGame.botColor):
                gameState.currentPosition.getCloudKingMove
            else:
                noMove

            let (value, pv) = if suggestedMove != noMove:
                doAssert suggestedMove in gameState.currentPosition.legalMoves
                logInfo "Using suggested move instead of search: ", suggestedMove
                (0.Value, @[suggestedMove])
            else:
                logInfo "Using difficulty level ", bgs.difficultyLevel
                timeManagedSearch(
                    position = gameState.currentPosition,
                    hashTable = hashTable,
                    positionHistory = gameState.getPositionHistory,
                    increment = [white: gameState.winc, black: gameState.binc],
                    timeLeft = [white: wtime, black: btime],
                    difficultyLevel = bgs.difficultyLevel
                )

            logInfo "Game ", gameId, ": Finished search"

            # rage quit
            if value < -600.cp and gameState.timeLeft(gameState.lichessGame.botColor) <= initDuration(seconds = 80):
                if rand(1.0) < 0.1 and not consideredRageQuitting:
                    if bgs.sendComment(rageQuit):
                        logWarn "Rage quitting"
                        quit QuitSuccess
                consideredRageQuitting = true
    
            let move = if pv.len >= 1: pv[0] else: gameState.currentPosition.legalMoves()[0]

            # offer a draw if opponent has forced checkmate, lol
            let offerDraw = value <= -valueCheckmate and not weOfferedDrawAlready
            if offerDraw:
                weOfferedDrawAlready = true

            let query = fmt"https://lichess.org/api/bot/game/{gameId}/move/{move}?offeringDraw={offerDraw}"

            try:
                discard bgs.requestsSession.jsonResponse(httpPost, query, token)
            except CatchableError:
                if "Not your turn, or game already over" in getCurrentExceptionMsg():
                    logInfo "Tried to play move when it's not our turn, or game already over"
                    continue
                logError &"Failed to send move {move} for game {gameId} to lichess\nQuery: {query}\nException: ", getCurrentExceptionMsg()
                raise
            bgs.sentMovesForPositions.add gameState.currentPosition.fen
            logInfo "Played move ", move
            bgs.afterBotMove(gameState, if pv.len > 0 and pv[0] == move: pv else: @[move], value)

while true:
    try:
        main()
        break
    except CatchableError:
        logError "Encountered exception while playing game ", gameId, ": ", getCurrentExceptionMsg(), "\n", getCurrentException().getStackTrace()
        let cooldownMilliseconds = 1_000
        logInfo "Trying to play game again in ", cooldownMilliseconds, " ms"
        sleep cooldownMilliseconds

logInfo "Exiting process for game ", gameId
        
    

    




