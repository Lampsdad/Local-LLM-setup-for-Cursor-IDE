@echo off
:: ============================================================
::  Variant registry -- the one place that knows what a model
::  variant IS. download / start / launch all resolve through
::  here so a third variant means editing one file.
::
::  Usage:   call lib_variants.bat <id>
::  Sets:    V_ID V_LABEL V_REPO V_PREFIX V_ALIAS V_UNCENSORED
::  Returns: errorlevel 1 on an unknown id
::
::  Deliberately has NO setlocal -- the caller wants these
::  variables back.
::
::  Why the two variants share their MTP head and vision
::  projector: huihui-ai's UD-* quants are re-ablations of the
::  same unsloth/Qwen3.8-27B-GGUF files this repo already used,
::  and huihui states the MTP and vision weights are left
::  unmodified by the ablation. So models\mtp-Qwen3.8-27B-Q8_0
::  .gguf and models\mmproj-F16.gguf serve both. Adding the
::  second variant costs ~21 GB of disk, not ~25.
::
::  It also means the quant names, the file sizes, and every
::  number probe_hardware.ps1 derives from them line up between
::  the two -- the context table in README.md is valid for both.
:: ============================================================

set "V_ID="
set "V_LABEL="
set "V_REPO="
set "V_PREFIX="
set "V_ALIAS="
set "V_UNCENSORED=0"

if /I "%~1"=="base"        goto :v_base
if /I "%~1"=="stock"       goto :v_base
if /I "%~1"=="ablit"       goto :v_ablit
if /I "%~1"=="abliterated" goto :v_ablit
exit /b 1

:v_base
set "V_ID=base"
set "V_LABEL=Qwen3.8-27B"
set "V_REPO=unsloth/Qwen3.8-27B-GGUF"
set "V_PREFIX=Qwen3.8-27B"
set "V_ALIAS=qwen3.8-27b"
set "V_UNCENSORED=0"
exit /b 0

:v_ablit
:: huihui-ai ablates layers 18-51 of the unsloth UD quants and
:: leaves the first 15 untouched, which is what keeps the coding
:: and tool-calling ability close to stock. Refusal behaviour is
:: removed, not softened -- see the warning launch.bat prints.
set "V_ID=ablit"
set "V_LABEL=Qwen3.8-27B abliterated"
set "V_REPO=huihui-ai/Huihui-Qwen3.8-27B-abliterated-GGUF"
set "V_PREFIX=Huihui-Qwen3.8-27B-abliterated"
set "V_ALIAS=qwen3.8-27b-abliterated"
set "V_UNCENSORED=1"
exit /b 0
