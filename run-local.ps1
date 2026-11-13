# CityRoute - start the local demo (Windows PowerShell)
#
#   powershell -ExecutionPolicy Bypass -File .\run-local.ps1
#
# Opens two windows: the API with auto-reload and the Vite dev server. Ports
# are picked automatically, because Windows reserves ranges (Hyper-V, WSL,
# Docker Desktop) where binding fails with WinError 10013.

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$venvPython = Join-Path $repoRoot '.venv\Scripts\python.exe'
$frontendDir = Join-Path $repoRoot 'frontend'

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

if (-not (Test-Path -LiteralPath $venvPython)) {
    Write-Host 'The virtual environment is missing. Run .\setup.ps1 first.' -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath (Join-Path $frontendDir 'node_modules'))) {
    Write-Host 'Frontend dependencies are missing. Run .\setup.ps1 first.' -ForegroundColor Red
    exit 1
}

$apiPort = 0
foreach ($candidate in 8010, 8011, 8020, 8050, 8080, 8110, 8210, 18100, 8001) {
    if (Test-PortFree -Port $candidate) { $apiPort = $candidate; break }
}

if ($apiPort -eq 0) {
    Write-Host 'No free port was found for the API.' -ForegroundColor Red
    exit 1
}

$webPort = 0
foreach ($candidate in 5173, 5174, 5180, 5190, 5199) {
    if (Test-PortFree -Port $candidate) { $webPort = $candidate; break }
}

if ($webPort -eq 0) {
    Write-Host 'No free port was found for the frontend.' -ForegroundColor Red
    exit 1
}

$apiOrigin = "http://127.0.0.1:$apiPort"
$backendCommand = "Set-Location -LiteralPath '$repoRoot'; & '$venvPython' -m uvicorn app.main:app --reload --port $apiPort"
$frontendCommand = "Set-Location -LiteralPath '$frontendDir'; `$env:VITE_API_ORIGIN = '$apiOrigin'; npm run dev -- --port $webPort"

Write-Host "Starting the CityRoute API on $apiOrigin ..."
Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoExit', '-Command', $backendCommand)

Start-Sleep -Seconds 3

Write-Host "Starting the frontend dev server on http://localhost:$webPort ..."
Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoExit', '-Command', $frontendCommand)

Write-Host ''
Write-Host 'Two windows opened:'
Write-Host "    API   $apiOrigin/docs"
Write-Host "    Demo  http://localhost:$webPort"
Write-Host ''
Write-Host 'Close those windows (or press Ctrl+C in them) to stop the demo.'
