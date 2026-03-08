#AutoIt3Wrapper_UseX64=n

; ============================================================
; Example: Reusing compiled binaries
;
; Compiling code via the Godbolt API requires a network request
; which takes time and puts load on the server.
; After the first successful compile, save the ReusableString
; and reuse it in future runs with _JIT_LoadBinary().
;
; Workflow:
;   1. Compile once with _JIT_Compile, note $mCode.ReusableString
;   2. Paste the ReusableString into your script as a constant
;   3. Use _JIT_LoadBinary() for all subsequent runs
;      (returns the same map structure as _JIT_Compile, including Funcs)
; ============================================================

#include "..\JIT.au3"

; --- STEP 1: First run - compile and output the reusable string ---
; (uncomment this section to compile and get the ReusableString)
;~ Global $sSourceCode = _
;~ 'CALLCONV double doubleIt(double x) {' & @LF & _
;~ '    return x * 2.0;                 ' & @LF & _
;~ '}' & @LF & _
;~ 'CALLCONV double tripleIt(double x) {' & @LF & _
;~ '    return x * 3.0;                 ' & @LF & _
;~ '}'
;~ Global $mCode = _JIT_Compile($sSourceCode)
;~ If @error Then Exit MsgBox(16, "Error", "Compilation failed")
;~ ; print the ReusableString - contains binary AND function offsets
;~ ConsoleWrite("ReusableString: " & $mCode.ReusableString & @CRLF)
;~ _JIT_Free($mCode)


; --- STEP 2: Subsequent runs - load from saved ReusableString ---
; these strings were captured from a previous _JIT_Compile call
; (one for 64-bit, one for 32-bit AutoIt)
Global $sReusable = @AutoItX64 _
		? '{"b":"f20f58c0c366662e0f1f840000000000f20f590508000000c3CCCCCCCCCCCCCC0000000000000840","f":{"doubleIt":0,"tripleIt":16}}' _
		: '{"b":"dd442404d8c0c208008db42600000000d90500000000dc4c2404c20800","f":{"doubleIt":0,"tripleIt":16}}'

; load the binary into executable memory - no API call needed!
; function offsets are included automatically
Global $mCode = _JIT_LoadBinary($sReusable)
If @error Then Exit MsgBox(16, "Error", "Failed to load binary")

; call functions using pointer + offset, just like with _JIT_Compile
Global $aResult = DllCallAddress("double", $mCode.ptr + $mCode.Funcs["doubleIt"], "DOUBLE", 21.0)
ConsoleWrite("doubleIt(21.0) = " & $aResult[0] & @CRLF) ; expected: 42.0

If MapExists($mCode.Funcs, "tripleIt") Then
	$aResult = DllCallAddress("double", $mCode.ptr + $mCode.Funcs["tripleIt"], "DOUBLE", 21.0)
	ConsoleWrite("tripleIt(21.0) = " & $aResult[0] & @CRLF) ; expected: 63.0
EndIf

_JIT_Free($mCode)
