import std/[
    json,
    times,
    options,
    random,
    strutils,
    strformat,
    os,
    sequtils,
    tables
]

import
    types,
    position,
    move,
    lichessGame,
    lichessNetUtils,
    anarchyConditions,
    anarchyParameters,
    log


type
    CommentTimeStamp* = object
        halfMoveNumber*: int
        timePoint*: DateTime
    BotGameState* = object
        requestsSession*: PyObject
        lastComment*: array[CommentType, Option[CommentTimeStamp]]
        commentHistory*: seq[string]
        evalHistory*: seq[Value]
        gameId*: string
        token*: string

const lichessChatCharLimit = 140

var commentTable = none array[CommentType, seq[string]]

proc loadAnarchyComments*(fileName: string) =
    var tmp: array[CommentType, seq[string]]
    let jsonNode = fileName.readFile.parseJson
    for commentType in CommentType:
        doAssert tmp[commentType].len == 0
        if jsonNode.hasKey($commentType):
            tmp[commentType] = jsonNode{$commentType}.to(seq[string])
        
        if tmp[commentType].len == 0:
            logWarn "Didn't find an entry for comment type ", commentType
            tmp[commentType] = @[$commentType & " text 1"]
        for comment in tmp[commentType]:
            for line in comment.split('\n'):
                if line.len > lichessChatCharLimit:
                    logWarn &"Line too long: \"{line}\" (comment type: {commentType})"

    commentTable = some tmp
    

proc sampleComment*(commentType: CommentType, excluded: openArray[string] = []): Option[string] =
    doAssert commentTable.isSome, "Need to load anarchy comment table first with"
    let length = commentTable.get[commentType].len
    doAssert length >= 1, "Need at least one comment per comment type"
    let startIndex = rand(0..<length)
    for i in 0..<length:
        let candidate = commentTable.get[commentType][(startIndex + i) mod length]
        if candidate notin excluded:
            return some(candidate)
    logWarn "Failed to sample suitable comment of type ", commentType
    none(string)


proc registerSentComment*(bgs: var BotGameState, commentType: CommentType, gameState: LichessGameState, text: string) =
    bgs.lastComment[commentType] = some CommentTimeStamp(
        halfMoveNumber: gameState.positionMoveHistory.len,
        timePoint: now()
    )
    bgs.commentHistory.add text

proc sendMessage*(bgs: var BotGameState, text: string, toSpectator = false, toPlayer = true) =
    for line in text.split('\n'):

        var
            words = line.splitWhitespace
            smallText = ""

        for i, word in words:
            if smallText.len > 0:
                smallText &= " "
            smallText &= word
            doAssert smallText.len <= lichessChatCharLimit
            if i == words.len - 1 or smallText.len + 1 + words[i + 1].len > lichessChatCharLimit:
                sleep 50
                if toPlayer:
                    discard bgs.requestsSession.jsonResponse(httpPost, &"https://lichess.org/api/bot/game/{bgs.gameId}/chat", bgs.token, {"room": "player", "text": smallText}.toTable)
                if toSpectator:
                    discard bgs.requestsSession.jsonResponse(httpPost, &"https://lichess.org/api/bot/game/{bgs.gameId}/chat", bgs.token, {"room": "spectator", "text": smallText}.toTable)
                smallText = ""



proc trySendSomeComments(
    bgs: var BotGameState,
    gameState: LichessGameState,
    cci: CommentConditionInfo,
    sleepTime: Duration,
    commentTypes, commentTypesImportant, commentTypesMust: openArray[CommentType]
) =
    var
        commentTypes = commentTypes.toSeq
        commentTypesImportant = commentTypesImportant.toSeq
        commentTypesMust = commentTypesMust.toSeq
    commentTypes.shuffle
    commentTypesImportant.shuffle
    commentTypesMust.shuffle

    # first make all must-comments
    var madeComment = false
    let bgsAddr = addr bgs
    proc handleCommentType(commentType: CommentType) =

        logInfo "commentType: ", commentType

        let
            moveCooldown =
                bgsAddr[].lastComment[commentType].isNone or
                bgsAddr[].lastComment[commentType].get.halfMoveNumber + commentTypeCooldown[commentType].halfMoves <= gameState.positionMoveHistory.len
            timeCooldown =
                bgsAddr[].lastComment[commentType].isNone or
                bgsAddr[].lastComment[commentType].get.timePoint + initDuration(seconds = commentTypeCooldown[commentType].timeInterval) <= now()
            applicable = commentType.checkIfCommentApplicable(cci)

        if applicable and moveCooldown and timeCooldown:
            logInfo "Comment type applicable: ", commentType
            let comment = commentType.sampleComment(excluded = bgsAddr[].commentHistory)
            if comment.isSome:
                if not madeComment:
                    if gameState.timeLeft(cci.botColor) >= initDuration(seconds = 10):
                        sleep sleepTime.inMilliseconds
                    else:
                        sleep min(sleepTime.inMilliseconds, 100)
                madeComment = true
                bgsAddr[].sendMessage comment.get
                bgsAddr[].registerSentComment commentType, gameState, comment.get
                logInfo &"Sent comment \"{comment.get}\" (type: {commentType})"
    
    for commentType in commentTypesMust:
        commentType.handleCommentType()

    # if we haven't commented yet, make exactly one comment, favoring important comments over normal comments
    for commentType in concat(commentTypesImportant, commentTypes):
        if not madeComment:
            commentType.handleCommentType()


proc beforeBotMove*(bgs: var BotGameState, gameState: LichessGameState) =

    if gameState.positionMoveHistory.len == 0:
        return
    
    var cci = CommentConditionInfo(
        botColor: gameState.lichessGame.botColor,
        currentPosition: gameState.currentPosition,
        previousPosition: gameState.positionMoveHistory[^1].position,
        gameState: gameState,
        lastMove: gameState.positionMoveHistory[^1].move,
        pv: none(seq[Move]),
        evalDiff: none(Value),
        lastEval: none(Value)
    )

    if bgs.evalHistory.len > 0:
        cci.lastEval = some bgs.evalHistory[^1]

    logInfo "beforeBotMove"

    bgs.trySendSomeComments(
        gameState = gameState,
        cci = cci,
        sleepTime = initDuration(milliseconds = 600),
        commentTypes = @[
            enemyMovedPieceBackAtLeastTwoRanks,
            enemyCapturedEnPassant,
            enemyCheckedUs,
            enemyTradesQueen,
            enemyCastled,
            enemeyPromotingToQueen
        ],
        commentTypesImportant = @[
            enemyHasUndefendedBackRank,
            enemeyUnderpromoting
        ],
        commentTypesMust = @[
            enemyCapturedEnPassant,
            enemyDoesFirstKingCloudMove,
            enemyDoesSecondKingCloudMove
        ]
    )

proc afterBotMove*(bgs: var BotGameState, gameState: LichessGameState, pv: seq[Move], value: Value) = 

    bgs.evalHistory.add value

    if gameState.positionMoveHistory.len == 0:
        return
    
    doAssert pv.len >= 1

    var cci = CommentConditionInfo(
        botColor: gameState.lichessGame.botColor,
        currentPosition: gameState.currentPosition.doMove(pv[0]),
        previousPosition: gameState.currentPosition,
        gameState: gameState,
        lastMove: pv[0],
        pv: some(pv),
        evalDiff: none(Value)
    )

    if bgs.evalHistory.len >= 2 and bgs.evalHistory[^1].abs < valueCheckmate:
        cci.evalDiff = some(bgs.evalHistory[^1] - bgs.evalHistory[^2])

    if bgs.evalHistory.len > 0:
        cci.lastEval = some bgs.evalHistory[^1]

    logInfo "evalHistory: ", bgs.evalHistory
    logInfo "cci.evalDiff: ", cci.evalDiff

    logInfo "afterBotMove"

    bgs.trySendSomeComments(
        gameState = gameState,
        cci = cci,
        sleepTime = initDuration(milliseconds = 200),
        commentTypes = @[
            enemyLostGoodPiece,
            weCastled,
            weCheckedEnemy,
            wePromotingToQueen,
            enemyCanPushPawnForMeToDoEnPassant
        ],
        commentTypesImportant = @[
            enemyCanCaptureEnPassant,
            ourBestMoveIsKnightFork,
            weDoFirstKingCloudMove,
            weBlundered,
            weUnderpromoting
        ],
        commentTypesMust = @[
            weCaptureEnPassant
        ]
    )


proc sendComment*(bgs: var BotGameState, commentType: CommentType): bool =
    
    let comment = commentType.sampleComment(excluded = bgs.commentHistory)
    if comment.isSome:
        bgs.sendMessage comment.get
        logInfo &"Sent comment \"{comment.get}\" (type: {commentType})"
        return true
    else:
        logWarn "Couldn't sample comment of type ", commentType
        return false

const
    translateDifficultyLevel: array[DifficultyLevel, string] = [
        "A1", "A2", "A3", "B1", "B2", "B3", "C1", "C2", "C3", "D"
    ]
    commandHigherDiffculty* = "Please don't crush me!"
    commandLowerDiffculty* = "You are underestimating me."
    messageAlreadyAtHighestDifficulty* = "Better play against a rock if you're still intimidated"
    messageAlreadyAtLowestDifficulty* = "Sorry, I don't get more brilliant than this."
    messageCanOnlyChangeDifficultyAtBeginOfGame* = "You can only change the level at the begin of the game."
func messageNewDifficultyLevel*(dl: DifficultyLevel): string =
    fmt"Great, so you'll be playing against level {translateDifficultyLevel[dl]}."

func messageStartingDifficultyLevel*(dl: DifficultyLevel): string =

    if dl <= 3.DifficultyLevel:
        result = &"Because you're so cunning you'll be playing against level {translateDifficultyLevel[dl]}.\n"
    elif dl <= 6.DifficultyLevel:
        result = &"Based on your history of mediocracy we decided you best play against level {translateDifficultyLevel[dl]}.\n"
    elif dl <= 9.DifficultyLevel:
        result = &"Considering that you still fail to have even a basic grasp on how this game works, we thought it's best for you to play against level {translateDifficultyLevel[dl]}.\n"
    else:
        result = &"Aww, I think level {translateDifficultyLevel[dl]} is a good fit for you :).\n"

    result &= &"If you're already scared, say \"{commandHigherDiffculty}\".\n" &
    &"If you feel especially sharp and smart today, say \"{commandLowerDiffculty}\"."