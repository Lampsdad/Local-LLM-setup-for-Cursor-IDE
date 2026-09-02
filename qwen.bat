@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
call "%~dp0lib_ui.bat"

:: ============================================================
::  qwen -- one front door for this repo.
::
::    qwen                 status board, then a menu
::    qwen status          status board only
::    qwen setup           llama.cpp + cloudflared + models\
::    qwen get [base|ablit|both]
::    qwen start [base|ablit]
::    qwen stop            stop server and tunnel
::    qwen key [show|rotate|set <key>]
::    qwen update          upgrade llama.cpp
::    qwen bench | clean | help
::
::  Everything here delegates to the existing scripts, and none
::  of them changed to accommodate it -- any of them can still be
::  run directly. This is a front door, not a rewrite.
:: ============================================================

set "BINARY=llama-bin\llama-server.exe"
set "CF_EXE=C:\Program Files (x86)\cloudflared\cloudflared.exe"
set "CF_LOG=cloudflared-err.log"

set "CMD=%~1"
set "ARG=%~2"
set "ARG2=%~3"

if not defined CMD        goto :board_and_menu
if /I "%CMD%"=="status"   goto :cmd_status
if /I "%CMD%"=="setup"    goto :cmd_setup
if /I "%CMD%"=="get"      goto :cmd_get
if /I "%CMD%"=="download" goto :cmd_get
if /I "%CMD%"=="start"    goto :cmd_start
if /I "%CMD%"=="run"      goto :cmd_start
if /I "%CMD%"=="stop"     goto :cmd_stop
if /I "%CMD%"=="key"      goto :cmd_key
if /I "%CMD%"=="update"   goto :cmd_update
if /I "%CMD%"=="bench"    goto :cmd_bench
if /I "%CMD%"=="clean"    goto :cmd_clean
if /I "%CMD%"=="help"     goto :cmd_help
if /I "%CMD%"=="-h"       goto :cmd_help
if /I "%CMD%"=="--help"   goto :cmd_help

echo.
echo  %C_ERR%Unknown command:%C_0% %CMD%
goto :cmd_help


:: ============================================================
::  status board
:: ============================================================
:cmd_status
call :banner
call :gather
call :board
exit /b 0

:board_and_menu
call :banner
call :gather
call :board
goto :menu

:banner
echo.
if defined ESC <nul set /p "=%C_AC%%C_B%"
type "%~dp0banner.txt"
if defined ESC <nul set /p "=%C_0%"
echo.
exit /b 0

:board
call :rule
call :row "llama.cpp"    "%ST_BIN_S%"
call :row "MTP support"  "%ST_MTP_S%"
call :row "cloudflared"  "%ST_CF_S%"
call :row "GPU"          "%ST_GPU_S%"
call :row "disk free"    "%ST_FREE_S%"
call :rule
call :row "Qwen3.8-27B"  "%ST_BASE_S%"
call :row " abliterated" "%ST_ABL_S%"
call :row "shared files" "%ST_SHARED_S%"
call :rule
call :row "server"       "%ST_RUN_S%"
call :row "API key"      "%ST_KEY_S%"
call :row "tunnel"       "%ST_URL_S%"
call :rule
echo.
if defined ST_NEXT echo  %C_HL%Next:%C_0%  %ST_NEXT%
if defined ST_NEXT echo.
exit /b 0

:rule
echo  %C_MU%------------------------------------------------------------%C_0%
exit /b 0

:: :row <label> <value, may carry its own colour>
:row
set "L=%~1                "
echo   %C_MU%!L:~0,14!%C_0% %~2
exit /b 0


:: ============================================================
::  state gathering -- shared by the board and the "Next:" hint
:: ============================================================
:gather
set "ST_NEXT="

:: ---- llama.cpp ----
set "ST_BIN=0"
set "ST_BIN_S=%C_ERR%not installed%C_0%"
if exist "%BINARY%" (
    set "ST_BIN=1"
    set "ST_BUILD=?"
    rem llama-server prints "version: 8679 (94ca829b6)". Do NOT
    rem match /C:"build" - that also hits the "built with Clang"
    rem line and reports the build as the word "with".
    for /f "tokens=2 delims= " %%V in ('llama-bin\llama-server.exe --version 2^>^&1 ^| findstr /C:"version:"') do set "ST_BUILD=%%V"
    set "ST_BIN_S=%C_OK%installed%C_0%  %C_MU%build !ST_BUILD!%C_0%"
)

:: ---- MTP support, merged in b9180 ----
set "ST_MTP=0"
set "ST_MTP_S=%C_MU%-%C_0%"
if "%ST_BIN%"=="1" (
    "%BINARY%" --help 2>&1 | findstr /C:"draft-mtp" >nul
    if errorlevel 1 (
        set "ST_MTP_S=%C_WARN%unavailable%C_0%  %C_MU%build predates b9180%C_0%"
    ) else (
        set "ST_MTP=1"
        set "ST_MTP_S=%C_OK%available%C_0%"
    )
)

:: ---- cloudflared ----
if exist "%CF_EXE%" (
    set "ST_CF_S=%C_OK%installed%C_0%"
) else (
    set "ST_CF_S=%C_WARN%missing%C_0%  %C_MU%local only, no tunnel%C_0%"
)

:: ---- GPU ----
set "ST_GPU_S=%C_WARN%nvidia-smi not found%C_0%"
:: Each option quoted whole: inside a for/f backquote cmd re-parses
:: the line and treats the comma as an argument separator, so the
:: bare form reaches nvidia-smi as two options it does not know.
for /f "usebackq delims=" %%G in (`nvidia-smi "--query-gpu=name,memory.total" "--format=csv,noheader" 2^>nul`) do set "ST_GPU_S=%C_HL%%%G%C_0%"

:: ---- disk ----
set "ST_FREE_S=%C_MU%unknown%C_0%"
for /f "usebackq delims=" %%F in (`powershell -NoProfile -Command "[math]::Round((Get-PSDrive C).Free/1GB,0)"`) do set "ST_FREE_S=%C_HL%%%F GB%C_0%"

:: ---- weights ----
call :probe "Qwen3.8-27B"                    Q_BASE
call :probe "Huihui-Qwen3.8-27B-abliterated" Q_ABL
if defined Q_BASE (set "ST_BASE_S=%C_OK%!Q_BASE!%C_0%") else (set "ST_BASE_S=%C_MU%not downloaded%C_0%")
if defined Q_ABL  (set "ST_ABL_S=%C_OK%!Q_ABL!%C_0%")  else (set "ST_ABL_S=%C_MU%not downloaded%C_0%")

:: Both builds share these two, so they are their own row rather
:: than being counted against either one.
if exist "models\mtp-Qwen3.8-27B-Q8_0.gguf" (set "ST_SHARED_S=%C_OK%MTP head%C_0%") else (set "ST_SHARED_S=%C_MU%MTP head%C_0%")
if exist "models\mmproj-F16.gguf" (set "ST_SHARED_S=!ST_SHARED_S!   %C_OK%vision%C_0%") else (set "ST_SHARED_S=!ST_SHARED_S!   %C_MU%vision%C_0%")

:: ---- server ----
set "ST_RUN=0"
set "ST_RUN_S=%C_MU%stopped%C_0%"
tasklist /FI "IMAGENAME eq llama-server.exe" 2>nul | findstr /I "llama-server.exe" >nul
if not errorlevel 1 (
    set "ST_RUN=1"
    set "ST_RUN_S=%C_OK%running%C_0%  %C_MU%port 8080%C_0%"
)

:: ---- key ----
set "ST_KEY_S=%C_MU%not generated yet%C_0%"
if exist "api_key.txt" (
    set "K="
    set /p K=<api_key.txt
    set "ST_KEY_S=%C_HL%!K:~0,6!%C_0%%C_MU%...!K:~-4!   qwen key show%C_0%"
)

:: ---- tunnel: only meaningful while a server is up ----
set "ST_URL_S=%C_MU%none%C_0%"
if "%ST_RUN%"=="1" if exist "%CF_LOG%" (
    for /f "usebackq delims=" %%U in (`powershell -NoProfile -Command "(Select-String -Path '%CF_LOG%' -Pattern 'https://\S+trycloudflare\.com').Matches.Value ^| Select-Object -Last 1"`) do set "ST_URL_S=%C_HL%%%U/v1%C_0%"
)

:: ---- the one thing to do next ----
:: Ordered by dependency, first match wins, so the hint is always
:: the step that unblocks the rest.
if "%ST_BIN%"=="0" set "ST_NEXT=%C_AC%qwen setup%C_0%    install llama.cpp and cloudflared"
if not defined ST_NEXT if "%ST_MTP%"=="0" set "ST_NEXT=%C_AC%qwen update%C_0%   upgrade llama.cpp for MTP speculative decoding"
if not defined ST_NEXT if not defined Q_BASE if not defined Q_ABL set "ST_NEXT=%C_AC%qwen get both%C_0% download the weights"
if not defined ST_NEXT if "%ST_RUN%"=="0" set "ST_NEXT=%C_AC%qwen start%C_0%    serve a model to Cursor"
exit /b 0

:: :probe <filename prefix> <out var>
:: Best quant present, in the same order start_qwen3.8_27b.bat
:: picks, so the board names the file that would actually load.
:probe
set "%~2="
for %%Q in (UD-Q5_K_XL UD-Q4_K_XL UD-Q6_K_XL Q8_0 UD-IQ3_XXS) do (
    if not defined %~2 if exist "models\%~1-%%Q.gguf" set "%~2=%%Q"
)
exit /b 0


:: ============================================================
::  menu (no-argument mode)
:: ============================================================
:menu
echo   %C_HL%1%C_0%  start a model       %C_MU%qwen start%C_0%
echo   %C_HL%2%C_0%  download a model    %C_MU%qwen get%C_0%
echo   %C_HL%3%C_0%  stop the server     %C_MU%qwen stop%C_0%
echo   %C_HL%4%C_0%  show the API key    %C_MU%qwen key show%C_0%
echo   %C_HL%5%C_0%  install or update   %C_MU%qwen setup, qwen update%C_0%
echo   %C_HL%Q%C_0%  quit
echo.
set "SEL="
set /p "SEL=  choice: "
if not defined SEL exit /b 0
if /I "%SEL%"=="Q" exit /b 0
if "%SEL%"=="1" goto :cmd_start
if "%SEL%"=="2" goto :cmd_get
if "%SEL%"=="3" goto :cmd_stop
if "%SEL%"=="4" goto :menu_key
if "%SEL%"=="5" goto :cmd_setup
echo  %C_ERR%Not a choice.%C_0%
echo.
goto :menu

:menu_key
set "ARG=show"
goto :cmd_key


:: ============================================================
::  commands
:: ============================================================
:cmd_setup
call :step "Installing llama.cpp, cloudflared and models\"
call "%~dp0install_windows.bat"
exit /b %errorlevel%

:cmd_update
call :step "Upgrading llama.cpp"
call "%~dp0update_llama_bin.bat"
exit /b %errorlevel%

:cmd_get
if /I "%ARG%"=="both" goto :get_both
if defined ARG (
    call "%~dp0download_qwen3.8_27b.bat" "%ARG%"
    exit /b %errorlevel%
)
call "%~dp0download_qwen3.8_27b.bat"
exit /b %errorlevel%

:get_both
:: Stock first on purpose: it brings down the MTP head and the
:: vision projector, which the abliterated run then finds already
:: present and skips. The other order costs the same but reads as
:: if the second download were mysteriously smaller.
call :step "1 of 2   Qwen3.8-27B -- weights, MTP head, vision projector"
call "%~dp0download_qwen3.8_27b.bat" base
if errorlevel 1 exit /b 1
call :step "2 of 2   Qwen3.8-27B abliterated -- weights only"
call "%~dp0download_qwen3.8_27b.bat" ablit
exit /b %errorlevel%

:cmd_start
if defined ARG (
    call "%~dp0start_qwen3.8_27b.bat" "%ARG%"
    exit /b %errorlevel%
)
call "%~dp0launch.bat"
exit /b %errorlevel%

:cmd_stop
call :step "Stopping llama-server and cloudflared"
set "HIT=0"
tasklist /FI "IMAGENAME eq llama-server.exe" 2>nul | findstr /I "llama-server.exe" >nul
if not errorlevel 1 set "HIT=1"
taskkill /F /IM llama-server.exe >nul 2>&1
taskkill /F /IM cloudflared.exe  >nul 2>&1
if "%HIT%"=="1" (
    echo   %C_OK%stopped%C_0%
) else (
    echo   %C_MU%nothing was running%C_0%
)
echo.
exit /b 0

:cmd_key
if /I "%ARG%"=="rotate" goto :key_rotate
if /I "%ARG%"=="set"    goto :key_set

call "%~dp0lib_api_key.bat"
if errorlevel 1 exit /b 1
echo.
echo  %C_MU%API key -- paste into Cursor's OpenAI API Key field%C_0%
echo.
echo    %C_HL%%API_KEY%%C_0%
echo.
echo  %C_MU%Stored in api_key.txt, readable only by %USERNAME%.%C_0%
echo.
exit /b 0

:key_rotate
del "api_key.txt" >nul 2>&1
call "%~dp0lib_api_key.bat"
if errorlevel 1 exit /b 1
echo.
echo   %C_OK%new key%C_0%  %C_HL%%API_KEY%%C_0%
echo   %C_WARN%Update it in Cursor, then restart the server to load it.%C_0%
echo.
exit /b 0

:key_set
if not defined ARG2 (
    echo  %C_ERR%Usage:%C_0% qwen key set YOUR-KEY
    exit /b 1
)
:: Your own passphrase instead of the generated one. llama-server
:: compares it verbatim, so anything without a newline works.
powershell -NoProfile -Command "Set-Content -Path 'api_key.txt' -Value '%ARG2%' -Encoding ascii -NoNewline"
icacls "api_key.txt" /inheritance:r /grant:r "%USERNAME%:F" >nul 2>&1
echo.
echo   %C_OK%key set%C_0%
echo   %C_WARN%Restart the server to load it.%C_0%
echo.
exit /b 0

:cmd_bench
call "%~dp0benchmark_qwen3.8.bat"
exit /b %errorlevel%

:cmd_clean
call "%~dp0cleanup_disk.bat"
exit /b %errorlevel%

:step
echo.
echo  %C_AC%::%C_0%  %C_HL%%~1%C_0%
echo.
exit /b 0

:cmd_help
call :banner
echo  %C_HL%Usage:%C_0%  qwen COMMAND [ARGUMENT]
echo.
echo   %C_AC%status%C_0%                  what is installed, downloaded and running
echo   %C_AC%setup%C_0%                   one-time: llama.cpp, cloudflared, models\
echo   %C_AC%update%C_0%                  upgrade llama.cpp, needed for MTP
echo   %C_AC%get%C_0%   [base^|ablit^|both]  download weights
echo   %C_AC%start%C_0% [base^|ablit]       serve a model; no argument opens the picker
echo   %C_AC%stop%C_0%                    stop the server and the tunnel
echo   %C_AC%key%C_0%   [show^|rotate^|set] manage the API key
echo   %C_AC%bench%C_0%                   quant speed and throughput sweep
echo   %C_AC%clean%C_0%                   reclaim disk from superseded GGUFs
echo.
echo  %C_MU%With no command, qwen prints the status board and a menu.%C_0%
echo  %C_MU%Set NO_COLOR=1 to disable colour.%C_0%
echo.
exit /b 0
