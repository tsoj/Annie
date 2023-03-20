import
    types,
    move,
    position,
    movegen,
    see,
    evaluation,
    searchUtils

const zeroHistoryTable = block:
    var h: HistoryTable
    h

iterator moveIterator*(
    position: Position,
    tryFirstMove = noMove,
    historyTable: HistoryTable = zeroHistoryTable,
    killers = [noMove, noMove, noMove],
    previous = noMove,
    doQuiets = true
): Move =
    type OrderedMoveList = object
        moves: array[maxNumMoves, Move]
        movePriorities: array[maxNumMoves, Value]
        numMoves: int

    template findBestMoves(moveList: var OrderedMoveList, minValue = Value.low) =
        while true:
            var bestIndex = moveList.numMoves
            var bestValue = minValue
            for i in 0..<moveList.numMoves:
                if moveList.movePriorities[i] > bestValue:
                    bestValue = moveList.movePriorities[i]
                    bestIndex = i
            if bestIndex != moveList.numMoves:
                moveList.movePriorities[bestIndex] = Value.low
                let move = moveList.moves[bestIndex]

                if move != tryFirstMove and move notin killers:
                    yield move
            else:
                break

    # hash move
    if position.isPseudoLegal(tryFirstMove):
        yield tryFirstMove

    # init capture moves
    var captureList {.noinit.}: OrderedMoveList
    captureList.numMoves = position.generateCaptures(captureList.moves)
    for i in 0..<captureList.numMoves:
        captureList.movePriorities[i] = position.see(captureList.moves[i])

    # winning captures
    captureList.findBestMoves(minValue = -2*pawn.value)

    # killers
    if doQuiets:
        for i in killers.low..killers.high:
            if position.isPseudoLegal(killers[i]) and killers[i] != tryFirstMove:
                yield killers[i]

    # quiet moves
    if doQuiets:
        var quietList {.noinit.}: OrderedMoveList
        quietList.numMoves = position.generateQuiets(quietList.moves)
        for i in 0..<quietList.numMoves:
            quietList.movePriorities[i] = historyTable.get(quietList.moves[i], previous, position.us)
                
        quietList.findBestMoves()
    
    # losing captures
    captureList.findBestMoves()
        
