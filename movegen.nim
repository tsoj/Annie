import
    position,
    bitboard,
    move,
    types,
    castling

func generateCaptures(position: Position, piece: Piece, moves: var openArray[Move]): int =
    result = 0
    for source in position[position.us] and position[piece]:
        for target in piece.attackMask(source, position.occupancy) and position[position.enemy]:
            for captured in pawn..king:
                if (position[captured] and target.toBitboard) != 0:
                    moves[result].create(
                        source = source, target = target, enPassantTarget = noSquare,
                        moved = piece, captured = captured, promoted = noPiece,
                        castled = false, capturedEnPassant = false
                    )
                    result += 1
                    break

func generateQuiets(position: Position, piece: Piece, moves: var openArray[Move]): int =
    let occupancy = position.occupancy
    result = 0
    for source in position[position.us] and position[piece]:
        for target in piece.attackMask(source, occupancy) and (not occupancy):
            moves[result].create(
                source = source, target = target, enPassantTarget = noSquare,
                moved = piece, captured = noPiece, promoted = noPiece,
                castled = false, capturedEnPassant = false
            )
            result += 1

func generatePawnCaptures(position: Position, moves: var openArray[Move]): int =
    let
        us = position.us
        enemy = position.enemy
    result = 0

    proc addPromotions(moves: var openArray[Move], source, target: Square, counter: var int, captured = noPiece) =
        for promoted in knight..queen:
            moves[counter].create(
                source = source, target = target, enPassantTarget = noSquare,
                moved = pawn, captured = captured, promoted = promoted,
                castled = false, capturedEnPassant = false
            )
            counter += 1

    for source in position[pawn] and position[us]:
        # quiet promotions
        if (source.toBitboard and pawnHomeRank[enemy]) != 0 and (attackTablePawnQuiet[us][source] and position.occupancy) == 0:
            let target = attackTablePawnQuiet[us][source].toSquare
            moves.addPromotions(source, target, result)

        # captures
        for target in attackTablePawnCapture[us][source] and position[enemy]:
            for captured in pawn..king:
                if (position[captured] and target.toBitboard) != 0:
                    if (target.toBitboard and homeRank[enemy]) != 0:
                        moves.addPromotions(source, target, result, captured)
                    else:
                        moves[result].create(
                            source = source, target = target, enPassantTarget = noSquare,
                            moved = pawn, captured = captured, promoted = noPiece,
                            castled = false, capturedEnPassant = false
                        )
                        result += 1
                    break

        # en passant capture
        let attackMask = attackTablePawnCapture[us][source] and position.enPassantCastling and (ranks[a3] or ranks[a6])
        if attackMask != 0:
            let target = attackMask.toSquare
            moves[result].create(
                source = source, target = target, enPassantTarget = noSquare,
                moved = pawn, captured = pawn, promoted = noPiece,
                castled = false, capturedEnPassant = true
            )
            result += 1

func generatePawnQuiets(position: Position, moves: var openArray[Move]): int =
    let
        us = position.us
        occupancy = position.occupancy
    result = 0
    for source in position[pawn] and position[us]:
        if (attackTablePawnQuiet[us][source] and (occupancy or homeRank[position.enemy])) == 0:
            let target = attackTablePawnQuiet[us][source].toSquare
            moves[result].create(
                source = source, target = target, enPassantTarget = noSquare,
                moved = pawn, captured = noPiece, promoted = noPiece,
                castled = false, capturedEnPassant = false
            )
            result += 1

            # double pushs
            if (source.toBitboard and pawnHomeRank[us]) != 0:
                let doublePushTarget = attackTablePawnQuiet[us][target].toSquare
                if (doublePushTarget.toBitboard and occupancy) == 0:
                    moves[result].create(
                        source = source, target = doublePushTarget, enPassantTarget = target,
                        moved = pawn, captured = noPiece, promoted = noPiece,
                        castled = false, capturedEnPassant = false
                    )
                    result += 1

func generateCastlingMoves(position: Position, moves: var openArray[Move]): int =
    let
        us = position.us
        enemy = position.enemy
        occupancy = position.occupancy
        kingSource = (position[us] and position[king]).toSquare

    result = 0
    for (castlingSide, rookSource) in position.rookSource[us].pairs:
        # castling is still allowed
        if (position.enPassantCastling and rookSource.toBitboard and homeRank[us]) == 0:
            continue

        # all necessary squares are empty
        if (blockSensitive(us, castlingSide, kingSource, rookSource) and occupancy) != 0:
            continue

        # king will never be in check
        var kingInCheck = false
        for checkSquare in checkSensitive[us][castlingSide][kingSource]:
            if position.isAttacked(us, enemy, checkSquare):
                kingInCheck = true
                break
        if kingInCheck:
            continue

        moves[result].create(
            source = kingSource, target = rookSource, enPassantTarget = noSquare,
            moved = king, captured = noPiece, promoted = noPiece,
            castled = true, capturedEnPassant = false
        )
        result += 1

func generateCaptures*(position: Position, moves: var openArray[Move]): int =
    result = position.generatePawnCaptures(moves)
    for piece in knight..king:
        result += position.generateCaptures(piece, moves.toOpenArray(result, moves.len - 1))

func generateQuiets*(position: Position, moves: var openArray[Move]): int =
    result = position.generatePawnQuiets(moves)
    result += position.generateCastlingMoves(moves.toOpenArray(result, moves.len - 1))
    for piece in knight..king:
        result += position.generateQuiets(piece, moves.toOpenArray(result, moves.len - 1))

func generateMoves*(position: Position, moves: var openArray[Move]): int =
    result = position.generateCaptures(moves)
    result += position.generateQuiets(moves.toOpenArray(result, moves.len - 1))
