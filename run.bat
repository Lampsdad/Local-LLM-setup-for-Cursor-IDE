@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: ============================================================
::  One entry point for Windows.
::
::  Works out which step you are on and runs it. Repeat until it
::  launches the server:
::
::    install_windows.bat  ->  update_llama_bin.bat  ->  launch.bat
::
::  launch.bat is where you choose between the stock and the
::  abliterated build; it downloads whichever you pick if it is
::  missing, then hands off to start_qwen3.8_27b.bat.
::
::  Every step is still runnable on its own if you prefer.
:: ============================================================

set BINARY=llama-bin\llama-server.exe

echo ============================================================
echo  Local LLM for Cursor -- Qwen3.8-27B
echo ============================================================
echo.

:: ---- 1. llama.cpp present? ----------------------------------
if not exist "%BINARY%" (
    echo  [ ] llama.cpp binaries      not installed
    echo.
    echo  Next step: install_windows.bat
    echo  This downloads llama.cpp, cloudflared, and creates models\.
    echo.
    choice /C YN /M "Run it now"
    if errorlevel 2 exit /b 0
    call "%~dp0install_windows.bat"
    exit /b %errorlevel%
)
echo  [x] llama.cpp binaries      installed

:: ---- 2. MTP-capable build? ----------------------------------
set HAS_MTP_SUPPORT=0
"%BINARY%" --help 2>&1 | findstr /C:"draft-mtp" >nul
if not errorlevel 1 set HAS_MTP_SUPPORT=1

if "%HAS_MTP_SUPPORT%"=="0" (
    echo  [ ] MTP support            build predates b9180
    echo.
    echo  Next step: update_llama_bin.bat
    echo  MTP speculative decoding is the largest single speedup
    echo  available for this model; your build cannot do it yet.
    echo.
    choice /C YN /M "Upgrade llama.cpp now"
    if errorlevel 2 goto check_models
    call "%~dp0update_llama_bin.bat"
    exit /b %errorlevel%
)
echo  [x] MTP support            available

:check_models
:: ---- 3. weights present? ------------------------------------
:: Reported, not acted on: launch.bat below offers to download
:: whichever variant you pick, so a missing file is not a dead
:: end here. Either variant counts as "installed".
set "FOUND="
for %%P in ("Qwen3.8-27B" "Huihui-Qwen3.8-27B-abliterated") do (
    for %%Q in (UD-Q5_K_XL UD-Q4_K_XL UD-Q6_K_XL Q8_0 UD-IQ3_XXS) do (
        if not defined FOUND if exist "models\%%~P-%%Q.gguf" set "FOUND=%%~P-%%Q.gguf"
    )
)

if defined FOUND (
    echo  [x] model weights          !FOUND!
) else (
    echo  [ ] model weights          none yet -- launch.bat will fetch one
)

:: ---- 4. pick a model and launch it ---------------------------
echo.
call "%~dp0launch.bat"
exit /b %errorlevel%
