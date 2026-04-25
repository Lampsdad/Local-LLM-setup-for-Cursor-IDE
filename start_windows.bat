@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

set MODEL=models\Qwen_Qwen3.6-35B-A3B-Q6_K_L.gguf
set BINARY=llama-bin\llama-server.exe
set CF_EXE=C:\Program Files (x86)\cloudflared\cloudflared.exe
set PORT=8080
set LOG=server.log
set CF_LOG=cloudflared.log

:: ── pre-flight checks ────────────────────────────────────────
if not exist "%BINARY%" (
    echo ERROR: %BINARY% not found. Run install_windows.bat first.
    pause & exit /b 1
)
if not exist "%MODEL%" (
    echo ERROR: %MODEL% not found. Run download_model.bat first.
    pause & exit /b 1
)

:: ── stop any running instances ───────────────────────────────
echo Stopping any existing instances...
taskkill /F /IM llama-server.exe >nul 2>&1
taskkill /F /IM cloudflared.exe  >nul 2>&1
timeout /t 2 >nul

:: ── start llama-server ───────────────────────────────────────
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
    --log-file     "%LOG%"

:: ── wait for server to be ready (health poll) ────────────────
echo Waiting for server to load (1-2 min for a 30 GB model)...
:health_loop
timeout /t 5 >nul
curl -sf "http://localhost:%PORT%/health" >nul 2>&1
if errorlevel 1 goto health_loop
echo Server is ready.

:: ── start cloudflared tunnel ─────────────────────────────────
if not exist "%CF_EXE%" (
    echo WARNING: cloudflared not found at "%CF_EXE%". Skipping tunnel.
    echo The API is still reachable at http://localhost:%PORT%/v1
    goto done
)

echo Starting Cloudflare tunnel...
start /B "" "%CF_EXE%" tunnel --url "http://localhost:%PORT%" > "%CF_LOG%" 2>&1
timeout /t 12 >nul

:: ── print tunnel URL ─────────────────────────────────────────
echo.
echo ============================================================
for /f "tokens=*" %%L in ('findstr "trycloudflare.com" "%CF_LOG%"') do (
    echo  %%L
)
echo  Append /v1 to use as an OpenAI base URL.
echo ============================================================

:done
echo.
pause
