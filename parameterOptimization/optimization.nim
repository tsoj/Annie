import
    ../evalParameters,
    startingParameters,
    winningProbability,
    gradient,
    dataUtils,
    calculatePieceValue,
    times,
    strformat,
    terminal,
    threadpool

type ThreadResult = tuple[weight: float, gradient: EvalParametersFloat]

proc calculateGradient(data: openArray[Entry], currentSolution: EvalParameters, k: float, suppressOutput = false): ThreadResult =
    const numProgressBarPoints = 100
    if not suppressOutput:
        eraseLine()
        stdout.write("[")
        for p in 1..numProgressBarPoints:
            stdout.write("-")
        stdout.write("]")
        setCursorXPos(1)
        stdout.flushFile
    var p = 0
    for entry in data:
        p += 1
        if p mod (data.len div numProgressBarPoints) == 0 and not suppressOutput:
            stdout.write("#")
            stdout.flushFile
        
        result.weight += entry.weight
        result.gradient.addGradient(currentSolution, entry.position, entry.outcome, k = k, weight = entry.weight)

proc optimize(
    start: EvalParametersFloat,
    data: seq[Entry],
    lr = 6400.0,
    minLearningRate = 80.0,
    maxIterations = int.high,
    minTries = 10,
    discount = 0.9,
    numThreads = 31
): EvalParameters =

    echo "-------------------"
    let k = optimizeK(getError = proc(k: float): float = start.convert.error(data, k))

    var bestSolution: EvalParametersFloat = start

    echo "-------------------"

    var lr = lr
    var decreaseLr = true
    var bestError = bestSolution.convert.error(data, k)
    echo "starting error: ", fmt"{bestError:>9.7f}", ", starting lr: ", lr

    var previousGradient: EvalParametersFloat 
    for j in 0..<maxIterations:
        let startTime = now()
        var currentSolution = bestSolution
        let batchSize = data.len div numThreads

        template batchSlize(i: int): auto =
            let
                b = data.len mod numThreads + (i+1)*batchSize
                a = if i == 0: 0 else: b - batchSize
            doAssert b > a
            doAssert i < numThreads - 1 or b == data.len
            doAssert i == 0 or b - a == batchSize
            doAssert i > 0 or b - a == batchSize + data.len mod numThreads
            doAssert b <= data.len
            data[a..<b]

        var threadSeq = newSeq[FlowVar[ThreadResult]](numThreads)
        
        let bestSolutionConverted = bestSolution.convert
        for i, flowVar in threadSeq.mpairs:
            flowVar = spawn calculateGradient(
                i.batchSlize,
                bestSolutionConverted,
                k, i > 0
            )    

        var gradient: EvalParametersFloat
        var totalWeight: float = 0.0
        for flowVar in threadSeq.mitems:
            let (threadWeight, threadGradient) = ^flowVar
            totalWeight += threadWeight
            gradient += threadGradient
        # smooth the gradient out over previous discounted gradients. Seems to help in optimization speed and the final
        # result is better
        gradient *= (1.0/totalWeight)
        gradient *= 1.0 - discount
        previousGradient *= discount
        gradient += previousGradient
        previousGradient = gradient

        gradient *= lr

        let oldBestError = bestError
        
        eraseLine()
        stdout.write("iteration: " & fmt"{j:>3}")
        stdout.flushFile

        var leftTries = minTries
        var successes = 0
        var tries = 0
        while leftTries > 0:

            currentSolution += gradient

            let currentSolutionConverted = currentSolution.convert
            var errors = newSeq[FlowVar[tuple[error, summedWeight: float]]](numThreads)
            for i, error in errors.mpairs:
                error = spawn errorTuple(currentSolutionConverted, i.batchSlize, k)
            var
                error: float = 0.0
                summedWeight: float = 0.0
            for e in errors.mitems:
                let r = ^e
                error += r.error
                summedWeight += r.summedWeight
            error /= summedWeight

            tries += 1                    
            if error < bestError:
                leftTries += 1
                successes += 1

                bestError = error
                bestSolution = currentSolution
            else:
                leftTries -= 1
            
            # print info
            eraseLine()
            let s = $successes & "/" & $tries
            let passedTime = now() - startTime
            stdout.write(
                "iteration: ", fmt"{j:>3}", ", successes: ", fmt"{s:>9}",
                ", error: ", fmt"{bestError:>9.7f}", ", lr: ", lr, ", time: ", $passedTime.inSeconds, " s"
            )
            stdout.flushFile
        
        stdout.write("\n")
        stdout.flushFile

        if oldBestError <= bestError and lr >= minLearningRate:
            previousGradient *= 0.5
            if decreaseLr:
                lr /= 2.0
            else:
                decreaseLr = true
        else:
            decreaseLr = false

        if lr < minLearningRate:
            break

    let filename = "optimizationResult_" & now().format("yyyy-MM-dd-HH-mm-ss") & ".txt"
    echo "filename: ", filename
    writeFile(filename, $bestSolution.convert)
        
    return bestSolution.convert

var data: seq[Entry]
# data.loadData("quietSetZuri.epd")
# data.loadData("quietSetNalwald.epd")
# data.loadData("quietSetCombinedCCRL4040.epd")
# data.loadData("quietSmallPoolGamesNalwald.epd")
# data.loadData("quietSetNalwald2.epd")
data.loadData("quietSmallLichessGamesSet.epd")

let startingEvalParametersFloat = startingEvalParameters

let ep = startingEvalParametersFloat.optimize(data)
printPieceValues(ep)
