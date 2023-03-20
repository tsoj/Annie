import
    types,
    position,
    positionUtils,
    move

import std/[
    json,
    strformat,
    strutils,
    times
]

type 
    LichessGame* = object
        botUserId: string
        gameId*: string
        initialFEN*: string
        userId: array[white..black, string]
        opponentElo*: float
    LichessGameState* = object
        lichessGame*: LichessGame
        positionMoveHistory*: seq[tuple[position: Position, move: Move]]
        currentPosition*: Position
        wtime*, btime*, winc*, binc*: Duration

proc lichessFenToPosition(fen: string): Position =
    if fen == "startpos":
        result = startpos
    else:
        result = fen.toPosition

func botIsWhite(lg: LichessGame): bool =
    lg.botUserId == lg.userId[white]

func botColor*(lg: LichessGame): Color =
    if lg.botIsWhite: white else: black

func timeLeft*(lgs: LichessGameState, color: Color): Duration =
    if color == white:
        lgs.wtime
    else:
        lgs.btime

func newLichessGame*(gameFullNode: JsonNode, botUserId: string): LichessGame =
    if gameFullNode{"type"}.getStr != "gameFull":
        raise newException(ValueError, &"Can only create LichessGame from JSON responses of type \"gameFull\". {gameFullNode = }")

    result = LichessGame(
        botUserId: botUserId,
        gameId: gameFullNode{"id"}.getStr,
        initialFEN: gameFullNode{"initialFen"}.getStr,
        userId: [white: gameFullNode{"white"}{"id"}.getStr, black: gameFullNode{"black"}{"id"}.getStr]
    )
    result.opponentElo = if result.botIsWhite:
        gameFullNode{"black"}{"rating"}.getFloat
    else:
        gameFullNode{"white"}{"rating"}.getFloat

proc getCurrentState*(lichessGame: LichessGame, gameStateNode: JsonNode): LichessGameState =
    if gameStateNode{"type"}.getStr != "gameState":
        raise newException(ValueError, &"Can only create LichessGameState from JSON responses of type \"gameState\". {gameStateNode = }")

    result.lichessGame = lichessGame

    var position: Position
    try:
        position = lichessGame.initialFEN.lichessFenToPosition
    except ValueError:
        raise newException(ValueError, &"Wrongly formatted initial FEN in lichess game: {lichessGame = }\n{getCurrentExceptionMsg() = }")

    for moveString in gameStateNode{"moves"}.getStr.splitWhitespace:
        try:
            let move = moveString.toMove(position)
            result.positionMoveHistory.add (position, move)
            position = position.doMove move
        except ValueError:
            raise newException(ValueError, &"Failed to apply move string \"{moveString}\" in position \"{position.fen}\". \n{getCurrentExceptionMsg()}")

    result.wtime = initDuration(milliseconds = gameStateNode{"wtime"}.getInt)
    result.btime = initDuration(milliseconds = gameStateNode{"btime"}.getInt)
    result.winc = initDuration(milliseconds = gameStateNode{"winc"}.getInt)
    result.binc = initDuration(milliseconds = gameStateNode{"binc"}.getInt)

    result.currentPosition = position

proc getPositionHistory*(lgs: LichessGameState): seq[Position] =
    for (position, move) in lgs.positionMoveHistory:
        result.add position
        
    result.add lgs.currentPosition

    doAssert result.len == lgs.positionMoveHistory.len + 1
    doAssert lgs.currentPosition == result[^1]