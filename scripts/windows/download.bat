@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0..\.."

:: ============================================================
::  Download: Qwen3.8 weights, sized to the machine present.
::
::  Takes the variant as argument 1 ("base", "ablit", "9b",
::  "4b") and asks if it is missing. launch.bat supplies it.
::
::  Up to three separate files make up a full install:
::    1. weights   -- per variant, see lib_variants.bat
::    2. MTP head  -- ggml-org/Qwen3.8-27B-GGUF  (speculative decoding)
::    3. mmproj    -- vision encoder
::
::  Files 2 and 3 exist for the 27B variants only, come from the
::  same place for BOTH of them, and are downloaded once.
::  huihui-ai ablates the language layers of unsloth's own UD
::  quants and states the MTP head and vision tower are left
::  untouched, so the stock ones stay correct -- the second 27B
::  variant costs ~21 GB, not ~25.
::
::  WHAT CHANGED: this used to offer five quants with hardcoded
::  sizes and always default to UD-Q5_K_XL, which is right on a
::  32 GB card and a guaranteed OOM on a 12 GB one. The menu is
::  now built from scripts\hardware.py, which knows every quant
::  in the repo, what each one weighs, and what context each
::  would leave on THIS GPU. The default is whatever that says.
::
::  NOTE: Qwen3.8-27B has a 248,320-token vocab with UNTIED
::  embeddings -- the embed + output tensors alone are ~2.5B
::  params. Unsloth's "_XL" quants keep those at higher
::  precision; plain Q4_K_M does not. Prefer the UD-*_XL files.
:: ============================================================

call :find_python
if not defined PY_EXE (
    echo  ERROR: Python not found. Install Python 3.8+ from https://python.org
    pause & exit /b 1
)

set "HW=%~dp0..\hardware.py"

:: ---- what does this machine want? ---------------------------
:: Done before anything is offered, so the menus can mark the
:: recommendation rather than making the user work it out from a
:: table in the README.
set "PROBED=0"
set "VRAM_MIB=0"
set "TIER_LABEL="
set "REC_FAMILY="
set "REC_QUANT="
for /f "usebackq tokens=1,* delims==" %%A in (`%PY_EXE% "%HW%" --recommend 2^>nul`) do set "%%A=%%B"

echo ============================================================
if "%PROBED%"=="1" (
    echo  Detected: %GPU_NAME%  ^(%VRAM_MIB% MiB^)
    echo  Tier    : %TIER_LABEL%
) else (
    echo  No GPU detected ^(is nvidia-smi on PATH?^).
    echo  Sizes below are shown without a context estimate.
)
echo ============================================================
echo.

:: ---- which variant? ----------------------------------------
set "WANT=%~1"
if defined WANT goto :have_variant

:: Mark the recommended family so the default is visible rather
:: than implied.
set "M1= " & set "M2= " & set "M3= " & set "M4= "
if "%REC_FAMILY%"=="base" set "M1=*"
if "%REC_FAMILY%"=="ablit" set "M2=*"
if "%REC_FAMILY%"=="9b"   set "M3=*"
if "%REC_FAMILY%"=="4b"   set "M4=*"

echo  Which build?
echo.
echo   %M1% [1] Qwen3.8-27B              stock Qwen release
echo   %M2% [2] Qwen3.8-27B abliterated  refusal behaviour removed
echo   %M3% [3] Qwen3.8-9B distill       third-party, text-only
echo   %M4% [4] Qwen3.8-4B distill       third-party, text-only
echo.
echo      * = fits this machine best
echo.
echo   3 and 4 are Empero's distillations of Qwen3.8-2.4T-A95B into
echo   the smaller Qwen3.5 architectures. They are NOT Qwen releases
echo   and have no MTP head and no vision tower, but they beat a 27B
echo   crushed into 2 bits on a small card.
echo.
set "VCHOICE="
set /p VCHOICE="Enter choice [1-4] (default=recommended): "
if not defined VCHOICE (
    set "WANT=%REC_FAMILY%"
    if not defined WANT set "WANT=base"
)
if "!VCHOICE!"=="1" set "WANT=base"
if "!VCHOICE!"=="2" set "WANT=ablit"
if "!VCHOICE!"=="3" set "WANT=9b"
if "!VCHOICE!"=="4" set "WANT=4b"

:have_variant
call "%~dp0lib_variants.bat" "%WANT%"
if errorlevel 1 (
    echo  ERROR: unknown variant "%WANT%" -- expected base, ablit, 9b or 4b.
    pause & exit /b 1
)

echo.
echo ============================================================
echo  Download: %V_LABEL%
echo  Source: %V_REPO%
echo ============================================================
echo.

:: ---- quant menu, built from the registry -------------------
:: Sizes and context estimates both come from hardware.py, so the
:: number shown here and the number the free-space check uses
:: cannot drift apart.
set "N=0"
set "DEFN="
echo  Weight quant options:
echo.
for /f "usebackq tokens=1-7 delims=|" %%A in (`%PY_EXE% "%HW%" --quants "%V_ID%" 2^>nul`) do (
    set /a N+=1
    set "Q_!N!=%%A"
    set "G_!N!=%%B"
    set "MARK= "
    if "%%G"=="1" ( set "MARK=*" & set "DEFN=!N!" )
    if "%%F"=="0" (
        set "NOTE=does not fit this GPU"
    ) else (
        set /a KCTX=%%C/1024
        set "NOTE=!KCTX!K ctx, MTP %%D, vision %%E"
    )
    echo    !MARK! [!N!] %%A   %%B GB   !NOTE!
)

if "%N%"=="0" (
    echo  ERROR: could not read the quant list from hardware.py.
    pause & exit /b 1
)
echo.
echo      * = recommended for this machine
echo.
set "CHOICE="
set /p CHOICE="Enter choice [1-%N%] (default=%DEFN%): "
if not defined CHOICE set "CHOICE=%DEFN%"
if not defined CHOICE set "CHOICE=1"

:: Validate before indexing: an out-of-range pick would silently
:: leave QUANT empty and download a file named "-.gguf".
set "QUANT=!Q_%CHOICE%!"
set "SIZE=!G_%CHOICE%!"
if not defined QUANT (
    echo  Invalid choice.
    pause & exit /b 1
)

:: ---- resolve the full plan for that exact quant -------------
:: Gives back the MTP head and mmproj precision that fit alongside
:: it. On a 24 GB card that is the q4_0 head rather than q8_0 --
:: 1.4 GB smaller, and the difference between keeping speculative
:: decoding and losing it.
set "REC_MTP_FILE="
set "REC_MMPROJ_FILE="
set "REC_MTP_REPO="
set "REC_MMPROJ_REPO="
set "REC_CTX=0"
set "REC_TOTAL_GB=%SIZE%"
set "REC_BELOW_MIN=0"
for /f "usebackq tokens=1,* delims==" %%A in (`%PY_EXE% "%HW%" --recommend --family "%V_ID%" --quant "%QUANT%" 2^>nul`) do set "%%A=%%B"

set "FILE=%V_PREFIX%-%QUANT%.gguf"

echo.
echo  Will download:
echo    weights : %FILE%  (~%SIZE% GB)
if defined REC_MTP_FILE    echo    MTP head: %REC_MTP_FILE%
if defined REC_MMPROJ_FILE echo    vision  : %REC_MMPROJ_FILE%
if "%PROBED%"=="1" (
    set /a SHOWCTX=%REC_CTX%/1024
    echo.
    echo    context : !SHOWCTX!K tokens on this GPU
)
if "%REC_BELOW_MIN%"=="1" (
    echo.
    echo  [WARN] this leaves less context than agentic coding really
    echo         wants. A smaller quant, or one of the distill builds,
    echo         would give you a much larger window.
)
echo.

:: ---- free space check ----
for /f "usebackq delims=" %%F in (`powershell -NoProfile -Command ^
    "[math]::Round((Get-PSDrive C).Free/1GB,1)"`) do set FREE=%%F
echo  Free space on C: : %FREE% GB
for /f "usebackq delims=" %%N in (`powershell -NoProfile -Command ^
    "[math]::Round(%REC_TOTAL_GB% + 5, 1)"`) do set NEEDED=%%N
echo  Recommended free  : %NEEDED% GB  (includes 5 GB working margin)
echo.
powershell -NoProfile -Command "if ((Get-PSDrive C).Free/1GB -lt %NEEDED%) { exit 1 } else { exit 0 }"
if errorlevel 1 (
    echo  WARNING: not enough free space. Run: kiln clean
    echo.
    set /p GOON="Continue anyway? [y/N]: "
    if /I not "!GOON!"=="y" exit /b 1
)

echo  Installing/upgrading huggingface_hub...
%PY_EXE% -m pip install -q "huggingface_hub>=0.22" "hf_transfer"

:: hf_transfer gives a large speedup on multi-GB files over fast links.
set HF_HUB_ENABLE_HF_TRANSFER=1

if not exist "models" mkdir "models"

call :fetch "%V_REPO%" "%FILE%"
if errorlevel 1 goto failed

if defined REC_MMPROJ_FILE (
    call :fetch "%REC_MMPROJ_REPO%" "%REC_MMPROJ_FILE%"
    if errorlevel 1 goto failed
)
if defined REC_MTP_FILE (
    call :fetch "%REC_MTP_REPO%" "%REC_MTP_FILE%"
    if errorlevel 1 goto failed
)

echo.
echo ============================================================
echo  Download complete: %FILE%
echo.
echo  Launch it with:
echo      launch.bat            ^(picks between installed builds^)
echo  or  kiln start %V_ID%
echo.
echo  The start script finds the quant on its own and sizes the
echo  context to this GPU -- nothing to edit if you did not take
echo  the default.
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
%PY_EXE% -c "from huggingface_hub import hf_hub_download; import os; p=hf_hub_download(repo_id='%REPO%', filename='%TARGET%', local_dir='models'); print('    saved:', p, '(' + str(round(os.path.getsize(p)/1e9, 1)) + ' GB)')"
if errorlevel 1 exit /b 1
exit /b 0

:: ------------------------------------------------------------
:: Sets PY_EXE, or leaves it undefined. "python" on a stock
:: Windows can be the App Execution Alias stub that opens the
:: Store and prints nothing, so check it actually answers.
::
:: NOTE for every for/f below: %PY_EXE% is used UNQUOTED inside
:: the backquotes. cmd re-parses that command line, and a quoted
:: program name followed by further quoted arguments breaks the
:: re-parse silently -- no error, no output.
:find_python
set "PY_EXE="
for %%P in (python python3 py) do (
    if not defined PY_EXE (
        %%P -c "import sys" >nul 2>&1 && set "PY_EXE=%%P"
    )
)
exit /b 0
