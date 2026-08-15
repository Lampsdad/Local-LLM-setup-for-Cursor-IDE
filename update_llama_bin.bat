@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: ============================================================
::  Update llama.cpp binaries to the latest GitHub release.
::
::  Qwen3.8-27B needs a build with MTP speculative decoding,
::  which merged in b9180 (2026-05-16, PR #22673). Builds older
::  than that will load the model but silently lose the ~1.5-2x
::  MTP speedup -- `--spec-type draft-mtp` is rejected outright.
::
::  Target: win-cuda-13.3-x64 (RTX 5090 / Blackwell sm_120)
:: ============================================================

set ASSET_PATTERN=bin-win-cuda-13.3-x64
set BACKUP=llama-bin-backup

echo ============================================================
echo  Update llama.cpp binaries
echo ============================================================
echo.

:: ---- current version ----
if exist "llama-bin\llama-server.exe" (
    for /f "tokens=2 delims= " %%V in ('llama-bin\llama-server.exe --version 2^>^&1 ^| findstr /C:"build"') do set CURRENT=%%V
    echo  Installed build : !CURRENT!
) else (
    echo  Installed build : none
)

:: ---- latest release tag ----
echo  Querying GitHub for the latest release...
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command ^
    "(Invoke-RestMethod 'https://api.github.com/repos/ggml-org/llama.cpp/releases/latest').tag_name"`) do set TAG=%%T

if "%TAG%"=="" (
    echo  ERROR: could not reach the GitHub API.
    pause & exit /b 1
)
echo  Latest release  : %TAG%
echo.

set ZIP=llama-%TAG%-%ASSET_PATTERN%.zip
set URL=https://github.com/ggml-org/llama.cpp/releases/download/%TAG%/%ZIP%

:: ---- download ----
echo  Downloading %ZIP% ...
powershell -NoProfile -Command ^
    "$ProgressPreference='SilentlyContinue'; try { Invoke-WebRequest -Uri '%URL%' -OutFile '%TEMP%\%ZIP%' } catch { Write-Host $_.Exception.Message; exit 1 }"
if errorlevel 1 (
    echo  ERROR: download failed. Asset may not exist for this release:
    echo    %URL%
    pause & exit /b 1
)

:: ---- back up the existing install ----
if exist "llama-bin\llama-server.exe" (
    echo  Backing up current llama-bin\ to %BACKUP%\ ...
    if exist "%BACKUP%" rmdir /S /Q "%BACKUP%"
    move /Y "llama-bin" "%BACKUP%" >nul
)

:: ---- extract ----
echo  Extracting to llama-bin\ ...
if not exist "llama-bin" mkdir "llama-bin"
powershell -NoProfile -Command ^
    "Expand-Archive -LiteralPath '%TEMP%\%ZIP%' -DestinationPath 'llama-bin' -Force"
if errorlevel 1 (
    echo  ERROR: extraction failed. Restoring backup...
    if exist "%BACKUP%" (
        rmdir /S /Q "llama-bin" 2>nul
        move /Y "%BACKUP%" "llama-bin" >nul
    )
    pause & exit /b 1
)

:: Some releases nest everything one level deep -- flatten it.
if exist "llama-bin\build\bin\llama-server.exe" (
    move /Y "llama-bin\build\bin\*" "llama-bin\" >nul 2>&1
)

:: ---- CUDA runtime DLLs ----
:: The main zip omits cudart. Carry them over from the backup if
:: the new archive did not ship them.
if not exist "llama-bin\cudart64_13.dll" (
    if exist "%BACKUP%\cudart64_13.dll" (
        echo  Carrying CUDA runtime DLLs over from the previous install...
        copy /Y "%BACKUP%\cublas64_13.dll"   "llama-bin\" >nul 2>&1
        copy /Y "%BACKUP%\cublasLt64_13.dll" "llama-bin\" >nul 2>&1
        copy /Y "%BACKUP%\cudart64_13.dll"   "llama-bin\" >nul 2>&1
    ) else (
        echo.
        echo  WARNING: no CUDA runtime DLLs found. If the server fails to
        echo  start, download and extract this into llama-bin\ :
        echo    https://github.com/ggml-org/llama.cpp/releases/download/%TAG%/cudart-llama-bin-win-cuda-13.3-x64.zip
    )
)

del "%TEMP%\%ZIP%" >nul 2>&1

:: ---- verify ----
echo.
echo  Verifying new build...
llama-bin\llama-server.exe --version 2>&1 | findstr /C:"build"
if errorlevel 1 (
    echo  ERROR: the new binary failed to run. Restoring backup...
    rmdir /S /Q "llama-bin" 2>nul
    if exist "%BACKUP%" move /Y "%BACKUP%" "llama-bin" >nul
    pause & exit /b 1
)

echo.
echo  Checking MTP speculative-decoding support...
llama-bin\llama-server.exe --help 2>&1 | findstr /C:"draft-mtp" >nul
if errorlevel 1 (
    echo    [WARN] this build does NOT support --spec-type draft-mtp.
    echo           Qwen3.8 will run, but without the MTP speedup.
) else (
    echo    [OK]   --spec-type draft-mtp is supported.
)

echo.
echo ============================================================
echo  Updated to %TAG%. Previous build kept in %BACKUP%\
echo  Delete that folder once you have confirmed the new one works.
echo ============================================================
pause
