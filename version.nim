import strutils

func version*(): string = "Anarkin"
func compileDate*(): string = CompileDate & " " & CompileTime & " (UTC)"
func compileYear*(): string = CompileDate.split('-')[0]
