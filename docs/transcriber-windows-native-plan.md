# Transcriber — Windows-native models, Docker harness (migration plan)

Status: **Phase 1 in progress (implemented).** Native Windows Ollama + whisper
server are live behind the Docker harness; Phase 2 GPU spikes are benchmark-or-
revert and not yet started. See the "Results" section at the bottom for what
was actually run and what changed vs this plan.

## 1. Goal

Move model inference (Whisper STT, Qwen2.5 7B insights) off Docker onto native
Windows processes so the Intel Arc iGPU (Vulkan) is usable and the recurring
Docker-on-Windows friction is gone:

- gRPC-FUSE bind mounts that cannot delete/rename files (broke Ollama prune,
  HF cache writes, yt-dlp renames),
- corrupt image/silicon extraction that shipped 0-byte runners once,
- no GPU passthrough for Intel iGPUs into Linux containers.

The **harness stays in Docker**: DB polling, yt-dlp audio download, LLM chunk
orchestration, GitHub publishing, manifest. Everything is managed by commands
(`scripts/ctrl.ps1` + `docker compose`).

## 2. Baseline

- `docker-compose.transcriber.yml`: `db` (postgres 16), `llm` (Ollama
  `qwen2.5:7b`, CPU), `worker` (`faster-whisper large-v3-turbo` int8 CPU +
  pipeline). Volumes: `pgdata`, `ollama-models`, `whisper-models`,
  `transcriber-work`.
- `services/transcriber/worker.py`: LLM via HTTP (`LLM_URL=http://llm:11434`);
  Whisper in-process (`Transcriber` wraps faster-whisper). Has `--redo`,
  `--retry-failed`, `--video-id`, `--no-llm`, `--insights-resume`,
  `LLM_TIMEOUT`, insight chunking (≤25k chars / call, 3 attempts, backoff),
  and poller "pending-only + startup sweep" claim fix.
- Validated end-to-end on real sermons (`jNQXAC9IVRw`, `2qWx-wQ7JJo`).

## 3. Target architecture

```
Windows native                          Docker (compose: transcriber net)
┌────────────────────────────────────┐  ┌────────────────────────────────┐
│ ollama serve        (0.0.0.0:11434)│  │ db     (postgres 16)           │
│  qwen2.5:7b                        │  │ worker (harness)               │
│  Vulkan OK -> Arc iGPU             │  │  ├─ poll DB (pending)          │
│  else CPU (16 threads)             │  │  ├─ yt-dlp audio → /work wav   │
│ whisper-server   (0.0.0.0:12788)   │  │  ├─ POST wav → whisper /transcribe│
│  whisper.cpp Vulkan  (fallback:    │  │  ├─ insights via LLM HTTP      │
│  faster-whisper CPU)               │  │  ├─ push transcripts/insights  │
│                                    │  │  └─ update index.json          │
│ scripts/ctrl.ps1 (start/stop/std)  │  └────────────────────────────────┘
└────────────────────────────────────┘   worker → host.docker.internal
                                          (extra_hosts host-gateway)
```

Why this works here: Ollama is already HTTP; Whisper becomes HTTP too, so the
worker never needs to exec into the Windows host. The `fogolin/ollama-wsl`
pattern (Ollama native + containerized UI) is the same shape and is verified
for Intel iGPUs.

## 4. Facts that shape the plan (2026)

| Concern | Finding | Consequence |
| --- | --- | --- |
| Ollama + Arc | Stock Windows Ollama auto-detects NVIDIA CUDA / AMD ROCm; **Intel Arc not first-class**. Vulkan exists (experimental) but fragile in 2026: a March-2026 Arc driver update made Vulkan fall back to 100% CPU; open crashes on Meteor Lake iGPU via Vulkan (#14610); hybrid-graphics device bugs (#16667). | Vulkan for the LLM is a **benchmark-or-revert spike**, not the default. |
| Core Ultra iGPU + LLM | Arc iGPU is memory-bandwidth-bound; 7B on the iGPU is typically ≈ CPU, not ≫ CPU. | Don't over-invest; CPU-native is acceptable parity for Phase 1. |
| whisper.cpp + Arc | Vulkan backend on Arc-class GPUs is widely reported **~10x CPU** for large-v3. | The real transcription win lives here; spike with a prebuilt/self-built Vulkan `whisper-server.exe`. |
| faster-whisper | CTranslate2 = CPU/CUDA only (no Vulkan) — it cannot use the Arc iGPU. | Phase 1 whisper service is faster-whisper **CPU**; GPU comes in Phase 2 via whisper.cpp. |
| Host → container | `host.docker.internal` on the custom `transcriber` network previously resolved to the gateway and refused; on Windows this is fixed by `extra_hosts: ["host.docker.internal:host-gateway"]` + binding native services to `0.0.0.0`. | Must be proven in Phase 1 step 8 with a fallback (default-bridge+links, or the gateway/LAN IP). |
| Models | qwen2.5:7b 4.7 GB; whisper HF cache already at `D:\ml-models\whisper\models--mobiuslabsgmbh--faster-whisper-large-v3-turbo`. | Pull exactly once on Windows; point the whisper server's `download_root` at the existing cache. |

## 5. Phase 1 — native CPU models, harness point-switch

Keep GPU experiments out; this phase must be boring and fast to land.

### 5.1 Native Ollama

```powershell
winget install Ollama.Ollama
setx OLLAMA_HOST 0.0.0.0          # reachable from the Docker VM gateway
setx OLLAMA_KEEP_ALIVE 30m        # model stays warm across chunks
# restart Ollama (tray/Scheduled Task) so env takes effect
ollama pull qwen2.5:7b            # fresh copy, 4.7 GB (avoids fragile volume→host copy)
ollama list
ollama run qwen2.5:7b "Reply with exactly: PONG"
```

- Verify device with `ollama ps` then a generation; expect CPU (Phase 1).
- Exports: `%USERPROFILE%\.ollama\models` is the new source of truth; the
  Docker `ollama-models` volume stays until rollback is no longer needed.

### 5.2 Native whisper server (CPU faster-whisper)

New file `services/transcriber/whisper_server.py` (also runnable on the host):

- `POST /transcribe` — multipart wav upload (16 k mono), returns
  `{"segments":[{"start":…,"end":…,"text":…}]}`.
- Vanilla vs worker: configured via env `WHISPER_MODEL_DIR` →
  `D:\ml-models\whisper\large-v3-turbo-flat` (a **flat** model directory; see
  the symlink caveat below).
- Same tuning as today: `large-v3-turbo`, `device=cpu`, `int8`,
  `vad_filter=True`, `beam_size=5`, `temperature=[0.0,0.2,…,1.0]`.
- Deps: `pip install faster-whisper fastapi uvicorn python-multipart` into a
  dedicated venv at `D:\ml-models\whisper\venv`.
- Run managed by `ctrl.ps1` (background process, logs to
  `D:\ml-models\logs\whisper.log`).

> **Filesystem caveat (found during Phase 1):** the original HF cache at
> `D:\ml-models\whisper\models--mobiuslabsgmbh--faster-whisper-large-v3-turbo`
> stores its `snapshots/<commit>/*` files as **symlinks** to `blobs/`. On this
> Windows/D: setup those reparse points cannot be resolved by `os.stat`
> (`WinError 1920`), so the model could not load directly from the cache. Fix:
> built a flat dir `D:\ml-models\whisper\large-v3-turbo-flat` whose files are
> real copies of the blobs. Note also the CTranslate2 filename mapping: here
> `tokenizer.json` = the JSON *object* (`added_tokens`) and `vocabulary.json` =
> the JSON *array* of tokens — the intuitive mapping is reversed vs
> faster-whisper's expectations.

### 5.3 Harness changes (Docker/compose + worker.py)

`docker-compose.transcriber.yml`:

- drop `llm` service + `ollama-models` + `whisper-models`;
- worker env:
  `LLM_URL=http://host.docker.internal:11434`,
  `WHISPER_URL=http://host.docker.internal:12788`,
  `extra_hosts: ["host.docker.internal:host-gateway"]`;
- `depends_on: db` only.

`services/transcriber/worker.py`:

- Replace in-process `Transcriber` with `WhisperClient(url)` that POSTs the
  wav and rebuilds the same `[MM:SS -> MM:SS]` lines via existing `fmt_ts`
  (no numpy / `load_wav_to_float32`).
- `process_video`: pass the wav path to `WhisperClient`, keep progress markers
  (40→70) and `--insights-resume`/chunk/retry/poller logic untouched.
- env-gated: if `WHISPER_URL` unset, keep the in-process native path (Docker
  fallback) — makes rollback a one-line env flip.
- `requirements.txt` / `Dockerfile`: drop `faster-whisper`, `ctranslate2`,
  `onnxruntime`, `numpy`; keep `yt-dlp`, `psycopg2-binary`, `requests`.

### 5.4 Connectivity gate (must pass or stop)

```powershell
docker run --rm --network christian-tube_transcriber \
  curlimages/curl sh -c \
  "curl -sf http://host.docker.internal:11434/api/tags >/dev/null && echo LLM-OK; \
   curl -sf http://host.docker.internal:12788/health >/dev/null && echo WHISPER-OK"
```

Fallbacks if the gateway trick fails on this Docker Desktop:
default-bridge + `links`, or bind services additionally on the host LAN IP and
point `LLM_URL`/`WHISPER_URL` at it.

### 5.5 Rebuild + validation

```powershell
docker compose -f docker-compose.transcriber.yml up -d --build worker
# 1) resume-insights through native LLM (proves LLM_URL + retry/chunk):
docker exec -it christiantube-transcriber sh -c \
  "cd /app && python -u worker.py --insights-resume --video-id 2qWx-wQ7JJo"
# 2) fresh whisper path on a short video, sanity-diff transcript quality
```

Pass criteria: both produce DB `completed`/100 + GitHub assets with the same
shapes as today.

## 6. Phase 2 — GPU spikes (benchmark or revert)

### 6a. Ollama Vulkan on the Arc iGPU (LLM)

```powershell
setx OLLAMA_VULKAN 1                 # restart Ollama after
ollama run qwen2.5:7b                # watch for crash / CPU-fallback
ollama ps                            # processor: GPU vs CPU
# steady-state tok/s on a fixed ~2048-token generation, 3 runs
```

Known landmines (record as we go):

- silent CPU fallback after the March-2026 Arc driver update — check `ollama ps`
- Vulkan iGPU crash on first batch → retry with `GGML_VK_DISABLE_COOPMAT=1`
  / `GGML_VK_NO_PIPELINE_CACHE=1`
- expected: iGPU ≈ CPU for 7B anyway (bandwidth-bound)

**Keep gate:** ≥1.5x steady throughput vs CPU-native, no crashes. Else revert
plain env (`setx OLLAMA_VULKAN 0`).

### 6b. whisper.cpp Vulkan (transcription — the real win)

```powershell
# model (GGML format)
git clone https://github.com/ggml-org/whisper.cpp.git D:\ml-models\whisper.cpp
cd D:\ml-models\whisper.cpp
models/download-ggml-model.sh large-v3-turbo     # ggml-large-v3-turbo.bin
# binary: prebuilt Vulkan build (jerryshell/whisper.cpp-windows-vulkan-bin)
#   or self-build: cmake -B build -DGGML_VULKAN=1 [-DGGML_AVX512=OFF] &&
#   cmake --build build --config Release
examples/server/whisper-server.exe --model ggml-large-v3-turbo.bin `
  --host 0.0.0.0 --port 12788 --vad on --beam-size 5
```

Benchmark: same 63-min sermon audio via `/inference`; compare wall time and
transcript diff vs faster-whisper CPU.

**Keep gate:** ≥2x faster and stable; map its segment/timestamp output into the
worker's `[MM:SS -> MM:SS]` format. Else keep the faster-whisper CPU server.

## 6c. Model bake-off (optional but cheap)

Worker is model-agnostic (`LLM_MODEL` env), so candidates are one `ollama pull`
away. Motivation: the insight task is prompt/KV-bound on CPU, so CPU speed
scales with **total** params — hence a smaller model, not a sexier one, is the
only CPU speedup; on a future GPU, larger/better models become viable.

| Candidate | Total params | Verdict for this pipeline |
| --- | --- | --- |
| `qwen2.5:7b` (current) | 7.6B | baseline, validated on `2qWx-wQ7JJo` |
| `gemma4:e2b` | 5.1B | only likely CPU speedup; risks JSON/quote quality |
| `gemma4` (e4b) | 8B | same speed class — no win |
| `gemma4:26b` (MoE A4B) | 26B (dense prompt pass) | bad fit on CPU; revisit if Arc Vulkan lands |
| `gemma4:31b` / `gemma4:12b` | 31B / 12B | slower on CPU |

Bake-off (Phase 1, after the native-Ollama move):

1. `ollama pull gemma4:e2b` (+ optionally `gemma4`).
2. Re-run `--insights-resume --video-id 2qWx-wQ7JJo` with `LLM_MODEL=gemma4:e2b`.
3. Gate = all of: wall-time < qwen baseline, `bibleQuotes` JSON valid (no
   repair needed), quote references/confidence comparable (review the 14-quote
   file), no thinking-mode preamble in output.
4. Adopt by flipping `LLM_MODEL` in `.transcriber.env`; keep qwen as rollback.

## 7. Management — `scripts/ctrl.ps1` (to be written in the implementation phase)

Skeleton (all CLI):

```powershell
.\scripts\ctrl.ps1 ollama start|stop|status   # Start-Process ollama serve; log D:\ml-models\logs\ollama.log
.\scripts\ctrl.ps1 whisper start|stop|status  # python whisper_server.py; health poll /health
.\scripts\ctrl.ps1 stack up|down|logs         # docker compose wrappers
.\scripts\ctrl.ps1 run  --video-id X [--insights-resume]
.\scripts\ctrl.ps1 status                     # one screen: ollama ps + whisper health + docker ps
# optional (deferred — user chose not to configure autostart yet):
#   scheduled-task logon autostart for ollama + whisper
```

## 8. Rollback

```powershell
git restore docker-compose.transcriber.yml services/transcriber/worker.py
docker compose -f docker-compose.transcriber.yml up -d --build   # llm back
# LLM_URL flips back to http://llm:11434; whisper falls back in-container via
# WHISPER_URL-unset default. Docker model volumes untouched during Phase 1.
```

## 9. Risks

| Risk | Mitigation |
| --- | --- |
| `host.docker.internal` refused on custom network | extra_hosts host-gateway; fallback default-bridge+links / host LAN IP (tested in 5.4) |
| Ollama Arc Vulkan flaky / silently CPU | Phase-2 spike with keep/revert gate; GPU not required for the plan |
| whisper.cpp Vulkan build complexity | Prebuilt binaries; stay on faster-whisper CPU if unstable |
| Native services exposed on LAN (0.0.0.0) | Windows Firewall rules scoped to the Docker VM / local subnet as needed |
| Whisper quality drift (faster-whisper VAD vs whisper.cpp VAD) | Benchmark transcript diff on a known sermon before adopting |
| Model copy bloat (fresh pull duplicates) | Docker volumes untouched until rollback window closes, then reclaim |

## 10. Acceptance criteria

1. `ctrl.ps1 status` shows Ollama + whisper healthy, harness containers up.
2. A real queued sermon runs end-to-end **without any Docker-bound model
   compute**, all assets published to the releases repo.
3. Phase-2 keep/revert decisions recorded with the benchmark numbers in this
   file (append a "Results" section).
4. `flutter analyze` + `flutter test` unaffected (no mobile code touched);
   `python -m py_compile` for worker/whisper server.

## 11. Results (appended as work happens)

### Phase 1 landed (2026-09-02)

- **Native Ollama**: `winget install Ollama.Ollama` (v0.33.2); `OLLAMA_HOST=0.0.0.0`
  + `OLLAMA_KEEP_ALIVE=30m` set as user env; `ollama pull qwen2.5:7b`; verified
  serving on `0.0.0.0:11434` and `PONG` generation. Device = 100% CPU (expected
  for Phase 1).
- **Native whisper server**: `services/transcriber/whisper_server.py`
  (FastAPI, faster-whisper). venv at `D:\ml-models\whisper\venv`. Uses the
  flat model dir `D:\ml-models\whisper\large-v3-turbo-flat` (see symlink caveat
  in 5.2). `/health` OK.
- **Harness**: compose dropped `llm` + `ollama-models` + `whisper-models`;
  worker env set to `LLM_URL=http://host.docker.internal:11434`,
  `WHISPER_URL=http://host.docker.internal:12788`, `extra_hosts:
  host.docker.internal:host-gateway`; old `christiantube-llm` container
  removed via `--remove-orphans`. worker.py gained `WhisperClient` (HTTP) +
  env-gated fallback to in-process `Transcriber` when `WHISPER_URL` is unset;
  `numpy`/`faster-whisper` imports made lazy so the container image only
  carries `yt-dlp`, `psycopg2-binary`, `requests`.
- **Connectivity gate (5.4) passed** on the first try: from inside the worker
  container both `host.docker.internal:11434` and `:12788` returned 200. No
  fallback needed.
- **LLM validation (insights-resume)** on `2qWx-wQ7JJo`: native Ollama loaded
  qwen2.5:7b (100% CPU, 32768 ctx) and re-ran the 4-chunk insight extraction.
- **Management**: `scripts/ctrl.ps1` written (ollama/whisper/stack/run/status).
  Note: when the `start` actions are invoked through a nested shell wrapper
  they spawn a persistent background process that makes the wrapper report a
  killed child, but the services do start and are healthy; running
  `ctrl.ps1 <svc> status` confirms.

Still open / deferred:
- Fresh-whisper end-to-end validation on a short video (planned, not yet run —
  pending a queued short English video).
- Phase 2 GPU spikes (Ollama Vulkan; whisper.cpp Vulkan) — not started.
- Deciding reclaim of the now-unused Docker `ollama-models` / `whisper-models`
  volumes once rollback window closes.