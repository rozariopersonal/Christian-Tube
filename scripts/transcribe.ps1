param(
    [string]$Model = "small",
    [string]$Device = "cpu",
    [int]$Limit = 10,
    [switch]$RetryFailed,
    [switch]$DryRun,
    [switch]$Redo,
    [switch]$KeepAudio,
    [string]$VideoId = ""
)

<#
.SYNOPSIS
    Launcher for scripts/transcribe.py — local Whisper transcription.
.DESCRIPTION
    Adds the locally-installed Python, yt-dlp and ffmpeg to PATH, then invokes
    transcribe.py with the given options. Reads DATABASE_URL from apps/backend/.env.
.EXAMPLE
    .\scripts\transcribe.ps1 -DryRun              # preview what would be transcribed
    .\scripts\transcribe.ps1 -Limit 5            # transcribe up to 5 pending English videos
    .\scripts\transcribe.ps1 -VideoId dQw4w9WgXcQ # transcribe one specific video
    .\scripts\transcribe.ps1 -RetryFailed        # also retry 'failed' videos (under max-retries)
#>

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot

# Locate Python (prefer the user-installed interpreter over the WindowsApps stub).
$Python = $null
$CandidatePaths = @(
    "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python310\python.exe",
    "python.exe"
)
foreach ($cand in $CandidatePaths) {
    try {
        & $cand -c "import sys" 2>$null
        if ($LASTEXITCODE -eq 0) { $Python = $cand; break }
    } catch { }
}
if (-not $Python) {
    Write-Error "Python not found. Install Python 3.10+ and ensure it is installed for this user."
    exit 1
}

# Tool directories that must be on PATH for yt-dlp/ffmpeg subprocesses.
$PythonDir = Split-Path $Python -Parent
$ToolDirs = @(
    $PythonDir,
    (Join-Path $PythonDir "Scripts"),
    "$env:LOCALAPPDATA\ChristianTubeTools"
) | Where-Object { $_ -and (Test-Path $_) }

$env:PATH = (($ToolDirs + @($env:PATH)) -join [System.IO.Path]::PathSeparator)
$env:HF_HUB_DISABLE_SYMLINKS_WARNING = "1"

$Script = Join-Path $PSScriptRoot "transcribe.py"
$Args = @("$Script", "--model", $Model, "--device", $Device, "--limit", "$Limit")
if ($RetryFailed)   { $Args += "--retry-failed" }
if ($DryRun)        { $Args += "--dry-run" }
if ($Redo)          { $Args += "--redo" }
if ($KeepAudio)     { $Args += "--keep-audio" }
if ($VideoId)       { $Args += "--video-id", $VideoId }

Write-Host "Using Python: $Python"
& $Python @Args
exit $LASTEXITCODE
