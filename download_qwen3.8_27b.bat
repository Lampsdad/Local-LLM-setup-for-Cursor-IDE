@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: ============================================================
::  Download: Qwen3.8-27B  (released 2026-08-05)
::
::  Three separate files make up a full install:
::    1. weights   -- unsloth/Qwen3.8-27B-GGUF   (UD dynamic quants)
::    2. MTP head  -- ggml-org/Qwen3.8-27B-GGUF  (speculative decoding)
::    3. mmproj    -- unsloth/Qwen3.8-27B-GGUF   (vision encoder)
::
::  The MTP head is only published by ggml-org, so it is paired
::  with unsloth weights. Both are conversions of the same
::  Qwen/Qwen3.8-27B checkpoint, so vocab and hidden dims match.
::
::  NOTE: Qwen3.8-27B has a 248,320-token vocab with UNTIED
::  embeddings -- the embed + output tensors alone are ~2.5B
::  params. Unsloth's "_XL" quants keep those at higher
::  precision; plain Q4_K_M does not. Prefer the UD-*_XL files.
:: ============================================================

set BASE_REPO=unsloth/Qwen3.8-27B-GGUF
set MTP_REPO=ggml-org/Qwen3.8-27B-GGUF

echo ============================================================
echo  Download: Qwen3.8-27B
echo  Target: RTX 5090 (32 GB VRAM)
echo ============================================================
echo.
echo  Weight quant options:
echo.
echo    [1] UD-Q5_K_XL   20.2 GB  recommended -- best quality that
echo                              still leaves room for MTP + 131K ctx
echo    [2] UD-Q4_K_XL   17.9 GB  more headroom -- reaches ~200K ctx
echo    [3] UD-Q6_K_XL   25.9 GB  highest quality, but NO room for
echo                              the MTP head (loses the speedup)
echo    [4] UD-IQ3_XXS   11.9 GB  small; noticeably weaker on agentic
echo                              tool-calling -- not recommended
echo    [5] Q8_0         29.0 GB  near-lossless reference for benchmarking
echo.
set /p CHOICE="Enter choice [1-5] (default=1): "
if "%CHOICE%"=="" set CHOICE=1

if "%CHOICE%"=="1" set "FILE=Qwen3.8-27B-UD-Q5_K_XL.gguf" & set "SIZE=20.2"
if "%CHOICE%"=="2" set "FILE=Qwen3.8-27B-UD-Q4_K_XL.gguf" & set "SIZE=17.9"
if "%CHOICE%"=="3" set "FILE=Qwen3.8-27B-UD-Q6_K_XL.gguf" & set "SIZE=25.9"
if "%CHOICE%"=="4" set "FILE=Qwen3.8-27B-UD-IQ3_XXS.gguf" & set "SIZE=11.9"
if "%CHOICE%"=="5" set "FILE=Qwen3.8-27B-Q8_0.gguf"       & set "SIZE=29.0"

if not defined FILE (
    echo  Invalid choice.
    pause & exit /b 1
)

:: ---- MTP head sizing ----
:: Q8_0 head (3.2 GB) is the quality pick. With a Q6_K_XL base
:: there is no VRAM left for it at all.
set "MTP_FILE=mtp-Qwen3.8-27B-Q8_0.gguf"
set "MTP_SIZE=3.2"
if "%CHOICE%"=="3" (
    set "MTP_FILE="
    echo.
    echo  NOTE: UD-Q6_K_XL leaves no VRAM for the MTP head, so it
    echo        will not be downloaded. Generation will be slower.
)

echo.
echo  Will download:
echo    weights : %FILE%  (~%SIZE% GB)
if defined MTP_FILE echo    MTP head: %MTP_FILE%  (~%MTP_SIZE% GB)
echo    vision  : mmproj-F16.gguf  (~0.93 GB)
echo.

:: ---- free space check ----
for /f "usebackq delims=" %%F in (`powershell -NoProfile -Command ^
    "[math]::Round((Get-PSDrive C).Free/1GB,1)"`) do set FREE=%%F
echo  Free space on C: : %FREE% GB
for /f "usebackq delims=" %%N in (`powershell -NoProfile -Command ^
    "[math]::Round(%SIZE% + 0.93 + $(if('%MTP_FILE%' -ne ''){%MTP_SIZE%}else{0}) + 5, 1)"`) do set NEEDED=%%N
echo  Recommended free  : %NEEDED% GB  (includes 5 GB working margin)
echo.
powershell -NoProfile -Command "if ((Get-PSDrive C).Free/1GB -lt %NEEDED%) { exit 1 } else { exit 0 }"
if errorlevel 1 (
    echo  WARNING: not enough free space. Run cleanup_disk.bat first.
    echo.
    set /p GOON="Continue anyway? [y/N]: "
    if /I not "!GOON!"=="y" exit /b 1
)

:: ---- python ----
python --version >nul 2>&1
if errorlevel 1 (
    python3 --version >nul 2>&1
    if errorlevel 1 (
        echo  ERROR: Python not found. Install Python 3.8+ from https://python.org
        pause & exit /b 1
    )
    set PYTHON=python3
) else (
    set PYTHON=python
)

echo  Installing/upgrading huggingface_hub...
%PYTHON% -m pip install -q "huggingface_hub>=0.22" "hf_transfer"

:: hf_transfer gives a large speedup on multi-GB files over fast links.
set HF_HUB_ENABLE_HF_TRANSFER=1

if not exist "models" mkdir "models"

call :fetch "%BASE_REPO%" "%FILE%"
if errorlevel 1 goto failed

call :fetch "%BASE_REPO%" "mmproj-F16.gguf"
if errorlevel 1 goto failed

if defined MTP_FILE (
    call :fetch "%MTP_REPO%" "%MTP_FILE%"
    if errorlevel 1 goto failed
)

echo.
echo ============================================================
echo  Download complete.
echo.
echo  Set the model in start_qwen3.8_27b.bat if you did not pick
echo  the default:
echo      set MODEL=models\%FILE%
echo.
echo  Then run: start_qwen3.8_27b.bat
echo ============================================================
pause
exit /b 0

:failed
echo.
echo  ERROR: a download failed. Re-running this script resumes
echo  from where it stopped.
pause
exit /b 1

:: ------------------------------------------------------------
:fetch
set "REPO=%~1"
set "TARGET=%~2"
if exist "models\%TARGET%" (
    echo  [OK] already present: %TARGET%
    exit /b 0
)
echo.
echo  [*] Downloading %TARGET% from %REPO% ...
:: No %-formatting in this one-liner: cmd.exe pairs up percent
:: signs across the whole line, so a Python '%' operator sitting
:: alongside %REPO% / %TARGET% gets eaten during expansion.
%PYTHON% -c "from huggingface_hub import hf_hub_download; import os; p=hf_hub_download(repo_id='%REPO%', filename='%TARGET%', local_dir='models'); print('    saved:', p, '(' + str(round(os.path.getsize(p)/1e9, 1)) + ' GB)')"
if errorlevel 1 exit /b 1
exit /b 0
