import
    types,
    position,
    positionUtils,
    move,
    utils,
    bitboard,
    castling

import std/[
    strutils,
    strformat,
    tables,
    sugar
]

## Here the code may at times be less beautiful than it could be.
## The reason for that is, that I want to avoid string copies as much as possible
## to make this PGN parser fast enough.

func validSANMove(position: Position, move: Move, san: string): bool =

    # TODO optimize (avoid string copies)

    if san == "O-O":
        return move.castled and files[move.target] == files[kingTarget[white][kingside]]
    if san == "O-O-O":
        return move.castled and files[move.target] == files[kingTarget[white][queenside]]

    var san = san
    doAssert san.len > 0
    
    if not san[0].isUpperAscii:
        san = "P" & san
    let moved = san[0].toColoredPiece.piece
    san = san[1..^1]
    

    let isCapture = "x" in san

    san = san.replace("+")
    san = san.replace("#")
    san = san.replace("x")

    let promoted = if "=" in san:
        doAssert san.len >= 2 and san[^2] == '='
        san = san.replace("=")
        san[^1].toColoredPiece.piece
    else:
        noPiece

    doAssert san.len >= 2
    let target = parseEnum[Square] san[^2..^1]

    let sourceRank = if san.len >= 1 and san[1] in "12345678":
        ranks[parseEnum[Square]("a" & san[1])]
    else:
        not 0.Bitboard

    let sourceFile = if san.len >= 1 and san[0] in "abcdefgh":
        files[parseEnum[Square](san[0] & "1")]
    else:
        not 0.Bitboard

    return move.moved == moved and
    (move.captured != noPiece) == isCapture and
    move.promoted == promoted and
    move.target == target and
    (sourceRank and sourceFile and move.source.toBitboard) != 0
        
func moveFromSANMove(position: Position, sanMove: string): Move =
    result = noMove
    for move in position.legalMoves:
        if validSANMove(position, move, sanMove):
            doAssert result == noMove, fmt"Ambiguous SAN move notation: {sanMove} (possible moves: {result}, {move}"
            result = move

func parseTags(pgn: var string): Table[string, string] =
    var
        pngIndex = 0
        insideTag = false
        insideQuote = false
        currentKey = ""
        currentValue = ""

    while pngIndex < pgn.len:
        var c = pgn[pngIndex]
        pngIndex += 1

        if insideQuote:
            if c == '"':

                while currentKey.len > 0 and currentKey[0].isSpaceAscii:
                    currentKey = currentKey[1..^1]
                while currentKey.len > 0 and currentKey[^1].isSpaceAscii:
                    currentKey.setLen currentKey.len - 1
                doAssert currentKey notin result, "Trying to add tag multiple times: " & currentKey
                result[currentKey] = currentValue
                
                currentKey = ""
                currentValue = ""
                insideQuote = false
                continue

            if c == '\\' and pngIndex < pgn.len and pgn[pngIndex] in ['\\', '"']:
                c = pgn[pngIndex]
                pngIndex += 1
                doAssert c in ['\\', '"']
            currentValue &= c

        elif insideTag:
            if c == '"':
                insideQuote = true
            elif c == ']':
                insideTag = false
            else:
                currentKey &= c

        elif c == '[':
            insideTag = true
        else:
            continue

        pgn[pngIndex] = ' '

func removeComments(pgn: var string) =
    var
        insideBraceComment = false
        insideLineComment = false
    for c in pgn.mitems:
        if insideLineComment:
            insideLineComment = c != '\n'
        elif insideBraceComment:
            insideBraceComment = c != '}'
        elif c == ';':
            insideLineComment = true
        elif c == '{':
            insideBraceComment = true
        else:
            continue

        c = ' '

func removeNumbering(pgn: var string) =
    for i in 0..<pgn.len:
        if pgn[i] == '.':
            pgn[i] = ' '
            var j = i - 1
            while j > 0 and pgn[j].isDigit:
                pgn[j] = ' '
                j -= 1
            
proc parsePGN(pgn: string): tuple[tags: Table[string, string], startPosition: Position, moves: seq[Move]] =
    var pgn = pgn
    result.tags = pgn.parseTags
    pgn.removeComments
    pgn.removeNumbering

    var position: Position
    if "FEN" in result.tags:
        position = result.tags["FEN"].toPosition
    else:
        position = startpos

    
    var indexStartOfMoveString = 0
    while indexStartOfMoveString < pgn.len:
        if not pgn[indexStartOfMoveString].isSpaceAscii:
            var indexAfterEndOfMoveString = indexStartOfMoveString
            while indexAfterEndOfMoveString < pgn.len and not pgn[indexAfterEndOfMoveString].isSpaceAscii:
                indexAfterEndOfMoveString += 1
            doAssert indexStartOfMoveString > indexAfterEndOfMoveString + 1
            let move = moveFromSANMove(position, pgn[indexStartOfMoveString ..< indexAfterEndOfMoveString])
            result.moves.add move
            position.doMove(move)
    

    result.startPosition = position

    
    discard