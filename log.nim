import std/[
    logging,
    strutils,
    strformat,
    os,
    times,
    locks
]

export strformat

let
    logDir = "logs"
    appName = getAppFilename().splitFile.name
    logFilePath = fmt"{logDir}/{appName}_Latest.log"
    previousLogFilePath = fmt"{logDir}/{appName}_Previous.log"

discard existsOrCreateDir(logDir)

if fileExists logFilePath:
    moveFile logFilePath, previousLogFilePath

var
    consoleLog = newConsoleLogger(levelThreshold = lvlWarn, fmtStr = "")
    fileLog = newFileLogger(
        filename = logFilePath,
        fmtStr = "",
        mode = fmWrite,
        levelThreshold = lvlInfo
    )
    loggingLock: Lock

type Pos = tuple[filename: string, line: int, column: int]

template logCustom[L: ConsoleLogger or FileLogger](logger: var L, lvl: Level, pos: static Pos, args: varargs[string, `$`]): untyped =
    let addition = "[$1][$2:$3] - $4: " % [now().format("yyyy-MM-dd HH:mm:ss'.'fff"), pos.filename, $pos.line, LevelNames[lvl]]
    var
        s = addition
        indent = ""

    for i in 0..<s.len:
        indent.add ' '
       
    for a in args:
        s &= a

    let lines = s.split('\n')
    var finalS = ""

    for i, line in lines:
        if i > 0:
            finalS &= '\n' & indent
        finalS &= line

    logger.log(lvl, finalS)

template logFile(lvl: Level, pos: static Pos, args: varargs[string, `$`]): untyped =
    logCustom(fileLog, lvl, pos, args)
    fileLog.file.flushFile

template echoLog*(args: varargs[string, `$`]): untyped =
    const ii = instantiationInfo()
    {.cast(noSideEffect).}:
        withLock loggingLock:
            logFile(lvlInfo, ii, args)

            var s: string
            for a in args:
                s &= a
            debugEcho s

template logCustom(lvl: Level, pos: static Pos, args: varargs[string, `$`]): untyped =
    {.cast(noSideEffect).}:
        withLock loggingLock:
            logCustom(consoleLog, lvl, pos, args)
            logFile(lvl, pos, args)

template logDebug*(args: varargs[string, `$`]) =
    logCustom(lvlDebug, instantiationInfo(), args)

template logInfo*(args: varargs[string, `$`]) =
    logCustom(lvlInfo, instantiationInfo(), args)

template logNotice*(args: varargs[string, `$`]) =
    logCustom(lvlNotice, instantiationInfo(), args)

template logWarn*(args: varargs[string, `$`]) =
    logCustom(lvlWarn, instantiationInfo(), args)

template logError*(args: varargs[string, `$`]) =
    logCustom(lvlError, instantiationInfo(), args)

template logFatal*(args: varargs[string, `$`]) =
    logCustom(lvlFatal, instantiationInfo(), args)

template fileDebug*(args: varargs[string, `$`]) =
    logFile(lvlDebug, instantiationInfo(), args)

template fileInfo*(args: varargs[string, `$`]) =
    logFile(lvlInfo, instantiationInfo(), args)

template fileNotice*(args: varargs[string, `$`]) =
    logFile(lvlNotice, instantiationInfo(), args)

template fileWarn*(args: varargs[string, `$`]) =
    logFile(lvlWarn, instantiationInfo(), args)

template fileError*(args: varargs[string, `$`]) =
    logFile(lvlError, instantiationInfo(), args)

template fileFatal*(args: varargs[string, `$`]) =
    logFile(lvlFatal, instantiationInfo(), args)

logNotice "APPLICATION STARTUP: ", getAppFilename()