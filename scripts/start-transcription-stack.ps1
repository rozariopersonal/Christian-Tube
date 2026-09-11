# Start-Transcription-Stack.ps1
# Ensures all components of the Christian-Tube transcription stack are running:
# 1. Native Ollama LLM
# 2. Native Whisper server
# 3. Docker harness (Postgres + Transcriber worker)

$ErrorActionPreference = "Continue"
$RootDir = Split-Path -Parent $PSScriptRoot

Write-Host "=== Christian-Tube Transcriber Stack Auto-Start ===" -ForegroundColor Cyan

# 1. Start Ollama
Write-Host "`n[1/3] Ensuring Ollama is running..." -ForegroundColor Yellow
& "$RootDir\scripts\ctrl.ps1" ollama start

# 2. Start Whisper Server
Write-Host "`n[2/3] Ensuring Whisper Server is running..." -ForegroundColor Yellow
& "$RootDir\scripts\ctrl.ps1" whisper start

# 3. Ensure Docker Desktop & start Compose Stack
Write-Host "`n[3/3] Checking Docker daemon & starting Compose stack..." -ForegroundColor Yellow
$docker = "$env:LOCALAPPDATA\Programs\DockerDesktop\resources\bin\docker.exe"
if (-not (Test-Path $docker)) {
    $docker = "docker"
}

# Test if docker daemon is responding
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
    Write-Host "Docker is ready! Launching transcriber stack..." -ForegroundColor Green
    & "$RootDir\scripts\ctrl.ps1" stack up
} else {
    Write-Warning "Docker daemon did not become ready within timeout. If Docker Desktop requires manual start, please open Docker Desktop."
}

Write-Host "`n=== Current Stack Status ===" -ForegroundColor Cyan
& "$RootDir\scripts\ctrl.ps1" status
