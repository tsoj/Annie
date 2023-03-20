import
    ../position,
    ../positionUtils,
    ../types,
    ../timeManagedSearch,
    ../hashTable,
    ../move,
    ../evaluation

type
    Game* = object
        hashTable: HashTable
        positionHistory: seq[Position]
        maxNodes: uint64
        earlyResignMargin: Value
        earlyAdjudicationPly: Ply
        evaluation: proc(position: Position): Value {.noSideEffect.}
    GameStatus* = enum
        running, fiftyMoveRule, threefoldRepetition, stalemate, checkmateWhite, checkmateBlack

func gameStatus*(positionHistory: openArray[Position]): GameStatus =
    doAssert positionHistory.len >= 1
    let position = positionHistory[^1]
    if position.legalMoves.len == 0:
        if position.inCheck(position.us, position.enemy):
            return (if position.enemy == black: checkmateBlack else: checkmateWhite)
        else:
            return stalemate
    if position.fiftyMoveRuleHalfmoveClock >= 100:
            return fiftyMoveRule
    var repetitions = 0
    for p in positionHistory:
        if p.zobristKey == position.zobristKey:
            repetitions += 1
    doAssert repetitions >= 1
    doAssert repetitions <= 3
    if repetitions == 3:
        return threefoldRepetition
    running

proc makeNextMove*(game: var Game): (GameStatus, Value, Move) =
    doAssert game.positionHistory.len >= 1
    try:
        doAssert game.positionHistory.gameStatus == running, $game.positionHistory.gameStatus
        let position = game.positionHistory[^1]
        let (value, pv) = position.timeManagedSearch(
            hashTable = game.hashTable,
            positionHistory = game.positionHistory,
            evaluation = game.evaluation,
            maxNodes = game.maxNodes
        )
        doAssert pv.len >= 1
        doAssert pv[0] != noMove
        game.positionHistory.add(position)
        game.positionHistory[^1].doMove(pv[0])
        return (game.positionHistory.gameStatus, value * (if position.us == white: 1 else: -1), pv[0])
        
    except CatchableError:
        var s = getCurrentExceptionMsg() & "\n"
        s &= game.positionHistory[^1].fen & "\n"
        s &= $game.positionHistory[^1] & "\n"
        s &= game.positionHistory[^1].debugString & "\n"
        raise newException(AssertionDefect, s)



func newGame*(
    startingPosition: Position,
    maxNodes = 20_000'u64,
    earlyResignMargin = 800.Value,
    earlyAdjudicationPly = 8.Ply,
    hashSize = 4_000_000,
    evaluation: proc(position: Position): Value {.noSideEffect.} = evaluate
): Game =
    result = Game(
        hashTable: newHashTable(),
        positionHistory: @[startingPosition],
        maxNodes: maxNodes,
        earlyResignMargin: earlyResignMargin,
        earlyAdjudicationPly: earlyAdjudicationPly,
        evaluation: evaluation
    )
    result.hashTable.setSize(hashSize)

proc playGame*(game: var Game, suppressOutput = false): float =
    doAssert game.positionHistory.len >= 1
    if not suppressOutput:
        echo "-----------------------------"
        echo "starting position:"
        echo game.positionHistory[0]

    var drawPlies = 0.Ply
    var whiteResignPlies = 0.Ply
    var blackResignPlies = 0.Ply

    while true:
        var (gameStatus, value, move) = game.makeNextMove()
        if value == 0.Value:
            drawPlies += 1.Ply
        else:
            drawPlies = 0.Ply

        if value >= game.earlyResignMargin:
            blackResignPlies += 1.Ply
        else:
            blackResignPlies = 0.Ply
        if -value >= game.earlyResignMargin:
            whiteResignPlies += 1.Ply
        else:
            whiteResignPlies = 0.Ply

        if not suppressOutput:
            echo "Move: ", move
            echo game.positionHistory[^1]
            echo "Value: ", value
            if gameStatus != running:
                echo gameStatus

        if gameStatus != running:
            case gameStatus:
            of stalemate, fiftyMoveRule, threefoldRepetition:
                return 0.5
            of checkmateWhite:
                return 1.0
            of checkmateBlack:
                return 0.0
            else:
                doAssert false

        if drawPlies >= game.earlyAdjudicationPly:
            return 0.5
        if whiteResignPlies >= game.earlyAdjudicationPly:
            return 0.0
        if blackResignPlies >= game.earlyAdjudicationPly:
            return 1.0



