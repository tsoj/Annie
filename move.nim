import
    types,
    bitboard,
    utils

type Move* = distinct uint32
# source: [0..6], target: [7..13], moved: [14..16], captured: [17..19], promoted: [20..22],
# castled: 23, capturedEnPassant: 24, enPassantTarget: [25..31]

func `==`*(a,b: Move): bool =
    cast[uint32](a) == cast[uint32](b)

template create*(
    move: var Move,
    source, target, enPassantTarget: Square,
    moved, captured, promoted: Piece,
    castled, capturedEnPassant: bool
) =
    move = cast[Move](0u32)
    move = cast[Move](cast[uint32](move) or (source.uint32 and 0b1111111))
    move = cast[Move](cast[uint32](move) or ((target.uint32 and 0b1111111) shl 7))
    move = cast[Move](cast[uint32](move) or ((moved.uint32 and 0b111) shl 14))
    move = cast[Move](cast[uint32](move) or ((captured.uint32 and 0b111) shl 17))
    move = cast[Move](cast[uint32](move) or ((promoted.uint32 and 0b111) shl 20))
    move = cast[Move](cast[uint32](move) or ((castled.uint32 and 0b1) shl 23))
    move = cast[Move](cast[uint32](move) or ((capturedEnPassant.uint32 and 0b1) shl 24))
    move = cast[Move](cast[uint32](move) or ((enPassantTarget.uint32 and 0b1111111) shl 25))

template source*(move: Move): Square =
    (cast[uint32](move) and 0b1111111).Square
template target*(move: Move): Square  =
    ((cast[uint32](move) shr 7) and 0b1111111).Square
template moved*(move: Move): Piece =
    ((cast[uint32](move) shr 14) and 0b111).Piece
template captured*(move: Move): Piece =
    ((cast[uint32](move) shr 17) and 0b111).Piece
template promoted*(move: Move): Piece =
    ((cast[uint32](move) shr 20) and 0b111).Piece
template castled*(move: Move): bool =
    ((cast[uint32](move) shr 23) and 0b1).bool
template capturedEnPassant*(move: Move): bool =
    ((cast[uint32](move) shr 24) and 0b1).bool
template enPassantTarget*(move: Move): Square =
    ((cast[uint32](move) shr 25) and 0b1111111).Square

const noMove*: Move = block:
    var move: Move
    move.create(noSquare, noSquare, noSquare, noPiece, noPiece, noPiece, false, false)
    move
static: doAssert noMove.source == noSquare
static: doAssert noMove.target == noSquare
static: doAssert noMove.moved == noPiece
static: doAssert noMove.captured == noPiece
static: doAssert noMove.promoted == noPiece
static: doAssert noMove.castled == false
static: doAssert noMove.capturedEnPassant == false
static: doAssert noMove.enPassantTarget == noSquare

template isCapture*(move: Move): bool =
    move.captured != noPiece

template isPromotion*(move: Move): bool =
    move.promoted != noPiece

template isTactical*(move: Move): bool =
    move.isCapture or move.isPromotion

template isPawnMoveToSecondRank*(move: Move): bool =
    (move.moved == pawn and (move.target.toBitboard and (ranks[a2] or ranks[a7])) != 0)

func `$`*(move: Move): string =
    result = $move.source & $move.target
    if move.promoted != noPiece:
        result &= move.promoted.notation