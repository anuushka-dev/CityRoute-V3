# CityRoute - local setup (Windows PowerShell)
#
#   powershell -ExecutionPolicy Bypass -File .\setup.ps1
#
# Creates .venv with Python 3.11, installs the backend dependencies, copies
# .env.example to .env when it is missing, and installs the frontend
# dependencies. Run it from the project folder.

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $repoRoot

function Write-Step { param([string]$Text) Write-Host ""; Write-Host "==> $Text" -ForegroundColor Cyan }
function Fail { param([string]$Text) Write-Host ""; Write-Host "ERROR: $Text" -ForegroundColor Red; exit 1 }

if ($env:VIRTUAL_ENV) {
    Fail "A virtual environment is active ($env:VIRTUAL_ENV). Run 'deactivate' or open a new PowerShell window, then start setup.ps1 again."
}

Write-Step 'Checking Python 3.11'
$pythonOk = $false
try {
    & py -3.11 --version
    if ($LASTEXITCODE -eq 0) { $pythonOk = $true }
}
catch {
    $pythonOk = $false
}
if (-not $pythonOk) {
    Fail 'Python 3.11 was not found by the py launcher. Install it with: winget install --id Python.Python.3.11 -e'
}

$venvPython = Join-Path $repoRoot '.venv\Scripts\python.exe'
$createVenv = $true

if (Test-Path -LiteralPath $venvPython) {
    $existing = & $venvPython --version
    if ($existing -like 'Python 3.11*') {
        $createVenv = $false
        Write-Host "Reusing .venv ($existing)"
    }
    else {
        Write-Host "The existing .venv uses $existing; recreating it with Python 3.11"
    }
}

if ($createVenv) {
    Write-Step 'Creating .venv with Python 3.11'
    if (Test-Path -LiteralPath (Join-Path $repoRoot '.venv')) {
        Remove-Item -LiteralPath (Join-Path $repoRoot '.venv') -Recurse -Force
    }
    & py -3.11 -m venv .venv
    if ($LASTEXITCODE -ne 0) { Fail 'Could not create the virtual environment.' }
}

Write-Step 'Installing backend dependencies (this takes a few minutes)'
& $venvPython -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { Fail 'Upgrading pip failed.' }
& $venvPython -m pip install -r requirements.txt
if ($LASTEXITCODE -ne 0) { Fail 'Installing requirements.txt failed.' }

if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.env'))) {
    Copy-Item -LiteralPath (Join-Path $repoRoot '.env.example') -Destination (Join-Path $repoRoot '.env')
    Write-Host 'Created .env from .env.example'
}

Write-Step 'Checking Node.js'
$nodeOk = $false
try {
    $nodeVersion = & node --version
    if ($LASTEXITCODE -eq 0) { $nodeOk = $true }
}
catch {
    $nodeOk = $false
}
if (-not $nodeOk) {
    Fail 'Node.js was not found. Install Node 22 LTS from https://nodejs.org and run this script again.'
}
Write-Host "Found Node $nodeVersion"

Write-Step 'Installing frontend dependencies'
Push-Location -LiteralPath (Join-Path $repoRoot 'frontend')
try {
    & npm install --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { Fail 'npm install failed in frontend.' }
}
finally {
    Pop-Location
}

Write-Host ''
Write-Host 'Setup complete.' -ForegroundColor Green
Write-Host ''
Write-Host 'Start the demo with:'
Write-Host '    .\run-local.ps1'
Write-Host ''
Write-Host 'Then open http://localhost:5173 (API docs: the URL printed by run-local.ps1)'
