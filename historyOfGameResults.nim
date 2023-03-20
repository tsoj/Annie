import
    anarchyParameters,
    log

import std/[
    strutils,
    strformat,
    os,
    random
]

type HistoryOfGameResults = object
    sumOpponentRating: float# = 1500.0
    sumScore: float# = 0.5
    numGames: int# = 0

let
    baseLockFileName = "lockFile_historyOfGameResults"
    unlockedFileName = baseLockFileName & ".unlocked"
    lockedFileName = baseLockFileName & ".locked." & $getCurrentProcessId()
    expectedMoveError = "No such file or directory"

func getBaseDir(fileName: string): string =
    doAssert fileName.len > 0 and fileName[0] == '/', "fileName must be an absolute path"
    fileName.splitFile.dir & "/"

proc historyOfGameResultsResetAllLockFiles*(fileName: string) =
    let baseDir = getBaseDir fileName
    for lockFileName in walkFiles baseDir & baseLockFileName & "*":
        removeFile baseDir & lockFileName
    writeFile baseDir & unlockedFileName, ""

proc lockFile(fileName: string) =
    let
        baseDir = getBaseDir fileName
        unlockedFileName = baseDir & unlockedFileName
        lockedFileName = baseDir & lockedFileName
    while true:
        try:
            moveFile(unlockedFileName, lockedFileName)
            logInfo "Moved file: ", unlockedFileName, " -> ", lockedFileName
            break
        except OSError:
            if getCurrentExceptionMsg().len < expectedMoveError.len or expectedMoveError[0..<expectedMoveError.len] != expectedMoveError:
                raise
            sleep 1000

proc unlockFile(fileName: string) =
    let
        baseDir = getBaseDir fileName
        unlockedFileName = baseDir & unlockedFileName
        lockedFileName = baseDir & lockedFileName
    doAssert fileExists lockedFileName
    moveFile(lockedFileName, unlockedFileName)
    logInfo "Moved file: ", lockedFileName, " -> ", unlockedFileName


proc getHistoryOfGameResults(file: File): array[DifficultyLevel, HistoryOfGameResults] =

    ## each line has the following formatting:
    ## difficultyLevel sumOpponentRating sumScore numGames
    let lines = file.readAll.splitLines
    for line in lines:
        if line == "":
            continue

        let words = line.splitWhitespace
        doAssert words.len == 4

        let difficultyLevelAsInt = words[0].parseInt
        doAssert difficultyLevelAsInt in DifficultyLevel.low.int ..
                DifficultyLevel.high.int
        let difficultyLevel = difficultyLevelAsInt

        result[difficultyLevel].sumOpponentRating = words[1].parseFloat
        result[difficultyLevel].sumScore = words[2].parseFloat
        result[difficultyLevel].numGames = words[3].parseInt

func getElo(hgr: HistoryOfGameResults): float =
    let
        averageScore = hgr.sumScore / hgr.numGames.float
        averageOpponentRating = hgr.sumOpponentRating / hgr.numGames.float
    averageOpponentRating + 800.0 * (averageScore - 0.5)


proc writeHistoryOfGameResults(file: File, hgrArray: array[DifficultyLevel, HistoryOfGameResults]) =
    var s = ""
    for difficultyLevel, hgr in hgrArray:
        s &= &"{difficultyLevel} {hgr.sumOpponentRating} {hgr.sumScore} {hgr.numGames}\n"
    s &= '\n'
    file.write s


proc updateHistoryOfGameResults*(fileName: string, difficultyLevel: DifficultyLevel, opponentElo: float, score: float) =

    lockFile fileName
    var file = fileName.open(mode = fmReadWriteExisting)
    defer:
        file.close()
        unlockFile fileName

    var historyOfGameResults = file.getHistoryOfGameResults
    
    discard reopen(file, fileName, mode = fmWrite)

    historyOfGameResults[difficultyLevel].sumOpponentRating += opponentElo
    historyOfGameResults[difficultyLevel].sumScore += score
    historyOfGameResults[difficultyLevel].numGames += 1

    file.writeHistoryOfGameResults historyOfGameResults


proc getDifficultyLevel*(fileName: string, opponentElo: float): DifficultyLevel =

    if not fileExists fileName:

        lockFile fileName
        var file = fileName.open(mode = fmWrite)
        defer:
            file.close()
            unlockFile fileName

        var s: array[DifficultyLevel, HistoryOfGameResults]
        for difficulty, historyOfGameResults in s.mpairs:
            historyOfGameResults = HistoryOfGameResults(
                sumOpponentRating: difficulty.difficultyEloEstimate,
                sumScore: 0.5,
                numGames: 1
            )

        file.writeHistoryOfGameResults s


    doAssert fileExists fileName
    lockFile fileName
    var file = fileName.open(mode = fmRead)
    defer:
        file.close()
        unlockFile fileName

    let historyOfGameResultsSeq = file.getHistoryOfGameResults

    const offsetElo = 50.0
    let optimalElo = opponentElo + offsetElo

    var
        bestHigherElo: float = float.high
        bestLowerElo: float = float.low
        bestHigherDifficulty = DifficultyLevel.high
        bestLowerDifficulty = DifficultyLevel.low
        highestEloSoFar = 0.0
    result = 1.DifficultyLevel

    

    for difficulty, historyOfGameResults in historyOfGameResultsSeq:
        var elo = historyOfGameResults.getElo

        logInfo fmt"Elo for difficulty {difficulty}: {elo}"

        # because we know that the difficulty should be strict monotonically increase
        # we need to adjust if that's not the case in our historic results
        if highestEloSoFar >= elo:
            elo = highestEloSoFar + 50.0
            logInfo fmt"Updated elo for difficulty {difficulty}: {elo}"

        highestEloSoFar = elo

        if elo >= optimalElo and elo < bestHigherElo:
            bestHigherElo = elo
            bestHigherDifficulty = difficulty
        if elo <= optimalElo and elo > bestLowerElo:
            bestLowerElo = elo
            bestLowerDifficulty = difficulty
    
    logInfo fmt"{optimalElo = }"
    logInfo fmt"{bestHigherElo = }"
    logInfo fmt"{bestHigherDifficulty = }"
    logInfo fmt"{bestLowerElo = }"
    logInfo fmt"{bestLowerDifficulty = }"

    # we want to choose the level that closer to the optimal elo more often
    if rand(bestLowerElo..bestHigherElo) > optimalElo:
        result = bestLowerDifficulty
    else:
        result = bestHigherDifficulty



