#AutoIt3Wrapper_UseX64=y

; ============================================================
; Example: Scalar operations
; Demonstrates the basic principle of compiling a simple C
; function and calling it from AutoIt with scalar values.
; ============================================================

#include "..\JIT.au3"

; Define a simple C function that doubles a value
; Every exported function must be prefixed with CALLCONV
Global $sSourceCode = _
'CALLCONV double doubleIt(double x) {' & @LF & _
'    return x * 2.0;                 ' & @LF & _
'}'

; compile the code via the Godbolt Compiler Explorer API
Global $mCode = _JIT_Compile($sSourceCode)
If @error Then Exit MsgBox(16, "Error", "Compilation failed")

; call the compiled function using DllCallAddress
Global $aDll = DllCallAddress("double", $mCode.FuncPtr["doubleIt"], "DOUBLE", 21.0)
ConsoleWrite("doubleIt(21.0) = " & $aDll[0] & @CRLF) ; expected: 42.0

; always free the allocated executable memory when done
_JIT_Free($mCode)
