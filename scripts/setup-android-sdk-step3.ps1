$ErrorActionPreference = "Stop"
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot"
$SdkDir = "d:\Projects\Christian-Tube\.android-sdk"
$LatestDir = "$SdkDir\cmdline-tools\latest"
$AvdManager = "$LatestDir\bin\avdmanager.bat"

Write-Host "Creating AVD 'test_device'..."
"no`n" | & $AvdManager create avd -n test_device -k "system-images;android-33;google_apis;x86_64" --device "pixel_6" --force

Write-Host "AVD created successfully!"
