#AutoIt3Wrapper_UseX64=y

; ============================================================
; Example: Reusing compiled binaries
;
; Compiling code via the Godbolt API requires a network request
; which takes time and puts load on the server.
; After the first successful compile, save the BinaryString
; and reuse it in future runs with _JIT_LoadBinary().
;
; Workflow:
;   1. Compile once with _JIT_Compile, note $mCode.BinaryString
;   2. Paste the binary string into your script as a constant
;   3. Use _JIT_LoadBinary() for all subsequent runs
; ============================================================

#include "..\JIT.au3"

; --- STEP 1: First run - compile and output the binary string ---
; (uncomment this section to compile and get the binary string)
;~ Global $sSourceCode = _
;~ 'CALLCONV double doubleIt(double x) {' & @LF & _
;~ '    return x * 2.0;                 ' & @LF & _
;~ '}'
;~ Global $mCode = _JIT_Compile($sSourceCode)
;~ If @error Then Exit MsgBox(16, "Error", "Compilation failed")
;~ ; print the binary string and function offsets for reuse
;~ ConsoleWrite("BinaryString: " & $mCode.BinaryString & @CRLF)
;~ ; for multiple functions, also save the Funcs map
;~ For $sKey In MapKeys($mCode.Funcs)
;~     ConsoleWrite("Func: " & $sKey & " = " & $mCode.Funcs[$sKey] & @CRLF)
;~ Next
;~ _JIT_Free($mCode)


; --- STEP 2: Subsequent runs - load from saved binary ---
; these binary strings were captured from a previous _JIT_Compile call
; (one for 64-bit, one for 32-bit AutoIt)
Global $sBinary = @AutoItX64 _
		? "f20f58c0c3" _
		: "dd44240483c0f4dc0424d9c9c20400"

; load the binary into executable memory - no API call needed!
Global $mCode = _JIT_LoadBinary($sBinary)
If @error Then Exit MsgBox(16, "Error", "Failed to load binary")

; call the function (single function = offset 0, so use .ptr directly)
Global $aDll = DllCallAddress("double", $mCode.ptr, "DOUBLE", 21.0)
ConsoleWrite("doubleIt(21.0) = " & $aDll[0] & @CRLF) ; expected: 42.0

_JIT_Free($mCode)
