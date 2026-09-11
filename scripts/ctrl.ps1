param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("processor", "stack", "run", "status", "stop-retired-transcriber")]
    [string]$Command,
    [Parameter(Position = 1)]
    [ValidateSet("start", "stop", "status", "up", "down", "logs", "restart", "build")]
    [string]$Action = "status",
    [string]$VideoId,
    [switch]$Redo
)

<#
.SYNOPSIS
    Manage the ChristianApp YouTube Video Processor service.

.DESCRIPTION
    Extracts audio from ChristianApp channel videos (excluding shorts), uploads to
    Audio.com with rich metadata, and updates the GitHub Releases audio catalog.

    Commands:
      ctrl.ps1 processor up|down|logs|restart|build
      ctrl.ps1 run -VideoId <YouTubeID> [-Redo]
      ctrl.ps1 status
      ctrl.ps1 stop-retired-transcriber
#>

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
$Compose = Join-Path $RootDir "docker-compose.yml"

function Resolve-Docker {
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\DockerDesktop\resources\bin\docker.exe",
        "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe",
        "docker.exe"
    )
    return $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Invoke-Processor {
    $docker = Resolve-Docker
    if (-not $docker) { Write-Error "docker.exe not found." }
    switch ($Action) {
        "up"      { & $docker compose -f $Compose up -d --remove-orphans youtube-processor; break }
        "down"    { & $docker compose -f $Compose stop youtube-processor; break }
        "restart" { & $docker compose -f $Compose restart youtube-processor; break }
        "build"   { & $docker compose -f $Compose build youtube-processor; break }
        "logs"    { & $docker compose -f $Compose logs -f --tail=200 youtube-processor; break }
        default   { Write-Error "processor action must be up|down|restart|build|logs" }
    }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Invoke-Run {
    if (-not $VideoId) { Write-Error "run requires -VideoId <YouTubeID>" }
    $docker = Resolve-Docker
    if (-not $docker) { Write-Error "docker.exe not found." }
    $args = @("compose", "-f", $Compose, "exec", "-T", "youtube-processor",
              "python", "-u", "worker.py", "--video-id", $VideoId)
    if ($Redo) { $args += "--redo" }
    & $docker @args
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Stop-RetiredTranscriber {
    Write-Host "Stopping any lingering Whisper STT and retired transcriber containers..."
    # Stop native whisper server if still running
    Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*whisper_server.py*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    
    $docker = Resolve-Docker
    if ($docker) {
        try {
            & $docker rm -f christiantube-transcriber 2>$null | Out-Null
        } catch { }
    }
    Write-Host "Retired transcriber stopped cleanly."
}

function Show-Status {
    Write-Host "== ChristianApp YouTube Video Processor ==" -ForegroundColor Cyan
    $docker = Resolve-Docker
    if ($docker) {
        & $docker compose -f $Compose ps youtube-processor
    } else {
        Write-Host "  docker not found"
    }
}

switch ($Command) {
    "processor"                { Invoke-Processor }
    "stack"                    { Invoke-Processor }
    "run"                      { Invoke-Run }
    "status"                   { Show-Status }
    "stop-retired-transcriber" { Stop-RetiredTranscriber }
}
