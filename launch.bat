@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: ============================================================
::  Model picker.
::
::    launch.bat            interactive menu
::    launch.bat base       stock Qwen3.8-27B, no prompt
::    launch.bat ablit      abliterated build, no prompt
::
::  Both variants use the same port, the same MTP head and the
::  same vision projector, and start_qwen3.8_27b.bat kills any
::  running server before starting -- so this switches between
::  them rather than running both. What actually changes is the
::  weights file and the --alias Cursor sees.
::
::  Variant definitions live in lib_variants.bat.
:: ============================================================

set "PICK=%~1"
if defined PICK goto :resolve

:menu
call :probe "Qwen3.8-27B"                    HAVE_BASE
call :probe "Huihui-Qwen3.8-27B-abliterated" HAVE_ABL

:: The MTP head and the vision projector serve both variants, so
:: whichever you fetch first pays for them and the second is
:: weights-only. Say which case you are in rather than quoting a
:: number that is wrong half the time.
set "SHARED= + ~4 GB shared MTP/vision"
if exist "models\mtp-Qwen3.8-27B-Q8_0.gguf" if exist "models\mmproj-F16.gguf" set "SHARED="

if defined HAVE_BASE (set "S1=installed: !HAVE_BASE!") else (set "S1=not downloaded, ~20 GB!SHARED!")
if defined HAVE_ABL  (set "S2=installed: !HAVE_ABL!")  else (set "S2=not downloaded, ~21 GB!SHARED!")

echo ============================================================
echo  Which model do you want to serve?
echo ============================================================
echo.
echo    [1] Qwen3.8-27B
echo        %S1%
echo        stock Qwen release; refusal behaviour intact
echo        Cursor model name: qwen3.8-27b
echo.
echo    [2] Qwen3.8-27B abliterated
echo        %S2%
echo        huihui-ai ablation of the same unsloth quants, with
echo        refusals removed and no safety evaluation
echo        Cursor model name: qwen3.8-27b-abliterated
echo.
echo    [Q] quit
echo.

if not defined HAVE_BASE if not defined HAVE_ABL (
    echo  Nothing downloaded yet -- picking one will fetch it.
    echo.
)

set "SEL="
set /p SEL="Enter choice [1-2, Q] (default=1): "
if not defined SEL set "SEL=1"
if /I "%SEL%"=="Q" exit /b 0
if "%SEL%"=="1" set "PICK=base"
if "%SEL%"=="2" set "PICK=ablit"
if not defined PICK (
    echo.
    echo  Not a choice. Try again.
    echo.
    goto :menu
)

:resolve
call "%~dp0lib_variants.bat" "%PICK%"
if errorlevel 1 (
    echo  ERROR: unknown variant "%PICK%" -- expected "base" or "ablit".
    pause & exit /b 1
)

:: ---- present? ----------------------------------------------
call :probe "%V_PREFIX%" HAVE
if defined HAVE goto :go

echo.
echo  %V_LABEL% is not downloaded yet.
echo.
choice /C YN /M "Download it now"
if errorlevel 2 exit /b 0

call "%~dp0download_qwen3.8_27b.bat" "%V_ID%"

:: Re-probe rather than trusting the exit code: the download
:: script offers a "continue anyway" path past its free-space
:: check, and a cancelled fetch there still returns 0.
call :probe "%V_PREFIX%" HAVE
if not defined HAVE (
    echo.
    echo  No %V_LABEL% weights in models\ -- the download did not finish.
    pause & exit /b 1
)

:go
echo.
echo  Launching %V_LABEL% (%HAVE%)...
echo.
call "%~dp0start_qwen3.8_27b.bat" "%V_ID%"
exit /b %errorlevel%

:: ------------------------------------------------------------
:: :probe <filename-prefix> <out-var>
:: Sets <out-var> to the best quant present for that prefix, or
:: clears it. Same order start_qwen3.8_27b.bat picks in, so the
:: menu reports the quant that would actually be loaded.
:probe
set "%~2="
for %%Q in (UD-Q5_K_XL UD-Q4_K_XL UD-Q6_K_XL Q8_0 UD-IQ3_XXS) do (
    if not defined %~2 (
        if exist "models\%~1-%%Q.gguf" set "%~2=%%Q"
    )
)
exit /b 0
