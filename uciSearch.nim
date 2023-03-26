import
    types,
    move,
    position,
    positionUtils,
    timeManagedSearch,
    hashTable,
    evaluation,
    anarchyParameters

import std/[
    atomics,
    times,
    strformat,
    strutils,
    math,
    algorithm
]


func infoString(
    iteration: int,
    value: Value,
    nodes: uint64,
    time: Duration,
    hashFull: int,
    pv: string,
    multiPvIndex = -1
): string =
    var scoreString = " score cp " & fmt"{value.toCp:>4}"
    if abs(value) >= valueCheckmate:
        if value < 0:
            scoreString = " score mate -"
        else:
            scoreString = " score mate "
        scoreString &= $(value.plysUntilCheckmate.float / 2.0).ceil.int

    let nps = 1000*(nodes div (time.inMilliseconds.uint64 + 1))

    result = "info"
    if multiPvIndex != -1:
        result &= " multipv " & fmt"{multiPvIndex:>2}"
    result &= " depth " & fmt"{iteration+1:>2}"
    result &= " time " & fmt"{time.inMilliseconds:>6}"
    result &= " nodes " & fmt"{nodes:>9}"
    result &= " nps " & fmt"{nps:>7}"
    result &= " hashfull " & fmt"{hashFull:>5}"
    result &= scoreString
    result &= " pv " & pv

func bestMoveString(move: Move, position: Position): string =
    let moveNotation = move.notation(position)
    if move in position.legalMoves:
        return "bestmove " & moveNotation
    else:
        result = "info string found illegal move: " & moveNotation & "\n"
        if position.legalMoves.len > 0:
            result &= "bestmove "  & position.legalMoves[0].notation(position)
        else:
            result &= "info string no legal move available"
        

type SearchInfo* = object
    position*: Position
    hashTable*: ptr HashTable
    positionHistory*: seq[Position]
    targetDepth*: Ply
    stop*: ptr Atomic[bool]
    movesToGo*: int16
    increment*, timeLeft*: array[white..black, Duration]
    moveTime*: Duration
    multiPv*: int
    searchMoves*: seq[Move]
    numThreads*: int
    nodes*: uint64
    difficultyLevel*: DifficultyLevel

proc uciSearchSinglePv(searchInfo: SearchInfo) =
    var
        bestMove = noMove
        iteration = 0

    for (value, pv, nodes, passedTime) in searchInfo.position.iterativeTimeManagedSearch(
        searchInfo.hashTable[],
        searchInfo.positionHistory,
        searchInfo.targetDepth,
        searchInfo.stop,
        movesToGo = searchInfo.movesToGo,
        increment = searchInfo.increment,
        timeLeft = searchInfo.timeLeft,
        moveTime = searchInfo.moveTime,
        numThreads = searchInfo.numThreads,
        maxNodes = searchInfo.nodes,
        difficultyLevel = searchInfo.difficultyLevel
    ):
        doAssert pv.len >= 1
        bestMove = pv[0]

        # uci info
        echo iteration.infoString(
            value,
            nodes,
            passedTime,
            searchInfo.hashTable[].hashFull,
            pv.notation(searchInfo.position)
        )

        iteration += 1

    echo bestMove.bestMoveString(searchInfo.position)

type SearchResult = object
    move: Move
    value: Value
    pv: seq[Move]
    nodes: uint64
    passedTime: Duration

proc uciSearch*(searchInfo: SearchInfo) =

    if searchInfo.multiPv <= 0:
        return

    if searchInfo.multiPv == 1 and searchInfo.searchMoves.len == 0:
        searchInfo.uciSearchSinglePv()
        return

    var searchMoves = searchInfo.searchMoves
    if searchMoves.len == 0:
        for move in searchInfo.position.legalMoves():
            searchMoves.add move

    var iterators: seq[iterator (): SearchResult{.closure, gcsafe.}]

    for move in searchMoves:
        var newPositionHistory = searchInfo.positionHistory
        newPositionHistory.add searchInfo.position
        let newPosition = searchInfo.position.doMove(move)
        proc genIter(newPosition: Position, move: Move): iterator (): SearchResult{.closure, gcsafe.} =
            return iterator(): SearchResult{.closure, gcsafe.} =
                for (value, pv, nodes, passedTime) in iterativeTimeManagedSearch(
                    newPosition,
                    searchInfo.hashTable[],
                    newPositionHistory,
                    searchInfo.targetDepth - 1.Ply,
                    searchInfo.stop,
                    movesToGo = searchInfo.movesToGo,
                    increment = searchInfo.increment,
                    timeLeft = searchInfo.timeLeft,
                    moveTime = searchInfo.moveTime,
                    numThreads = searchInfo.numThreads,
                    maxNodes = searchInfo.nodes,
                    difficultyLevel = searchInfo.difficultyLevel
                ):
                    yield SearchResult(move: move, value: value, pv: pv, nodes: nodes, passedTime: passedTime)
        iterators.add genIter(newPosition, move)
        
    var
        iteration = 1
        bestMove = noMove

    while true:
        
        var searchResults: seq[SearchResult]
        for iter in iterators:
            searchResults.add iter()
            searchResults[^1].value *= -1
            searchResults[^1].pv.insert(searchResults[^1].move, 0)
        
        for iter in iterators:
            if iter.finished:
                echo bestMove.bestMoveString(searchInfo.position)
                return

        searchResults.sort do (x, y: auto) -> int: cmp(y.value, x.value)

        for i, searchResult in searchResults.pairs:
            if i+1 > searchInfo.multiPv:
                break
            echo iteration.infoString(
                searchResult.value,
                searchResult.nodes,
                searchResult.passedTime,
                searchInfo.hashTable[].hashFull,
                searchResult.pv.notation(searchInfo.position),
                i+1,
            )

        doAssert searchResults.len > 0
        let bestPv = searchResults[0].pv
        doAssert bestPv.len >= 1
        bestMove = bestPv[0]

        iteration += 1

