#AutoIt3Wrapper_UseX64=y

; ============================================================
; Example: Array processing - Kahan summation
; Demonstrates passing an array from AutoIt to a compiled C
; function. Uses the Kahan summation algorithm which is more
; numerically stable than naive summation.
;
; The test data:  [1e16, 1.0, 1.0, ...(10000x)..., -1e16]
; Mathematically:  1e16 + 10000 * 1.0 - 1e16 = 10000.0
;
; But in double arithmetic, 1e16 + 1.0 = 1e16 (the 1.0 is
; lost because the ULP at 1e16 is 2.0). So naive summation
; accumulates 1e16, adds 10000 ones that all vanish, then
; subtracts 1e16 and gets 0.0 instead of 10000.0.
;
; Kahan summation tracks the lost digits in a compensation
; variable, so it correctly returns 10000.0.
; ============================================================

#include "..\JIT.au3"

; Kahan compensated summation: tracks rounding errors in a
; separate compensation variable to preserve precision.
Global $sSourceCode = _
'CALLCONV double kahanSum(double *arr, int n) {' & @LF & _
'    double sum = 0.0;                         ' & @LF & _
'    double comp = 0.0;                        ' & @LF & _
'    for (int i = 0; i < n; i++) {             ' & @LF & _
'        double y = arr[i] - comp;             ' & @LF & _
'        double t = sum + y;                   ' & @LF & _
'        comp = (t - sum) - y;                 ' & @LF & _
'        sum = t;                              ' & @LF & _
'    }                                         ' & @LF & _
'    return sum;                               ' & @LF & _
'}'

; compile
Global $mCode = _JIT_Compile($sSourceCode)
If @error Then Exit MsgBox(16, "Error", "Compilation failed")

; build test data
Global Const $iONES = 10000
Global $iN = $iONES + 2
Global $tData = DllStructCreate("DOUBLE [" & $iN & "]")
DllStructSetData($tData, 1, 1e16, 1)
For $i = 2 To $iN - 1
	DllStructSetData($tData, 1, 1.0, $i)
Next
DllStructSetData($tData, 1, -1e16, $iN)

; Kahan summation via compiled C code
Global $aDll = DllCallAddress("double", $mCode.FuncPtr["kahanSum"], _
		"PTR", DllStructGetPtr($tData), _
		"INT", $iN)

; naive summation in AutoIt for comparison
Global $fNaiveSum = 1e16
For $i = 1 To $iONES
	$fNaiveSum += 1.0
Next
$fNaiveSum -= 1e16

; expected correct result: 10000.0
ConsoleWrite(StringFormat("Correct answer:  %d", $iONES) & @CRLF)
ConsoleWrite(StringFormat("Kahan sum:       %.1f", $aDll[0]) & @CRLF)
ConsoleWrite(StringFormat("Naive sum:       %.1f", $fNaiveSum) & @CRLF)

_JIT_Free($mCode)
