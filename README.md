# JIT.au3 - Compile and Run C Code Directly from AutoIt

Sometimes you wish critical parts of your AutoIt script could run at native speed - tight loops, numerical algorithms, or bit-level operations that AutoIt simply wasn't designed for. **JIT.au3** lets you write C code as a string, compile it at runtime, and call it directly from AutoIt.

No compiler installation required. All you need is this UDF and an internet connection.
The compilation is handled by the [Compiler Explorer (Godbolt)](https://godbolt.org/) API - the compiled machine code is loaded into executable memory and made callable via `DllCallAddress`.

## Quick Start

```autoit
#include "JIT.au3"

; Write C code - prefix exported functions with CALLCONV
Global $sCode = _
    'CALLCONV double doubleIt(double x) {' & @LF & _
    '    return x * 2.0;                 ' & @LF & _
    '}'

; Compile via Godbolt API
Global $mCode = _JIT_Compile($sCode)

; Call the compiled function
Global $aResult = DllCallAddress("double", $mCode.ptr + $mCode.Funcs["doubleIt"], "DOUBLE", 21.0)
ConsoleWrite("Result: " & $aResult[0] & @CRLF)  ; → 42.0

; Free memory when done
_JIT_Free($mCode)
```

## Compile Once, Reuse Forever

> **Please treat the Godbolt API with respect.**
> The [Compiler Explorer](https://godbolt.org/) is a free community project. Every call to `_JIT_Compile` sends a request to their servers.

After the first successful compilation, save the binary string and reuse it - no further API calls needed and much faster startup:

```autoit
; First run: compile and note the binary
Global $mCode = _JIT_Compile($sCode)
ConsoleWrite($mCode.BinaryString & @CRLF)  ; → save this string
_JIT_Free($mCode)

; All subsequent runs: load from saved binary (no internet needed!)
Global $mCode = _JIT_LoadBinary("f20f58c0c3")
```

See [`examples/example_reuse.au3`](examples/example_reuse.au3) for a complete walkthrough.

## API Overview

| Function | Description |
|----------|-------------|
| `_JIT_Compile($sCode)` | Compile C code and return executable memory |
| `_JIT_LoadBinary($sBinary)` | Load a previously compiled binary (no API call) |
| `_JIT_Free($mCode)` | Release allocated executable memory |
| `_JIT_SetServer(...)` | Configure server, compiler, language, proxy |
| `_JIT_GetCompilers()` | List available compilers |
| `_JIT_GetLanguages()` | List available languages |
| `_JIT_DescribeOpcode($sOp)` | Get description of an assembler opcode |

## Limitations

This UDF is designed for **small, self-contained code snippets** - not for full C projects.

- **No `#include` support** - the C standard library is not available. There is no linker; the code must be fully self-contained.
- **No `math.h` functions** - `sin()`, `cos()`, `pow()` etc. require `libm` which is not linked. Some GCC `__builtin_*` functions work as inline alternatives (see [`examples/example_builtins.au3`](examples/example_builtins.au3)).
- **Internet required for compilation** - use `_JIT_LoadBinary` to work offline after the first compile.
- **Single translation unit** - all code must be in one string, no multi-file compilation.

## Examples

| Example | Description |
|---------|-------------|
| [`example_scalar.au3`](examples/example_scalar.au3) | Basic principle - compile and call a simple function |
| [`example_array.au3`](examples/example_array.au3) | Pass an array to C - Kahan summation vs. naive summation |
| [`example_string.au3`](examples/example_string.au3) | String processing - alternating case transformation |
| [`example_builtins.au3`](examples/example_builtins.au3) | GCC `__builtin_*` functions - what works, what doesn't |
| [`example_reuse.au3`](examples/example_reuse.au3) | Save and reload compiled binaries for offline use |

## Dependencies

- [JSON.au3](https://github.com/Sylvan86/autoit-json-udf) - JSON UDF for API communication (included in release)

## Acknowledgements

This project would not be possible without the **[Compiler Explorer (Godbolt)](https://godbolt.org/)** by Matt Godbolt and contributors. It is an incredible open-source tool for the programming community. Please use their API responsibly.
