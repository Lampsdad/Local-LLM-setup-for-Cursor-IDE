@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ============================================================
echo  Local Model Runtime - Windows Install
echo ============================================================
echo.

:: ── llama-bin ────────────────────────────────────────────────
if exist "llama-bin\llama-server.exe" (
    echo [OK] llama-bin\ already populated, skipping download.
) else (
    echo [*] Fetching latest llama.cpp release from GitHub...
    mkdir llama-bin 2>nul

    powershell -NoProfile -Command ^
        "$rel = Invoke-RestMethod 'https://api.github.com/repos/ggml-org/llama.cpp/releases/latest';" ^
        "$asset = $rel.assets | Where-Object { $_.name -match 'win.*cuda.*x64.*\.zip' } | Select-Object -First 1;" ^
        "if (-not $asset) { Write-Error 'No Windows CUDA asset found'; exit 1 }" ^
        "Write-Host \"Downloading $($asset.name) ($([math]::Round($asset.size/1MB,0)) MB)...\";" ^
        "Invoke-WebRequest $asset.browser_download_url -OutFile 'llama-bin\llama-bin.zip' -UseBasicParsing;" ^
        "Expand-Archive 'llama-bin\llama-bin.zip' -DestinationPath 'llama-bin' -Force;" ^
        "Remove-Item 'llama-bin\llama-bin.zip';" ^
        "Write-Host 'llama.cpp binaries extracted.'"

    if errorlevel 1 (
        echo.
        echo ERROR: Failed to download llama.cpp binaries.
        echo Download manually from: https://github.com/ggml-org/llama.cpp/releases/latest
        echo Extract into the llama-bin\ folder.
        pause
        exit /b 1
    )
)

:: ── cloudflared ──────────────────────────────────────────────
set "CF_DIR=C:\Program Files (x86)\cloudflared"
set "CF_EXE=%CF_DIR%\cloudflared.exe"

if exist "%CF_EXE%" (
    echo [OK] cloudflared already installed.
) else (
    echo [*] Downloading cloudflared...
    mkdir "%CF_DIR%" 2>nul
    powershell -NoProfile -Command ^
        "Invoke-WebRequest 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe' -OutFile '%CF_EXE%' -UseBasicParsing;" ^
        "Write-Host 'cloudflared installed.'"

    if errorlevel 1 (
        echo ERROR: Failed to download cloudflared.
        echo Download from: https://github.com/cloudflare/cloudflared/releases/latest
        echo Place cloudflared.exe at: %CF_EXE%
        pause
        exit /b 1
    )
)

:: ── models dir ───────────────────────────────────────────────
if not exist "models\" mkdir models
echo [OK] models\ directory ready.

echo.
echo ============================================================
echo  Setup complete! Next steps:
echo    1. download_model.bat   -- downloads the ~30 GB model
echo    2. start_windows.bat    -- launches server + tunnel
echo ============================================================
echo.
pause
