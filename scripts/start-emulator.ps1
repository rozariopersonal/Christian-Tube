$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot"
$env:ANDROID_HOME = "d:\Projects\Christian-Tube\.android-sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME

Write-Host "Starting Android Emulator (test_device)..."
& "$env:ANDROID_HOME\emulator\emulator.exe" -avd test_device -no-audio -gpu host
