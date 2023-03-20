import
    types,
    position,
    move,
    movegen,
    utils,
    bitboard,
    castling,
    strutils,
    options



func legalMoves*(position: Position): seq[Move] =
    var moveArray: array[maxNumMoves, Move]
    let numMoves = position.generateMoves(moveArray)
    for i in 0..<numMoves:
        let newPosition = position.doMove(moveArray[i])
        if newPosition.inCheck(position.us):
            continue
        result.add(moveArray[i])

func isChess960*(position: Position): bool =
    let us = position.us
    (position.enPassantCastling and homeRank[us]) != 0 and
    (position.rookSource != classicalRookSource or position.kingSquare(us) != classicalKingSource[us])

func toMove*(s: string, position: Position): Move =

    if s.len != 4 and s.len != 5:
        raise newException(ValueError, "Move string is wrong length: " & s)

    let
        source = parseEnum[Square](s[0..1])
        target = parseEnum[Square](s[2..3])
        promoted = if s.len == 5: s[4].toColoredPiece.piece else: noPiece

    for move in position.legalMoves:
        if move.source == source and move.promoted == promoted:
            if move.target == target:
                return move
            if move.castled and target == kingTarget[position.us][position.castlingSide(move)] and not position.isChess960:
                return move
    raise newException(ValueError, "Move is illegal: " & s)

proc toPosition*(fen: string, suppressWarnings = false): Position =
    var fenWords = fen.splitWhitespace()    
    if fenWords.len < 4:
        raise newException(ValueError, "FEN must have at least 4 words")
    if fenWords.len > 6 and not suppressWarnings:
        echo "Warning: FEN shouldn't have more than 6 words"
    while fenWords.len < 6:
        fenWords.add("0")   

    let piecePlacement = fenWords[0]
    let activeColor = fenWords[1]
    let castlingRights = fenWords[2]
    let enPassant = fenWords[3]
    let fiftyMoveRuleHalfmoveClock = fenWords[4]
    let fullmoveNumber = fenWords[5]

    var currentSquare = a8
    for pieceChar in piecePlacement:
        case pieceChar
        of '/':
            currentSquare = ((currentSquare).int8 - 16).Square
        of '8', '7', '6', '5', '4', '3', '2', '1':
            currentSquare = (currentSquare.int8 + parseInt($pieceChar)).Square
        else:
            if currentSquare > h8 or currentSquare < a1:
                raise newException(ValueError, "FEN piece placement is not correctly formatted: " & $currentSquare)
            try:
                result.addColoredPiece(pieceChar.toColoredPiece, currentSquare)
            except ValueError:
                raise newException(ValueError, "FEN piece placement is not correctly formatted: " &
                        getCurrentExceptionMsg())
            currentSquare = (currentSquare.int8 + 1).Square
    
    # active color
    case activeColor
    of "w", "W":
        result.us = white
        result.enemy = black
    of "b", "B":
        result.us = black
        result.enemy = white
    else:
        raise newException(ValueError, "FEN active color notation does not exist: " & activeColor)

    # castling rights
    result.enPassantCastling = 0
    result.rookSource = [[d4,d4],[d4,d4]] # d4 should be ignored by castling and enpassant
    for castlingChar in castlingRights:
        let castlingChar = case castlingChar:
        of '-':
            continue
        of 'K':
            'H'
        of 'k':
            'h'
        of 'Q':
            'A'
        of 'q':
            'a'
        else:
            castlingChar

        let
            us = if castlingChar.isUpperAscii: white else: black
            kingSquare = (result[us] and result[king]).toSquare
            rookSource = (files[parseEnum[Square](castlingChar.toLowerAscii & "1")] and homeRank[us]).toSquare
            castlingSide = if rookSource < kingSquare: queenside else: kingside
        
        result.enPassantCastling = result.enPassantCastling or rookSource.toBitboard
        result.rookSource[us][castlingSide] = rookSource

    # en passant square
    if enPassant != "-":
        try:
            result.enPassantCastling = result.enPassantCastling or parseEnum[Square](enPassant.toLowerAscii).toBitboard
        except ValueError:
            raise newException(ValueError, "FEN en passant target square is not correctly formatted: " &
                    getCurrentExceptionMsg())

    # halfmove clock and fullmove number
    try:
        result.fiftyMoveRuleHalfmoveClock = parseUInt(fiftyMoveRuleHalfmoveClock).int16
    except ValueError:
        raise newException(ValueError, "FEN halfmove clock is not correctly formatted: " & getCurrentExceptionMsg())

    try:
        result.halfmovesPlayed = parseUInt(fullmoveNumber).int16 * 2
    except ValueError:
        raise newException(ValueError, "FEN fullmove number is not correctly formatted: " & getCurrentExceptionMsg())

    result.zobristKey = result.calculateZobristKey

func fen*(position: Position): string =
    result = ""
    var emptySquareCounter = 0
    for rank in countdown(7, 0):
        for file in 0..7:
            let square = (rank*8 + file).Square
            let coloredPiece = position.coloredPiece(square)
            if coloredPiece.piece != noPiece and coloredPiece.color != noColor:
                if emptySquareCounter > 0:
                    result &= $emptySquareCounter
                    emptySquareCounter = 0
                result &= coloredPiece.notation
            else:
                emptySquareCounter += 1
        if emptySquareCounter > 0:
            result &= $emptySquareCounter
            emptySquareCounter = 0
        if rank != 0:
            result &= "/"
            
    result &= (if position.us == white: " w " else: " b ")

    for color in [white, black]:
        for castlingSide in queenside..kingside:
            let rookSource = position.rookSource[color][castlingSide]
            if (position.enPassantCastling and rookSource.toBitboard and homeRank[color]) != 0:
                result &= ($rookSource)[0]

                if result[^1] == 'h':
                    result[^1] = 'k'
                if result[^1] == 'a':
                    result[^1] = 'q'

                if color == white:
                    result[^1] = result[^1].toUpperAscii
                
    if result.endsWith(' '):
        result &= "-"

    result &= " "

    if (position.enPassantCastling and (ranks[a3] or ranks[a6])) != 0:
        result &= $((position.enPassantCastling and (ranks[a3] or ranks[a6])).toSquare)
    else:
        result &= "-"

    result &= " " & $position.fiftyMoveRuleHalfmoveClock & " " & $(position.halfmovesPlayed div 2)

func `$`*(position: Position): string =
    result = boardString(proc (square: Square): Option[string] =
        if (square.toBitboard and position.occupancy) != 0:
            return some($position.coloredPiece(square))
        none(string)
    ) & "\n"
    let fenWords = position.fen.splitWhitespace
    for i in 1..<fenWords.len:
        result &= fenWords[i] & " "

func debugString*(position: Position): string =    
    for piece in pawn..king:
        result &= $piece & ":\n"
        result &= position[piece].bitboardString & "\n"
    for color in white..black:
        result &= $color & ":\n"
        result &= position[color].bitboardString & "\n"
    result &= "enPassantCastling:\n"
    result &= position.enPassantCastling.bitboardString & "\n"
    result &= "us: " & $position.us & ", enemy: " & $position.enemy & "\n"
    result &= "halfmovesPlayed: " & $position.halfmovesPlayed & ", fiftyMoveRuleHalfmoveClock: " & $position.fiftyMoveRuleHalfmoveClock & "\n"
    result &= "zobristKey: " & $position.zobristKey & "\n"
    result &= "rookSource: " & $position.rookSource

func notation*(move: Move, position: Position): string =
    if move.castled and not position.isChess960:
        return $move.source & $kingTarget[position.us][position.castlingSide(move)]
    $move

func notation*(pv: seq[Move], position: Position): string =
    var currentPosition = position
    for move in pv:
        result &= move.notation(currentPosition) & " "
        currentPosition = currentPosition.doMove(move)

func insufficientMaterial*(position: Position): bool =
    (position[pawn] or position[rook] or position[queen]) == 0 and (position[bishop] or position[knight]).countSetBits <= 1

const startpos* = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition

proc standardizedFEN*(fen: string): string =
    fen.toPosition.fen