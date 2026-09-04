@echo off
:: ============================================================
::  kiln -- Windows front door.
::
::  The real CLI lives in scripts\windows\kiln.bat, next to the
::  libraries it calls. This shim exists so the command you type
::  sits at the root of the repo.
::
::    kiln            status board, then a menu
::    kiln setup      install llama.cpp + cloudflared
::    kiln get both   download the weights
::    kiln start      serve a model to Cursor
::    kiln help       every command
:: ============================================================
call "%~dp0scripts\windows\kiln.bat" %*
exit /b %errorlevel%
