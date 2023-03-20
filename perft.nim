import
    types,
    position,
    positionUtils,
    move,
    movegen,
    moveIterator,
    strutils,
    times,
    random

var randomMoves = newSeq[Move](10000)

func perft*(
    position: Position,
    depth: int, height: int = 0,
    testZobristKeys = false,
    testPseudoLegality = false,
    printMoveNodes = false
): uint64 =
    if depth == 0:
        return 1

    var nodes: uint64 = 0

    var claimedPseudoLegalMoves: seq[Move]
    if testPseudoLegality:
        {.cast(noSideEffect).}:
            for move in randomMoves:
                if position.isPseudoLegal(move):
                    claimedPseudoLegalMoves.add(move)

    for move in position.moveIterator:
        if testPseudoLegality:
            doAssert position.isPseudoLegal(move)
            for claimedMove in claimedPseudoLegalMoves.mitems:
                if claimedMove == move:
                    claimedMove = noMove
            {.cast(noSideEffect).}:
                randomMoves[rand(0..<randomMoves.len)] = move

        let newPosition = position.doMove(move)

        if testZobristKeys:
            doAssert newPosition.zobristKey == newPosition.calculateZobristKey

        if not newPosition.inCheck(position.us):
            let n = newPosition.perft(
                depth - 1, height + 1,
                testZobristKeys = testZobristKeys,
                testPseudoLegality = testPseudoLegality
            )                
            nodes += n

            if printMoveNodes:
                debugEcho "    ", move, " ", n, " ", newPosition.fen

    if testPseudoLegality:
        for claimedMove in claimedPseudoLegalMoves:
            doAssert claimedMove == noMove
    nodes

func fastPerft*(position: Position, depth: int): uint64 =
    if depth <= 0:
        return 1
    var moves: array[maxNumMoves, Move]
    let numMoves = position.generateMoves(moves)
    for i in 0..<numMoves:
        template move: Move = moves[i]
        let newPosition = position.doMove(move)
        if not newPosition.inCheck(position.us):
            result += newPosition.fastPerft(depth - 1)

type PerftData = object
    position: Position
    nodes: seq[uint64]

proc getPerftTestData(useInternal, useExternal: bool): seq[PerftData] =

    var lines = if useInternal:
        @[
            # classical positions
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w QKqk - 0 1,48,2039,97862,4085603,193690690",
            "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1,14,191,2812,43238,674624,11030083,178633661",
            "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w qk - 0 1,6,264,9467,422333,15833292",
            "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w QK - 1 8,44,1486,62379,2103487,89941194",
            "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10,46,2079,89890,3894594,164075551",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w QKqk -,20,400,8902,197281,4865609,119060324",
            # Chess960 positions
            "rnbqkbrn/p1pp1pp1/4p3/7p/2p4P/2P5/PP1PPPP1/R1BQKBRN w QGqg - 0 9,17,445,9076,255098,5918310,174733195",
            "b1rkrbnq/1pp1pppp/2np4/p5N1/8/1P2P3/P1PP1PPP/BNRKRB1Q w CEce - 0 9,37,740,27073,581744,21156664,485803600",
            "nrknbrqb/3p1ppp/ppN1p3/8/6P1/8/PPPPPP1P/1RKNBRQB w BFbf - 0 9,32,526,17267,319836,10755190,220058991",
            "bbqrnnkr/1ppp1p1p/5p2/p5p1/P7/1P4P1/2PPPP1P/1BQRNNKR w DKdk - 0 9,20,322,7224,145818,3588435,82754650"

        ]
    else:
        @[]

    var file: File
    if useExternal and file.open("./perft_test.txt"):
        var line: string
        while file.readLine(line):
            if line.isEmptyOrWhitespace:
                continue
            lines.add(line)
        file.close

    for line in lines:
        var words = line.split(',')
        doAssert words.len >= 1
        result.add(PerftData(position: words[0].toPosition, nodes: newSeq[uint64](0)))
        for i in 1..<words.len:
            result[^1].nodes.add(words[i].parseBiggestUInt)


proc perftTest*(
    maxNodes = uint64.high,
    testZobristKeys = true,
    testPseudoLegality = false,
    useInternal = true,
    useExternal = true
) =

    let data = getPerftTestData(useInternal = useInternal, useExternal = useExternal)
    
    var totalPassedMilliseconds: int64 = 0
    var totalNumNodes: uint64 = 0
        
    for perftData in data:
        echo "---------------\nTesting ", perftData.position.fen
        for depth in 0..<perftData.nodes.len:
            if perftData.nodes[depth] > maxNodes:
                break

            let start = now()
            let perftResult = perftData.position.perft(
                depth + 1,
                testZobristKeys = testZobristKeys,
                testPseudoLegality = testPseudoLegality
            )
            let passedTime = now() - start
            totalPassedMilliseconds += passedTime.inMilliseconds
            totalNumNodes += perftResult

            echo perftResult, (if perftResult == perftData.nodes[depth]: " == " else: " != "), perftData.nodes[depth]
            doAssert perftResult == perftData.nodes[depth], "Failed perft test"

    echo "---------------\nPassed time: ", totalPassedMilliseconds, " ms"
    echo "Counted nodes: ", totalNumNodes
    echo "Nodes per second: ", (1000 * totalNumNodes) div max(1, totalPassedMilliseconds).uint64, " nps"
    
    echo "Finished perft test successfully"

