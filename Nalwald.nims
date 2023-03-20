import version

--mm:arc
--define:useMalloc
--passL:"-static"
--cc:clang
--threads:on
--styleCheck:hint

func lto() =
    --passC:"-flto"
    --passL:"-flto"

    if defined(windows):
        --passL:"-fuse-ld=lld"

func highPerformance() =
    --panics:on    
    --define:danger
    lto()

func debuggerProfilerInfo() =
    --passC:"-fno-omit-frame-pointer -g"
    --debugger:native

let suffix = if defined(windows): ".exe" else: ""
let name = projectName() & "-" & version()

task debug, "debug compile":
    --define:debug
    --passC:"-O2"
    debuggerProfilerInfo()
    switch("o", name & "-debug" & suffix)
    setCommand "c"

task checks, "checks compile":
    --define:release
    debuggerProfilerInfo()
    switch("o", name & "-checks" & suffix)
    setCommand "c"

task profile, "profile compile":
    highPerformance()
    debuggerProfilerInfo()
    switch("o", name & "-profile" & suffix)
    setCommand "c"

task default, "default compile":
    highPerformance()
    switch("o", name & suffix)
    setCommand "c"

task native, "native compile":
    highPerformance()
    --passC:"-march=native"
    --passC:"-mtune=native"
    switch("o", name & "-native" & suffix)
    setCommand "c"

task modern, "BMI2 and POPCNT compile":
    highPerformance()
    --passC:"-mbmi2"
    --passC:"-mpopcnt"
    switch("o", name & "-modern" & suffix)
    setCommand "c"