import
    position,
    types,
    bitboard,
    bitops,
    evalParameters,
    utils,
    defaultParameters,
    algorithm,
    macros

func value*(piece: Piece): Value =
    const table = [
        pawn: 139.Value,
        knight: 383.Value,
        bishop: 421.Value,
        rook: 621.Value,
        queen: 1227.Value,
        king: 1000000.Value,
        noPiece: 0.Value
    ]
    table[piece]

func cp*(cp: int): Value {.inline.} =
    (pawn.value * cp.Value) div 100.Value

func toCp*(value: Value): int {.inline.} =
    (100 * value.int) div pawn.value.int

func material*(position: Position): Value =
    result = 0
    for piece in pawn..king:
        result += (position[piece] and position[position.us]).countSetBits.Value * piece.value
        result -= (position[piece] and position[position.enemy]).countSetBits.Value * piece.value

func absoluteMaterial*(position: Position): Value =
    result = position.material
    if position.us == black:
        result = -result

func `+=`[T: Value or float32](a: var array[Phase, T], b: array[Phase, T]) {.inline.} =
    for phase in Phase:
        a[phase] += b[phase]

func `-=`[T: Value or float32](a: var array[Phase, T], b: array[Phase, T]) {.inline.} =
    for phase in Phase:
        a[phase] -= b[phase]    

type Nothing = enum nothing
type GradientOrNothing = EvalParametersFloat or Nothing

macro getParameter(structName, parameter: untyped): untyped =
    parseExpr($toStrLit(quote do: `structName`[phase]) & "." & $toStrLit(quote do: `parameter`))

template addValue(
    value: var array[Phase, Value],
    evalParameters: EvalParameters,
    gradient: GradientOrNothing,
    us: Color,
    parameter: untyped
) =
    for phase {.inject.} in Phase:
        value[phase] += getParameter(evalParameters, parameter)

    when gradient isnot Nothing:
        for phase {.inject.} in Phase:
            getParameter(gradient, parameter) += (if us == black: -1.0 else: 1.0)

func getPstValue(
    evalParameters: EvalParameters,
    square: Square,
    piece: Piece,
    us, enemy: Color,
    kingSquare: array[white..black, Square],
    gradient: var GradientOrNothing
): array[Phase, Value] {.inline.} =
    template pmirror(x: auto, color: Color): auto = (if color == white: x.mirror else: x) 
    let
        square = square.pmirror(us)
        kingSquare = [
            ourKing: kingSquare[us].pmirror(us),
            enemyKing: kingSquare[enemy].pmirror(enemy)
        ]

    for phase in Phase:
        result[phase] =
            evalParameters[phase].pst[enemyKing][kingSquare[enemyKing]][piece][square] +
            evalParameters[phase].pst[ourKing][kingSquare[ourKing]][piece][square]

    when gradient isnot Nothing:

        for whoseKing in ourKing..enemyKing:
            for currentKingSquare in a1..h8:
                let multiplier = (if us == black: -1.0 else: 1.0) * (if currentKingSquare == kingSquare[whoseKing]:
                    2.0
                elif (currentKingSquare.toBitboard and mask3x3[kingSquare[whoseKing]]) != 0:
                    0.3
                elif (currentKingSquare.toBitboard and mask5x5[kingSquare[whoseKing]]) != 0:
                    0.2
                else:
                    0.1)

                for (kingSquare, pieceSquare) in [
                    (currentKingSquare, square),
                    (currentKingSquare.mirrorVertically, square.mirrorVertically)
                ]:
                    for phase in Phase: gradient[phase].pst[whoseKing][kingSquare][piece][pieceSquare] += multiplier

func pawnMaskIndex*(
    position: Position,
    square: static Square,
    us, enemy: Color,
    doChecks: static bool = false
): int =
    template pmirror(x: auto): auto = (if us == black: x.mirror else: x)

    let square = square.pmirror

    assert not square.isEdge
    assert square >= b2

    when doChecks:
        if square.isEdge: # includes cases when square < b2
            raise newException(ValueError, "Can't calculate pawn mask index of edge square")

    let
        ourPawns = (position[us] and position[pawn]).pmirror shr (square.int8 - b2.int8)
        enemyPawns = (position[enemy] and position[pawn]).pmirror shr (square.int8 - b2.int8)

    var counter = 1
    for bit in [
        a3.toBitboard, b3.toBitboard, c3.toBitboard,
        a2.toBitboard, b2.toBitboard, c2.toBitboard,
        a1.toBitboard, b1.toBitboard, c1.toBitboard
    ]:
        if (ourPawns and bit) != 0:
            result += counter * 2
        elif (enemyPawns and bit) != 0:
            result += counter * 1
        counter *= 3

func pawnMaskBonus(
    evalParameters: EvalParameters,
    position: Position,
    square: static Square,
    us, enemy: Color,
    gradient: var GradientOrNothing
): array[Phase, Value] =
    
    let index = position.pawnMaskIndex(square, us, enemy)
    result.addValue(evalParameters, gradient, us, pawnMaskBonus[index])

func mobility(
    evalParameters: EvalParameters,
    position: Position,
    piece: static Piece,
    us: Color,
    attackMask: Bitboard,
    gradient: var GradientOrNothing
): array[Phase, Value] =
    let reachableSquares = (attackMask and not position[us]).countSetBits
    result.addValue(evalParameters, gradient, us, bonusMobility[piece][reachableSquares])

func targetingKingArea(
    evalParameters: EvalParameters,
    position: Position,
    piece: static Piece,
    us, enemy: Color,
    kingSquare: array[white..black, Square],
    attackMask: Bitboard,
    gradient: var GradientOrNothing
): array[Phase, Value] =
    # knight and pawn are not included, as the king contextual piece square tables are enough in this case
    static: doAssert piece in bishop..queen
    if (attackMask and king.attackMask(kingSquare[enemy], 0)) != 0:
        result.addValue(evalParameters, gradient, us, bonusTargetingKingArea[piece])
    
    if (attackMask and kingSquare[enemy].toBitboard) != 0:
        result.addValue(evalParameters, gradient, us, bonusAttackingKing[piece])

func forkingMajorPieces(
    evalParameters: EvalParameters,
    position: Position,
    us, enemy: Color,
    attackMask: Bitboard,
    gradient: var GradientOrNothing
): array[Phase, Value] =
    # TODO try also consider king
    if (attackMask and position[enemy] and (position[queen] or position[rook])).countSetBits >= 2:
        result.addValue(evalParameters, gradient, us, bonusPieceForkedMajorPieces)

func attackedByPawn(
    evalParameters: EvalParameters,
    position: Position,
    square: Square,
    us, enemy: Color,
    gradient: var GradientOrNothing
): array[Phase, Value] =
    if (position[enemy] and position[pawn] and attackMaskPawnCapture(square, us)) != 0:
        result.addValue(evalParameters, gradient, us, bonusPieceAttackedByPawn)


#-------------- pawn evaluation --------------#

func evaluatePawn(
    position: Position,
    square: Square,
    us, enemy: Color,
    kingSquare: array[white..black, Square],
    evalParameters: EvalParameters,
    gradient: var GradientOrNothing
): array[Phase, Value] {.inline.} =

    # passed pawn
    let isPassed = position.isPassedPawn(us, square)
    if isPassed:
        result += evalParameters.getPstValue(
            square, noPiece, # noPiece stands for passed pawn
            us, enemy,
            kingSquare,
            gradient
        )

    # can move forward
    if (position.occupancy and attackMaskPawnQuiet(square, us)) == 0:
        if isPassed:
            var index = square.int div 8
            if us == black:
                index = 7 - index
            result.addValue(evalParameters, gradient, us, bonusPassedPawnCanMove[index])
        else:
            result.addValue(evalParameters, gradient, us, bonusPawnCanMove)
    


#-------------- knight evaluation --------------#

func evaluateKnight(
    position: Position,
    square: Square,
    us, enemy: Color,
    kingSquare: array[white..black, Square],
    evalParameters: EvalParameters,
    gradient: var GradientOrNothing
): array[Phase, Value] {.inline.} =

    let attackMask = knight.attackMask(square, position.occupancy)
    
    # mobility
    result += evalParameters.mobility(position, knight, us, attackMask, gradient)

    # forks
    result += evalParameters.forkingMajorPieces(position, us, enemy, attackMask, gradient)

    # attacked by pawn
    result += evalParameters.attackedByPawn(position, square, us, enemy, gradient)

    # attacking bishop, rook, or queen
    if (attackMask and position[enemy] and (position[bishop] or position[rook] or position[queen])) != 0:
        result.addValue(evalParameters, gradient, us, bonusKnightAttackingPiece)

#-------------- bishop evaluation --------------#

func evaluateBishop(
    position: Position,
    square: Square,
    us, enemy: Color,
    kingSquare: array[white..black, Square],
    evalParameters: EvalParameters,
    gradient: var GradientOrNothing
): array[Phase, Value] {.inline.} =

    let attackMask = bishop.attackMask(square, position.occupancy)

    # mobility
    result += evalParameters.mobility(position, bishop, us, attackMask, gradient)

    # forks
    result += evalParameters.forkingMajorPieces(position, us, enemy, attackMask, gradient)

    # attacked by pawn
    result += evalParameters.attackedByPawn(position, square, us, enemy, gradient)
    
    # targeting enemy king area
    result += evalParameters.targetingKingArea(
        position, bishop, us, enemy, kingSquare, attackMask, gradient
    )
    
    # both bishops
    if (position[us] and position[bishop] and (not square.toBitboard)) != 0:
        result.addValue(evalParameters, gradient, us, bonusBothBishops)


#-------------- rook evaluation --------------#

func evaluateRook(
    position: Position,
    square: Square,
    us, enemy: Color,
    kingSquare: array[white..black, Square],
    evalParameters: EvalParameters,
    gradient: var GradientOrNothing
): array[Phase, Value] {.inline.} =

    let attackMask = rook.attackMask(square, position.occupancy)

    # mobility
    result += evalParameters.mobility(position, rook, us, attackMask, gradient)

    # attacked by pawn
    result += evalParameters.attackedByPawn(position, square, us, enemy, gradient)
    
    # targeting enemy king area
    result += evalParameters.targetingKingArea(
        position, rook, us, enemy, kingSquare, attackMask, gradient
    )
    
    # rook on open file
    if (files[square] and position[pawn]) == 0:
        result.addValue(evalParameters, gradient, us, bonusRookOnOpenFile)

#-------------- queen evaluation --------------#

func evaluateQueen(
    position: Position,
    square: Square,
    us, enemy: Color,
    kingSquare: array[white..black, Square],
    evalParameters: EvalParameters,
    gradient: var GradientOrNothing
): array[Phase, Value] {.inline.} =

    let attackMask = queen.attackMask(square, position.occupancy)

    # mobility
    result += evalParameters.mobility(position, queen, us, attackMask, gradient)

    # attacked by pawn
    result += evalParameters.attackedByPawn(position, square, us, enemy, gradient)
    
    # targeting enemy king area
    result += evalParameters.targetingKingArea(
        position, queen, us, enemy, kingSquare, attackMask, gradient
    )

#-------------- king evaluation --------------#

func evaluateKing(
    position: Position,
    square: Square,
    us, enemy: Color,
    kingSquare: array[white..black, Square],
    evalParameters: EvalParameters,
    gradient: var GradientOrNothing
): array[Phase, Value] {.inline.} =

    # kingsafety by pawn shielding
    let numPossibleQueenAttack = queen.attackMask(square, position[pawn] and position[us]).countSetBits
    result.addValue(evalParameters, gradient, us, bonusKingSafety[numPossibleQueenAttack])

    # numbers of attackers near king
    let numNearAttackers = (position[enemy] and mask5x5[square]).countSetBits
    result.addValue(evalParameters, gradient, us, bonusAttackersNearKing[numNearAttackers])


func evaluatePiece(
    position: Position,
    piece: Piece,
    square: Square,
    us, enemy: static Color,
    kingSquare: array[white..black, Square],
    evalParameters: EvalParameters,
    gradient: var GradientOrNothing
): array[Phase, Value] {.inline.} =
    const evaluationFunctions = [
        pawn: evaluatePawn[GradientOrNothing],
        knight: evaluateKnight[GradientOrNothing],
        bishop: evaluateBishop[GradientOrNothing],
        rook: evaluateRook[GradientOrNothing],
        queen: evaluateQueen[GradientOrNothing],
        king: evaluateKing[GradientOrNothing]
    ]
    assert piece != noPiece

    result.addValue(evalParameters, gradient, us, pieceValues[piece])

    result += evaluationFunctions[piece](position, square, us, enemy, kingSquare, evalParameters, gradient)
    result += evalParameters.getPstValue(
        square, piece, us, enemy,
        kingSquare,
        gradient
    )
    
func evaluatePieceType(
    position: Position,
    piece: static Piece,
    us, enemy: static Color,
    kingSquare: array[white..black, Square],
    evalParameters: EvalParameters,
    gradient: var GradientOrNothing
): array[Phase, Value] {.inline.}  =
    
    template evaluatePiece(square: Square, us, enemy: Color): auto =
        position.evaluatePiece(
            piece, square,
            us, enemy,
            kingSquare,
            evalParameters, gradient
        )
     
    for square in (position[piece] and position[us]):
        result += evaluatePiece(square, us, enemy)

    for square in (position[piece] and position[enemy]):
        result -= evaluatePiece(square, enemy, us)

func evaluate*(position: Position, evalParameters: EvalParameters, gradient: var GradientOrNothing): Value {.inline.} =
    if position.halfmoveClock >= 100:
        return 0.Value

    var value = [opening: 0.Value, endgame: 0.Value]

    let kingSquare = [
        white: position.kingSquare(white),
        black: position.kingSquare(black)
    ]
    
    # evaluating pieces
    for piece in (pawn, knight, bishop, rook, queen, king).fields:
        if position.us == white:
            value += position.evaluatePieceType(piece, white, black, kingSquare, evalParameters, gradient)
        else:
            value += position.evaluatePieceType(piece, black, white, kingSquare, evalParameters, gradient)

    # evaluation pawn patters
    for square in (
        b3, c3, d3, e3, f3, g3,
        b4, c4, d4, e4, f4, g4,
        b5, c5, d5, e5, f5, g5,
        b6, c6, d6, e6, f6, g6
    ).fields:
        if (mask3x3[square] and position[pawn]).countSetBits >= 2:
            value += evalParameters.pawnMaskBonus(
                position,
                square,
                position.us, position.enemy,
                gradient
            )

    # interpolating between opening and endgame values
    let gamePhase = position.gamePhase

    result = gamePhase.interpolate(forOpening = value[opening], forEndgame = value[endgame])
    doAssert valueCheckmate > result.abs

    when gradient isnot Nothing:
        gradient[opening] *= gamePhase.interpolate(forOpening = 1.0, forEndgame = 0.0)
        gradient[endgame] *= gamePhase.interpolate(forOpening = 0.0, forEndgame = 1.0)


#-------------- sugar functions --------------#

func evaluate*(position: Position): Value =
    var gradient: Nothing = nothing
    position.evaluate(defaultEvalParameters, gradient)

func absoluteEvaluate*(position: Position, evalParameters: EvalParameters, gradient: var GradientOrNothing): Value =
    result = position.evaluate(evalParameters, gradient)
    if position.us == black:
        result = -result

func absoluteEvaluate*(position: Position, evalParameters: EvalParameters): Value =
    var gradient: Nothing = nothing
    position.absoluteEvaluate(evalParameters, gradient)

func absoluteEvaluate*(position: Position): Value =
    var gradient: Nothing = nothing
    position.absoluteEvaluate(defaultEvalParameters, gradient)