import
    ../position,
    ../positionUtils,
    game,
    times,
    threadpool,
    os,
    psutil,
    tables,
    strutils

proc playGame(fen: string): (string, float) =
    try:
        
        var game = newGame(
            startingPosition = fen.toPosition,
            maxNodes = 50_000,
        )
        return (fen, game.playGame(suppressOutput = true))
        
    except CatchableError:
        echo getCurrentExceptionMsg()
        return ("", -1.0)

const
    maxLoadPercentageCPU = 70.0
    readFilename = "unlabeledQuietSetNalwald2.epd"#"unlabeledQuietSmallNalwaldCCRL4040.epd"
    writeFilename = "quietSetNalwald2.epd"#"quietSmallNalwaldCCRL4040.epd"

proc labelPositions() =
    var alreadyLabeled = block:
        var r: Table[string, int8]
        let g = open(writeFilename)
        var line: string
        while g.readLine(line):
            if line == "":
                continue
            let words = line.splitWhitespace
            doAssert words.len == 7
            let fen = words[0] & " " & words[1] & " " & words[2] & " " & words[3] & " " & words[4] & " " & words[5]
            r[fen.toPosition.fen] = 1
        g.close
        r

    let f = open(readFilename)
    let g = open(writeFilename, fmAppend)

    var line: string
    var i = 0

    var threadResults: seq[FlowVar[(string, float)]]
    template writeResults() =
        var newThreadResults: seq[FlowVar[(string, float)]]
        for tr in threadResults:
            if tr.isReady:
                let (fen, outcome) = ^tr
                if fen != "":
                    g.writeLine(fen & " " & $outcome)
                    g.flushFile
            else:
                newThreadResults.add(tr)
        threadResults = newThreadResults

    while f.readLine(line):
        i += 1
        if (i mod 1000) == 0:
            echo i
        let fen = line.toPosition.fen 
        if fen in alreadyLabeled and alreadyLabeled[fen] == 1:
            alreadyLabeled[fen] = 0
            continue
        writeResults()
        while cpu_percent() >= maxLoadPercentageCPU:
            sleep(10)
        threadResults.add(spawn playGame(fen))
        sleep(10)
    
    while threadResults.len > 0:
        writeResults()

    f.close
    g.close

labelPositions()