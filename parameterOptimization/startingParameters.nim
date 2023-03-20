import
    ../types,
    ../evalParameters

const pst: array[Phase, array[pawn..king, array[a1..h8, int]]] = [
    opening: [
        pawn:
        [
            0, 0, 0, 0, 0, 0, 0, 0,
            45, 45, 45, 45, 45, 45, 45, 45,
            10, 10, 20, 30, 30, 20, 10, 10,
            5, 5, 10, 25, 25, 10, 5, 5,
            0, 0, 0, 20, 20, 0, 0, 0,
            5, -5, -10, 0, 0, -10, -5, 5,
            5, 10, 10, -20, -20, 10, 10, 5,
            0, 0, 0, 0, 0, 0, 0, 0
        ],
        knight:
        [
            -50, -40, -30, -30, -30, -30, -40, -50,
            -40, -20, 0, 0, 0, 0, -20, -40,
            -30, 0, 10, 15, 15, 10, 0, -30,
            -30, 5, 15, 20, 20, 15, 5, -30,
            -30, 0, 15, 20, 20, 15, 0, -30,
            -30, 5, 10, 15, 15, 10, 5, -30,
            -40, -20, 0, 5, 5, 0, -20, -40,
            -50, -40, -30, -30, -30, -30, -40, -50
        ],
        bishop:
        [
            -20, -10, -10, -10, -10, -10, -10, -20,
            -10, 0, 0, 0, 0, 0, 0, -10,
            -10, 0, 5, 10, 10, 5, 0, -10,
            -10, 5, 5, 10, 10, 5, 5, -10,
            -10, 0, 10, 10, 10, 10, 0, -10,
            -10, 10, 10, 10, 10, 10, 10, -10,
            -10, 5, 0, 0, 0, 0, 5, -10,
            -20, -10, -10, -10, -10, -10, -10, -20
        ],
        rook:
        [
            0, 0, 0, 0, 0, 0, 0, 0,
            5, 10, 10, 10, 10, 10, 10, 5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            0, 0, 0, 5, 5, 0, 0, 0
        ],
        queen:
        [
            -20, -10, -10, -5, -5, -10, -10, -20,
            -10, 0, 0, 0, 0, 0, 0, -10,
            -10, 0, 5, 5, 5, 5, 0, -10,
            -5, 0, 5, 5, 5, 5, 0, -5,
            0, 0, 5, 5, 5, 5, 0, -5,
            -10, 5, 5, 5, 5, 5, 0, -10,
            -10, 0, 5, 0, 0, 0, 0, -10,
            -20, -10, -10, -5, -5, -10, -10, -20
        ],
        king:
        [
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -20, -30, -30, -40, -40, -30, -30, -20,
            -10, -20, -20, -20, -20, -20, -20, -10,
            20, 20, 0, 0, 0, 0, 20, 20,
            20, 30, 10, 0, 0, 10, 30, 20
        ],
    ],
    endgame: [
        pawn:
        [
            0, 0, 0, 0, 0, 0, 0, 0,
            90, 90, 90, 90, 90, 90, 90, 90,
            30, 30, 40, 45, 45, 40, 40, 30,
            20, 20, 20, 25, 25, 20, 20, 20,
            0, 0, 0, 20, 20, 0, 0, 0,
            -5, -5, -10, -10, -10, -10, -5, -5,
            -15, -15, -15, -20, -20, -15, -15, -15,
            0, 0, 0, 0, 0, 0, 0, 0
        ],
        knight:
        [
            -50, -40, -30, -30, -30, -30, -40, -50,
            -40, -20, 0, 0, 0, 0, -20, -40,
            -30, 0, 10, 15, 15, 10, 0, -30,
            -30, 5, 15, 20, 20, 15, 5, -30,
            -30, 0, 15, 20, 20, 15, 0, -30,
            -30, 5, 10, 15, 15, 10, 5, -30,
            -40, -20, 0, 5, 5, 0, -20, -40,
            -50, -40, -30, -30, -30, -30, -40, -50
        ],
        bishop:
        [
            -20, -10, -10, -10, -10, -10, -10, -20,
            -10, 0, 0, 0, 0, 0, 0, -10,
            -10, 0, 5, 10, 10, 5, 0, -10,
            -10, 5, 5, 10, 10, 5, 5, -10,
            -10, 0, 10, 10, 10, 10, 0, -10,
            -10, 10, 10, 10, 10, 10, 10, -10,
            -10, 5, 0, 0, 0, 0, 5, -10,
            -20, -10, -10, -10, -10, -10, -10, -20
        ],
        rook:
        [
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 5, 5, 5, 5, 5, 5, 0,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            0, 0, 0, 0, 0, 0, 0, 0
        ],
        queen:
        [
            -20, -10, -10, -5, -5, -10, -10, -20,
            -10, 0, 0, 0, 0, 0, 0, -10,
            -10, 0, 5, 5, 5, 5, 0, -10,
            -5, 0, 5, 5, 5, 5, 0, -5,
            0, 0, 5, 5, 5, 5, 0, -5,
            -10, 0, 5, 5, 5, 5, 0, -10,
            -10, 0, 0, 0, 0, 0, 0, -10,
            -20, -10, -10, -5, -5, -10, -10, -20
        ],
        king:
        [
            -50, -40, -30, -20, -20, -30, -40, -50,
            -30, -20, -10, 0, 0, -10, -20, -30,
            -30, -10, 20, 30, 30, 20, -10, -30,
            -30, -10, 30, 40, 40, 30, -10, -30,
            -30, -10, 30, 40, 40, 30, -10, -30,
            -30, -10, 20, 30, 30, 20, -10, -30,
            -30, -30, 0, 0, 0, 0, -30, -30,
            -50, -30, -30, -30, -30, -30, -30, -50
        ],
    ]
]

const passedPawnTable = [
    opening: [0, 0, 0, 10, 15, 20, 45, 0],
    endgame: [0, 20, 30, 40, 60, 100, 120, 0]
]

const startingEvalParameters* = block:
    let pst = pst # workaround for https://github.com/nim-lang/Nim/issues/19075
    var startingEvalParameters: EvalParametersFloat
    for phase in Phase:
        startingEvalParameters[phase] = SinglePhaseEvalParametersTemplate[float32](
            pieceValues: [
                pawn: 100.0.float32,
                knight: 300.0,
                bishop: 300.0,
                rook: 500.0,
                queen: 900.0,
                king: 0.0
            ],
            bonusKnightAttackingPiece: 5.0.float32,
            bonusBothBishops: 10.0.float32,
            bonusRookOnOpenFile: 5.0.float32,
            bonusTargetingKingArea: [bishop: 5.0.float32, rook: 5.0, queen: 8.0],
            bonusAttackingKing: [bishop: 5.0.float32, rook: 5.0, queen: 8.0]
        )
        for i in 0..<32:
            startingEvalParameters[phase].bonusMobility[knight][i] = i.float32 * 2.0.float32
            startingEvalParameters[phase].bonusMobility[bishop][i] = i.float32 * 3.0.float32
            startingEvalParameters[phase].bonusMobility[rook][i] = i.float32 * 4.0.float32
            startingEvalParameters[phase].bonusMobility[queen][i] = i.float32 * 2.0.float32
            startingEvalParameters[phase].bonusKingSafety[i] = i.float32 * -2.5.float32
        for whoseKing in ourKing..enemyKing:
            for kingSquare in a1..h8:
                for square in a1..h8:
                    for piece in pawn..king:
                        startingEvalParameters[phase].pst[whoseKing][kingSquare][piece][square] =
                            pst[phase][piece][square].float32
                    
                    # noPiece stands for passed pawns here
                    startingEvalParameters[phase].pst[whoseKing][kingSquare][noPiece][square] =
                        passedPawnTable[phase][7 - (square.int div 8)].float32

    doAssert startingEvalParameters[endgame].pst[ourKing][a1][noPiece][e2] == 120.0
    startingEvalParameters
