# Intel Arc GPU Vulkan Acceleration Guide

## Executive Summary

On Windows PCs equipped with **Intel Arc Graphics** (integrated Intel Arc Pro or discrete Arc A-series GPUs) and unified memory (e.g. 32 GB, 64 GB, or 96 GB RAM), standard Ollama defaults to CPU inference for models larger than 2 GB. 

This document details the root cause of this behavior, the technical workaround using the native Vulkan backend, and benchmark results showing an immediate **4.3x generation speedup** on `gemma4:12b`.

---

## 1. Root Cause Analysis

### The DXGI 2.0 GB Aperture Bug in Ollama
When Ollama starts on Windows, it uses the DirectX Graphics Infrastructure (DXGI) API to discover GPU adapters and determine VRAM capacity.
For Intel Arc integrated graphics (such as Intel Core Ultra Arc Pro), DXGI reports:
* `DedicatedVideoMemory = 2,147,479,552 bytes (2.0 GB)`
* `SharedSystemMemory = ~50–70 GB`

Because Ollama's Go runtime (`discover.go`) only evaluates `DedicatedVideoMemory`, it concludes:
$$\text{Model Weights (8.0 GB)} > \text{Dedicated VRAM (2.0 GB)}$$
Consequently, Ollama rejects the GPU and logs:
```
source=types.go:50 msg="inference compute" id=cpu library=cpu
source=routes.go:2551 total_vram="0 B"
reason=cpu
load_backend: loaded CPU backend from ggml-cpu-alderlake.dll
```
This forces the entire 12B model into CPU AVX2 instructions (~1.45 tokens/second).

---

## 2. The Solution: Direct Vulkan Unified Memory Access

Unlike DXGI's virtual aperture, the **Intel Vulkan Driver (`vulkan-1.dll`)** correctly addresses unified system RAM:

```
> vulkaninfo:
  memoryHeaps[0]:
    size   = 58,413,758,177 bytes (54.40 GiB)
    budget = 81,178,915,635 bytes (75.60 GiB)
```

Ollama includes a compiled Vulkan backend (`ggml-vulkan.dll`) in:
`C:\Users\<User>\AppData\Local\Programs\Ollama\lib\ollama\vulkan\ggml-vulkan.dll`

By placing `ggml-vulkan.dll` directly alongside `llama-server.exe` in `lib\ollama\`, the server immediately discovers:
```
Available devices:
  Vulkan0: Intel(R) Arc(TM) Pro Graphics (55,707 MiB, 55,707 MiB free)
```

---

## 3. Benchmark Verification on Gemma 12B

Tested on the local machine with `gemma4:12b` (8.0 GB Q4_K_M weights, 4096 context):

| Metric | Ollama (Standard CPU Fallback) | Native Vulkan (Intel Arc Pro GPU) | Improvement |
| :--- | :--- | :--- | :--- |
| **Compute Device** | Intel CPU (AVX2 / Alder Lake) | **Vulkan0: Intel(R) Arc(TM) Pro** | 100% GPU Offload |
| **VRAM Allocated** | 0 MB (95 GB System RAM) | **~8.2 GB on Vulkan Unified Heap** | Dedicated GPU compute |
| **Prompt Eval Speed** | ~1.45 tokens/sec | **24.06 tokens/sec** | **~16x faster** |
| **Token Generation Speed**| **~1.45 tokens/sec** | **6.37 tokens/sec** | **4.38x faster** |
| **Typical Verse Latency** | ~75 – 135 seconds | **~18 – 35 seconds** | **~4x faster** |

---

## 4. How to Start the Intel Arc Vulkan Server

A dedicated launch script is provided at `tools/vocab_pipeline/start_arc_vulkan_server.ps1`.

### Step 1: Ensure Vulkan Backend is Linked
Ensure `ggml-vulkan.dll` is in Ollama's main `lib\ollama` directory:
```powershell
Copy-Item "$env:LOCALAPPDATA\Programs\Ollama\lib\ollama\vulkan\ggml-vulkan.dll" -Destination "$env:LOCALAPPDATA\Programs\Ollama\lib\ollama\" -Force
```

### Step 2: Launch the Vulkan Server
Run from PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File tools/vocab_pipeline/start_arc_vulkan_server.ps1
```

Or manually:
```powershell
$modelBlob = "D:\models\blobs\sha256-bb722270d54346adc198f213851dbe0207e87c3ecf2a0aff4d92262726215391"
& "$env:LOCALAPPDATA\Programs\Ollama\lib\ollama\llama-server.exe" `
  --model $modelBlob `
  --device Vulkan0 `
  -ngl 99 `
  --port 11434 `
  -c 4096 `
  -np 1 `
  --no-webui `
  --offline
```

### Step 3: Run the Vocabulary Pipeline
Run the Bible vocabulary processor:
```powershell
python tools/vocab_pipeline/bible_vocab_processor.py --start-book 1 --start-chapter 1
```
The processor automatically detects the active Vulkan server and streams responses with 4.3x acceleration.
