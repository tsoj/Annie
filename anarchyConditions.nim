
import std/[
    options,
    macros,
    random
]

import
    types,
    position,
    positionUtils,
    move,
    see,
    evaluation,
    bitboard,
    search,
    lichessGame,
    anarchyParameters

type
    CommentType* = enum
        enemyMovedPieceBackAtLeastTwoRanks,
        enemyHasUndefendedBackRank,
        enemyCanPushPawnForMeToDoEnPassant,
        enemyCanCaptureEnPassant,
        enemyCastled,
        weCastled,
        enemyCheckedUs,
        enemyTradesQueen,
        ourBestMoveIsKnightFork,
        enemyLostGoodPiece,
        enemyDoesFirstKingCloudMove,
        weDoFirstKingCloudMove,
        enemyDoesSecondKingCloudMove,
        enemyCapturedEnPassant,
        weCaptureEnPassant,
        weCheckedEnemy,
        weBlundered,
        rageQuit,
        enemeyPromotingToQueen,
        enemeyUnderpromoting,
        wePromotingToQueen,
        weUnderpromoting,
        weResign,
        weGetMated,
        weRunOutOfTime,
        enemyResigns,
        enemyGetsMated,
        enemyRunsOutOfTime,
        stalemate,
        draw,
        enemyOffersDraw,
        greeting
    TypedParam[T: static auto] = distinct int
    CommentConditionInfo* = object
        botColor*: Color
        currentPosition*, previousPosition*: Position
        lastMove*: Move
        gameState*: LichessGameState # this is important for some conditions, but it is important to know that this might miss the most current move/position
        pv*: Option[seq[Move]]
        evalDiff*: Option[Value]
        lastEval*: Option[Value]
        difficultyLevel*: DifficultyLevel

const blunderMargin: array[DifficultyLevel, Value] = [
    1: 800.cp, # we need to make it that large because the eval values with anarchy parameters can be a bit wild ...
    2: 700.cp,
    3: 600.cp,
    4: 500.cp,
    5: 450.cp,
    6: 400.cp,
    7: 350.cp,
    8: 300.cp,
    9: 250.cp,
    10: 200.cp
]

const commentTypeCooldown*: array[CommentType, tuple[halfMoves: int, timeInterval: int]] = [ # in seconds
    enemyMovedPieceBackAtLeastTwoRanks: (halfMoves: 6, timeInterval: 60),
    enemyHasUndefendedBackRank: (halfMoves: 3000, timeInterval: 300000), # want this only once per game
    enemyCanPushPawnForMeToDoEnPassant: (halfMoves: 6, timeInterval: 20),
    enemyCanCaptureEnPassant: (halfMoves: 0, timeInterval: 1),
    enemyCastled: (halfMoves: 30, timeInterval: 1),
    weCastled: (halfMoves: 30, timeInterval: 1),
    enemyCheckedUs: (halfMoves: 4, timeInterval: 30),
    enemyTradesQueen: (halfMoves: 0, timeInterval: 1),
    ourBestMoveIsKnightFork: (halfMoves: 0, timeInterval: 20),
    enemyLostGoodPiece: (halfMoves: 0, timeInterval: 5),
    enemyDoesFirstKingCloudMove: (halfMoves: 0, timeInterval: 1),
    weDoFirstKingCloudMove: (halfMoves: 0, timeInterval: 1),
    enemyDoesSecondKingCloudMove: (halfMoves: 0, timeInterval: 1),
    enemyCapturedEnPassant: (halfMoves: 0, timeInterval: 1),
    weCaptureEnPassant: (halfMoves: 0, timeInterval: 1),
    weCheckedEnemy: (halfMoves: 8, timeInterval: 20),
    weBlundered: (halfMoves: 20, timeInterval: 30),
    rageQuit: (halfMoves: 0, timeInterval: 0),
    enemeyPromotingToQueen: (halfMoves: 4, timeInterval: 20),
    enemeyUnderpromoting: (halfMoves: 4, timeInterval: 20),
    wePromotingToQueen: (halfMoves: 4, timeInterval: 20),
    weUnderpromoting: (halfMoves: 4, timeInterval: 20),
    weResign: (halfMoves: 0, timeInterval: 0),
    weGetMated: (halfMoves: 0, timeInterval: 0),
    weRunOutOfTime: (halfMoves: 0, timeInterval: 0),
    enemyResigns: (halfMoves: 0, timeInterval: 0),
    enemyGetsMated: (halfMoves: 0, timeInterval: 0),
    enemyRunsOutOfTime: (halfMoves: 0, timeInterval: 0),
    stalemate: (halfMoves: 0, timeInterval: 0),
    draw: (halfMoves: 0, timeInterval: 0),
    enemyOffersDraw: (halfMoves: 0, timeInterval: 0),
    greeting: (halfMoves: 0, timeInterval: 0),
]

proc checkIfCommentApplicable*(commentType: TypedParam[enemyMovedPieceBackAtLeastTwoRanks], cci: CommentConditionInfo): bool =
    doAssert cci.previousPosition.enemy == cci.botColor, "Only consider this when the enemy already did their turn (position is before the move)"

    if cci.currentPosition[pawn].countSetBits < 8:
        return false

    if cci.previousPosition.inCheck(cci.botColor.opposite):
        return false

    # not counting if piece is attacked by less valuable piece
    let lva = cci.previousPosition.doNullMove.getLeastValuableAttacker(cci.lastMove.source).piece
    if lva != noPiece and lva.value < cci.lastMove.moved.value:
        return false

    if cci.lastMove.captured != noPiece:
        return false

    if cci.previousPosition.us == white and
    cci.lastMove.source < a7 and
    (cci.lastMove.target.int div 8) + 1 < (cci.lastMove.source.int div 8):
        return true
    if cci.previousPosition.us == black and
    cci.lastMove.source > h2 and
    (cci.lastMove.target.int div 8) > (cci.lastMove.source.int div 8) + 1:
        return true

    false

proc checkIfCommentApplicable*(commentType: TypedParam[enemyHasUndefendedBackRank], cci: CommentConditionInfo): bool =
    doAssert cci.currentPosition.us == cci.botColor, "Only consider this when the enemy already did their turn (position is after the move)"

    let
        notBot = cci.botColor.opposite
        backRank = homeRank[notBot]
        kingPosition = (cci.currentPosition[king] and cci.currentPosition[notBot]).toSquare

    # only king on backrank
    if (backRank and cci.currentPosition[notBot]) != kingPosition.toBitboard:
        return false

    # king can't move up
    let position = if cci.currentPosition.us == notBot:
        cci.currentPosition
    else:
        cci.currentPosition.doNullMove

    for move in position.legalMoves:
        if move.moved == king and (move.target.toBitboard and backRank) == 0:
            return false

    # king has at least two pawns in front
    if (mask3x3[kingPosition] and cci.currentPosition[notBot] and cci.currentPosition[pawn]).countSetBits <= 1:
        return false

    true

proc checkIfCommentApplicable*(commentType: TypedParam[enemyCanPushPawnForMeToDoEnPassant], cci: CommentConditionInfo): bool =
    doAssert cci.currentPosition.enemy == cci.botColor, "Only consider this when it's the enemys turn"

    for move in cci.currentPosition.legalMoves:
        if move.moved == pawn and move.enPassantTarget != noSquare:

            let potentialPawnAttackers = (attackTablePawnCapture[cci.currentPosition.us][move.enPassantTarget] and cci.currentPosition[pawn] and cci.currentPosition[cci.botColor])

            # only applicable when the potential en passant capture pawn moved there in a time window, such that
            # we don't comment on the same pawn twice 

            if cci.lastMove.moved == pawn and (cci.lastMove.target.toBitboard and potentialPawnAttackers) != 0:
                return true

            for i in 1..cci.gameState.positionMoveHistory.len:
                if i >= commentTypeCooldown[enemyCanPushPawnForMeToDoEnPassant].halfMoves - 1:
                    break
                let (position, move) = cci.gameState.positionMoveHistory[^i]
                if position.us == cci.botColor and move.moved == pawn and (move.target.toBitboard and potentialPawnAttackers) != 0:
                    return true

            

    false

proc checkIfCommentApplicable*(commentType: TypedParam[enemyCanCaptureEnPassant], cci: CommentConditionInfo): bool =
    doAssert cci.currentPosition.enemy == cci.botColor, "Only consider this when it's the enemys turn"

    if rand(1.0) < 0.1:
        return false

    for move in cci.currentPosition.legalMoves:
        if move.capturedEnPassant:
            return true

    false

proc checkIfCommentApplicable*(commentType: TypedParam[enemyCheckedUs], cci: CommentConditionInfo): bool =
    doAssert cci.currentPosition.us == cci.botColor, "Only consider this when the enemy already did their turn (position is after the move)"

    if rand(1.0) < 0.3:
        return false

    return cci.currentPosition.inCheck(us = cci.botColor) and cci.currentPosition.legalMoves.len >= 1

proc checkIfCommentApplicable*(commentType: TypedParam[enemyTradesQueen], cci: CommentConditionInfo): bool =
    doAssert cci.currentPosition.us == cci.botColor, "Only consider this when the enemy already did their turn (position is before the move)"

    if rand(1.0) < 0.1:
        return false

    return cci.lastMove.moved == queen and cci.lastMove.captured == queen

proc checkIfCommentApplicable*(commentType: TypedParam[ourBestMoveIsKnightFork], cci: CommentConditionInfo): bool =
    doAssert cci.previousPosition.us == cci.botColor, "Only consider this when we made our move (position is before the move)"
    doAssert cci.pv.isSome
    let pv = cci.pv.get

    if pv.len <= 2:
        return false

    if cci.evalDiff.isSome and cci.evalDiff.get < -100.cp:
        return false

    if pv[0].moved != knight:
        return false

    if (
        knight.attackMask(pv[0].target, 0) and
        cci.previousPosition[cci.botColor.opposite] and
        (cci.previousPosition[queen] or cci.previousPosition[rook] or cci.previousPosition[king])
    ).countSetBits < 2:
        return false

    # only if the knight fork likely leads to capturing one of the forked pieces
    for i, move in pv:
        if i == 0 or (i mod 2) != 0:
            continue

        if move.moved == knight and move.source == pv[0].target and move.captured in [rook, queen, king]:
            return true

    false

proc checkIfCommentApplicable*(commentType: TypedParam[enemyLostGoodPiece], cci: CommentConditionInfo): bool = #position: Position, move: Move, enemyMoveWasBlunder: bool, botColor: Color): bool =
    doAssert cci.previousPosition.us == cci.botColor, "Only consider this when we made our move (position is before the move)"
    doAssert cci.pv.isSome
    
    if cci.evalDiff.isNone or cci.evalDiff.get < blunderMargin[cci.difficultyLevel]:
        return false

    if cci.lastMove.captured == noPiece:
        return false
    
    true

proc checkIfCommentApplicable*(commentType: TypedParam[enemyDoesFirstKingCloudMove], cci: CommentConditionInfo): bool =
    doAssert cci.previousPosition.enemy == cci.botColor, "Only consider this when the enemy already did their move (position is before the move)"

    if not cci.previousPosition.isCloudKingMove(cci.lastMove):
        return false

    for (position, move) in cci.gameState.positionMoveHistory:
        if position.us == cci.botColor and position.isCloudKingMove(move):
            # if we made a cloud king move first
            return false

    true

proc checkIfCommentApplicable*(commentType: TypedParam[weDoFirstKingCloudMove], cci: CommentConditionInfo): bool =
    doAssert cci.previousPosition.us == cci.botColor, "Only consider this when we made our move (position is before the move)"

    if not cci.previousPosition.isCloudKingMove(cci.lastMove):
        return false

    for (position, move) in cci.gameState.positionMoveHistory:
        if position.enemy == cci.botColor and position.isCloudKingMove(move):
            # enemy made a cloud king move first
            return false

    true
    
proc checkIfCommentApplicable*(commentType: TypedParam[enemyDoesSecondKingCloudMove], cci: CommentConditionInfo): bool =
    doAssert cci.previousPosition.enemy == cci.botColor, "Only consider this when the enemy already did their move (position is before the move)"

    if not cci.previousPosition.isCloudKingMove(cci.lastMove):
        return false

    for (position, move) in cci.gameState.positionMoveHistory:
        if position.us == cci.botColor and position.isCloudKingMove(move):
            # if we made a cloud king move first
            return true

    false

proc checkIfCommentApplicable*(commentType: TypedParam[enemyCapturedEnPassant], cci: CommentConditionInfo): bool =
    doAssert cci.currentPosition.us == cci.botColor, "Only consider this when the enemy already did their move (position is after the move)"
    return cci.lastMove.capturedEnPassant

proc checkIfCommentApplicable*(commentType: TypedParam[enemyCastled], cci: CommentConditionInfo): bool =
    doAssert cci.currentPosition.us == cci.botColor, "Only consider this when the enemy already did their move (position is after the move)"

    if rand(1.0) < 0.2:
        return false

    return cci.lastMove.castled

proc checkIfCommentApplicable*(commentType: TypedParam[weCastled], cci: CommentConditionInfo): bool =
    doAssert cci.previousPosition.us == cci.botColor, "Only consider this when we made our move (position is before the move)"

    if rand(1.0) < 0.5:
        return false

    return cci.lastMove.castled

proc checkIfCommentApplicable*(commentType: TypedParam[weCaptureEnPassant], cci: CommentConditionInfo): bool =
    doAssert cci.previousPosition.us == cci.botColor, "Only consider this when we made our move (position is before the move)"
    return cci.lastMove.capturedEnPassant

proc checkIfCommentApplicable*(commentType: TypedParam[weCheckedEnemy], cci: CommentConditionInfo): bool =
    doAssert cci.previousPosition.us == cci.botColor, "Only consider this when we made our move (position is before the move)"

    if rand(1.0) < 0.6:
        return false

    return cci.currentPosition.inCheck(us = cci.botColor.opposite) and cci.currentPosition.legalMoves.len >= 1

proc checkIfCommentApplicable*(commentType: TypedParam[weBlundered], cci: CommentConditionInfo): bool =
    doAssert cci.previousPosition.us == cci.botColor, "Only consider this when we made our move (position is before the move)"

    if cci.lastEval.isNone or cci.lastEval.get notin (-1000.cp + cci.evalDiff.get)..100.cp:
        return false

    if cci.gameState.positionMoveHistory.len <= 8:
        return false

    return cci.evalDiff.isSome and cci.evalDiff.get <= -blunderMargin[cci.difficultyLevel] 

proc checkIfCommentApplicable*(commentType: TypedParam[rageQuit], cci: CommentConditionInfo): bool =
    doAssert false, "Not implemented"

proc checkIfCommentApplicable*(commentType: TypedParam[weResign], cci: CommentConditionInfo): bool =
    doAssert false, "Not implemented"

proc checkIfCommentApplicable*(commentType: TypedParam[weGetMated], cci: CommentConditionInfo): bool =
    doAssert false, "Not implemented"

proc checkIfCommentApplicable*(commentType: TypedParam[weRunOutOfTime], cci: CommentConditionInfo): bool =
    doAssert false, "Not implemented"

proc checkIfCommentApplicable*(commentType: TypedParam[enemyResigns], cci: CommentConditionInfo): bool =
    doAssert false, "Not implemented"

proc checkIfCommentApplicable*(commentType: TypedParam[enemyGetsMated], cci: CommentConditionInfo): bool =
    doAssert false, "Not implemented"

proc checkIfCommentApplicable*(commentType: TypedParam[enemyRunsOutOfTime], cci: CommentConditionInfo): bool =
    doAssert false, "Not implemented"

proc checkIfCommentApplicable*(commentType: TypedParam[stalemate], cci: CommentConditionInfo): bool =
    doAssert false, "Not implemented"

proc checkIfCommentApplicable*(commentType: TypedParam[draw], cci: CommentConditionInfo): bool =
    doAssert false, "Not implemented"

proc checkIfCommentApplicable*(commentType: TypedParam[enemyOffersDraw], cci: CommentConditionInfo): bool =
    doAssert false, "Not implemented"

proc checkIfCommentApplicable*(commentType: TypedParam[greeting], cci: CommentConditionInfo): bool =
    doAssert false, "Not implemented"

proc checkIfCommentApplicable*(commentType: TypedParam[enemeyPromotingToQueen], cci: CommentConditionInfo): bool =
    doAssert cci.currentPosition.us == cci.botColor, "Only consider this when the enemy already did their move (position is after the move)"

    cci.lastMove.promoted == queen

proc checkIfCommentApplicable*(commentType: TypedParam[enemeyUnderpromoting], cci: CommentConditionInfo): bool =
    doAssert cci.currentPosition.us == cci.botColor, "Only consider this when the enemy already did their move (position is after the move)"

    cci.lastMove.promoted notin [queen, noPiece]

proc checkIfCommentApplicable*(commentType: TypedParam[wePromotingToQueen], cci: CommentConditionInfo): bool =
    doAssert cci.previousPosition.us == cci.botColor, "Only consider this when we made our move (position is before the move)"

    if rand(1.0) < 0.3:
        return false

    cci.lastMove.promoted == queen

proc checkIfCommentApplicable*(commentType: TypedParam[weUnderpromoting], cci: CommentConditionInfo): bool =
    doAssert cci.previousPosition.us == cci.botColor, "Only consider this when we made our move (position is before the move)"

    if rand(1.0) < 0.6:
        return false

    cci.lastMove.promoted notin [queen, noPiece]

proc checkIfCommentApplicable*(commentType: CommentType, cci: CommentConditionInfo): bool=

    macro unrollCommentTypes(name, body: untyped) =
        result = newStmtList()
        for a in CommentType:
            result.add(newBlockStmt(newStmtList(
                newConstStmt(name, newLit(a)),
                copy body
            )))    

    unrollCommentTypes(candidateCommentType):
        if candidateCommentType == commentType:
            return checkIfCommentApplicable(commentType = TypedParam[candidateCommentType](0), cci)

    doAssert false