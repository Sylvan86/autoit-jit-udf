#AutoIt3Wrapper_UseX64=y

; ============================================================
; Example: GCC __builtin functions
;
; Since the code is compiled without access to the C standard
; library, you CANNOT use #include <math.h> or similar headers.
; However, GCC provides __builtin_* functions that compile to
; efficient CPU instructions without needing any #include.
;
; IMPORTANT: Many builtins (even with the __builtin_ prefix!)
; internally call the C math library (libm) which is NOT
; linked here. To force GCC to emit inline CPU instructions
; instead, use the compiler flag: -ffast-math
; Without it, even __builtin_fmin or __builtin_floor will
; generate library calls and CRASH.
;
; Always work (no special flags needed):
;   __builtin_sqrt(x)      - square root             (sqrtsd)
;   __builtin_fabs(x)      - absolute value           (andpd)
;
; Work WITH -ffast-math flag:
;   __builtin_fmin(x,y)    - minimum of two doubles   (minsd)
;   __builtin_fmax(x,y)    - maximum of two doubles   (maxsd)
;   __builtin_ceil(x)      - round up to integer      (roundsd)
;   __builtin_floor(x)     - round down to integer    (roundsd)
;   __builtin_round(x)     - round to nearest integer (roundsd)
;
; NEVER work (always need libm, will CRASH):
;   __builtin_sin, __builtin_cos, __builtin_tan,
;   __builtin_exp, __builtin_log, __builtin_log2, __builtin_log10,
;   __builtin_pow
;
; Integer builtins (always work, no flags needed):
;   __builtin_abs(x)       - absolute value (integer)
;   __builtin_popcount(x)  - count set bits           (popcnt)
;   __builtin_clz(x)       - count leading zeros      (bsr)
;   __builtin_ctz(x)       - count trailing zeros     (bsf)
;   __builtin_bswap32(x)   - reverse byte order       (bswap)
;   __builtin_bswap64(x)   - reverse byte order       (bswap)
; ============================================================

#include "..\JIT.au3"

Global $sSourceCode = _
'CALLCONV double hypotenuse(double a, double b) {          ' & @LF & _
'    return __builtin_sqrt(a * a + b * b);                 ' & @LF & _
'}                                                         ' & @LF & _
'                                                          ' & @LF & _
'CALLCONV double clamp(double val, double lo, double hi) { ' & @LF & _
'    return __builtin_fmin(__builtin_fmax(val, lo), hi);   ' & @LF & _
'}                                                         ' & @LF & _
'                                                          ' & @LF & _
'CALLCONV double roundDown(double x) {                     ' & @LF & _
'    return __builtin_floor(x);                            ' & @LF & _
'}'

; -ffast-math is CRITICAL: without it, builtins like fmin/fmax/floor
; generate calls to the C math library (libm) which is not available here
Global $mCode = _JIT_Compile($sSourceCode, "-O2 -ffast-math")
If @error Then Exit MsgBox(16, "Error", "Compilation failed")

; hypotenuse(3, 4) = 5.0  (uses __builtin_sqrt)
Global $aDll = DllCallAddress("double", $mCode.ptr + $mCode.Funcs["hypotenuse"], "DOUBLE", 3.0, "DOUBLE", 4.0)
ConsoleWrite("hypotenuse(3, 4) = " & $aDll[0] & @CRLF)

; clamp(7.5, 0, 5) = 5.0  (uses __builtin_fmin + __builtin_fmax)
$aDll = DllCallAddress("double", $mCode.ptr + $mCode.Funcs["clamp"], "DOUBLE", 7.5, "DOUBLE", 0.0, "DOUBLE", 5.0)
ConsoleWrite("clamp(7.5, 0, 5) = " & $aDll[0] & @CRLF)

; roundDown(3.7) = 3.0  (uses __builtin_floor)
$aDll = DllCallAddress("double", $mCode.ptr + $mCode.Funcs["roundDown"], "DOUBLE", 3.7)
ConsoleWrite("roundDown(3.7) = " & $aDll[0] & @CRLF)

_JIT_Free($mCode)
