param(
    [switch]$InstallTask,
    [switch]$UninstallTask,
    [switch]$Restart,
    [switch]$SkipBuild
)

<#
.SYNOPSIS
    Starts (and optionally auto-starts at logon) the Christian-Tube transcription
    + local-LLM insights Docker stack.

.DESCRIPTION
    - Locates the Docker Desktop CLI (per-user install).
    - Starts Docker Desktop if the engine is not already running.
    - Brings up `docker-compose.transcriber.yml` (worker + Ollama LLM).
    - With -InstallTask: registers a logon scheduled task so the stack comes up
      every time the user logs in (idempotent).
    - With -UninstallTask: removes that task.

    The worker writes transcripts + extracted Bible insights to the releases
    repo configured in `.transcriber.env` (GITHUB_REPO/GITHUB_TOKEN).

.EXAMPLE
    .\scripts\start-transcriber.ps1 -InstallTask
    .\scripts\start-transcriber.ps1 -Restart -SkipBuild
#>

$ErrorActionPreference = "Stop"
$RootDir   = Split-Path -Parent $PSScriptRoot
$Compose   = Join-Path $RootDir "docker-compose.transcriber.yml"
$TaskName  = "ChristianTube-Transcriber"

# --- Locate docker.exe (Docker Desktop per-user install) ----------------------
$DockerCandidates = @(
    "$env:LOCALAPPDATA\Programs\DockerDesktop\resources\bin\docker.exe",
    "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"
)
$Docker = $DockerCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Docker) {
    Write-Error "docker.exe not found. Install Docker Desktop first."
    exit 1
}
$DockerDesktopExe = "$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe"

# --- Ensure engine is running ------------------------------------------------
& $Docker info *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker engine is down; starting Docker Desktop..."
    if (Test-Path $DockerDesktopExe) {
        Start-Process $DockerDesktopExe
    } else {
        Write-Warning "Docker Desktop executable not found; starting engine via 'docker'."
    }
    $ok = $false
    for ($i = 0; $i -lt 60 -and -not $ok; $i++) {
        Start-Sleep -Seconds 5
        & $Docker info *> $null
        if ($LASTEXITCODE -eq 0) { $ok = $true }
    }
    if (-not $ok) {
        Write-Error "Docker engine did not become ready within 5 minutes."
        exit 1
    }
    Write-Host "Docker engine ready."
}

# --- Compose up ---------------------------------------------------------------
$env:DOCKER_HOST = & $Docker context show 2>$null
$args = @("compose", "-f", $Compose, "up", "-d")
if (-not $SkipBuild) { $args += "--build" }
Write-Host ">> docker $($args -join ' ')"
& $Docker @args
if ($LASTEXITCODE -ne 0) {
    Write-Error "docker compose up failed (exit $LASTEXITCODE). Check .transcriber.env."
    exit $LASTEXITCODE
}

if ($Restart) {
    Write-Host "Restarting worker to pick up config changes..."
    & $Docker compose -f $Compose restart worker
}

# --- Scheduled task at logon -------------------------------------------------
function Register-TranscriberTask {
    $action  = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Restart -SkipBuild"
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Description "Bring up Christian-Tube transcriber + LLM stack at logon." -Force | Out-Null
    Write-Host "Registered logon task '$TaskName'."
}
function Unregister-TranscriberTask {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Removed logon task '$TaskName'."
}

if ($InstallTask)   { Register-TranscriberTask }
if ($UninstallTask) { Unregister-TranscriberTask }

Write-Host "Stack status:"
& $Docker compose -f $Compose ps