#AutoIt3Wrapper_UseX64=y

; ============================================================
; Example: String processing
; Demonstrates passing a string to a compiled C function
; which modifies it in-place using alternating case.
; ============================================================

#include "..\JIT.au3"

; alternatingCase: converts every letter to alternating upper/lower case
; non-letter characters are skipped without affecting the alternation
; uses ASCII arithmetic instead of <ctype.h> (no #include available)
Global $sSourceCode = _
'CALLCONV void alternatingCase(char *str) {' & @LF & _
'    int upper = 1;                        ' & @LF & _
'    for (int i = 0; str[i] != 0; i++) {   ' & @LF & _
'        char c = str[i];                  ' & @LF & _
'        if (c >= 65 && c <= 90) {         ' & @LF & _
'            str[i] = upper ? c : c + 32;  ' & @LF & _
'            upper = !upper;               ' & @LF & _
'        } else if (c >= 97 && c <= 122) { ' & @LF & _
'            str[i] = upper ? c - 32 : c;  ' & @LF & _
'            upper = !upper;               ' & @LF & _
'        }                                 ' & @LF & _
'    }                                     ' & @LF & _
'}'

; compile
Global $mCode = _JIT_Compile($sSourceCode)
If @error Then Exit MsgBox(16, "Error", "Compilation failed")

; pass the string using "STR" type
; AutoIt creates an internal ANSI buffer which the C function modifies in-place
; the modified result can be read back from $aDll[1] (first parameter)
Global $sInput = "Hello World, this is a JIT Test!"
Global $aDll = DllCallAddress("none", $mCode.FuncPtr["alternatingCase"], "STR", $sInput)

ConsoleWrite("Input:  " & $sInput & @CRLF)
ConsoleWrite("Output: " & $aDll[1] & @CRLF)
; expected: HeLlO wOrLd, ThIs Is A jIt TeSt!

_JIT_Free($mCode)
