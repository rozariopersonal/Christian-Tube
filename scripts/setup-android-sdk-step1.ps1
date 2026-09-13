$ErrorActionPreference = "Stop"
$SdkDir = "d:\Projects\Christian-Tube\.android-sdk"
$CmdlineToolsDir = "$SdkDir\cmdline-tools"
$LatestDir = "$CmdlineToolsDir\latest"

if (-not (Test-Path $SdkDir)) {
    New-Item -ItemType Directory -Path $SdkDir | Out-Null
}

if (-not (Test-Path "$LatestDir\bin\sdkmanager.bat")) {
    Write-Host "Downloading Android Command Line Tools..."
    $ZipPath = "$SdkDir\cmdline-tools.zip"
    Invoke-WebRequest -Uri "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip" -OutFile $ZipPath
    
    Write-Host "Extracting..."
    Expand-Archive -Path $ZipPath -DestinationPath $CmdlineToolsDir -Force
    Remove-Item $ZipPath

    # the zip extracts to cmdline-tools\cmdline-tools, we need to rename the inner dir to 'latest'
    Rename-Item "$CmdlineToolsDir\cmdline-tools" "latest"
}

Write-Host "Command Line Tools Installed!"
