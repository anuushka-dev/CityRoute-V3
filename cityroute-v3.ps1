<#
  CityRoute v3 - one script for local and Docker.

  Run it from the project folder:
      powershell -ExecutionPolicy Bypass -File .\cityroute-v3.ps1

  It checks Python 3.11, Node and Docker, creates the virtual environment,
  installs both dependency sets, picks free ports (Windows reserves some,
  which causes WinError 10013), then either starts the local demo or builds
  and runs the container. Options:

      -Mode local | docker | compose | setup | check
      -Root "C:\path\to\project"   (default: the script's own folder)
      -ApiPort 8010 -WebPort 5173 -DockerPort 8000   (force a port)
#>

param(
    [ValidateSet('auto', 'local', 'docker', 'compose', 'setup', 'check')]
    [string]$Mode = 'auto',
    [string]$Root = '',
    [int]$ApiPort = 0,
    [int]$WebPort = 0,
    [int]$DockerPort = 0
)

$ErrorActionPreference = 'Stop'

function Write-Head { param([string]$Text) Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan }
function Write-Ok { param([string]$Text) Write-Host "   OK   $Text" -ForegroundColor Green }
function Write-Note { param([string]$Text) Write-Host "   ..   $Text" -ForegroundColor DarkGray }
function Fail { param([string]$Text) Write-Host ''; Write-Host "ERROR: $Text" -ForegroundColor Red; exit 1 }

function Get-ProjectRoot {
    $candidates = @()
    if ($Root) { $candidates += $Root }
    if ($PSScriptRoot) { $candidates += $PSScriptRoot }
    $candidates += (Get-Location).Path
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'app\main.py')) { return $candidate }
    }
    return ''
}

function Test-PortFree {
    param([int]$Port)
    $listener = $null
    try {
        $listener = New-Object -TypeName System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        return $true
    }
    catch { return $false }
    finally { if ($listener) { $listener.Stop() } }
}

function Find-FreePort {
    param([int[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if (Test-PortFree -Port $candidate) { return $candidate }
    }
    return 0
}

function Get-VenvPython { return (Join-Path $script:Root '.venv\Scripts\python.exe') }
function Install-Backend {
    Write-Head 'Python environment'
    if ($env:VIRTUAL_ENV) {
        Fail "A virtual environment is active ($env:VIRTUAL_ENV). Open a new PowerShell window, or run 'deactivate', then start this script again."
    }
    $pythonOk = $false
    try {
        & py -3.11 --version | Out-Null
        if ($LASTEXITCODE -eq 0) { $pythonOk = $true }
    }
    catch { $pythonOk = $false }
    if (-not $pythonOk) {
        Fail 'Python 3.11 was not found. Install it with: winget install --id Python.Python.3.11 -e   then open a new PowerShell window.'
    }
    Write-Ok 'Python 3.11 is available'

    $venvPython = Get-VenvPython
    $recreate = $false
    if (Test-Path -LiteralPath $venvPython) {
        $existing = & $venvPython --version
        if ($existing -like 'Python 3.11*') { Write-Ok "Reusing .venv ($existing)" } else { Write-Note "The existing .venv uses $existing, recreating it with Python 3.11"; $recreate = $true }
    } else { $recreate = $true }

    if ($recreate) {
        $venvDir = Join-Path $script:Root '.venv'
        if (Test-Path -LiteralPath $venvDir) { Remove-Item -LiteralPath $venvDir -Recurse -Force }
        Write-Note 'Creating .venv ...'
        & py -3.11 -m venv $venvDir
        if ($LASTEXITCODE -ne 0) { Fail 'Could not create the virtual environment.' }
    }

    Write-Note 'Installing backend dependencies with python -m pip (first run takes a few minutes) ...'
    & $venvPython -m pip install --upgrade pip --quiet
    & $venvPython -m pip install -r (Join-Path $script:Root 'requirements.txt')
    if ($LASTEXITCODE -ne 0) { Fail 'Installing requirements.txt failed.' }
    Write-Ok 'Backend dependencies are installed'

    $envFile = Join-Path $script:Root '.env'
    if (-not (Test-Path -LiteralPath $envFile)) {
        Copy-Item -LiteralPath (Join-Path $script:Root '.env.example') -Destination $envFile
        Write-Ok 'Created .env from .env.example'
    }
}

function Install-Frontend {
    Write-Head 'Frontend'
    $nodeOk = $false
    try {
        $nodeVersion = & node --version
        if ($LASTEXITCODE -eq 0) { $nodeOk = $true }
    }
    catch { $nodeOk = $false }
    if (-not $nodeOk) { Fail 'Node.js was not found. Install Node 22 LTS from https://nodejs.org and run this script again.' }
    Write-Ok "Node $nodeVersion"

    $frontendDir = Join-Path $script:Root 'frontend'
    Push-Location -LiteralPath $frontendDir
    try {
        Write-Note 'Installing frontend dependencies ...'
        & npm install --no-audit --no-fund
        if ($LASTEXITCODE -ne 0) { Fail 'npm install failed.' }
    }
    finally { Pop-Location }
    Write-Ok 'Frontend dependencies are installed'
}
function Test-Docker {
    $dockerOk = $false
    try {
        & docker version --format '{{.Server.Version}}' | Out-Null
        if ($LASTEXITCODE -eq 0) { $dockerOk = $true }
    }
    catch { $dockerOk = $false }
    return $dockerOk
}

function Start-Local {
    Write-Head 'Checking the local setup'
    Install-Backend

    if (-not (Test-Path -LiteralPath (Join-Path $script:Root 'frontend\node_modules'))) {
        Install-Frontend
    } else {
        Write-Ok 'Frontend dependencies are already installed'
    }

    $api = $ApiPort
    if ($api -le 0) { $api = Find-FreePort -Candidates @(8010, 8011, 8020, 8050, 8080, 8110, 8210, 18100, 8001) }
    if ($api -le 0) { Fail 'No free port was found for the API. Pass one with -ApiPort 9080.' }

    $web = $WebPort
    if ($web -le 0) { $web = Find-FreePort -Candidates @(5173, 5174, 5180, 5190, 5199) }
    if ($web -le 0) { Fail 'No free port was found for the demo. Pass one with -WebPort 5185.' }

    $venvPython = Get-VenvPython
    $frontendDir = Join-Path $script:Root 'frontend'
    $origin = "http://127.0.0.1:$api"
    $backendCommand = "Set-Location -LiteralPath '$script:Root'; & '$venvPython' -m uvicorn app.main:app --reload --port $api"
    $frontendCommand = "Set-Location -LiteralPath '$frontendDir'; `$env:VITE_API_ORIGIN = '$origin'; npm run dev -- --port $web"

    Write-Head 'Starting the demo'
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoExit', '-Command', $backendCommand)
    Start-Sleep -Seconds 3
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoExit', '-Command', $frontendCommand)

    Write-Host ''
    Write-Host "   Demo   http://localhost:$web" -ForegroundColor Green
    Write-Host "   API    $origin/docs" -ForegroundColor Green
    Write-Host ''
    Write-Host '   Two windows opened. Close them, or press Ctrl+C in them, to stop.'
    Write-Host '   Redis is optional: without it the demo runs and only readiness reports degraded.'
}

function Start-Docker {
    if (-not (Test-Docker)) {
        Fail 'Docker is not answering. Start Docker Desktop, wait until it reports that it is running, then try again.'
    }
    $port = $DockerPort
    if ($port -le 0) { $port = Find-FreePort -Candidates @(8000, 8010, 8080, 8110, 9000, 9001) }
    if ($port -le 0) { Fail 'No free host port was found. Pass one with -DockerPort 9080.' }

    Push-Location -LiteralPath $script:Root
    try {
        Write-Head 'Building the image'
        Write-Note 'The first build downloads base images and runs npm ci, so it takes a few minutes.'
        & docker build -f Dockerfile.render-free -t cityroute:local .
        if ($LASTEXITCODE -ne 0) { Fail 'The image build failed.' }
        Write-Head 'Starting the container'
        Write-Host "   http://localhost:$port   (Ctrl+C stops it)" -ForegroundColor Green
        & docker run --rm --name cityroute-local -p "${port}:8000" cityroute:local
    }
    finally { Pop-Location }
}

function Start-Compose {
    if (-not (Test-Docker)) { Fail 'Docker is not answering. Start Docker Desktop first.' }
    Write-Note 'The API is published on http://localhost:8010, Prometheus on 9090.'
    Push-Location -LiteralPath $script:Root
    try { & docker compose up --build }
    finally { Pop-Location }
}
function Show-Check {
    Write-Head 'Setup check (nothing is changed)'
    $pythonOk = $false
    try { & py -3.11 --version; if ($LASTEXITCODE -eq 0) { $pythonOk = $true } } catch { $pythonOk = $false }
    if ($pythonOk) { Write-Ok 'Python 3.11 is available' } else { Write-Note 'Python 3.11 is missing: winget install --id Python.Python.3.11 -e' }
    try { Write-Ok "Node $((& node --version)) is available" } catch { Write-Note 'Node.js is missing: install Node 22 LTS from https://nodejs.org' }
    if (Test-Docker) { Write-Ok 'Docker is answering' } else { Write-Note 'Docker is not answering (only needed for the container path)' }
    $venvPython = Get-VenvPython
    if (Test-Path -LiteralPath $venvPython) { Write-Ok "Virtual environment: $((& $venvPython --version))" } else { Write-Note 'No .venv yet' }
    if (Test-Path -LiteralPath (Join-Path $script:Root '.env')) { Write-Ok '.env exists' } else { Write-Note 'No .env yet' }
    $graph = Join-Path $script:Root 'data\graphs\kanpur_central.graphml'
    if (Test-Path -LiteralPath $graph) { Write-Ok 'Graph file is present' } else { Write-Note 'data\graphs\kanpur_central.graphml is missing' }
    if (Test-Path -LiteralPath (Join-Path $script:Root 'frontend\node_modules')) { Write-Ok 'Frontend dependencies are installed' } else { Write-Note 'Frontend dependencies are missing' }
    $api = Find-FreePort -Candidates @(8010, 8011, 8020, 8050, 8080, 8110, 8210, 18100, 8001)
    if ($api -gt 0) { Write-Ok "Free API port available: $api" } else { Write-Note 'No free API port found in the usual range' }
    $web = Find-FreePort -Candidates @(5173, 5174, 5180, 5190, 5199)
    if ($web -gt 0) { Write-Ok "Free demo port available: $web" } else { Write-Note 'No free demo port found in the usual range' }
}

$script:Root = Get-ProjectRoot
if (-not $script:Root) {
    Fail 'app\main.py was not found. Put this script in the CityRoute project folder, or run it with -Root "C:\path\to\project".'
}

Write-Host ''
Write-Host 'CityRoute v3' -ForegroundColor Cyan
Write-Host "   Project: $script:Root"

$missing = @()
foreach ($required in @('requirements.txt', 'app\main.py', 'frontend\package.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $script:Root $required))) { $missing += $required }
}
if ($missing.Count -gt 0) { Fail ("These files are missing: " + ($missing -join ', ') + ' - extract the full project folder first.') }

if ($Mode -eq 'auto') {
    Write-Host ''
    Write-Host '  1  Run locally   (API + demo with hot reload)'
    Write-Host '  2  Run in Docker (build the image, then serve it)'
    Write-Host '  3  Docker Compose (API + Redis + Prometheus)'
    Write-Host '  4  Set up only   (install everything, start nothing)'
    Write-Host '  5  Check my setup'
    $choice = Read-Host '  Choose 1-5, then press Enter (default 1)'
    switch ($choice) {
        '2' { $Mode = 'docker' }
        '3' { $Mode = 'compose' }
        '4' { $Mode = 'setup' }
        '5' { $Mode = 'check' }
        default { $Mode = 'local' }
    }
}

switch ($Mode) {
    'setup' { Install-Backend; Install-Frontend; Write-Head 'Setup complete'; Write-Host '   Run this script again and choose 1 (local) or 2 (Docker).' }
    'local' { Start-Local }
    'docker' { Start-Docker }
    'compose' { Start-Compose }
    'check' { Show-Check }
}
