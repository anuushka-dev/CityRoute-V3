# CityRoute - run the demo in Docker (Windows PowerShell)
#
#   powershell -ExecutionPolicy Bypass -File .\run-docker.ps1
#   powershell -ExecutionPolicy Bypass -File .\run-docker.ps1 -Port 9080
#   powershell -ExecutionPolicy Bypass -File .\run-docker.ps1 -Compose
#
# Builds Dockerfile.render-free (Node builds the .jsx bundle, Python serves the
# API and the app together) and runs it in the foreground so the logs stream.
# Press Ctrl+C to stop the container.

param(
    [int]$Port = 0,
    [switch]$Compose
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $repoRoot

function Fail { param([string]$Text) Write-Host ''; Write-Host "ERROR: $Text" -ForegroundColor Red; exit 1 }

function Test-PortFree {
    param([int]$Port)

    $listener = $null
    try {
        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($listener) { $listener.Stop() }
    }
}

$dockerOk = $false
try {
    $null = & docker version --format '{{.Server.Version}}' 2>$null
    if ($LASTEXITCODE -eq 0) { $dockerOk = $true }
}
catch {
    $dockerOk = $false
}

if (-not $dockerOk) {
    Fail 'Docker is not answering. Start Docker Desktop, wait until it reports that it is running, then try again.'
}

if ($Compose) {
    Write-Host 'Starting the full stack with docker compose (API + Redis + Prometheus) ...'
    Write-Host 'The API is published on http://localhost:8010 (see docker-compose.yml).'
    & docker compose up --build
    exit $LASTEXITCODE
}

if ($Port -le 0) {
    foreach ($candidate in 8000, 8010, 8080, 8110, 9000, 9001) {
        if (Test-PortFree -Port $candidate) { $Port = $candidate; break }
    }
}

if ($Port -le 0) {
    Fail 'No free host port was found. Pass one, for example: .\run-docker.ps1 -Port 9080'
}

if (-not (Test-PortFree -Port $Port)) {
    Fail "Port $Port is already in use or reserved by Windows. Pass another one, for example: .\run-docker.ps1 -Port 9080"
}

Write-Host 'Building the image. The first build downloads base images and runs npm ci, so it takes a few minutes ...'
& docker build -f Dockerfile.render-free -t cityroute:local .
if ($LASTEXITCODE -ne 0) { Fail 'The image build failed.' }

Write-Host ''
Write-Host "Starting the container on http://localhost:$Port ..."
Write-Host 'Press Ctrl+C to stop it.'
Write-Host ''

& docker run --rm --name cityroute-local -p "${Port}:8000" cityroute:local
exit $LASTEXITCODE
