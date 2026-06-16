@echo off
cd /d "%~dp0"

echo ============================================================
echo  Download: Qwen3.6-27B MTP GGUF (Unsloth)
echo  Repo: unsloth/Qwen3.6-27B-MTP-GGUF
echo ============================================================
echo.
echo  These GGUFs contain native MTP heads (speculative decoding)
echo  trained into the model -- ~1.5-2x faster generation when
echo  llama.cpp MTP support is active (see start script notes).
echo.
echo  Quant options (choose one):
echo    [1] UD-Q4_K_XL  -- 17.9 GB  ~93 tok/s on RTX 5090  (recommended)
echo    [2] UD-IQ2_M    -- 11.0 GB  ~114 tok/s on RTX 5090 (fastest, lower quality)
echo    [3] UD-Q6_K_XL  -- 26.0 GB  ~75 tok/s on RTX 5090  (highest quality)
echo    [4] Q8_0        -- 29.0 GB  ~35 tok/s baseline     (no MTP speedup reference)
echo.
set /p CHOICE="Enter choice [1-4] (default=1): "
if "%CHOICE%"=="" set CHOICE=1

if "%CHOICE%"=="1" (
    set FILE=Qwen3.6-27B-UD-Q4_K_XL.gguf
    set SIZE=17.9
)
if "%CHOICE%"=="2" (
    set FILE=Qwen3.6-27B-UD-IQ2_M.gguf
    set SIZE=11.0
)
if "%CHOICE%"=="3" (
    set FILE=Qwen3.6-27B-UD-Q6_K_XL.gguf
    set SIZE=26.0
)
if "%CHOICE%"=="4" (
    set FILE=Qwen3.6-27B-Q8_0.gguf
    set SIZE=29.0
)

if "%FILE%"=="" (
    echo Invalid choice.
    pause & exit /b 1
)

set REPO=unsloth/Qwen3.6-27B-MTP-GGUF
set DEST=models\%FILE%

if exist "%DEST%" (
    echo [OK] Already downloaded: %DEST%
    goto done
)

:: Detect python
python3 --version >nul 2>&1
if errorlevel 1 (
    python --version >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Python not found. Install Python 3.8+ from https://python.org
        pause & exit /b 1
    )
    set PYTHON=python
) else (
    set PYTHON=python3
)

echo [*] Installing/upgrading huggingface_hub...
%PYTHON% -m pip install -q "huggingface_hub>=0.22"

echo.
echo [*] Downloading %FILE% (~%SIZE% GB) from %REPO%
echo     This may take a while on first run.
echo.

%PYTHON% -c "from huggingface_hub import hf_hub_download; import os; p = hf_hub_download(repo_id='%REPO%', filename='%FILE%', local_dir='models'); print('Done:', p, '(' + str(round(os.path.getsize(p)/1e9,1)) + ' GB)')"

if errorlevel 1 (
    echo ERROR: Download failed. Check your internet connection or HuggingFace token.
    pause & exit /b 1
)

:done
echo.
echo ============================================================
echo  Downloaded: %DEST%
echo  Run start_qwen3.6_27b_mtp.bat to launch the server.
echo ============================================================
pause
