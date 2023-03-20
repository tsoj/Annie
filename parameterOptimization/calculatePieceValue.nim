import
    ../types,
    ../position,
    ../positionUtils,
    ../evaluation,
    ../bitboard,
    ../evalParameters,
    dataUtils

when isMainModule:
    import ../defaultParameters

func getPieceValue(piece: Piece, evalParameters: EvalParameters, data: seq[Entry]): Value =
    var sum: int64 = 0
    var numPieceEvals: int64 = 0
    for entry in data:
        let position = entry.position
        let startEval = position.absoluteEvaluate(evalParameters)
        for square in position[piece]:
            let us = position.coloredPiece(square).color
            assert position.coloredPiece(square).piece == piece
            var newPosition = position
            newPosition.removePiece(us, piece, square.toBitboard)
            var diff = startEval - newPosition.absoluteEvaluate(evalParameters)
            if us == black:
                diff *= -1
            if piece == rook and diff < 0.Value:
                debugEcho position
                debugEcho square
                debugEcho piece
                debugEcho diff
                doAssert diff >= 0.Value
            sum += diff.int
            numPieceEvals += 1
    (sum div numPieceEvals).Value

proc printPieceValues*(evalParameters: EvalParameters) =
    var data: seq[Entry]
    data.loadData("quietSetZuri.epd")
    data.loadData("quietSetNalwald.epd")
    data.loadData("quietSetCombinedCCRL4040.epd")
    data.loadData("quietSmallPoolGamesNalwald.epd")
    data.loadData("quietSetNalwald2.epd")
    echo "Piece values:"
    for piece in pawn..queen:
        echo piece, ": ", getPieceValue(piece, evalParameters, data)

when isMainModule:
    printPieceValues(defaultEvalParameters)