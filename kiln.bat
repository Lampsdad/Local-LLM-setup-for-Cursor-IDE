@echo off
:: ============================================================
::  kiln -- Windows front door.
::
::  The real CLI lives in scripts\windows\kiln.bat, next to the
::  libraries it calls. This shim exists so the command you type
::  sits at the root of the repo.
::
::    kiln            full-screen TUI
::    kiln status     status board
::    kiln setup      install llama.cpp + cloudflared
::    kiln get both   download the weights
::    kiln start      serve a model to Cursor
::    kiln help       every command
::
::  The call and the exit share a line on purpose: kiln self-update
::  can rewrite this file while it runs, and cmd reads a batch file
::  one line at a time from a byte offset. The exit needs an explicit
::  code, because a bare exit /b leaves cmd /c exiting 0. The call in
::  front of it delays reading errorlevel until the CLI has returned.
:: ============================================================
call "%~dp0scripts\windows\kiln.bat" %* & call exit /b %%errorlevel%%
