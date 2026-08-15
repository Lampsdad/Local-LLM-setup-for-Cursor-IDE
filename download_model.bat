@echo off
:: ============================================================
::  Kept for muscle memory. Downloads now go through
::  download_qwen3.8_27b.bat, which fetches all three pieces of
::  a Qwen3.8-27B install: weights, MTP head, and vision projector.
:: ============================================================
cd /d "%~dp0"
call "download_qwen3.8_27b.bat" %*
