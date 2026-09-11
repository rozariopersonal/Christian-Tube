# Start-YouTube-Processor.ps1
# Auto-starts the ChristianApp YouTube Video Processor service (Docker Compose).

$ErrorActionPreference = "Continue"
$RootDir = Split-Path -Parent $PSScriptRoot

Write-Host "=== ChristianApp YouTube Video Processor Auto-Start ===" -ForegroundColor Cyan

# 1. Stop any retired whisper/transcriber processes
& "$RootDir\scripts\ctrl.ps1" stop-retired-transcriber

# 2. Ensure Docker Desktop & start YouTube Processor
Write-Host "`nChecking Docker daemon & starting YouTube Processor service..." -ForegroundColor Yellow
$docker = "$env:LOCALAPPDATA\Programs\DockerDesktop\resources\bin\docker.exe"
if (-not (Test-Path $docker)) {
    $docker = "docker"
}

$ready = $false
try {
    $null = & $docker info 2>$null
    if ($LASTEXITCODE -eq 0) { $ready = $true }
} catch { }

if (-not $ready) {
    Write-Host "Starting Docker Desktop..." -ForegroundColor Yellow
    $dockerDesktop = "$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe"
    if (Test-Path $dockerDesktop) {
        Start-Process $dockerDesktop
    }
    Write-Host "Waiting for Docker daemon to become responsive..."
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 3
        try {
            $null = & $docker info 2>$null
            if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        } catch { }
    }
}

if ($ready) {
    Write-Host "Docker is ready! Launching youtube-processor container..." -ForegroundColor Green
    & "$RootDir\scripts\ctrl.ps1" processor up
} else {
    Write-Warning "Docker daemon not ready yet. When Docker Desktop starts, youtube-processor will launch automatically."
}

Write-Host "`n=== Processor Status ===" -ForegroundColor Cyan
& "$RootDir\scripts\ctrl.ps1" status
