param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("ollama", "whisper", "stack", "run", "status")]
    [string]$Command,
    [Parameter(Position = 1)]
    [ValidateSet("start", "stop", "status", "up", "down", "logs", "restart")]
    [string]$Action,
    [string]$VideoId,
    [switch]$InsightsResume
)

<#
.SYNOPSIS
    Manage the Christian-Tube transcription stack: native Windows model
    services (Ollama LLM + whisper STT) plus the Docker harness, all from the
    command line.

.DESCRIPTION
    Models run natively on Windows; the harness (DB polling, yt-dlp download,
    chunk orchestration, GitHub publishing) stays in Docker. See
    docs/transcriber-windows-native-plan.md.

    Commands:
      ctrl.ps1 ollama  start|stop|status
      ctrl.ps1 whisper start|stop|status
      ctrl.ps1 stack   up|down|logs
      ctrl.ps1 run     -VideoId X [-InsightsResume]
      ctrl.ps1 status

.EXAMPLE
    .\scripts\ctrl.ps1 ollama start
    .\scripts\ctrl.ps1 whisper start
    .\scripts\ctrl.ps1 stack up
    .\scripts\ctrl.ps1 run -VideoId 2qWx-wQ7JJo -InsightsResume
    .\scripts\ctrl.ps1 status
#>

$ErrorActionPreference = "Stop"
$RootDir    = Split-Path -Parent $PSScriptRoot
$Compose    = Join-Path $RootDir "docker-compose.transcriber.yml"
$OllamaExe  = "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe"
$WhisperPy  = [System.IO.Path]::GetFullPath((Join-Path $RootDir "services\transcriber\whisper_server.py"))
$LogsDir    = "D:\ml-models\logs"
$OllamaLog  = Join-Path $LogsDir "ollama.log"
$WhisperLog = Join-Path $LogsDir "whisper.log"
$VenvPy     = "D:\ml-models\whisper\venv\Scripts\python.exe"

if (-not (Test-Path $LogsDir)) { New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null }

function Resolve-Docker {
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\DockerDesktop\resources\bin\docker.exe",
        "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"
    )
    return $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Get-OllamaStatus {
    if (Get-Process -Name "ollama" -ErrorAction SilentlyContinue) { "running" } else { "stopped" }
}

function Start-OllamaService {
    if ((Get-OllamaStatus) -eq "running") { Write-Host "ollama: already running."; return }
    # Apply host-binding + keep-alive from the user environment for this session.
    $env:OLLAMA_HOST = "0.0.0.0"
    $env:OLLAMA_KEEP_ALIVE = "30m"
    $proc = Start-Process -FilePath $OllamaExe -ArgumentList "serve" `
        -WindowStyle Hidden -RedirectStandardOutput $OllamaLog `
        -RedirectStandardError "$OllamaLog.err" -PassThru
    Start-Sleep -Seconds 3
    if (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) {
        Write-Host "ollama: started (pid $($proc.Id))."
    } else {
        Write-Error "ollama failed to start. See $OllamaLog"
    }
}

function Stop-OllamaService {
    Get-Process -Name "ollama app", "ollama" -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "ollama: stopped."
}

function Get-WhisperStatus {
    try {
        $r = Invoke-RestMethod http://localhost:12788/health -TimeoutSec 3
        "running ($($r.model))"
    } catch {
        # distinguish "no server" (connection refused) from "server up, model not ready"
        if (Test-Path $WhisperLog) {
            $tail = Get-Content $WhisperLog -Tail 1 -ErrorAction SilentlyContinue
            if ($tail) { return "starting (last log: $tail)" }
        }
        "stopped"
    }
}

function Start-WhisperService {
    $status = Get-WhisperStatus
    if ($status -like "running*") { Write-Host "whisper: already $status"; return }
    if (-not (Test-Path $VenvPy)) { Write-Error "Whisper venv missing: $VenvPy" }
    $proc = Start-Process -FilePath $VenvPy -ArgumentList $WhisperPy `
        -WindowStyle Hidden -RedirectStandardOutput $WhisperLog `
        -RedirectStandardError "$WhisperLog.err" -PassThru
    Write-Host "whisper: starting (pid $($proc.Id)); loading model, then poll health..."
    $ok = $false
    for ($i = 0; $i -lt 120 -and -not $ok; $i++) {
        Start-Sleep -Seconds 2
        try { Invoke-RestMethod http://localhost:12788/health -TimeoutSec 3 | Out-Null; $ok = $true }
        catch { }
    }
    if ($ok) { Write-Host "whisper: healthy." } else { Write-Warning "whisper not healthy yet; check $WhisperLog" }
}

function Stop-WhisperService {
    Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*whisper_server.py*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Write-Host "whisper: stopped."
}

function Invoke-Stack {
    $docker = Resolve-Docker
    if (-not $docker) { Write-Error "docker.exe not found." }
    $env:DOCKER_HOST = & $docker context show 2>$null
    switch ($Action) {
        "up"   { & $docker compose -f $Compose up -d --build; break }
        "down" { & $docker compose -f $Compose down; break }
        "logs" { & $docker compose -f $Compose logs -f --tail=200 worker; break }
        default { Write-Error "stack action must be up|down|logs" }
    }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Invoke-Run {
    if (-not $VideoId) { Write-Error "run requires -VideoId" }
    $docker = Resolve-Docker
    if (-not $docker) { Write-Error "docker.exe not found." }
    $env:DOCKER_HOST = & $docker context show 2>$null
    $args = @("compose", "-f", $Compose, "exec", "-T", "worker",
              "python", "-u", "worker.py", "--video-id", $VideoId)
    if ($InsightsResume) { $args += "--insights-resume" }
    & $docker @args
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Show-Status {
    Write-Host "== Native model services =="
    Write-Host ("  ollama : {0}" -f (Get-OllamaStatus))
    Write-Host ("  whisper: {0}" -f (Get-WhisperStatus))
    $ollama = "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe"
    if ((Get-OllamaStatus) -eq "running") {
        Write-Host "  ollama models:"
        & $ollama list 2>$null | Write-Host
    }
    Write-Host "== Docker harness =="
    $docker = Resolve-Docker
    if ($docker) {
        $env:DOCKER_HOST = & $docker context show 2>$null
        & $docker compose -f $Compose ps
    } else {
        Write-Host "  docker not found"
    }
}

switch ($Command) {
    "ollama" {
        switch ($Action) {
            "start"  { Start-OllamaService }
            "stop"   { Stop-OllamaService }
            "status" { Write-Host (Get-OllamaStatus) }
            default  { Write-Error "ollama action must be start|stop|status" }
        }
    }
    "whisper" {
        switch ($Action) {
            "start"  { Start-WhisperService }
            "stop"   { Stop-WhisperService }
            "status" { Write-Host (Get-WhisperStatus) }
            default  { Write-Error "whisper action must be start|stop|status" }
        }
    }
    "stack"   { Invoke-Stack }
    "run"     { Invoke-Run }
    "status"  { Show-Status }
}
