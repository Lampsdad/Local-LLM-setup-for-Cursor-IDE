@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: ============================================================
::  Qwen3.8-27B on RTX 5090 (32 GB) -- tuned launch
::
::  Hardware this is sized for:
::    GPU  RTX 5090, 32606 MiB VRAM, Blackwell sm_120
::    CPU  Ryzen 9 9900X3D, 12C/24T
::    RAM  61.6 GB
::
::  Architecture notes that drive the settings below:
::    - 64 layers: 16 x (3 x GatedDeltaNet -> 1 x GatedAttention).
::      Only the 16 full-attention layers hold a KV cache; the 48
::      linear-attention layers carry a small fixed recurrent state.
::      That makes long context unusually cheap here.
::    - KV cost: 16 layers x 4 KV heads x 256 head-dim x 2 (K+V)
::      = 32,768 elem/token -> 64 KiB/token at f16, 34 KiB at q8_0.
::    - MTP (multi-token prediction) heads are trained into the
::      model and shipped as a SEPARATE GGUF, loaded as a draft
::      model. This is the single biggest generation speedup.
:: ============================================================

set BINARY=llama-bin\llama-server.exe
set PORT=8080
set LOG=server.log
set CF_LOG=cloudflared-err.log
set CF_EXE=C:\Program Files (x86)\cloudflared\cloudflared.exe
set ALIAS=qwen3.8-27b

set MMPROJ=models\mmproj-F16.gguf
set MTP=models\mtp-Qwen3.8-27B-Q8_0.gguf

:: ---- pick whichever weight file is present, best first ----
:: The second argument is only a fallback for machines where
:: nvidia-smi is unavailable; normally probe_hardware.ps1 computes
:: the context window from the GPU actually present. The fallback
:: values assume a 32 GB card.
set "MODEL="
call :pick "models\Qwen3.8-27B-UD-Q5_K_XL.gguf" 131072
call :pick "models\Qwen3.8-27B-UD-Q4_K_XL.gguf" 196608
call :pick "models\Qwen3.8-27B-UD-Q6_K_XL.gguf" 32768
call :pick "models\Qwen3.8-27B-Q8_0.gguf"       16384
call :pick "models\Qwen3.8-27B-UD-IQ3_XXS.gguf" 262144

if not defined MODEL (
    echo  ERROR: no Qwen3.8-27B weights found in models\
    echo  Run download_qwen3.8_27b.bat first.
    pause & exit /b 1
)

if not exist "%BINARY%" (
    echo  ERROR: %BINARY% not found. Run install_windows.bat or update_llama_bin.bat.
    pause & exit /b 1
)

:: ---- MTP requires a build with draft-mtp support (b9180+) ----
set USE_MTP=0
"%BINARY%" --help 2>&1 | findstr /C:"draft-mtp" >nul
if not errorlevel 1 (
    if exist "%MTP%" set USE_MTP=1
) else (
    echo  [WARN] this llama.cpp build predates MTP support (merged b9180).
    echo         Run update_llama_bin.bat to get the ~1.5-2x speedup.
)

:: ---- vision ----
set USE_VISION=0
if exist "%MMPROJ%" set USE_VISION=1

:: ---- size to the machine actually present ----
:: Context and thread count used to be hardcoded for an RTX 5090 +
:: 9900X3D. probe_hardware.ps1 derives both from the GPU and CPU it
:: finds, so this runs unmodified on a 16 or 24 GB card.
set "PROBE_MTP="
set "PROBE_MMPROJ="
if "%USE_MTP%"=="1"    set "PROBE_MTP=%MTP%"
if "%USE_VISION%"=="1" set "PROBE_MMPROJ=%MMPROJ%"

set PROBED=0
set VRAM_MIB=0
set CORES=0
set CTX=0
for /f "usebackq tokens=1,2 delims==" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -File "probe_hardware.ps1" -Model "%MODEL%" -Mtp "%PROBE_MTP%" -Mmproj "%PROBE_MMPROJ%" 2^>nul`) do set "%%A=%%B"

if "%CORES%"=="0" set CORES=8

if "%PROBED%"=="0" (
    echo  [WARN] could not read GPU memory ^(is nvidia-smi on PATH?^).
    echo         Falling back to %CTX_FALLBACK% context, which assumes a 32 GB card.
    set "CTX=%CTX_FALLBACK%"
)

:: CTX=0 with a successful probe means the fixed costs alone exceed
:: VRAM -- no context window would fit, so starting is pointless.
if "%CTX%"=="0" (
    echo.
    echo  ERROR: these weights do not leave room for any context on a
    echo         %VRAM_MIB% MiB GPU.
    echo.
    if "%USE_MTP%"=="1" echo    - the MTP head costs ~3 GB; delete %MTP% to trade
    if "%USE_MTP%"=="1" echo      speed for context, or
    echo    - use a smaller quant. See the quant table in README.md.
    echo.
    pause & exit /b 1
)

if %CTX% LSS 16384 (
    echo.
    echo  [WARN] only %CTX% tokens of context fit alongside these weights
    echo         in %VRAM_MIB% MiB. A smaller quant would give you a much
    echo         larger window -- see the quant table in README.md.
    echo.
)

:: ---- tunnel authentication ----
:: The quick-tunnel URL is public. Cursor makes you enter an API
:: key anyway, so requiring one costs nothing and stops strangers
:: who guess the URL from spending your GPU. Generated once and
:: kept in api_key.txt (gitignored).
if not exist "api_key.txt" (
    echo Generating an API key for this server ^(api_key.txt^)...
    powershell -NoProfile -Command ^
        "[System.Guid]::NewGuid().ToString('N') | Set-Content -Path 'api_key.txt' -Encoding ascii -NoNewline"
)
set /p API_KEY=<api_key.txt

echo ============================================================
echo  Qwen3.8-27B
echo ------------------------------------------------------------
echo   weights : %MODEL%
echo   context : %CTX%  ^(sized to %VRAM_MIB% MiB VRAM^)
echo   threads : %CORES%  ^(physical cores^)
if "%USE_MTP%"=="1"    (echo   MTP     : enabled  ^(%MTP%^)) else (echo   MTP     : disabled)
if "%USE_VISION%"=="1" (echo   vision  : enabled) else (echo   vision  : disabled)
echo ============================================================
echo.

:: ---- stop anything already running ----
echo Stopping any existing instances...
taskkill /F /IM llama-server.exe >nul 2>&1
taskkill /F /IM cloudflared.exe  >nul 2>&1
timeout /t 2 >nul

del "%LOG%"    >nul 2>&1
del "%CF_LOG%" >nul 2>&1

:: ------------------------------------------------------------
::  Flag rationale
:: ------------------------------------------------------------
::  -ngl 99            all 64 layers on GPU
::  -c %CTX%           sized per quant so weights+KV fit in 32 GB
::  -fa auto           Flash Attention where the backend supports it.
::                     'auto' not 'on': gated attention with a 256
::                     head-dim falls back cleanly instead of erroring.
::  -ctk/-ctv q8_0     halves KV vs f16 at negligible quality cost.
::                     NOT q4_0: the 48 recurrent layers accumulate
::                     error along the sequence, so cheap KV precision
::                     hurts more on this architecture than on a
::                     standard transformer.
::  -np 1              ONE server slot. With the default (-1 = auto)
::                     llama.cpp splits the KV cache across slots and
::                     each request gets ctx/N. Single-user Cursor use
::                     wants the whole window in one slot.
::  -b 4096 -ub 1024   larger prefill batches; the 5090 has bandwidth
::                     and VRAM headroom to spare at these sizes.
::  -t %CORES%         physical cores only, detected at launch. With
::                     everything on GPU the CPU just feeds batches, so
::                     counting SMT siblings only adds contention.
::  --jinja            proper tool-call parsing for agentic use.
::  --reasoning-format deepseek
::                     puts chain-of-thought in message.reasoning_content
::                     so thinking tokens do not land in code output.
::  --spec-draft-n-max 3
::                     Qwen trains MTP for multi-step draft; 3 is the
::                     llama.cpp default and matches the released head.
::  sampling           Qwen's published thinking-mode values.
:: ------------------------------------------------------------

set ARGS=--model "%MODEL%"
set ARGS=%ARGS% --n-gpu-layers 99
set ARGS=%ARGS% --ctx-size %CTX%
set ARGS=%ARGS% --flash-attn auto
set ARGS=%ARGS% --cache-type-k q8_0
set ARGS=%ARGS% --cache-type-v q8_0
set ARGS=%ARGS% --parallel 1
set ARGS=%ARGS% --batch-size 4096
set ARGS=%ARGS% --ubatch-size 1024
set ARGS=%ARGS% --threads %CORES%
set ARGS=%ARGS% --jinja
set ARGS=%ARGS% --reasoning-format deepseek
set ARGS=%ARGS% --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0
set ARGS=%ARGS% --port %PORT% --host 0.0.0.0
set ARGS=%ARGS% --alias "%ALIAS%"
set ARGS=%ARGS% --api-key-file "api_key.txt"

if "%USE_MTP%"=="1" (
    set ARGS=!ARGS! --spec-type draft-mtp
    set ARGS=!ARGS! --spec-draft-model "%MTP%"
    set ARGS=!ARGS! --spec-draft-ngl 99
    set ARGS=!ARGS! --spec-draft-n-max 3
)
if "%USE_VISION%"=="1" (
    set ARGS=!ARGS! --mmproj "%MMPROJ%"
)

set ARGS=%ARGS% --log-file "%LOG%"

echo Starting llama-server...
start /B "" "%BINARY%" %ARGS%

:: ---- wait for readiness, but give up rather than spin forever ----
echo Waiting for model to load (typically 1-3 min)...
set /a TRIES=0
:wait_loop
timeout /t 5 >nul
set /a TRIES+=1
findstr /C:"server is listening" "%LOG%" >nul 2>&1
if not errorlevel 1 goto ready

:: Detect failure by checking the process is still alive rather than
:: grepping the log for "error" -- llama.cpp emits plenty of benign
:: lines containing that word, and a false positive would abort a
:: perfectly good startup.
tasklist /FI "IMAGENAME eq llama-server.exe" 2>nul | findstr /I "llama-server.exe" >nul
if errorlevel 1 (
    echo.
    echo  ERROR: llama-server exited during startup. Last lines of %LOG%:
    echo ------------------------------------------------------------
    powershell -NoProfile -Command "if (Test-Path '%LOG%') { Get-Content '%LOG%' -Tail 30 } else { 'no log written' }"
    echo ------------------------------------------------------------
    echo.
    echo  Common causes:
    echo    - out of VRAM: lower --ctx-size or use a smaller quant
    echo    - MTP head mismatched with the weights: delete the
    echo      --spec-type block to test without speculative decoding
    pause & exit /b 1
)
if %TRIES% GEQ 72 (
    echo.
    echo  ERROR: timed out after 6 minutes. Check %LOG%.
    pause & exit /b 1
)
goto wait_loop

:ready
echo Server ready.

:: ---- report what actually got allocated ----
echo.
echo  VRAM in use:
for /f "usebackq delims=" %%M in (`nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader`) do echo    %%M
echo.

:: ---- tunnel ----
if not exist "%CF_EXE%" (
    echo  cloudflared not found -- serving locally only.
    echo  Base URL: http://localhost:%PORT%/v1   ^(model: %ALIAS%^)
    echo  API key : %API_KEY%
    pause & exit /b 0
)

echo Starting Cloudflare tunnel...
powershell -NoProfile -Command ^
    "Start-Process -FilePath '%CF_EXE%' -ArgumentList 'tunnel','--url','http://localhost:%PORT%' -RedirectStandardOutput '%CD%\cloudflared.log' -RedirectStandardError '%CD%\%CF_LOG%' -WindowStyle Hidden"

echo Waiting for tunnel URL...
set /a TTRIES=0
:tunnel_loop
timeout /t 3 >nul
set /a TTRIES+=1
findstr "https://.*trycloudflare\.com" "%CF_LOG%" >nul 2>&1
if not errorlevel 1 goto got_tunnel
if %TTRIES% GEQ 40 (
    echo  WARNING: tunnel did not come up. Local URL still works:
    echo    http://localhost:%PORT%/v1
    pause & exit /b 0
)
goto tunnel_loop

:got_tunnel
for /f "usebackq delims=" %%U in (`powershell -NoProfile -Command ^
    "(Select-String -Path '%CF_LOG%' -Pattern 'https://\S+trycloudflare\.com').Matches.Value | Select-Object -Last 1"`) do set TUNNEL_URL=%%U

echo.
echo ============================================================
echo.
echo   Cursor Base URL:
echo.
echo     !TUNNEL_URL!/v1
echo.
echo   API key (paste into Cursor's OpenAI API Key field):
echo.
echo     %API_KEY%
echo.
echo   Settings ^> Models ^> Base URL   (model name: %ALIAS%)
echo.
echo   NOTE: the URL is public and changes on every restart.
echo   Requests without the API key above are rejected.
echo.
echo ============================================================
echo.
pause >nul
exit /b 0

:: ------------------------------------------------------------
:pick
if defined MODEL exit /b 0
if exist %1 (
    set "MODEL=%~1"
    set "CTX_FALLBACK=%~2"
)
exit /b 0
