@echo off
:: ============================================================
::  Kept for muscle memory. The tuned Windows launcher is now
::  start_qwen3.8_27b.bat -- it auto-detects which Qwen3.8 quant
::  you downloaded, enables MTP speculative decoding and vision
::  when the files are present, and sizes context to the GPU.
:: ============================================================
cd /d "%~dp0"
call "start_qwen3.8_27b.bat" %*
