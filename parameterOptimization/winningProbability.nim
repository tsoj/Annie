import
    ../types,
    math,
    strformat

func winningProbability*(centipawn: Value, k: float): float =
    1.0/(1.0 + pow(10.0, -((k*centipawn.float)/400.0)))

func winningProbabilityDerivative*(centipawn: Value, k: float): float =
    (ln(10.0) * pow(2.0, -2.0 - ((k*centipawn.float)/400.0)) * pow(5.0, -((k*centipawn.float)/400.0))) /
    pow(1.0 + pow(10.0, -((k*centipawn.float)/400.0)) , 2.0)

proc optimizeK*(getError: proc(k: float): float, suppressOutput = false): float =
    var change = 1.0
    var k = 1.0
    result = k
    var bestError = getError(k)
    while change.abs >= 0.000001:
        k += change
        let currentError = getError(k)
        if currentError < bestError:
            if not suppressOutput:
                debugEcho "k: ", fmt"{k:>9.7f}", ", error: ", fmt"{currentError:>9.7f}"
            bestError = currentError
            result = k
        else:
            change /= -2.0
            k = result
    if not suppressOutput:
        debugEcho "optimized k: ", result
