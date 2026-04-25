@echo off
cd /d "%~dp0"

echo ============================================================
echo  Download model: Qwen_Qwen3.6-35B-A3B-Q6_K_L (~30 GB)
echo ============================================================
echo.

set REPO=bartowski/Qwen_Qwen3.6-35B-A3B-GGUF
set FILE=Qwen_Qwen3.6-35B-A3B-Q6_K_L.gguf
set DEST=models\%FILE%

if exist "%DEST%" (
    echo [OK] Model already present at %DEST%
    goto done
)

python3 --version >nul 2>&1
if errorlevel 1 (
    python --version >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Python not found. Install Python 3.8+ from https://python.org
        pause
        exit /b 1
    )
    set PYTHON=python
) else (
    set PYTHON=python3
)

echo [*] Installing huggingface_hub...
%PYTHON% -m pip install -q "huggingface_hub>=0.22"

echo [*] Downloading %FILE% from %REPO%...
echo     This is ~30 GB. Grab a coffee.
echo.

%PYTHON% -c "from huggingface_hub import hf_hub_download; import os; p = hf_hub_download(repo_id='%REPO%', filename='%FILE%', local_dir='models'); print('Done: ' + p + ' (' + str(round(os.path.getsize(p)/1e9, 1)) + ' GB)')"

if errorlevel 1 (
    echo ERROR: Download failed.
    pause
    exit /b 1
)

:done
echo.
echo Run start_windows.bat to launch the server.
pause
