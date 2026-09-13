$ErrorActionPreference = "Stop"
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot"
$SdkDir = "d:\Projects\Christian-Tube\.android-sdk"
$LatestDir = "$SdkDir\cmdline-tools\latest"
$SdkManager = "$LatestDir\bin\sdkmanager.bat"

Write-Host "Accepting Android SDK Licenses..."
# Use yes utility logic or simple loop to accept all licenses
"y`n" * 10 | & $SdkManager --licenses --sdk_root=$SdkDir

Write-Host "Installing platform-tools, emulator, and android-33 system image..."
& $SdkManager "platform-tools" "emulator" "system-images;android-33;google_apis;x86_64" --sdk_root=$SdkDir

Write-Host "Packages installed successfully!"
