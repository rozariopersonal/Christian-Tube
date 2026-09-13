<#
.SYNOPSIS
    Automated E2E Test Runner for Christian-Tube APKs (Local & Agent friendly).
.DESCRIPTION
    Runs static analysis, unit/widget tests, builds the APK, installs it on a running
    Android device/emulator, and executes Maestro E2E test flows.
.EXAMPLE
    .\scripts\test-e2e.ps1
    .\scripts\test-e2e.ps1 -SkipUnit -Flow google_auth_flow.yaml
    .\scripts\test-e2e.ps1 -Instance centum_academy
#>

[CmdletBinding()]
param (
    [string]$Instance = "christian_tube",
    [string]$Flow = "smoke_flow.yaml",
    [switch]$SkipUnit,
    [switch]$SkipBuild,
    [switch]$ReleaseMode
)

$ErrorActionPreference = "Stop"
$RootDir = Resolve-Path "$PSScriptRoot\.."
$MobileDir = Join-Path $RootDir "apps\mobile"

if (-not $env:JAVA_HOME) {
    $env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot"
}
if (-not $env:ANDROID_HOME) {
    $env:ANDROID_HOME = "$RootDir\.android-sdk"
}
$env:GRADLE_OPTS = "-Djava.net.preferIPv4Stack=true"

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "   Christian-Tube E2E Quality Gate (Local Runner)     " -ForegroundColor Cyan
Write-Host "   Instance: $Instance | Flow: $Flow                  " -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

# ----------------------------------------------------
# 1. Environment & Tool Discovery
# ----------------------------------------------------
Write-Host "`n[1/5] Checking Toolchain Environment..." -ForegroundColor Yellow

# Locate Android SDK & adb if not in PATH
if (-not (Get-Command "adb" -ErrorAction SilentlyContinue)) {
    $SdkPaths = @(
        "$RootDir\.android-sdk\platform-tools",
        "$env:ANDROID_HOME\platform-tools",
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools",
        "C:\Android\sdk\platform-tools"
    )
    foreach ($p in $SdkPaths) {
        if (Test-Path "$p\adb.exe") {
            $env:PATH = "$p;" + $env:PATH
            Write-Host "  -> Added adb to PATH from: $p" -ForegroundColor Green
            break
        }
    }
}

# Locate Maestro if not in PATH
if (-not (Get-Command "maestro" -ErrorAction SilentlyContinue)) {
    $MaestroPaths = @(
        "$env:USERPROFILE\.maestro\bin",
        "$env:LOCALAPPDATA\Programs\maestro\bin"
    )
    foreach ($m in $MaestroPaths) {
        if ((Test-Path "$m\maestro.bat") -or (Test-Path "$m\maestro")) {
            $env:PATH = "$m;" + $env:PATH
            Write-Host "  -> Added maestro to PATH from: $m" -ForegroundColor Green
            break
        }
    }
}

# Verify adb
if (-not (Get-Command "adb" -ErrorAction SilentlyContinue)) {
    Write-Warning "adb was not found in PATH or standard Android SDK locations."
    Write-Host "Please ensure Android SDK Command-Line Tools or Platform-Tools are installed." -ForegroundColor Red
    exit 1
}

# Verify Maestro
if (-not (Get-Command "maestro" -ErrorAction SilentlyContinue)) {
    Write-Warning "Maestro CLI was not found."
    Write-Host "Install Maestro by running: powershell -c `"Invoke-WebRequest -Uri 'https://get.maestro.mobile.dev' -OutFile 'install.ps1'; .\install.ps1`"" -ForegroundColor Yellow
    exit 1
}

# Check for active Android device or emulator
$devices = & adb devices | Select-String -Pattern "\bdevice\b"
if ($devices.Count -eq 0) {
    Write-Host "No active Android device or emulator detected via adb!" -ForegroundColor Red
    Write-Host "Please start an Android emulator or connect a device with USB debugging enabled." -ForegroundColor Yellow
    Write-Host "Tip: Run 'emulator -avd <device_name> -snapshot google_auth' to start with Google Auth." -ForegroundColor Gray
    exit 1
} else {
    Write-Host "  -> Target device ready: $(($devices | Select-Object -First 1).Line.Trim())" -ForegroundColor Green
}

# ----------------------------------------------------
# 2. Gate 1: Code & Unit Quality Gate
# ----------------------------------------------------
if (-not $SkipUnit) {
    Write-Host "`n[2/5] Running Gate 1: Unit & Widget Test Suite..." -ForegroundColor Yellow
    Push-Location $MobileDir
    try {
        Write-Host "  -> flutter analyze..." -ForegroundColor Gray
        & flutter analyze --no-fatal-infos
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Flutter analyze failed!" -ForegroundColor Red
            exit $LASTEXITCODE
        }

        Write-Host "  -> flutter test..." -ForegroundColor Gray
        & flutter test
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Flutter unit/widget tests failed!" -ForegroundColor Red
            exit $LASTEXITCODE
        }
        Write-Host "✅ Gate 1 Passed (Analyze & Unit Tests Green)" -ForegroundColor Green
    } finally {
        Pop-Location
    }
} else {
    Write-Host "`n[2/5] Skipping Unit & Widget Tests (-SkipUnit)" -ForegroundColor DarkGray
}

# ----------------------------------------------------
# 3. Gate 2: Prepare Instance & Build APK
# ----------------------------------------------------
$buildType = if ($ReleaseMode) { "release" } else { "debug" }
$apkPath = Join-Path $MobileDir "build\app\outputs\flutter-apk\app-$buildType.apk"

if (-not $SkipBuild) {
    Write-Host "`n[3/5] Preparing Instance & Building $buildType APK..." -ForegroundColor Yellow
    
    # 1. Run prepare-instance
    node (Join-Path $RootDir "scripts\prepare-instance.js") $Instance
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Instance preparation failed!" -ForegroundColor Red
        exit $LASTEXITCODE
    }

    # 2. Build APK
    Push-Location $MobileDir
    try {
        if ($ReleaseMode) {
            Write-Host "  -> Building Release APK (Obfuscated)..." -ForegroundColor Gray
            & flutter build apk --release --target-platform=android-arm64 --android-skip-build-dependency-validation
        } else {
            Write-Host "  -> Building Debug APK (Fast)..." -ForegroundColor Gray
            & flutter build apk --debug --android-skip-build-dependency-validation
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Flutter APK build failed!" -ForegroundColor Red
            exit $LASTEXITCODE
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "`n[3/5] Skipping APK Build (-SkipBuild)" -ForegroundColor DarkGray
}

if (-not (Test-Path $apkPath)) {
    Write-Host "❌ Target APK not found at: $apkPath" -ForegroundColor Red
    exit 1
}

# ----------------------------------------------------
# 4. Install APK onto Device/Emulator
# ----------------------------------------------------
Write-Host "`n[4/5] Installing APK on Target Device via adb..." -ForegroundColor Yellow
& adb install -r $apkPath
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ adb install failed!" -ForegroundColor Red
    exit $LASTEXITCODE
}
Write-Host "✅ APK successfully installed" -ForegroundColor Green

# ----------------------------------------------------
# 5. Gate 3: Execute Maestro E2E Flow
# ----------------------------------------------------
$flowPath = Join-Path $RootDir ".maestro\$Flow"
if (-not (Test-Path $flowPath)) {
    Write-Host "❌ Maestro flow file not found: $flowPath" -ForegroundColor Red
    exit 1
}

Write-Host "`n[5/5] Running Maestro E2E Flow: $Flow..." -ForegroundColor Yellow
Push-Location $RootDir
try {
    & maestro test $flowPath
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n======================================================" -ForegroundColor Green
        Write-Host "🎉 ALL QUALITY GATES PASSED! E2E VERIFICATION COMPLETE " -ForegroundColor Green
        Write-Host "======================================================" -ForegroundColor Green
    } else {
        Write-Host "`n❌ MAESTRO E2E TEST FAILED!" -ForegroundColor Red
        Write-Host "Check the output above for the failing step and screenshots." -ForegroundColor Red
        exit $LASTEXITCODE
    }
} finally {
    Pop-Location
}
