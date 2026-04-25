@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

set MODEL=models\Qwen_Qwen3.6-35B-A3B-Q6_K_L.gguf
set BINARY=llama-bin\llama-server.exe
set CF_EXE=C:\Program Files (x86)\cloudflared\cloudflared.exe
set PORT=8080
set LOG=server.log
set CF_LOG=cloudflared-err.log

:: pre-flight checks
if not exist "%BINARY%" (
    echo ERROR: %BINARY% not found.
    pause & exit /b 1
)
if not exist "%MODEL%" (
    echo ERROR: %MODEL% not found.
    pause & exit /b 1
)

:: stop any running instances
echo Stopping any existing instances...
taskkill /F /IM llama-server.exe >nul 2>&1
taskkill /F /IM cloudflared.exe  >nul 2>&1
timeout /t 2 >nul

:: clear old logs so we don't match stale URLs
del "%LOG%"    >nul 2>&1
del "%CF_LOG%" >nul 2>&1

:: start llama-server
echo Starting llama-server...
start /B "" "%BINARY%" ^
    --model        "%MODEL%" ^
    --n-gpu-layers 99 ^
    --ctx-size     131072 ^
    --flash-attn   auto ^
    --port         %PORT% ^
    --host         0.0.0.0 ^
    --alias        "qwen3.6-35b-a3b" ^
    --cache-type-k q4_0 ^
    --cache-type-v q4_0 ^
    --log-verbose ^
    --log-file     "%LOG%"

:: wait until server is listening
echo Waiting for model to load (1-2 min)...
:wait_loop
timeout /t 5 >nul
findstr /C:"server is listening" "%LOG%" >nul 2>&1
if errorlevel 1 goto wait_loop
echo Server ready.

:: start cloudflared tunnel via PowerShell Start-Process
echo Starting Cloudflare tunnel...
powershell -NoProfile -Command ^
    "Start-Process -FilePath 'C:\Program Files (x86)\cloudflared\cloudflared.exe' -ArgumentList 'tunnel','--url','http://localhost:%PORT%' -RedirectStandardOutput '%CD%\cloudflared.log' -RedirectStandardError '%CD%\%CF_LOG%' -WindowStyle Hidden"

:: wait for tunnel URL to appear in log
echo Waiting for tunnel URL...
:tunnel_loop
timeout /t 3 >nul
findstr "https://.*trycloudflare\.com" "%CF_LOG%" >nul 2>&1
if errorlevel 1 goto tunnel_loop

:: extract just the https URL using PowerShell regex
for /f "usebackq delims=" %%U in (`powershell -NoProfile -Command ^
    "(Select-String -Path '%CF_LOG%' -Pattern 'https://\S+trycloudflare\.com').Matches.Value | Select-Object -Last 1"`) do set TUNNEL_URL=%%U

echo.
echo ============================================================
echo.
echo   Cursor Base URL:
echo.
echo   !TUNNEL_URL!/v1
echo.
echo   Settings ^> Models ^> Base URL  (model name: qwen3.6-35b-a3b)
echo.
echo ============================================================
echo.
pause >nul
