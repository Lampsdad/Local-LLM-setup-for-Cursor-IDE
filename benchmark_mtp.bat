@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ============================================================
echo  Benchmark: Qwen3.6-27B MTP GGUF vs Baseline
echo  Tool: llama-bench  --  RTX 5090 target
echo ============================================================
echo.

set BENCH=llama-bin\llama-bench.exe
set MODEL_NEW=models\Qwen3.6-27B-UD-Q4_K_XL.gguf
set MODEL_BASE=models\Qwen_Qwen3.6-35B-A3B-Q6_K_L.gguf
set RESULTS=benchmark_results.txt

if not exist "%BENCH%" (
    echo ERROR: %BENCH% not found.
    pause & exit /b 1
)

:: stop any running llama-server to free VRAM
echo Stopping any running llama-server to free VRAM...
taskkill /F /IM llama-server.exe >nul 2>&1
timeout /t 3 >nul

echo Results will be saved to: %RESULTS%
echo.

:: ---- Timestamps ----
for /f "tokens=1-3 delims=/ " %%a in ('date /t') do set DATESTAMP=%%a/%%b/%%c
for /f "tokens=1-2 delims=: " %%a in ('time /t') do set TIMESTAMP=%%a:%%b

echo ============================================================ > "%RESULTS%"
echo  Benchmark run: %DATESTAMP% %TIMESTAMP% >> "%RESULTS%"
echo  GPU: NVIDIA GeForce RTX 5090 >> "%RESULTS%"
echo ============================================================ >> "%RESULTS%"
echo. >> "%RESULTS%"

:: ============================================================
:: TEST 1: Qwen3.6-27B UD-Q4_K_XL (new MTP GGUF)
:: ============================================================
if exist "%MODEL_NEW%" (
    echo [1/3] Benchmarking Qwen3.6-27B UD-Q4_K_XL...
    echo --- Qwen3.6-27B UD-Q4_K_XL (unsloth/Qwen3.6-27B-MTP-GGUF) --- >> "%RESULTS%"
    "%BENCH%" ^
        -m "%MODEL_NEW%" ^
        -ngl 99 ^
        -fa 1 ^
        -p 512 -n 512 -r 3 ^
        -ctk q4_0 -ctv q4_0 ^
        >> "%RESULTS%" 2>&1
    echo. >> "%RESULTS%"
    echo [1/3] Done.
) else (
    echo [SKIP] %MODEL_NEW% not found. Run download_qwen3.6_27b_mtp.bat first.
    echo [SKIP] Qwen3.6-27B UD-Q4_K_XL not downloaded. >> "%RESULTS%"
    echo. >> "%RESULTS%"
)

:: ============================================================
:: TEST 2: Qwen3.6-27B UD-IQ2_M (fastest quant, if downloaded)
:: ============================================================
set MODEL_IQ2=models\Qwen3.6-27B-UD-IQ2_M.gguf
if exist "%MODEL_IQ2%" (
    echo [2/3] Benchmarking Qwen3.6-27B UD-IQ2_M...
    echo --- Qwen3.6-27B UD-IQ2_M (unsloth/Qwen3.6-27B-MTP-GGUF) --- >> "%RESULTS%"
    "%BENCH%" ^
        -m "%MODEL_IQ2%" ^
        -ngl 99 ^
        -fa 1 ^
        -p 512 -n 512 -r 3 ^
        -ctk q4_0 -ctv q4_0 ^
        >> "%RESULTS%" 2>&1
    echo. >> "%RESULTS%"
    echo [2/3] Done.
) else (
    echo [SKIP] UD-IQ2_M not present, skipping.
    echo [SKIP] Qwen3.6-27B UD-IQ2_M not downloaded. >> "%RESULTS%"
    echo. >> "%RESULTS%"
)

:: ============================================================
:: TEST 3: Existing baseline model (Qwen3.6-35B-A3B)
:: ============================================================
if exist "%MODEL_BASE%" (
    echo [3/3] Benchmarking existing baseline (Qwen3.6-35B-A3B-Q6_K_L)...
    echo --- BASELINE: Qwen3.6-35B-A3B-Q6_K_L (current model) --- >> "%RESULTS%"
    "%BENCH%" ^
        -m "%MODEL_BASE%" ^
        -ngl 99 ^
        -fa 1 ^
        -p 512 -n 512 -r 3 ^
        -ctk q4_0 -ctv q4_0 ^
        >> "%RESULTS%" 2>&1
    echo. >> "%RESULTS%"
    echo [3/3] Done.
) else (
    echo [SKIP] Baseline model not present, skipping.
)

:: ============================================================
:: Summary
:: ============================================================
echo. >> "%RESULTS%"
echo ============================================================ >> "%RESULTS%"
echo  NOTES >> "%RESULTS%"
echo  - pp = prompt processing tokens/s (prefill speed) >> "%RESULTS%"
echo  - tg = text generation tokens/s  (what you see while typing) >> "%RESULTS%"
echo  - r=3 means 3 runs averaged >> "%RESULTS%"
echo  - These are RAW tok/s WITHOUT MTP speculative decoding. >> "%RESULTS%"
echo  - MTP (~1.5-2x tg speedup) requires llama.cpp built from: >> "%RESULTS%"
echo      git clone -b mtp-clean https://github.com/am17an/llama.cpp >> "%RESULTS%"
echo      cmake llama.cpp -B llama.cpp/build -DGGML_CUDA=ON >> "%RESULTS%"
echo      cmake --build llama.cpp/build --config Release -j >> "%RESULTS%"
echo  - PR tracking MTP merge: https://github.com/ggml-org/llama.cpp/pull/22673 >> "%RESULTS%"
echo ============================================================ >> "%RESULTS%"

echo.
echo ============================================================
echo  Benchmark complete. Results saved to: %RESULTS%
echo ============================================================
echo.
type "%RESULTS%"
echo.
pause
