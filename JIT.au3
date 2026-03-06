#AutoIt3Wrapper_Au3Check_Parameters=-d -w 1 -w 2 -w 3 -w 4 -w 5 -w 6 -w 7
#include-once

#include "JSON.au3" ; https://github.com/Sylvan86/autoit-json-udf

; #INDEX# =======================================================================================================================
; Title .........: JIT
; AutoIt Version : 3.3.18.0
; Description ...: Compiles C code at runtime via the Godbolt Compiler Explorer API and makes it callable via DllCallAddress.
; Author(s) .....: AspirinJunkie
; Dll ...........: kernel32.dll
; ===============================================================================================================================

; #CURRENT# =====================================================================================================================
;_JIT_Compile
;_JIT_DescribeOpcode
;_JIT_Free
;_JIT_GetCompilers
;_JIT_GetLanguages
;_JIT_LoadBinary
;_JIT_SetServer
; ===============================================================================================================================

; #INTERNAL_USE_ONLY# ===========================================================================================================
;__JIT_BinaryToStruct
;__JIT_CompileCode
;__JIT_GetHTTP
;__JIT_IntToHexLE
;__JIT_ParseConstants
;__JIT_SendGET
;__JIT_SendPOST
; ===============================================================================================================================

; #CONSTANTS# ===================================================================================================================
Global Const $__JIT_MEM_COMMIT             = 0x1000
Global Const $__JIT_MEM_RELEASE            = 0x8000
Global Const $__JIT_PAGE_EXECUTE_READWRITE = 0x40
Global Const $__JIT_INT3                   = "CC" ; padding opcode between code and data
; ===============================================================================================================================

; #VARIABLES# ===================================================================================================================
Global $__g_JIT_oHTTP       = Null
Global $__g_JIT_sDomain     = "https://godbolt.org"
Global $__g_JIT_sLangID     = "c"
Global $__g_JIT_sCompilerID = "cg152"
Global $__g_JIT_sProxy      = ""
; ===============================================================================================================================


; #FUNCTION# ====================================================================================================================
; Name...........: _JIT_SetServer
; Description ...: Configures the Compiler Explorer server connection
; Syntax.........: _JIT_SetServer([$sDomain[, $sCompilerID[, $sLangID[, $sProxy]]]])
; Parameters ....: $sDomain     - [optional] Domain of the Compiler Explorer instance. Default is "https://godbolt.org".
;                  $sCompilerID - [optional] Compiler ID to use (derive with _JIT_GetCompilers). Default is "cg152".
;                  $sLangID     - [optional] Language ID (derive with _JIT_GetLanguages). Default is "c".
;                  $sProxy      - [optional] Proxy address (e.g. "localhost:3128"). Default is "" (no proxy).
; Return values .: None
; Author ........: AspirinJunkie
; Modified.......:
; Remarks .......: Call this before _JIT_Compile if you need non-default settings.
;                  Changing the proxy resets the internal HTTP object.
; Related .......: _JIT_Compile, _JIT_GetCompilers, _JIT_GetLanguages
; Link ..........:
; Example .......: Yes
; ===============================================================================================================================
Func _JIT_SetServer($sDomain = Default, $sCompilerID = Default, $sLangID = Default, $sProxy = Default)
	If $sDomain <> Default Then $__g_JIT_sDomain = $sDomain
	If $sCompilerID <> Default Then $__g_JIT_sCompilerID = $sCompilerID
	If $sLangID <> Default Then $__g_JIT_sLangID = $sLangID
	If $sProxy <> Default Then
		$__g_JIT_sProxy = $sProxy
		$__g_JIT_oHTTP = Null ; reset to apply new proxy settings
	EndIf
EndFunc   ;==>_JIT_SetServer


; #FUNCTION# ====================================================================================================================
; Name...........: _JIT_Compile
; Description ...: Compiles C source code via Godbolt and returns an executable memory structure
; Syntax.........: _JIT_Compile($sCode[, $sCompilerFlags = "-O2"])
; Parameters ....: $sCode          - C source code as string. Prefix exported functions with CALLCONV.
;                  $sCompilerFlags - [optional] Additional compiler flags. Default is "-O2".
; Return values .: Success         - Map with keys:
;                                  |.ptr    - Pointer to executable memory (use with DllCallAddress)
;                                  |.Funcs  - Map of function names to their byte offsets
;                                  |.Code   - Disassembled ASM code as string
;                                  |.Binary - Raw binary data
;                  Failure         - Null and @error is set:
;                                  |1 - Compilation failed
;                                  |2 - HTTP object creation failed
; Author ........: AspirinJunkie
; Modified.......:
; Remarks .......: The CALLCONV macro is automatically defined based on the AutoIt process architecture:
;                  - 64-bit: __attribute__((ms_abi))
;                  - 32-bit: __attribute__((stdcall))
;                  Use _JIT_Free to release the allocated memory when no longer needed.
; Related .......: _JIT_Free, _JIT_SetServer
; Link ..........: https://github.com/compiler-explorer/compiler-explorer/blob/main/docs/API.md
; Example .......: Yes
; ===============================================================================================================================
Func _JIT_Compile($sCode, $sCompilerFlags = "-O2")
	If @AutoItX64 Then
		$sCode = '#define CALLCONV __attribute__((ms_abi))' & @LF & $sCode
		$sCompilerFlags &= " -m64"
	Else
		$sCode = '#define CALLCONV __attribute__((stdcall))' & @LF & $sCode
		$sCompilerFlags &= " -m32"
	EndIf

	Local $mCompiled = __JIT_CompileCode($sCode, $sCompilerFlags)
	If @error Then Return SetError(@error, 0, Null)

	$mCompiled.struct = __JIT_BinaryToStruct($mCompiled.Binary)
	If @error Then Return SetError(3, 0, Null)
	$mCompiled.ptr = DllStructGetPtr($mCompiled.struct)

	Return $mCompiled
EndFunc   ;==>_JIT_Compile


; #FUNCTION# ====================================================================================================================
; Name...........: _JIT_LoadBinary
; Description ...: Loads a previously compiled binary string into executable memory
; Syntax.........: _JIT_LoadBinary($sBinaryString[, $mFuncOffsets = Default])
; Parameters ....: $sBinaryString - Hex-encoded binary string (as returned by $mCode.BinaryString from _JIT_Compile)
;                  $mFuncOffsets  - [optional] Map of function name to byte offset (as returned by $mCode.Funcs).
;                                  Default is an empty map (use offset 0 for single-function binaries).
; Return values .: Success       - Map with keys:
;                                 |.ptr    - Pointer to executable memory (use with DllCallAddress)
;                                 |.Funcs  - Map of function names to their byte offsets
;                                 |.struct - Internal DllStruct (prevents garbage collection)
;                  Failure       - Null and @error is set:
;                                 |1 - VirtualAlloc failed
; Author ........: AspirinJunkie
; Modified.......:
; Remarks .......: Use this to skip recompilation by reusing the BinaryString from a previous _JIT_Compile call.
;                  This avoids API calls and is much faster. Use _JIT_Free to release the memory when done.
; Related .......: _JIT_Compile, _JIT_Free
; Link ..........:
; Example .......: Yes
; ===============================================================================================================================
Func _JIT_LoadBinary($sBinaryString, $mFuncOffsets = Default)
	Local $tCode = __JIT_BinaryToStruct("0x" & $sBinaryString)
	If @error Then Return SetError(1, 0, Null)

	Local $mRet[]
	$mRet.ptr = DllStructGetPtr($tCode)
	$mRet.struct = $tCode
	If IsMap($mFuncOffsets) Then
		$mRet.Funcs = $mFuncOffsets
	Else
		Local $mEmpty[]
		$mRet.Funcs = $mEmpty
	EndIf

	Return $mRet
EndFunc   ;==>_JIT_LoadBinary


; #FUNCTION# ====================================================================================================================
; Name...........: _JIT_Free
; Description ...: Releases the executable memory allocated by _JIT_Compile
; Syntax.........: _JIT_Free(ByRef $mCode)
; Parameters ....: $mCode - [byref] Map returned by _JIT_Compile. Will be set to Null after freeing.
; Return values .: Success - True
;                  Failure - False and @error is set to 1
; Author ........: AspirinJunkie
; Modified.......:
; Remarks .......: Always call this when the compiled code is no longer needed to prevent memory leaks.
; Related .......: _JIT_Compile
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _JIT_Free(ByRef $mCode)
	If Not IsMap($mCode) Or Not MapExists($mCode, "ptr") Then Return SetError(1, 0, False)

	DllCall("kernel32.dll", "bool", "VirtualFree", "ptr", $mCode.ptr, "ulong_ptr", 0, "dword", $__JIT_MEM_RELEASE)
	$mCode = Null

	Return True
EndFunc   ;==>_JIT_Free


; #FUNCTION# ====================================================================================================================
; Name...........: _JIT_GetLanguages
; Description ...: Returns a list of languages supported by the Compiler Explorer server
; Syntax.........: _JIT_GetLanguages()
; Parameters ....: None
; Return values .: Success - Array of maps, each containing language properties (id, name, ...)
;                  Failure - Null and @error is set to 1 (HTTP request failed)
; Author ........: AspirinJunkie
; Modified.......:
; Remarks .......:
; Related .......: _JIT_GetCompilers, _JIT_SetServer
; Link ..........: https://github.com/compiler-explorer/compiler-explorer/blob/main/docs/API.md
; Example .......: No
; ===============================================================================================================================
Func _JIT_GetLanguages()
	Local $sResponse = __JIT_SendGET("/api/languages")
	If @error Then Return SetError(1, 0, Null)

	Return _JSON_Parse($sResponse)
EndFunc   ;==>_JIT_GetLanguages


; #FUNCTION# ====================================================================================================================
; Name...........: _JIT_GetCompilers
; Description ...: Returns a list of compilers supported by the Compiler Explorer server
; Syntax.........: _JIT_GetCompilers([$sLang = Default[, $sInstructionSet = Default]])
; Parameters ....: $sLang           - [optional] Filter by language ID (e.g. "c"). Default returns all.
;                  $sInstructionSet - [optional] Filter by instruction set (e.g. "amd64"). Default returns all.
; Return values .: Success          - Array of maps, each containing compiler properties (id, name, instructionSet, ...)
;                  Failure          - Null and @error is set to 1 (HTTP request failed)
; Author ........: AspirinJunkie
; Modified.......:
; Remarks .......:
; Related .......: _JIT_GetLanguages, _JIT_SetServer
; Link ..........: https://github.com/compiler-explorer/compiler-explorer/blob/main/docs/API.md
; Example .......: No
; ===============================================================================================================================
Func _JIT_GetCompilers($sLang = Default, $sInstructionSet = Default)
	Local $sEndpoint = "/api/compilers" & ($sLang = Default ? "" : "/" & $sLang)
	Local $sResponse = __JIT_SendGET($sEndpoint)
	If @error Then Return SetError(1, 0, Null)

	Local $aCompilers = _JSON_Parse($sResponse)

	; filter by instruction set if specified
	If $sInstructionSet <> Default Then
		Local $iNew = 0, $mCompiler
		For $i = 0 To UBound($aCompilers) - 1
			$mCompiler = $aCompilers[$i]
			If Not IsMap($mCompiler) Then ContinueLoop
			If Not MapExists($mCompiler, "instructionSet") Then ContinueLoop
			If $mCompiler["instructionSet"] <> $sInstructionSet Then ContinueLoop
			$aCompilers[$iNew] = $mCompiler
			$iNew += 1
		Next
		ReDim $aCompilers[$iNew]
	EndIf

	Return $aCompilers
EndFunc   ;==>_JIT_GetCompilers


; #FUNCTION# ====================================================================================================================
; Name...........: _JIT_DescribeOpcode
; Description ...: Returns a description of an assembler opcode
; Syntax.........: _JIT_DescribeOpcode($sOpCode[, $sInstructionSet = "amd64"])
; Parameters ....: $sOpCode         - The opcode to describe (e.g. "push", "mov")
;                  $sInstructionSet - [optional] Instruction set. Default is "amd64".
; Return values .: Success          - Map with opcode description (tooltip, html, url, ...)
;                  Failure          - Null and @error is set to 1 (HTTP request failed)
; Author ........: AspirinJunkie
; Modified.......:
; Remarks .......:
; Related .......: _JIT_Compile
; Link ..........: https://github.com/compiler-explorer/compiler-explorer/blob/main/docs/API.md
; Example .......: No
; ===============================================================================================================================
Func _JIT_DescribeOpcode($sOpCode, $sInstructionSet = "amd64")
	Local $sResponse = __JIT_SendGET("/api/asm/" & $sInstructionSet & "/" & $sOpCode)
	If @error Then Return SetError(1, 0, Null)

	Return _JSON_Parse($sResponse)
EndFunc   ;==>_JIT_DescribeOpcode


; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name...........: __JIT_CompileCode
; Description ...: Compiles code via the Compiler Explorer API and returns ASM, binary and function offsets
; Syntax.........: __JIT_CompileCode($sCode[, $sCompilerFlags = "-O2"])
; Parameters ....: $sCode          - Preprocessed C source code (with CALLCONV already defined)
;                  $sCompilerFlags - [optional] Compiler flags. Default is "-O2".
; Return values .: Success         - Map with keys: .Code, .Binary, .BinaryString, .Funcs
;                  Failure         - Null and @error set (1 = compilation failed, 2 = HTTP error)
; Author ........: AspirinJunkie
; Modified.......:
; Remarks .......: Performs up to two API calls: first for binary+relocations, second for constant data if needed.
; Related .......: _JIT_Compile
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func __JIT_CompileCode($sCode, $sCompilerFlags = "-O2")
	; build the POST request body
	Local $mFilters[]
	$mFilters.intel = True
	$mFilters.demangle = True
	$mFilters.labels = True
	$mFilters.directives = True
	$mFilters.commentOnly = True
	$mFilters.binary = True
	$mFilters.binaryObject = True
	$mFilters.execute = False

	Local $mOptions[]
	$mOptions.userArguments = $sCompilerFlags
	$mOptions.filters = $mFilters

	Local $mPostData[]
	$mPostData.source = $sCode
	$mPostData.compiler = $__g_JIT_sCompilerID
	$mPostData.lang = $__g_JIT_sLangID
	$mPostData.options = $mOptions

	; first API call: binary opcodes + relocation entries
	Local $sResponse = __JIT_SendPOST("/api/compiler/" & $__g_JIT_sCompilerID & "/compile", $mPostData)
	If @error Then Return SetError(2, 0, Null)

	; parse ASM lines, binary opcodes, function offsets and relocations
	Local $sASMCode = "", $sBinary = "", $sOpCode
	Local $mFuncs[], $iOffset = 0, $bSkip = False
	Local $aRelocs[16][3], $iRelocCount = 0 ; [][0]=byte position, [][1]=symbol, [][2]=addend

	For $mLine In _JSON_Parse($sResponse).asm
		If Not MapExists($mLine, "text") Then ContinueLoop

		; detect function labels
		If StringRegExp($mLine.text, '^\w+:') Then
			If $mLine.text = "main:" Then
				$bSkip = True
				ContinueLoop
			EndIf
			$bSkip = False
			$mFuncs[StringLeft($mLine.text, StringInStr($mLine.text, ":") - 1)] = $iOffset
		EndIf

		If $bSkip Then ContinueLoop

		; detect relocation entries (e.g. "    R_X86_64_PC32 .LC0-0x4")
		Local $aRelocMatch = StringRegExp($mLine.text, '^\s+R_X86_64_(\w+)\s+([\.\w]+)([+-]0x[0-9a-fA-F]+)?', 1)
		If Not @error Then
			If $aRelocMatch[0] = "PC32" Then
				If $iRelocCount >= UBound($aRelocs, 1) Then ReDim $aRelocs[$iRelocCount * 2][3]
				$aRelocs[$iRelocCount][0] = $iOffset - 4
				$aRelocs[$iRelocCount][1] = $aRelocMatch[1]
				$aRelocs[$iRelocCount][2] = 0
				If UBound($aRelocMatch) > 2 And $aRelocMatch[2] <> "" Then
					Local $iSign = (StringLeft($aRelocMatch[2], 1) = "-") ? -1 : 1
					$aRelocs[$iRelocCount][2] = $iSign * Dec(StringRegExpReplace($aRelocMatch[2], '^[+-]0x', ''))
				EndIf
				$iRelocCount += 1
			EndIf
			ContinueLoop
		EndIf

		$sASMCode &= $mLine.text & @CRLF

		If MapExists($mLine, "opcodes") Then
			For $sOpCode In $mLine.opcodes
				$sBinary &= $sOpCode
				$iOffset += 1
			Next
		EndIf
	Next

	; check for compilation failure
	If $sBinary = "" Then Return SetError(1, 0, Null)

	; if relocations exist: fetch constant data and patch the binary
	If $iRelocCount > 0 Then
		; second API call: pure ASM output for .LC* constant data
		_JSON_addChangeDelete($mPostData, "options.filters.binary", False)
		_JSON_addChangeDelete($mPostData, "options.filters.binaryObject", False)
		_JSON_addChangeDelete($mPostData, "options.filters.labels", False)
		_JSON_addChangeDelete($mPostData, "options.filters.directives", False)
		_JSON_addChangeDelete($mPostData, "options.filters.commentOnly", False)

		Local $sAsmResponse = __JIT_SendPOST("/api/compiler/" & $__g_JIT_sCompilerID & "/compile", $mPostData)
		If @error Then Return SetError(2, 0, Null)

		Local $mConstants = __JIT_ParseConstants($sAsmResponse)

		; pad code section to 8-byte alignment
		While Mod($iOffset, 8) <> 0
			$sBinary &= $__JIT_INT3
			$iOffset += 1
		WEnd

		; append constant data and record their positions
		Local $mDataOffsets[]
		For $sKey In MapKeys($mConstants)
			$mDataOffsets[$sKey] = $iOffset
			$sBinary &= $mConstants[$sKey]
			$iOffset += StringLen($mConstants[$sKey]) / 2
		Next

		; patch RIP-relative displacements: displacement = targetOffset + addend - patchOffset
		For $i = 0 To $iRelocCount - 1
			Local $sSymbol = $aRelocs[$i][1]
			If Not MapExists($mDataOffsets, $sSymbol) Then ContinueLoop
			Local $iDisp = $mDataOffsets[$sSymbol] + $aRelocs[$i][2] - $aRelocs[$i][0]
			Local $sHex = __JIT_IntToHexLE($iDisp, 4)
			; replace 4 bytes (8 hex chars) at the patch position
			Local $iHexPos = $aRelocs[$i][0] * 2
			$sBinary = StringLeft($sBinary, $iHexPos) & $sHex & StringMid($sBinary, $iHexPos + 9)
		Next
	EndIf

	Local $mRet[]
	$mRet.Code = $sASMCode
	$mRet.Binary = Binary("0x" & $sBinary)
	$mRet.BinaryString = $sBinary
	$mRet.Funcs = $mFuncs

	Return $mRet
EndFunc   ;==>__JIT_CompileCode


; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name...........: __JIT_BinaryToStruct
; Description ...: Allocates executable memory and copies binary data into it
; Syntax.........: __JIT_BinaryToStruct($bBinary)
; Parameters ....: $bBinary - Binary data to make executable
; Return values .: Success  - DllStruct with executable memory
;                  Failure  - Null and @error set to 1 (VirtualAlloc failed)
; Author ........: AspirinJunkie
; Modified.......:
; Remarks .......: Memory is allocated with PAGE_EXECUTE_READWRITE via VirtualAlloc.
;                  Use _JIT_Free to release the memory.
; Related .......: _JIT_Compile, _JIT_Free
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func __JIT_BinaryToStruct($bBinary)
	If IsString($bBinary) Then $bBinary = Binary($bBinary)
	Local $iSize = BinaryLen($bBinary)

	Local $aResult = DllCall("kernel32.dll", "ptr", "VirtualAlloc", _
			"ptr", 0, _
			"ulong_ptr", $iSize, _
			"dword", $__JIT_MEM_COMMIT, _
			"dword", $__JIT_PAGE_EXECUTE_READWRITE)
	If @error Or $aResult[0] = 0 Then Return SetError(1, 0, Null)

	Local $tCode = DllStructCreate("byte[" & $iSize & "]", $aResult[0])
	DllStructSetData($tCode, 1, $bBinary)

	Return $tCode
EndFunc   ;==>__JIT_BinaryToStruct


; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name...........: __JIT_GetHTTP
; Description ...: Returns the shared WinHTTP request object, creating it on first use
; Syntax.........: __JIT_GetHTTP()
; Parameters ....: None
; Return values .: Success - WinHTTP request object
;                  Failure - Null and @error set to 1
; Author ........: AspirinJunkie
; Modified.......:
; Remarks .......: Applies proxy settings from _JIT_SetServer if configured.
; Related .......: _JIT_SetServer
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func __JIT_GetHTTP()
	If Not IsObj($__g_JIT_oHTTP) Then
		$__g_JIT_oHTTP = ObjCreate("winhttp.winhttprequest.5.1")
		If Not IsObj($__g_JIT_oHTTP) Then Return SetError(1, 0, Null)
		If $__g_JIT_sProxy <> "" Then $__g_JIT_oHTTP.SetProxy(2, $__g_JIT_sProxy)
	EndIf
	Return $__g_JIT_oHTTP
EndFunc   ;==>__JIT_GetHTTP


; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name...........: __JIT_SendPOST
; Description ...: Sends a JSON POST request to the Compiler Explorer API
; Syntax.........: __JIT_SendPOST($sEndpoint, $mPostData)
; Parameters ....: $sEndpoint - API endpoint path (e.g. "/api/compiler/cg152/compile")
;                  $mPostData - Map to be serialized as JSON body
; Return values .: Success    - Response text
;                  Failure    - "" and @error set to 1
; Author ........: AspirinJunkie
; Modified.......:
; Remarks .......:
; Related .......: __JIT_SendGET, __JIT_GetHTTP
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func __JIT_SendPOST($sEndpoint, ByRef $mPostData)
	Local $oHTTP = __JIT_GetHTTP()
	If @error Then Return SetError(1, 0, "")

	$oHTTP.Open("POST", $__g_JIT_sDomain & $sEndpoint, False)
	$oHTTP.SetRequestHeader("Content-Type", "application/json")
	$oHTTP.SetRequestHeader("Accept", "application/json")
	$oHTTP.Send(_JSON_GenerateCompact($mPostData))

	Return $oHTTP.ResponseText
EndFunc   ;==>__JIT_SendPOST


; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name...........: __JIT_SendGET
; Description ...: Sends a JSON GET request to the Compiler Explorer API
; Syntax.........: __JIT_SendGET($sEndpoint)
; Parameters ....: $sEndpoint - API endpoint path (e.g. "/api/languages")
; Return values .: Success    - Response text
;                  Failure    - "" and @error set to 1
; Author ........: AspirinJunkie
; Modified.......:
; Remarks .......:
; Related .......: __JIT_SendPOST, __JIT_GetHTTP
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func __JIT_SendGET($sEndpoint)
	Local $oHTTP = __JIT_GetHTTP()
	If @error Then Return SetError(1, 0, "")

	$oHTTP.Open("GET", $__g_JIT_sDomain & $sEndpoint, False)
	$oHTTP.SetRequestHeader("Accept", "application/json")
	$oHTTP.Send()

	Return $oHTTP.ResponseText
EndFunc   ;==>__JIT_SendGET


; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name...........: __JIT_ParseConstants
; Description ...: Parses .LC* constant data blocks from pure ASM output
; Syntax.........: __JIT_ParseConstants($sAsmResponse)
; Parameters ....: $sAsmResponse - Raw JSON response from the Compiler Explorer API (pure ASM mode)
; Return values .: Map of label names (e.g. ".LC0") to their hex-encoded byte data
; Author ........: AspirinJunkie
; Modified.......:
; Remarks .......: Recognizes .long, .quad, .byte and .zero directives.
; Related .......: __JIT_CompileCode
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func __JIT_ParseConstants($sAsmResponse)
	Local $mConstants[], $sLabel = "", $sData = "", $aMatch

	For $mLine In _JSON_Parse($sAsmResponse).asm
		If Not IsMap($mLine) Or Not MapExists($mLine, "text") Then ContinueLoop
		Local $sText = $mLine.text

		; detect .LC labels (e.g. ".LC0:")
		$aMatch = StringRegExp($sText, '^(\.LC\d+):', 1)
		If Not @error Then
			If $sLabel <> "" And $sData <> "" Then $mConstants[$sLabel] = $sData
			$sLabel = $aMatch[0]
			$sData = ""
			ContinueLoop
		EndIf

		If $sLabel = "" Then ContinueLoop

		; .long (4 bytes little-endian)
		$aMatch = StringRegExp($sText, '^\s+\.long\s+(-?\d+)', 1)
		If Not @error Then
			$sData &= __JIT_IntToHexLE(Int($aMatch[0]), 4)
			ContinueLoop
		EndIf

		; .quad (8 bytes little-endian)
		$aMatch = StringRegExp($sText, '^\s+\.quad\s+(-?\d+)', 1)
		If Not @error Then
			$sData &= __JIT_IntToHexLE($aMatch[0], 8)
			ContinueLoop
		EndIf

		; .byte (1 byte)
		$aMatch = StringRegExp($sText, '^\s+\.byte\s+(0x[0-9a-fA-F]+|\d+)', 1)
		If Not @error Then
			$sData &= Hex(Number($aMatch[0]), 2)
			ContinueLoop
		EndIf

		; .zero N (N zero bytes)
		$aMatch = StringRegExp($sText, '^\s+\.zero\s+(\d+)', 1)
		If Not @error Then
			For $i = 1 To Int($aMatch[0])
				$sData &= "00"
			Next
			ContinueLoop
		EndIf

		; skip alignment/section directives
		If StringRegExp($sText, '^\s+\.(align|p2align|section)') Then ContinueLoop

		; any other line ends the current constant block
		If $sData <> "" Then $mConstants[$sLabel] = $sData
		$sLabel = ""
		$sData = ""
	Next

	; flush last block
	If $sLabel <> "" And $sData <> "" Then $mConstants[$sLabel] = $sData

	Return $mConstants
EndFunc   ;==>__JIT_ParseConstants


; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name...........: __JIT_IntToHexLE
; Description ...: Converts an integer to a little-endian hex string
; Syntax.........: __JIT_IntToHexLE($iVal[, $iBytes = 4])
; Parameters ....: $iVal   - Integer value to convert
;                  $iBytes - [optional] Number of bytes (4 or 8). Default is 4.
; Return values .: Hex string in little-endian byte order
; Author ........: AspirinJunkie
; Modified.......:
; Remarks .......:
; Related .......: __JIT_CompileCode, __JIT_ParseConstants
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func __JIT_IntToHexLE($iVal, $iBytes = 4)
	Local $sHex = Hex(Int($iVal), $iBytes * 2)
	Local $sResult = ""
	For $i = StringLen($sHex) - 1 To 1 Step -2
		$sResult &= StringMid($sHex, $i, 2)
	Next
	Return $sResult
EndFunc   ;==>__JIT_IntToHexLE
