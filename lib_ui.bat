@echo off
:: ============================================================
::  Terminal styling shared by the CLI scripts.
::
::  Sourced, not run:   call "%~dp0lib_ui.bat"
::
::  Sets ESC and a C_* palette. When colour is unavailable or
::  unwanted every C_* becomes an empty string, so callers never
::  branch on it -- `echo %C_OK%[ok]%C_0% ready` is correct either
::  way, it just prints without the escapes.
::
::  Deliberately no setlocal: the caller wants these back.
:: ============================================================

:: ---- should we emit ANSI at all? ---------------------------
:: NO_COLOR is the cross-tool convention (https://no-color.org);
:: TERM=dumb is what CI and some editors' terminals set.
set "ESC="
if defined NO_COLOR    goto :plain
if /I "%TERM%"=="dumb" goto :plain

:: Getting a literal ESC byte into a cmd variable. The widespread
:: trick is `for /F %%a in ('echo prompt $E ^| cmd')`, which takes
:: the last line a nested cmd prints -- a prompt containing ESC.
:: It works, but what it captures depends on that cmd's banner and
:: working directory, and it silently yields nothing rather than
:: failing when it doesn't. PowerShell emitting char 27 says what
:: it means and behaves the same everywhere, for one extra process
:: per script.
for /F "delims=" %%a in ('powershell -NoProfile -Command "[char]27"') do set "ESC=%%a"
if not defined ESC goto :plain

set "C_0=%ESC%[0m"
set "C_B=%ESC%[1m"
set "C_D=%ESC%[2m"
set "C_OK=%ESC%[92m"
set "C_WARN=%ESC%[93m"
set "C_ERR=%ESC%[91m"
set "C_AC=%ESC%[96m"
set "C_HL=%ESC%[97m"
set "C_MU=%ESC%[90m"
set "C_INV=%ESC%[7m"
:: Line control for the in-place progress indicators.
set "C_CLR=%ESC%[2K"
set "C_HOME=%ESC%[1G"
set "C_UP=%ESC%[1A"
exit /b 0

:plain
set "C_0="
set "C_B="
set "C_D="
set "C_OK="
set "C_WARN="
set "C_ERR="
set "C_AC="
set "C_HL="
set "C_MU="
set "C_INV="
set "C_CLR="
set "C_HOME="
set "C_UP="
exit /b 0
