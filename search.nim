import
    types,
    bitboard,
    position,
    positionUtils,
    move,
    searchUtils,
    moveIterator,
    hashTable,
    evaluation,
    see,
    anarchyParameters

import std/[
    atomics,
    bitops,
    random,
    tables,
    math
]

static: doAssert pawn.value == 100.cp

func futilityReduction(value: Value): Ply =
    if value < 100.cp: return 0.Ply
    if value < 150.cp: return 1.Ply
    if value < 250.cp: return 2.Ply
    if value < 400.cp: return 3.Ply
    if value < 650.cp: return 4.Ply
    if value < 900.cp: return 5.Ply
    if value < 1200.cp: return 6.Ply
    Ply.high

func hashResultFutilityMargin(depthDifference: Ply): Value =
    if depthDifference >= 5.Ply: return valueInfinity
    depthDifference.Value * 200.cp

func nullMoveDepth(depth: Ply): Ply =
    depth - 3.Ply - depth div 4.Ply

func lmrDepth(depth: Ply, lmrMoveCounter: int): Ply =
    const halfLife = 35
    ((depth.int * halfLife) div (halfLife + lmrMoveCounter)).Ply

func increaseBeta(newBeta: var Value, alpha, beta: Value) =
    newBeta = min(beta, newBeta + 10.cp + (newBeta - alpha)*2)

const
    deltaMargin = 150.cp
    failHighDeltaMargin = 50.cp

# Anarchy values

func evaluateAnarchyBonus(position: Position, rootColor: Color, dl: DifficultyLevel): Value =
    result = 0.Value

    # pawns are ready for en passant
    const fifthRank = [
        white: ranks[a5],
        black: ranks[a4]
    ]
    for color in white..black:
        for square in position[color] and position[pawn] and fifthRank[color]:
            doAssert not (square.isLowerEdge or square.isUpperEdge)
            let doublePushPawns = attackTablePawnCapture[color][square.up(color)] and position[color.opposite] and position[pawn]
            for doublePushSourceSquare in doublePushPawns:
                if ((
                    attackTablePawnQuiet[color.opposite][doublePushSourceSquare] or
                    attackTablePawnQuiet[color.opposite][doublePushSourceSquare.up(color.opposite)]
                ) and position.occupancy) == 0:
                    if color == rootColor:
                        result += anarchyParams(dl).bonusOurPawnReadyCaptureEnPassant
                    else:
                        result += anarchyParams(dl).bonusEnemyPawnReadyCaptureEnPassant

    # triple, quadruple, ... pawns
    for color in white..black:
        for square in a1..h1:
            let numberPawns = countSetBits(position[pawn] and position[color] and files[square])
            doAssert numberPawns in 0..7
            result += anarchyParams(dl).tuplePawnsBonus[numberPawns]

    # queens can cause chaos
    if (position[rootColor] and position[queen]) != 0:
        result += anarchyParams(dl).stillHaveAQueenBonus - anarchyParams(dl).stillHaveAQueenBonus div 2

    # pushing pawns is good, no?
    let
        ourPawns = position[rootColor] and position[pawn]
        numOurPawns = ourPawns.countSetBits
    var
        ranksWithHalveOfOurPawns = homeRank[rootColor]
        currentSquare = ranksWithHalveOfOurPawns.toSquare
        numStepsNeeded = 0
    while countSetBits(ourPawns and ranksWithHalveOfOurPawns)*2 < numOurPawns:
        numStepsNeeded += 1
        doAssert currentSquare.goUpColor(rootColor)
        ranksWithHalveOfOurPawns = ranksWithHalveOfOurPawns or ranks[currentSquare]
    result += numStepsNeeded.Value * anarchyParams(dl).bonusPerStepNeededToGetHalvePawns

func confidentInUnderpromotion(position: Position, value: Value, dl: DifficultyLevel): bool =
    (value >= anarchyParams(dl).minValueUnderpromotion and countSetBits(position[pawn] and position[position.us]) >= 2) or # still have one more pawn after promotion
    value >= anarchyParams(dl).minValueUnderpromotionNoPawnsLeft

                

type SearchState* = object
    stop*: ptr Atomic[bool]
    threadStop*: ptr Atomic[bool]
    hashTable*: ptr HashTable
    killerTable*: KillerTable
    historyTable*: ptr HistoryTable
    gameHistory*: GameHistory
    countedNodes*: uint64
    maxNodes*: uint64
    dl*: DifficultyLevel
    evaluation*: proc(position: Position): Value {.noSideEffect.}
    randState*: Rand

func update(
    state: var SearchState,
    position: Position,
    bestMove, previous: Move,
    depth, height: Ply,
    nodeType: NodeType,
    value: Value
) =
    if bestMove != noMove and not (state.stop[].load or state.threadStop[].load):
        state.hashTable[].add(position.zobristKey, nodeType, value, depth, bestMove)
        if nodeType != allNode:
            state.historyTable[].update(bestMove, previous, position.us, depth)
        if nodeType == cutNode:
            state.killerTable.update(height, bestMove)                

func isRootPlayer(height: Ply): bool = (height mod 2) == 0

func quiesce(
    position: Position,
    state: var SearchState,
    alpha, beta: Value, 
    height: Ply,
    doPruning: static bool = true,
    addAnarchyBonus: static bool = true
): Value =
    assert alpha < beta

    state.countedNodes += 1

    if height == Ply.high or
    position.insufficientMaterial:
        return if height.isRootPlayer: anarchyParams(state.dl).bonusDraw else: 0.Value


    let anarchyBonus = when addAnarchyBonus:
        if height.isRootPlayer:
            position.evaluateAnarchyBonus(rootColor = position.us, state.dl)
        else:
            -position.evaluateAnarchyBonus(rootColor = position.enemy, state.dl)
    else:
        0.Value
    
    let standPat = state.evaluation(position) + anarchyBonus

    var
        alpha = alpha
        bestValue = standPat

    if standPat >= beta:
        return standPat
    if standPat > alpha:
        alpha = standPat

    for move in position.moveIterator(doQuiets = false):
        let newPosition = position.doMove(move)
        
        let seeEval = standPat + position.see(move)
        
        # delta pruning
        if seeEval + deltaMargin < alpha and doPruning:
            # return instead of just continue, as later captures must have lower SEE value
            return bestValue

        if newPosition.inCheck(position.us):
            continue
        
        # fail-high delta pruning
        if seeEval - failHighDeltaMargin >= beta and doPruning:
            return seeEval - failHighDeltaMargin

        let value = -newPosition.quiesce(state, alpha = -beta, beta = -alpha, height + 1.Ply, doPruning = doPruning)

        if value > bestValue:
            bestValue = value
        if value >= beta:
            return bestValue
        if value > alpha:
            alpha = value
            
    bestValue

func materialQuiesce*(position: Position): Value =
    var state = SearchState(
        stop: nil,
        hashTable: nil,
        gameHistory: newGameHistory(@[]),
        evaluation: material
    )
    position.quiesce(state = state, alpha = -valueInfinity, beta = valueInfinity, height = 0.Ply, doPruning = false, addAnarchyBonus = false)

func search(
    position: Position,
    state: var SearchState,
    alpha, beta: Value,
    depth, height: Ply,
    previous: Move,
    skipMove = noMove
): Value =
    assert alpha < beta, $alpha & " " & $beta

    state.countedNodes += 1

    if height > 0 and (
        height == Ply.high or
        position.insufficientMaterial or
        position.fiftyMoveRuleHalfmoveClock >= 100 or
        state.gameHistory.checkForRepetition(position, height)
    ):
        return if height.isRootPlayer: anarchyParams(state.dl).bonusDraw else: 0.Value
    
    state.gameHistory.update(position, height)

    let
        inCheck = position.inCheck(position.us)
        depth = if inCheck or previous.isPawnMoveToSecondRank: depth + 1.Ply else: depth
        hashResult = if skipMove != noMove: noEntry else: state.hashTable[].get(position.zobristKey)
        originalAlpha = alpha

    var
        alpha = alpha
        beta = beta
        nodeType = allNode
        bestMove = noMove
        bestValue = -valueInfinity
        moveCounter = 0
        lmrMoveCounter = 0

    # update alpha, beta or value based on hash table result
    if (not hashResult.isEmpty) and height > 0 and (alpha > -valueInfinity or beta < valueInfinity):
        if hashResult.depth >= depth:
            case hashResult.nodeType:
            of exact:
                return hashResult.value
            of lowerBound:
                alpha = max(alpha, hashResult.value)
            of upperBound:
                beta = min(beta, hashResult.value)
            if alpha >= beta:
                return alpha
        else:
            # hash result futility pruning
            let margin = hashResultFutilityMargin(depth - hashResult.depth)
            if hashResult.nodeType == lowerBound and hashResult.value - margin >= beta:
                return hashResult.value - margin
            if hashResult.nodeType == upperBound and hashResult.value + margin <= alpha:
                return hashResult.value + margin

    if depth <= 0:
        return position.quiesce(state, alpha = alpha, beta = beta, height)

    # null move reduction
    if height > 0 and (not inCheck) and alpha > -valueInfinity and beta < valueInfinity and
    ((position[knight] or position[bishop] or position[rook] or position[queen]) and position[position.us]).countSetBits >= 1:
        let newPosition = position.doNullMove
        let value = -newPosition.search(
            state,
            alpha = -beta, beta = -beta + 1.Value,
            depth = nullMoveDepth(depth), height = height + 1.Ply,
            previous = noMove
        )
        
        if value >= beta:
            return value

    var valueStaticEval = valueInfinity # will be calculated on demand
    template staticEval(): auto =
        if valueStaticEval == valueInfinity:
            valueStaticEval = state.evaluation(position)
        valueStaticEval
        
    for move in position.moveIterator(hashResult.bestMove, state.historyTable[], state.killerTable.get(height), previous):

        if move == skipMove:
            continue

        let newPosition = position.doMove(move)
        if newPosition.inCheck(position.us):
            continue
        moveCounter += 1

        # don't cancel good underpromotions
        if height.isRootPlayer and
        bestMove.promoted != noPiece and
        move.promoted.value > bestMove.promoted.value and
        position.confidentInUnderpromotion(bestValue, state.dl):
            continue

        let givingCheck = newPosition.inCheck(newPosition.us)

        var
            newDepth = depth
            newBeta = beta

        if not (givingCheck or inCheck):

            # late move reduction
            if (not move.isTactical) and
            (moveCounter > 3 or (moveCounter > 2 and hashResult.isEmpty)) and
            not newPosition.isPassedPawnMove(move):
                newDepth = lmrDepth(newDepth, lmrMoveCounter)
                lmrMoveCounter += 1
                if lmrMoveCounter >= 5:
                    if depth <= 2.Ply:
                        continue
                    if depth <= 5.Ply:
                        newDepth -= 1.Ply

            # futility reduction
            if beta - originalAlpha <= 1 and moveCounter > 1:
                newDepth -= futilityReduction(originalAlpha - staticEval - position.see(move))
                if newDepth <= 0:
                    continue

        # first explore with null window
        if alpha > -valueInfinity and (hashResult.isEmpty or hashResult.bestMove != move or hashResult.nodeType == allNode):
            newBeta = alpha + 1

        if state.stop[].load or state.threadStop[].load or state.countedNodes >= state.maxNodes:
            if height > 0 or not state.hashTable[].get(position.zobristKey).isEmpty:
                if state.hashTable[].get(position.zobristKey).isEmpty:
                    break
                else:
                    return 0.Value

        let randomAddition = if height == 0:
            state.randState.rand(-anarchyParams(state.dl).maxRootRandAmplitude..anarchyParams(state.dl).maxRootRandAmplitude)
        else:
            0.Value
        
        var value = -newPosition.search(
            state,
            alpha = -newBeta, beta = -min(alpha - randomAddition, newBeta - 1),
            depth = newDepth - 1.Ply, height = height + 1.Ply,
            previous = move
        )
        if abs(value + randomAddition) < valueCheckmate:
            value += randomAddition

        # first re-search with increasing window and reduced depth
        while value >= newBeta and newBeta < beta:
            newBeta.increaseBeta(alpha, beta)
            value = -newPosition.search(
                state,
                alpha = -newBeta, beta = -min(alpha - randomAddition, newBeta - 1),
                depth = newDepth - 1.Ply, height = height + 1.Ply,
                previous = move
            )
            if abs(value + randomAddition) < valueCheckmate:
                value += randomAddition

        # re-search with full window and full depth
        if value > alpha and newDepth < depth:
            newDepth = depth
            value = -newPosition.search(
                state,
                alpha = -beta, beta = -min(alpha - randomAddition, newBeta - 1),
                depth = depth - 1.Ply, height = height + 1.Ply,
                previous = move
            )
            if abs(value + randomAddition) < valueCheckmate:
                value += randomAddition

        # under promotion bonus
        if height.isRootPlayer and
        move.promoted != noPiece and
        bestMove.promoted.value > move.promoted.value:
            value = -newPosition.search(
                state,
                alpha = -beta, beta = -originalAlpha,
                depth = depth - 1.Ply, height = height + 1.Ply,
                previous = move
            )
            if position.confidentInUnderpromotion(value, state.dl):
                # reset these values so it is as if we haven't found a better move yet
                bestValue = -valueInfinity
                alpha = originalAlpha
                nodeType = allNode
                

        if value > bestValue:
            bestValue = value
            bestMove = move

        if value >= beta:
            state.update(position, bestMove, previous, depth = depth, height = height, cutNode, value)
            return bestValue

        if value > alpha:
            nodeType = pvNode
            alpha = value
        else:
            state.historyTable[].update(move, previous, position.us, newDepth, weakMove = true)

    if moveCounter == 0:
        # checkmate
        if inCheck:
            bestValue = -(height.checkmateValue)
        # stalemate
        else:
            bestValue = 0.Value
    
    if skipMove == noMove:
        state.update(position, bestMove, previous, depth = depth, height = height, nodeType, bestValue)

    bestValue


func isCloudKingMove*(position: Position, move: Move): bool =
    countSetBits(position[position.us] and startpos[position.us]) == 15 and
    position.castlingAllowed(position.us) and
    (position.kingSquare(position.us).toBitboard and homeRank[position.us]) != 0 and
    move in position.legalMoves and
    move.moved == king


func cloudVariations*(position: Position): seq[Move] =
    let
        us = position.us
        kingSquare = position.kingSquare(us)

    if countSetBits(position[us] and startpos[us]) == 16 and
    (kingSquare.toBitboard and homeRank[us]) != 0:
        for move in position.legalMoves:
            if move.moved == pawn and
            (move.source.toBitboard and mask3x3[kingSquare]) != 0:
                # check if pawn can be captured
                # (we don't want that as we want to do could variations)
                let newPosition = position.doMove(move)
                if newPosition.getLeastValuableAttacker(move.target).piece == noPiece:
                    result.add move

    for move in position.legalMoves:
        if position.isCloudKingMove move:
            # check if we lose material immediately
            let newPosition = position.doMove(move)
            if newPosition.materialQuiesce == newPosition.material:
                result.add move

     
func searchNoExtraMoves*(position: Position, state: var SearchState, depth: Ply, skipMove = noMove): Value =
    position.search(
        state,
        alpha = -valueInfinity, beta = valueInfinity,
        depth = depth, height = 0,
        previous = noMove,
        skipMove = skipMove
    )           

func search*(
    position: Position,
    state: var SearchState,
    depth: Ply
): Value =


    result = position.searchNoExtraMoves(state, depth)


    template checkMoveWithBonus(move: Move, minValue: Value) =
        let newPosition = position.doMove(move)
        let value = -newPosition.searchNoExtraMoves(state, depth - 2.Ply)
        if value >= minValue and value.abs < valueInfinity:
            result = value
            state.hashTable[].add(position.zobristKey, pvNode, value, depth, move)
            return # returns for the function and not just the template

    if not state.threadStop[].load: # so that only the first search thread does this

        # do the cloud opening variations if possible
        if state.randState.rand(1.0) < anarchyParams(state.dl).probabilityCloudVariation.sqrt: # sqrt because to actually see a cloud variation we need to roll the dice for two moves
            var candidates = position.cloudVariations
            state.randState.shuffle candidates
            for i, move in candidates:
                if move.enPassantTarget == noSquare and i < candidates.len - 1 and state.randState.rand(1.0) < 0.3:
                    # only do non-double push in few cases
                    continue
                checkMoveWithBonus(move, anarchyParams(state.dl).minValueCloudVariation)

        # first check if I can take en passant
        for move in position.legalMoves:
            if move.capturedEnPassant:
                checkMoveWithBonus(move, anarchyParams(state.dl).minValueTakeEnPassant)

        # only if we can't take ourself, we try to offer en passant
        for move in position.legalMoves:
            if move.enPassantTarget != noSquare and (attackTablePawnCapture[position.us][move.enPassantTarget] and position[pawn] and position[position.enemy]) != 0:
                checkMoveWithBonus(move, anarchyParams(state.dl).minValueOfferEnPassant)
