import
    types,
    evaluation

type AnarchyParameters* = object
    bonusDraw*: Value
    bonusOurPawnReadyCaptureEnPassant*: Value
    bonusEnemyPawnReadyCaptureEnPassant*: Value
    minValueTakeEnPassant*: Value
    minValueOfferEnPassant*: Value
    minValueCloudVariation*: Value
    probabilityCloudVariation*: float
    tuplePawnsBonus*: array[0..6, Value]
    bonusPerStepNeededToGetHalvePawns*: Value
    stillHaveAQueenBonus*: Value
    minValueUnderpromotion*: Value
    minValueUnderpromotionNoPawnsLeft*: Value
    maxRootRandAmplitude*: Value

func newAnarchyParams(
    bonusDraw: Value,
    bonusOurPawnReadyCaptureEnPassant: Value,
    bonusEnemyPawnReadyCaptureEnPassant: Value,
    minValueTakeEnPassant: Value,
    minValueOfferEnPassant: Value,
    minValueCloudVariation: Value,
    probabilityCloudVariation: float,
    tuplePawnsBonus: array[3..6, Value],
    bonusPerStepNeededToGetHalvePawns: Value,
    stillHaveAQueenBonus: Value,
    minValueUnderpromotion: Value,
    minValueUnderpromotionNoPawnsLeft: Value,
    maxRootRandAmplitude: Value
): AnarchyParameters =
    result = AnarchyParameters(
        bonusDraw: bonusDraw,
        bonusOurPawnReadyCaptureEnPassant: bonusOurPawnReadyCaptureEnPassant,
        bonusEnemyPawnReadyCaptureEnPassant: bonusEnemyPawnReadyCaptureEnPassant,
        minValueTakeEnPassant: minValueTakeEnPassant - bonusOurPawnReadyCaptureEnPassant,
        minValueOfferEnPassant: minValueOfferEnPassant - bonusEnemyPawnReadyCaptureEnPassant,
        minValueCloudVariation: minValueCloudVariation,
        probabilityCloudVariation: probabilityCloudVariation,
        tuplePawnsBonus: [0.Value, 0, 0, 0, 0, 0, 0],
        bonusPerStepNeededToGetHalvePawns: bonusPerStepNeededToGetHalvePawns,
        stillHaveAQueenBonus: stillHaveAQueenBonus,
        minValueUnderpromotion: minValueUnderpromotion,
        minValueUnderpromotionNoPawnsLeft: minValueUnderpromotionNoPawnsLeft,
        maxRootRandAmplitude: maxRootRandAmplitude
    )
    result.tuplePawnsBonus[3..6] = tuplePawnsBonus

type DifficultyLevel* = 1..10

func inc*(dl: var DifficultyLevel, y = 1) =
    if dl.int64 + y notin DifficultyLevel.low.int .. DifficultyLevel.high.int:
        raise new OverflowDefect

    dl = (dl.int64 + y).DifficultyLevel

const anarchyParamsTable: array[DifficultyLevel, AnarchyParameters] = [

    #----------- like Walleye 1.5.1 -----------#
    # 1 ^2-chess 1.3.0                564      94     400   96.3%    1.0% 
    # 2 ^2-chess                      323      49     400   86.5%    3.0% 
    # 3 Walleye 1.5.1                  56      30     400   58.0%   24.0% 
    1: newAnarchyParams( 
        bonusDraw = -150.cp,
        bonusOurPawnReadyCaptureEnPassant = 210.cp,
        bonusEnemyPawnReadyCaptureEnPassant = 380.cp,
        minValueTakeEnPassant = -350.cp,
        minValueOfferEnPassant = -350.cp,
        minValueCloudVariation = -1000.cp,
        probabilityCloudVariation = 0.99,
        tuplePawnsBonus = [
            3: 250.cp,
            4: 400.cp,
            5: 800.cp,
            6: 2000.cp
        ],
        bonusPerStepNeededToGetHalvePawns = 60.cp,
        stillHaveAQueenBonus = 90.cp,
        minValueUnderpromotion = 200.cp,
        minValueUnderpromotionNoPawnsLeft = 500.cp,
        maxRootRandAmplitude = 90.cp
    ),

    #----------- 200 worse than 1.1 -----------#
    # 1 ^2-chess 1.3.0                368      55     400   89.3%    2.0% 
    # 2 ^2-chess                      203      39     400   76.3%    5.5% 
    # 3 Walleye 1.5.1                 -26      29     400   46.3%   26.5%
    2: newAnarchyParams(
        bonusDraw = -150.cp,
        bonusOurPawnReadyCaptureEnPassant = 200.cp,
        bonusEnemyPawnReadyCaptureEnPassant = 320.cp,
        minValueTakeEnPassant = -340.cp,
        minValueOfferEnPassant = -330.cp,
        minValueCloudVariation = -1000.cp,
        probabilityCloudVariation = 0.9,
        tuplePawnsBonus = [
            3: 250.cp,
            4: 400.cp,
            5: 800.cp,
            6: 2000.cp
        ],
        bonusPerStepNeededToGetHalvePawns = 60.cp,
        stillHaveAQueenBonus = 90.cp,
        minValueUnderpromotion = 200.cp,
        minValueUnderpromotionNoPawnsLeft = 500.cp,
        maxRootRandAmplitude = 40.cp
    ),

    #----------- 100 worse than 1.1 -----------#
    # 1 ^2-chess 1.3.0                262      43     400   81.9%    3.3% 
    # 2 ^2-chess                      134      36     400   68.4%    5.3% 
    # 3 Walleye 1.5.1                -136      32     400   31.4%   22.8% 
    3: newAnarchyParams(
        bonusDraw = -150.cp,
        bonusOurPawnReadyCaptureEnPassant = 180.cp,
        bonusEnemyPawnReadyCaptureEnPassant = 220.cp,
        minValueTakeEnPassant = -300.cp,
        minValueOfferEnPassant = -260.cp,
        minValueCloudVariation = -1000.cp,
        probabilityCloudVariation = 0.9,
        tuplePawnsBonus = [
            3: 150.cp,
            4: 400.cp,
            5: 800.cp,
            6: 2000.cp
        ],
        bonusPerStepNeededToGetHalvePawns = 60.cp,
        stillHaveAQueenBonus = 80.cp,
        minValueUnderpromotion = 200.cp,
        minValueUnderpromotionNoPawnsLeft = 500.cp,
        maxRootRandAmplitude = 20.cp
    ),

    #----------- like 1.1 -----------#
    # 1 ^2-chess 1.3.0                134      35     400   68.4%    6.3% 
    # 2 ^2-chess                      -24      33     400   46.5%    8.0% 
    # 3 Walleye 1.5.1                -210      34     400   23.0%   20.0%
    4: newAnarchyParams(
        bonusDraw = -150.cp,
        bonusOurPawnReadyCaptureEnPassant = 120.cp,
        bonusEnemyPawnReadyCaptureEnPassant = 140.cp,
        minValueTakeEnPassant = -260.cp,
        minValueOfferEnPassant = -200.cp,
        minValueCloudVariation = -320.cp,
        probabilityCloudVariation = 0.8,
        tuplePawnsBonus = [
            3: 100.cp,
            4: 300.cp,
            5: 600.cp,
            6: 1200.cp
        ],
        bonusPerStepNeededToGetHalvePawns = 50.cp,
        stillHaveAQueenBonus = 70.cp,
        minValueUnderpromotion = 200.cp,
        minValueUnderpromotionNoPawnsLeft = 500.cp,
        maxRootRandAmplitude = 20.cp
    ),

    #----------- like 1.3 -----------#
    # 1 Googleplex Starthinker 1.4     134      35     400   68.4%    8.8% 
    # 2 ^2-chess 1.3.0                 14      32     400   52.0%   10.5% 
    # 3 ^2-chess                     -116      34     400   33.9%    9.8%
    5: newAnarchyParams(
        bonusDraw = -120.cp,
        bonusOurPawnReadyCaptureEnPassant = 80.cp,
        bonusEnemyPawnReadyCaptureEnPassant = 120.cp,
        minValueTakeEnPassant = -220.cp,
        minValueOfferEnPassant = -180.cp,
        minValueCloudVariation = -270.cp,
        probabilityCloudVariation = 0.8,
        tuplePawnsBonus = [
            3: 100.cp,
            4: 300.cp,
            5: 600.cp,
            6: 1200.cp
        ],
        bonusPerStepNeededToGetHalvePawns = 40.cp,
        stillHaveAQueenBonus = 70.cp,
        minValueUnderpromotion = 200.cp,
        minValueUnderpromotionNoPawnsLeft = 500.cp,
        maxRootRandAmplitude = 10.cp
    ),

    #----------- like 1.4 -----------#
    # 1 Googleplex Starthinker 1.6      69      33     400   59.8%   10.5% 
    # 2 Googleplex Starthinker 1.4      10      32     400   51.4%   13.3% 
    # 3 ^2-chess 1.3.0               -104      33     400   35.5%   13.5%
    6: newAnarchyParams(
        bonusDraw = -100.cp,
        bonusOurPawnReadyCaptureEnPassant = 50.cp,
        bonusEnemyPawnReadyCaptureEnPassant = 80.cp,
        minValueTakeEnPassant = -150.cp,
        minValueOfferEnPassant = -140.cp,
        minValueCloudVariation = -250.cp,
        probabilityCloudVariation = 0.6,
        tuplePawnsBonus = [
            3: 50.cp,
            4: 200.cp,
            5: 300.cp,
            6: 1200.cp
        ],
        bonusPerStepNeededToGetHalvePawns = 30.cp,
        stillHaveAQueenBonus = 60.cp,
        minValueUnderpromotion = 200.cp,
        minValueUnderpromotionNoPawnsLeft = 500.cp,
        maxRootRandAmplitude = 8.cp
    ),

    #----------- like 1.6 -----------#
    # 1 Nalwald 1.8                    65      32     400   59.3%   13.0% 
    # 2 Googleplex Starthinker 1.6       8      32     400   51.1%   12.3% 
    # 3 Googleplex Starthinker 1.4     -53      32     400   42.4%   15.3% 
    7: newAnarchyParams(
        bonusDraw = -50.cp,
        bonusOurPawnReadyCaptureEnPassant = 50.cp,
        bonusEnemyPawnReadyCaptureEnPassant = 60.cp,
        minValueTakeEnPassant = -80.cp,
        minValueOfferEnPassant = -70.cp,
        minValueCloudVariation = -220.cp,
        probabilityCloudVariation = 0.5,
        tuplePawnsBonus = [
            3: 10.cp,
            4: 30.cp,
            5: 300.cp,
            6: 1200.cp
        ],
        bonusPerStepNeededToGetHalvePawns = 10.cp,
        stillHaveAQueenBonus = 40.cp,
        minValueUnderpromotion = 200.cp,
        minValueUnderpromotionNoPawnsLeft = 500.cp,
        maxRootRandAmplitude = 4.cp
    ),

    #----------- like 1.8 -----------#
    # 1 Nalwald 1.9                   174      34     400   73.1%   17.8% 
    # 2 Nalwald 1.8                    10      32     400   51.4%   13.3% 
    # 3 Googleplex Starthinker 1.6     -54      32     400   42.3%   12.0% 
    8: newAnarchyParams(
        bonusDraw = -50.cp,
        bonusOurPawnReadyCaptureEnPassant = 30.cp,
        bonusEnemyPawnReadyCaptureEnPassant = 50.cp,
        minValueTakeEnPassant = -50.cp,
        minValueOfferEnPassant = -50.cp,
        minValueCloudVariation = -200.cp,
        probabilityCloudVariation = 0.4,
        tuplePawnsBonus = [
            3: 10.cp,
            4: 30.cp,
            5: 300.cp,
            6: 1200.cp
        ],
        bonusPerStepNeededToGetHalvePawns = 10.cp,
        stillHaveAQueenBonus = 40.cp,
        minValueUnderpromotion = 200.cp,
        minValueUnderpromotionNoPawnsLeft = 500.cp,
        maxRootRandAmplitude = 4.cp
    ),

    #----------- like 1.9 -----------#
    # 1 Nalwald 1.11                  101      32     400   64.1%   18.8% 
    # 2 Nalwald 1.9                     3      30     400   50.5%   20.0% 
    # 3 Nalwald 1.8                  -112      32     400   34.4%   19.3%
    9: newAnarchyParams(
        bonusDraw = -20.cp,
        bonusOurPawnReadyCaptureEnPassant = 20.cp,
        bonusEnemyPawnReadyCaptureEnPassant = 20.cp,
        minValueTakeEnPassant = 0.cp,
        minValueOfferEnPassant = 0.cp,
        minValueCloudVariation = 150.cp,
        probabilityCloudVariation = 0.3,
        tuplePawnsBonus = [
            3: 0.cp,
            4: 0.cp,
            5: 300.cp,
            6: 1200.cp
        ],
        bonusPerStepNeededToGetHalvePawns = 5.cp,
        stillHaveAQueenBonus = 10.cp,
        minValueUnderpromotion = 200.cp,
        minValueUnderpromotionNoPawnsLeft = 500.cp,
        maxRootRandAmplitude = 3.cp
    ),

    #----------- like 1.10 -----------#
    # 1 Nalwald 1.11                   57      29     400   58.1%   28.2% 
    # 2 Nalwald 1.9                   -37      29     400   44.8%   30.0%
    10: newAnarchyParams( 
        bonusDraw = -20.cp,
        bonusOurPawnReadyCaptureEnPassant = 1.cp,
        bonusEnemyPawnReadyCaptureEnPassant = 2.cp,
        minValueTakeEnPassant = 70.cp,
        minValueOfferEnPassant = 70.cp,
        minValueCloudVariation = 120.cp,
        probabilityCloudVariation = 0.2,
        tuplePawnsBonus = [
            3: 0.cp,
            4: 0.cp,
            5: 300.cp,
            6: 1200.cp
        ],
        bonusPerStepNeededToGetHalvePawns = 0.cp,
        stillHaveAQueenBonus = 2.cp,
        minValueUnderpromotion = 200.cp,
        minValueUnderpromotionNoPawnsLeft = 500.cp,
        maxRootRandAmplitude = 2.cp
    )
]

func anarchyParams*(difficultyLevel: DifficultyLevel): AnarchyParameters =
    anarchyParamsTable[difficultyLevel]

const eloEstimateTable: array[DifficultyLevel, float] = [
    1: 1700.0,
    2: 1800.0,
    3: 1900.0,
    4: 2100.0,
    5: 2300.0,
    6: 2500.0,
    7: 2600.0,
    8: 2700.0,
    9: 2800.0,
    10: 2900.0
]

func difficultyEloEstimate*(difficultyLevel: DifficultyLevel): float =
    eloEstimateTable[difficultyLevel]