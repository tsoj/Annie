import
    types,
    bitboard,
    move,
    zobristBitmasks,
    castling,
    bitops

type Position* = object
    pieces: array[pawn..king, Bitboard]
    colors: array[white..black, Bitboard]
    enPassantCastling*: Bitboard
    rookSource*: array[white..black, array[CastlingSide, Square]]
    zobristKey*: uint64
    us*, enemy*: Color
    halfmovesPlayed*: int16
    fiftyMoveRuleHalfmoveClock*: int16

func `[]`*(position: Position, piece: Piece): Bitboard {.inline.} =
    position.pieces[piece]

func `[]=`*(position: var Position, piece: Piece, bitboard: Bitboard) {.inline.} =
    position.pieces[piece] = bitboard

func `[]`*(position: Position, color: Color): Bitboard {.inline.} =
    position.colors[color]

func `[]=`*(position: var Position, color: Color, bitboard: Bitboard) {.inline.} =
    position.colors[color] = bitboard

func addPiece*(position: var Position, color: Color, piece: Piece, target: Bitboard) {.inline.} =
    position[piece] = position[piece] or target
    position[color] = position[color] or target

func removePiece*(position: var Position, color: Color, piece: Piece, source: Bitboard) {.inline.} =
    position[piece] = position[piece] and (not source)
    position[color] = position[color] and (not source)

func movePiece*(position: var Position, color: Color, piece: Piece, source, target: Bitboard) {.inline.} =
    position.removePiece(color, piece, source)
    position.addPiece(color, piece, target)

func castlingSide*(position: Position, move: Move): CastlingSide =
    if move.target == position.rookSource[position.us][queenside]:
        return queenside
    kingside

func occupancy*(position: Position): Bitboard =
    position[white] or position[black]

func attackers(position: Position, us, enemy: Color, target: Square): Bitboard =
    let occupancy = position.occupancy
    (
        (bishop.attackMask(target, occupancy) and (position[bishop] or position[queen])) or
        (rook.attackMask(target, occupancy) and (position[rook] or position[queen])) or
        (knight.attackMask(target, occupancy) and position[knight]) or
        (king.attackMask(target, occupancy) and position[king]) or
        (attackTablePawnCapture[us][target] and position[pawn])
    ) and position[enemy]

func isAttacked*(position: Position, us, enemy: Color, target: Square): bool =
    position.attackers(us, enemy, target) != 0

func isPseudoLegal*(position: Position, move: Move): bool =
    if move == noMove:
        return false

    let
        target = move.target
        source = move.source
        moved = move.moved
        captured = move.captured
        enPassantTarget = move.enPassantTarget
        capturedEnPassant = move.capturedEnPassant
        us = position.us
        enemy = position.enemy
        occupancy = position.occupancy
    assert source != noSquare and target != noSquare and moved != noPiece

    if (source.toBitboard and position[us] and position[moved]) == 0:
        return false
    
    if (target.toBitboard and position[us]) != 0 and not move.castled:
        return false

    if captured != noPiece and (target.toBitboard and position[enemy] and position[captured]) == 0 and not capturedEnPassant:
        return false

    if captured == noPiece and  (target.toBitboard and position[enemy]) != 0:
        return false

    if moved == pawn and captured == noPiece and 
    ((occupancy and target.toBitboard) != 0 or (enPassantTarget != noSquare and (enPassantTarget.toBitboard and occupancy) != 0)):
        return false

    if capturedEnPassant and (target.toBitboard and position.enPassantCastling and not(ranks[a1] or ranks[a8])) == 0:
        return false

    if (moved == bishop or moved == rook or moved == queen) and
    (target.toBitboard and moved.attackMask(source, occupancy)) == 0:
        return false

    if moved == pawn:
        if captured != noPiece and (target.toBitboard and attackTablePawnCapture[us][source]) == 0:
            return false
        elif captured == noPiece and (target.toBitboard and attackTablePawnQuiet[us][source]) == 0 and
        (
            (attackTablePawnQuiet[enemy][target] and attackTablePawnQuiet[us][source]) == 0 or
            (occupancy and attackTablePawnQuiet[us][source]) != 0
        ):
            return false

    if move.castled:
        if (position.enPassantCastling and homeRank[us]) == 0:
            return false

        if not (target in position.rookSource[us]):
            return false

        let castlingSide = position.castlingSide(move)
        
        let
            kingSource = (position[us] and position[king]).toSquare
            rookSource = position.rookSource[us][castlingSide]

        if (position.enPassantCastling and rookSource.toBitboard) == 0 or
        (blockSensitive(us, castlingSide, kingSource, rookSource) and occupancy) != 0:
            return false

        for checkSquare in checkSensitive[us][castlingSide][kingSource]:
            if position.isAttacked(us, enemy, checkSquare):
                return false
    true

func calculateZobristKey*(position: Position): uint64 =
    result = 0
    for piece in pawn..king:
        for square in position[piece]:
            result = result xor (if (position[white] and square.toBitboard) != 0:
                zobristPieceBitmasks[white][piece][square]
            else:
                zobristPieceBitmasks[black][piece][square]
            )
    result = result xor position.enPassantCastling xor zobristSideToMoveBitmasks[position.us]

func doMoveInPlace*(position: var Position, move: Move) {.inline.} =
    assert position.isPseudoLegal(move)
    let
        target = move.target
        source = move.source
        moved = move.moved
        captured = move.captured
        promoted = move.promoted
        enPassantTarget = move.enPassantTarget
        us = position.us
        enemy = position.enemy

    position.zobristKey = position.zobristKey xor cast[uint64](position.enPassantCastling)
    position.enPassantCastling = position.enPassantCastling and (ranks[a1] or ranks[a8])
    position.enPassantCastling = position.enPassantCastling and (not (source.toBitboard or target.toBitboard))
    if enPassantTarget != noSquare:
        position.enPassantCastling = position.enPassantCastling or enPassantTarget.toBitboard
    if moved == king:
        position.enPassantCastling = position.enPassantCastling and not homeRank[us]
    position.zobristKey = position.zobristKey xor cast[uint64](position.enPassantCastling)

    # en passant
    if move.capturedEnPassant:
        position.removePiece(enemy, pawn, attackTablePawnQuiet[enemy][target])
        position.movePiece(us, pawn, source.toBitboard, target.toBitboard)

        let capturedSquare = attackTablePawnQuiet[enemy][target].toSquare
        position.zobristKey = position.zobristKey xor zobristPieceBitmasks[enemy][pawn][capturedSquare]
    # removing captured piece
    elif captured != noPiece:
        position.removePiece(enemy, captured, target.toBitboard)
        position.zobristKey = position.zobristKey xor zobristPieceBitmasks[enemy][captured][target]

    # castling
    if move.castled:
        let
            rookSource = target
            kingSource = source
            castlingSide = position.castlingSide(move)
            rookTarget = rookTarget[us][castlingSide]
            kingTarget = kingTarget[us][castlingSide]
        
        position.removePiece(us, king, kingSource.toBitboard)
        position.removePiece(us, rook, rookSource.toBitboard)

        for (piece, source, target) in [
            (king, kingSource, kingTarget),
            (rook, rookSource, rookTarget)
        ]:
            position.addPiece(us, piece, target.toBitboard)
            position.zobristKey = position.zobristKey xor zobristPieceBitmasks[us][piece][source]
            position.zobristKey = position.zobristKey xor zobristPieceBitmasks[us][piece][target]

    # moving piece
    else:
        position.zobristKey = position.zobristKey xor zobristPieceBitmasks[us][moved][source]
        if promoted != noPiece:
            position.removePiece(us, moved, source.toBitboard)
            position.addPiece(us, promoted, target.toBitboard)
            position.zobristKey = position.zobristKey xor zobristPieceBitmasks[us][promoted][target]
        else:
            position.movePiece(us, moved, source.toBitboard, target.toBitboard)
            position.zobristKey = position.zobristKey xor zobristPieceBitmasks[us][moved][target]

    position.halfmovesPlayed += 1 
    position.fiftyMoveRuleHalfmoveClock += 1
    if moved == pawn or captured != noPiece:
        position.fiftyMoveRuleHalfmoveClock = 0

    position.enemy = position.us
    position.us = position.us.opposite
    
    position.zobristKey = position.zobristKey xor zobristSideToMoveBitmasks[white]
    position.zobristKey = position.zobristKey xor zobristSideToMoveBitmasks[black]

func doMove*(position: Position, move: Move): Position {.inline.} =
    result = position
    result.doMoveInPlace(move)

func doNullMoveInplace*(position: var Position) =
    position.zobristKey = position.zobristKey xor position.enPassantCastling
    position.enPassantCastling = position.enPassantCastling and (ranks[a1] or ranks[a8])
    position.zobristKey = position.zobristKey xor position.enPassantCastling

    position.zobristKey = position.zobristKey xor zobristSideToMoveBitmasks[white]
    position.zobristKey = position.zobristKey xor zobristSideToMoveBitmasks[black]

    position.fiftyMoveRuleHalfmoveClock = 0

    position.enemy = position.us
    position.us = position.us.opposite

func doNullMove*(position: Position): Position {.inline.} =
    result = position
    result.doNullMoveInplace

func kingSquare*(position: Position, color: Color): Square =
    assert (position[king] and position[color]).countSetBits == 1
    (position[king] and position[color]).toSquare

func inCheck*(position: Position, us: Color): bool =
    position.isAttacked(us, us.opposite, position.kingSquare(us))

func isLegal*(position: Position, move: Move): bool =
    if not position.isPseudoLegal(move):
        return false
    let newPosition = position.doMove(move)
    return not newPosition.inCheck(us = position.us)

func coloredPiece*(position: Position, square: Square): ColoredPiece =
    for color in white..black:
        for piece in pawn..king:
            if (square.toBitboard and position[piece] and position[color]) != 0:
                return ColoredPiece(piece: piece, color: color)
    ColoredPiece(piece: noPiece, color: noColor)

func addColoredPiece*(position: var Position, coloredPiece: ColoredPiece, square: Square) =
    for color in [white, black]:
        position[color] = position[color] and (not square.toBitboard)
    for piece in pawn..king:
        position[piece] = position[piece] and (not square.toBitboard)

    position.addPiece(coloredPiece.color, coloredPiece.piece, square.toBitboard)

func isPassedPawn*(position: Position, us, enemy: Color, square: Square): bool {.inline.} =
    (isPassedMask[us][square] and position[pawn] and position[enemy]) == 0

func isPassedPawnMove*(newPosition: Position, move: Move): bool =
    move.moved == pawn and newPosition.isPassedPawn(newPosition.enemy, newPosition.us, move.target)

func gamePhase*(position: Position): GamePhase =
    position.occupancy.countSetBits.GamePhase

func castlingAllowed*(position: Position, color: Color, castlingSide: CastlingSide): bool =
    (position.enPassantCastling and position.rookSource[color][castlingSide].toBitboard and homeRank[color]) != 0

func castlingAllowed*(position: Position, color: Color): bool =
    position.castlingAllowed(color, queenside) or position.castlingAllowed(color, kingside)

