import
    types,
    position,
    move,
    movegen,
    utils,
    bitboard,
    castling

export move, position

import std/[
    strutils,
    options,
    bitops
]

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
            if rookSource != noSquare and (rookSource.toBitboard and homeRank[color]) != 0:
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

    if position.enPassantTarget != 0:
        result &= $(position.enPassantTarget.toSquare)
    else:
        result &= "-"

    result &= " " & $position.halfmoveClock & " " & $(position.halfmovesPlayed div 2)

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
    result &= "enPassantTarget:\n"
    result &= position.enPassantTarget.bitboardString & "\n"
    result &= "us: " & $position.us & ", enemy: " & $position.enemy & "\n"
    result &= "halfmovesPlayed: " & $position.halfmovesPlayed & ", halfmoveClock: " & $position.halfmoveClock & "\n"
    result &= "zobristKey: " & $position.zobristKey & "\n"
    result &= "rookSource: " & $position.rookSource

func legalMoves*(position: Position): seq[Move] =
    var pseudoLegalMoves = newSeq[Move](64)
    while true:
        # 'generateMoves' silently stops generating moves if the given array is not big enough
        let numMoves = position.generateMoves(pseudoLegalMoves)
        if pseudoLegalMoves.len <= numMoves:
            pseudoLegalMoves.setLen(numMoves * 2)
        else:
            pseudoLegalMoves.setLen(numMoves)
            for move in pseudoLegalMoves:
                let newPosition = position.doMove(move)
                if newPosition.inCheck(position.us):
                    continue
                result.add move
            break

func isChess960*(position: Position): bool =
    for color in white..black:
        if position.rookSource[color] != [noSquare, noSquare] and position.kingSquare(color) != classicalKingSource[color]:
            return true
        for side in queenside..kingside:
            if position.rookSource[color][side] notin [noSquare, classicalRookSource[color][side]]:
                return true
    false

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
        echo "WARNING: FEN shouldn't have more than 6 words"
    while fenWords.len < 6:
        fenWords.add("0")

    for i in 2..8:
        fenWords[0] = fenWords[0].replace($i, repeat("1", i))

    let piecePlacement = fenWords[0]
    let activeColor = fenWords[1]
    let castlingRights = fenWords[2]
    let enPassant = fenWords[3]
    let halfmoveClock = fenWords[4]
    let fullmoveNumber = fenWords[5]

    var squareList = block:
        var squareList: seq[Square]
        for y in 0..7:
            for x in countdown(7, 0):
                squareList.add Square(y*8 + x) 
        squareList

    for pieceChar in piecePlacement:
        if squareList.len == 0:
            raise newException(ValueError, "FEN is not correctly formatted (too many squares)")

        case pieceChar
        of '/':
            # we don't need to do anything, except check if the / is at the right place
            if not squareList[^1].isLeftEdge:
                raise newException(ValueError, "FEN is not correctly formatted (misplaced '/')")
        of '1':
            discard squareList.pop
        of '0':
            if not suppressWarnings:
                echo "WARNING: '0' in FEN piece placement data is not official notation"
        else:
            doAssert pieceChar notin ['2', '3', '4', '5', '6', '7', '8']
            try:
                let sq = squareList.pop
                result.addColoredPiece(pieceChar.toColoredPiece, sq)
            except ValueError:
                raise newException(ValueError, "FEN piece placement is not correctly formatted: " &
                        getCurrentExceptionMsg())
            
    if squareList.len != 0:
        raise newException(ValueError, "FEN is not correctly formatted (too few squares)")
    
    # active color
    case activeColor
    of "w", "W":
        result.us = white
    of "b", "B":
        result.us = black
    else:
        raise newException(ValueError, "FEN active color notation does not exist: " & activeColor)

    # castling rights
    result.rookSource = [[noSquare, noSquare], [noSquare, noSquare]]
    for castlingChar in castlingRights:
        if castlingChar == '-':
            continue

        let
            us = if castlingChar.isUpperAscii: white else: black
            kingSquare = (result[us] and result[king]).toSquare

        let rookSource = case castlingChar:
        of 'K', 'k':
            var rookSource = kingSquare
            while rookSource.goRight:
                if (result[rook, us] and rookSource.toBitboard) != 0:
                    break
            rookSource
        of 'Q', 'q':
            var rookSource = kingSquare
            while rookSource.goLeft:
                if (result[rook, us] and rookSource.toBitboard) != 0:
                    break
            rookSource
        else:
            let rookSourceBit = files[parseEnum[Square](castlingChar.toLowerAscii & "1")] and homeRank[us]
        
            if rookSourceBit.countSetBits != 1:
                raise newException(ValueError, "FEN castling ambiguous or erroneous: " & activeColor)
            (files[parseEnum[Square](castlingChar.toLowerAscii & "1")] and homeRank[us]).toSquare

        let castlingSide = if rookSource < kingSquare: queenside else: kingside
        result.rookSource[us][castlingSide] = rookSource

    # en passant square
    result.enPassantTarget = 0
    if enPassant != "-":
        try:
            result.enPassantTarget = parseEnum[Square](enPassant.toLowerAscii).toBitboard
        except ValueError:
            raise newException(ValueError, "FEN en passant target square is not correctly formatted: " &
                    getCurrentExceptionMsg())

    # halfmove clock and fullmove number
    try:
        result.halfmoveClock = parseUInt(halfmoveClock).int16
    except ValueError:
        raise newException(ValueError, "FEN halfmove clock is not correctly formatted: " & getCurrentExceptionMsg())

    try:
        result.halfmovesPlayed = parseUInt(fullmoveNumber).int16 * 2
    except ValueError:
        raise newException(ValueError, "FEN fullmove number is not correctly formatted: " & getCurrentExceptionMsg())

    result.zobristKey = result.calculateZobristKey

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
