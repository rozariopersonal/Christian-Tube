# Start Intel Arc Vulkan Accelerated Server for Gemma 12B
$ErrorActionPreference = "Stop"

$ollamaDir = "$env:LOCALAPPDATA\Programs\Ollama"
$libDir = "$ollamaDir\lib\ollama"
$serverExe = "$libDir\llama-server.exe"
$vulkanDllSrc = "$libDir\vulkan\ggml-vulkan.dll"
$vulkanDllDst = "$libDir\ggml-vulkan.dll"

# Stop existing processes on port 11434
Write-Host "[1/3] Stopping any conflicting Ollama/llama-server instances..." -ForegroundColor Cyan
Stop-Process -Name ollama, llama-server -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# Ensure Vulkan DLL is in lib\ollama
if (Test-Path $vulkanDllSrc) {
    if (-not (Test-Path $vulkanDllDst) -or ((Get-Item $vulkanDllSrc).Length -ne (Get-Item $vulkanDllDst).Length)) {
        Write-Host "[2/3] Enabling Intel Arc Vulkan backend DLL..." -ForegroundColor Cyan
        Copy-Item $vulkanDllSrc -Destination $vulkanDllDst -Force
    }
}

# Find model blob
$modelBlob = "D:\models\blobs\sha256-bb722270d54346adc198f213851dbe0207e87c3ecf2a0aff4d92262726215391"
if (-not (Test-Path $modelBlob)) {
    # Search for largest blob in D:\models\blobs
    $blobs = Get-ChildItem "D:\models\blobs" | Sort-Object Length -Descending
    if ($blobs.Count -gt 0) {
        $modelBlob = $blobs[0].FullName
    }
}

Write-Host "[3/3] Launching Gemma 12B on Intel Arc GPU (Vulkan0) on port 8080..." -ForegroundColor Green
Write-Host "Model: $modelBlob" -ForegroundColor Gray
Write-Host "Device: Vulkan0 (Intel Arc Pro Graphics with ~55 GB unified VRAM)" -ForegroundColor Gray

& $serverExe `
    --model $modelBlob `
    --device Vulkan0 `
    -ngl 99 `
    --port 8080 `
    --host 127.0.0.1 `
    -c 12288 `
    -np 3 `
    --reasoning-budget 0 `
    --no-webui `
    --offline
