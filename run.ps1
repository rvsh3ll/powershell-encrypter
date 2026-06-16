#requires -Version 5.1

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$venvPython = Join-Path $root '.venv\Scripts\python.exe'
$mainScript = Join-Path $root 'main.py'

if (-not (Test-Path $venvPython)) {
    throw "Virtual environment not found. Run .\install.ps1 first."
}

if (-not (Test-Path $mainScript)) {
    throw "main.py not found at $mainScript"
}

& $venvPython $mainScript
