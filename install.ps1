#requires -Version 5.1

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$versionPath = Join-Path $root 'VERSION'
$version = if (Test-Path -LiteralPath $versionPath) {
    (Get-Content -LiteralPath $versionPath -Raw).Trim()
} else {
    'v1.0.1'
}
Set-Location $root

Write-Host "PowerShell Script Encryptor $version"

function Get-PythonLauncher {
    if (Get-Command python -ErrorAction SilentlyContinue) {
        return @{ Command = 'python'; Args = @() }
    }

    if (Get-Command py -ErrorAction SilentlyContinue) {
        return @{ Command = 'py'; Args = @('-3') }
    }

    throw 'Python not found. Install Python 3 from https://www.python.org/downloads/'
}

$launcher = Get-PythonLauncher
$venvPython = Join-Path $root '.venv\Scripts\python.exe'

if (-not (Test-Path $venvPython)) {
    Write-Host 'Creating virtual environment...'
    & $launcher.Command @($launcher.Args + @('-m', 'venv', '.venv'))
}

Write-Host 'Installing dependencies...'
& $venvPython -m pip install --upgrade pip
& $venvPython -m pip install -r (Join-Path $root 'requirements.txt')

Write-Host ''
Write-Host 'Install complete. Run the app with:'
Write-Host '  .\run.ps1'
Write-Host 'or double-click run.bat'
