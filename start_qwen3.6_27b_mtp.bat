@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: ============================================================
::  MTP STATUS:
::  The current llama-bin\llama-server.exe does NOT yet support
::  --spec-type mtp. That flag requires building llama.cpp from:
::    git clone -b mtp-clean https://github.com/am17an/llama.cpp
::  Until then, this script uses --spec-type ngram-cache which
::  IS supported and gives ~10-20% speedup on repetitive/coding
::  output. Swap to the MTP block below once binary is updated.
:: ============================================================

set MODEL=models\Qwen3.6-27B-UD-Q4_K_XL.gguf
set BINARY=llama-bin\llama-server.exe
set CF_EXE=C:\Program Files (x86)\cloudflared\cloudflared.exe
set PORT=8080
set LOG=server_mtp.log
set CF_LOG=cloudflared_mtp_err.log

:: pre-flight checks
if not exist "%BINARY%" (
    echo ERROR: %BINARY% not found.
    pause & exit /b 1
)
if not exist "%MODEL%" (
    echo ERROR: %MODEL% not found. Run download_qwen3.6_27b_mtp.bat first.
    pause & exit /b 1
)

:: stop any running instances
echo Stopping any existing instances...
taskkill /F /IM llama-server.exe >nul 2>&1
taskkill /F /IM cloudflared.exe  >nul 2>&1
timeout /t 2 >nul

del "%LOG%"    >nul 2>&1
del "%CF_LOG%" >nul 2>&1

echo Starting llama-server (Qwen3.6-27B UD-Q4_K_XL)...
echo.

:: ---- CURRENT: ngram-cache speculative decoding (works now) ----
start /B "" "%BINARY%" ^
    --model          "%MODEL%" ^
    --n-gpu-layers   99 ^
    --ctx-size       65536 ^
    --flash-attn     on ^
    --port           %PORT% ^
    --host           0.0.0.0 ^
    --alias          "qwen3.6-27b-mtp" ^
    --cache-type-k   q4_0 ^
    --cache-type-v   q4_0 ^
    --spec-type      ngram-cache ^
    --draft          8 ^
    --log-verbose ^
    --log-file       "%LOG%"

:: ---- FUTURE: swap to this block once MTP binary is available ----
:: start /B "" "llama-bin-mtp\llama-server.exe" ^
::     --model          "%MODEL%" ^
::     --n-gpu-layers   99 ^
::     --ctx-size       65536 ^
::     --flash-attn     on ^
::     --port           %PORT% ^
::     --host           0.0.0.0 ^
::     --alias          "qwen3.6-27b-mtp" ^
::     --cache-type-k   q4_0 ^
::     --cache-type-v   q4_0 ^
::     --spec-type      mtp ^
::     --draft-max      3 ^
::     --log-verbose ^
::     --log-file       "%LOG%"

:: wait until server is listening
echo Waiting for model to load...
:wait_loop
timeout /t 5 >nul
findstr /C:"server is listening" "%LOG%" >nul 2>&1
if errorlevel 1 goto wait_loop
echo Server ready.

:: start cloudflared tunnel
echo Starting Cloudflare tunnel...
powershell -NoProfile -Command ^
    "Start-Process -FilePath 'C:\Program Files (x86)\cloudflared\cloudflared.exe' -ArgumentList 'tunnel','--url','http://localhost:%PORT%' -RedirectStandardOutput '%CD%\cloudflared_mtp.log' -RedirectStandardError '%CD%\%CF_LOG%' -WindowStyle Hidden"

echo Waiting for tunnel URL...
:tunnel_loop
timeout /t 3 >nul
findstr "https://.*trycloudflare\.com" "%CF_LOG%" >nul 2>&1
if errorlevel 1 goto tunnel_loop

for /f "usebackq delims=" %%U in (`powershell -NoProfile -Command ^
    "(Select-String -Path '%CF_LOG%' -Pattern 'https://\S+trycloudflare\.com').Matches.Value | Select-Object -Last 1"`) do set TUNNEL_URL=%%U

echo.
echo ============================================================
echo.
echo   Cursor Base URL:
echo.
echo   !TUNNEL_URL!/v1
echo.
echo   Settings ^> Models ^> Base URL  (model name: qwen3.6-27b-mtp)
echo.
echo   Spec decoding: ngram-cache (active now)
echo   MTP spec decoding: requires updated llama.cpp binary
echo.
echo ============================================================
echo.
pause >nul
