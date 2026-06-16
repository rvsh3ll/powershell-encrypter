@echo off
setlocal
cd /d "%~dp0"
for /f "usebackq delims=" %%i in ("%~dp0VERSION") do set VERSION=%%i
echo PowerShell Script Encryptor %VERSION%
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1"
if errorlevel 1 (
    echo.
    echo Run failed.
    pause
    exit /b 1
)
