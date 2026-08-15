@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: ============================================================
::  One entry point for Windows.
::
::  Works out which step you are on and runs it. Repeat until it
::  launches the server:
::
::    install_windows.bat  ->  update_llama_bin.bat
::                         ->  download_qwen3.8_27b.bat
::                         ->  start_qwen3.8_27b.bat
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
    call "install_windows.bat"
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
    call "update_llama_bin.bat"
    exit /b %errorlevel%
)
echo  [x] MTP support            available

:check_models
:: ---- 3. weights present? ------------------------------------
set "FOUND="
for %%F in (
    "models\Qwen3.8-27B-UD-Q5_K_XL.gguf"
    "models\Qwen3.8-27B-UD-Q4_K_XL.gguf"
    "models\Qwen3.8-27B-UD-Q6_K_XL.gguf"
    "models\Qwen3.8-27B-Q8_0.gguf"
    "models\Qwen3.8-27B-UD-IQ3_XXS.gguf"
) do (
    if not defined FOUND if exist %%F set "FOUND=%%~nxF"
)

if not defined FOUND (
    echo  [ ] model weights          not downloaded
    echo.
    echo  Next step: download_qwen3.8_27b.bat
    echo  Pick a quant sized to your GPU -- the menu explains the
    echo  trade-offs, and the README has a full table.
    echo.
    choice /C YN /M "Run it now"
    if errorlevel 2 exit /b 0
    call "download_qwen3.8_27b.bat"
    exit /b %errorlevel%
)
echo  [x] model weights          !FOUND!

:: ---- 4. launch ----------------------------------------------
echo.
echo  Everything is in place. Starting the server...
echo.
call "start_qwen3.8_27b.bat"
exit /b %errorlevel%
