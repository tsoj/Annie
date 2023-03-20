import 
    ../position,
    ../positionUtils,
    ../evalParameters,
    ../evaluation,
    winningProbability,
    error,
    strutils

type Entry* = object
    position*: Position
    outcome*: float
    weight*: float

proc loadData*(data: var seq[Entry], filename: string, weight: float = 1.0, maxLen = int.high, suppressOutput = false) =
    let f = open(filename)
    var line: string
    var numEntries = 0
    while f.readLine(line):
        let words = line.splitWhitespace()
        if words.len == 0 or words[0] == "LICENSE:":
            continue
        doAssert words.len >= 7
        numEntries += 1
        data.add(Entry(position: line.toPosition(suppressWarnings = true), outcome: words[6].parseFloat, weight: weight))
        if numEntries >= maxLen:
            break
    f.close()
    if not suppressOutput:
        debugEcho filename & ": ", numEntries, " entries", ", weight: ", numEntries.float * weight


func error*(evalParameters: EvalParameters, entry: Entry, k: float): float =
    let estimate = entry.position.absoluteEvaluate(evalParameters).winningProbability(k)
    error(entry.outcome, estimate)*entry.weight

func errorTuple*(evalParameters: EvalParameters, data: openArray[Entry], k: float): tuple[error, summedWeight: float] =
    result.error = 0.0    
    result.summedWeight = 0.0
    for entry in data:
        result.error += evalParameters.error(entry, k)
        result.summedWeight += entry.weight

func error*(evalParameters: EvalParameters, data: openArray[Entry], k: float): float =
    let (error, summedWeight) = evalParameters.errorTuple(data, k)
    error / summedWeight
