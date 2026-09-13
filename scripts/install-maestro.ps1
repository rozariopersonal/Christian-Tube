$ErrorActionPreference = "Stop"
$MaestroDir = "$env:USERPROFILE\.maestro"
$MaestroBin = "$MaestroDir\bin"

if (-not (Test-Path $MaestroDir)) {
    New-Item -ItemType Directory -Path $MaestroDir | Out-Null
}

if (-not (Test-Path "$MaestroBin\maestro.bat")) {
    Write-Host "Fetching latest Maestro release info..."
    $releaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/mobile-dev-inc/maestro/releases/latest"
    $zipUrl = $releaseInfo.assets | Where-Object { $_.name -eq "maestro.zip" } | Select-Object -ExpandProperty browser_download_url
    
    Write-Host "Downloading Maestro from $zipUrl..."
    $ZipPath = "$MaestroDir\maestro.zip"
    Invoke-WebRequest -Uri $zipUrl -OutFile $ZipPath
    
    Write-Host "Extracting..."
    Expand-Archive -Path $ZipPath -DestinationPath $MaestroDir -Force
    Remove-Item $ZipPath
    
    # maestro.zip extracts a 'maestro' folder, rename it or move contents to 'bin' if necessary
    # the zip structure usually is `maestro/bin/maestro.bat` and `maestro/lib/`
    # Let's assume it extracts directly to $MaestroDir\maestro\bin
    if (Test-Path "$MaestroDir\maestro\bin\maestro.bat") {
        Write-Host "Moving maestro files..."
        Move-Item -Path "$MaestroDir\maestro\*" -Destination $MaestroDir -Force
        Remove-Item "$MaestroDir\maestro" -Recurse -Force
    }
}

Write-Host "Maestro Installed at $MaestroDir!"
