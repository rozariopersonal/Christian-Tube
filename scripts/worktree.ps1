<#
.SYNOPSIS
    Agent & Developer Git Worktree Manager for Christian-Tube.
.DESCRIPTION
    Creates, lists, and removes isolated git worktrees for parallel agent execution.
    Each worktree has its own dedicated directory and branch branched off develop.
.EXAMPLE
    .\scripts\worktree.ps1 -Action create -Name "channel-filters"
    .\scripts\worktree.ps1 -Action list
    .\scripts\worktree.ps1 -Action remove -Name "channel-filters"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("create", "remove", "list", "prune")]
    [string]$Action,

    [Parameter(Position = 1)]
    [string]$Name,

    [string]$Base = "develop",

    [switch]$SkipPubGet
)

$ErrorActionPreference = "Stop"
$RootDir = Resolve-Path "$PSScriptRoot\.."
$WorktreesDir = Join-Path $RootDir ".worktrees"

function Normalize-Name ([string]$inputName) {
    if (-not $inputName) {
        Write-Error "Task name (-Name) is required for this action."
        exit 1
    }
    # Remove leading 'agent/' if provided
    $clean = $inputName -replace "^agent/", ""
    # Replace spaces and underscores with dashes
    $clean = $clean -replace "[\s_]+", "-"
    return $clean.ToLower().Trim()
}

switch ($Action) {
    "list" {
        Write-Host "=== Active Git Worktrees ===" -ForegroundColor Cyan
        & git worktree list
        break
    }

    "prune" {
        Write-Host "Pruning stale worktree references..." -ForegroundColor Yellow
        & git worktree prune
        Write-Host "Done." -ForegroundColor Green
        break
    }

    "create" {
        $taskName = Normalize-Name $Name
        $branchName = "agent/$taskName"
        $targetDir = Join-Path $WorktreesDir $taskName

        if (Test-Path $targetDir) {
            Write-Warning "Worktree directory already exists at: $targetDir"
            Write-Host "Switch to it using: cd $targetDir" -ForegroundColor Yellow
            exit 0
        }

        Write-Host "🚀 Creating isolated worktree for agent task: $taskName" -ForegroundColor Cyan
        Write-Host "  -> Directory: $targetDir"
        Write-Host "  -> Branch:    $branchName (Base: $Base)"

        # Ensure .worktrees container folder exists
        if (-not (Test-Path $WorktreesDir)) {
            New-Item -ItemType Directory -Path $WorktreesDir -Force | Out-Null
        }

        # Fetch latest base branch
        Write-Host "`n[1/3] Fetching latest origin/$Base..." -ForegroundColor Yellow
        & git fetch origin $Base

        # Determine start point (origin/$Base if exists, else local $Base)
        $startPoint = "origin/$Base"
        $remoteCheck = & git branch -r --list "origin/$Base"
        if (-not $remoteCheck) {
            $startPoint = $Base
        }

        # Create worktree and branch
        Write-Host "[2/3] Adding git worktree..." -ForegroundColor Yellow
        # Check if local branch already exists
        $localBranch = & git branch --list $branchName
        if ($localBranch) {
            & git worktree add $targetDir $branchName
        } else {
            & git worktree add -b $branchName $targetDir $startPoint
        }

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create worktree."
            exit $LASTEXITCODE
        }

        # Initialize submodules in the worktree
        Write-Host "[3/3] Bootstrapping releases submodule..." -ForegroundColor Yellow
        Push-Location $targetDir
        try {
            & git submodule update --init --recursive releases
            
            if (-not $SkipPubGet) {
                $mobileDir = Join-Path $targetDir "apps\mobile"
                if (Test-Path $mobileDir) {
                    Write-Host "Running flutter pub get in $mobileDir..." -ForegroundColor Yellow
                    Push-Location $mobileDir
                    try {
                        & flutter pub get
                    } finally {
                        Pop-Location
                    }
                }
            }
        } finally {
            Pop-Location
        }

        Write-Host "`n🎉 Worktree ready! Navigate to:" -ForegroundColor Green
        Write-Host "cd $targetDir" -ForegroundColor Cyan
        break
    }

    "remove" {
        $taskName = Normalize-Name $Name
        $branchName = "agent/$taskName"
        $targetDir = Join-Path $WorktreesDir $taskName

        Write-Host "Cleaning up worktree: $taskName..." -ForegroundColor Yellow

        if (Test-Path $targetDir) {
            & git worktree remove $targetDir --force
        } else {
            Write-Host "Worktree directory not found, running prune..."
            & git worktree prune
        }

        # Delete local branch if present
        $branchExists = (& git branch --list $branchName).Trim()
        if ($branchExists) {
            & git branch -D $branchName
            Write-Host "Deleted local branch: $branchName" -ForegroundColor Green
        }

        Write-Host "✅ Worktree cleanup complete." -ForegroundColor Green
        break
    }
}
