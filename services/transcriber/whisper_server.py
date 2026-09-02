#!/usr/bin/env python3
r"""
whisper_server.py — HTTP wrapper around faster-whisper for the transcriber
pipeline. Runs natively on the Windows host so the STT workload lives outside
Docker. The Docker worker POSTs a 16 kHz mono wav and gets back timestamped
segments that it reformats into its usual `[MM:SS -> MM:SS]` transcript lines.

Endpoints
---------
GET  /health
    -> 200 {"status":"ok","model":"<model>"}
    -> 503 when the model failed to load (service not ready)

POST /transcribe
    multipart form:
        file=<16 kHz mono wav>   (required)
        language="en"            (optional; blank/absent => auto-detect)
    -> {"segments":[{"start":…,"end":…,"text":…}], "language":"<code>"}

Configuration (env)
-------------------
WHISPER_MODEL_DIR   faster-whisper model: an HF cache root for the model name,
                    a bare snapshot dir containing config.json + model.bin, or
                    "large-v3-turbo" to download fresh. Default is the existing
                    host HF cache used in the proving runs.
WHISPER_MODEL       model name used when WHISPER_MODEL_DIR is a cache root.
WHISPER_DEVICE      "cpu" (default) — "cuda" works when a GPU is available.
WHISPER_COMPUTE     "int8" (default)
WHISPER_HOST        "0.0.0.0" (default)
WHISPER_PORT        12788 (default)

Run:  D:\ml-models\whisper\venv\Scripts\python whisper_server.py
"""
from __future__ import annotations

import logging
import os
import tempfile
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, UploadFile

log = logging.getLogger("whisper-server")

_DEFAULT_MODEL_DIR = r"D:\ml-models\whisper\large-v3-turbo-flat"

MODEL_DIR = os.environ.get("WHISPER_MODEL_DIR", _DEFAULT_MODEL_DIR)
MODEL_NAME = os.environ.get("WHISPER_MODEL", "large-v3-turbo")
WHISPER_DEVICE = os.environ.get("WHISPER_DEVICE", "cpu")
WHISPER_COMPUTE = os.environ.get("WHISPER_COMPUTE", "int8")
HOST = os.environ.get("WHISPER_HOST", "0.0.0.0")
PORT = int(os.environ.get("WHISPER_PORT", "12788"))


def _resolve_model() -> tuple[str, str | None]:
    """Return (model_arg, download_root) for faster_whisper.WhisperModel."""
    p = Path(MODEL_DIR)
    if MODEL_DIR and p.is_dir():
        for candidate in [p, *sorted(p.glob("snapshots/*"), reverse=True)]:
            if (candidate / "config.json").is_file() and (candidate / "model.bin").exists():
                return str(candidate), None
        return MODEL_NAME, MODEL_DIR
    return MODEL_NAME, (MODEL_DIR if MODEL_DIR != MODEL_NAME else None)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    _app.state.model = None
    _app.state.model_label = None
    _app.state.error = None
    try:
        from faster_whisper import WhisperModel

        model_arg, download_root = _resolve_model()
        _app.state.model = WhisperModel(
            model_arg,
            device=WHISPER_DEVICE,
            compute_type=WHISPER_COMPUTE,
            download_root=download_root,
        )
        _app.state.model_label = model_arg
        log.info(
            "Whisper '%s' ready (%s/%s) device='%s' compute='%s'",
            model_arg, WHISPER_DEVICE, WHISPER_COMPUTE, WHISPER_DEVICE, WHISPER_COMPUTE,
        )
    except Exception as exc:  # noqa: BLE001
        _app.state.error = str(exc)
        log.exception("Failed to load Whisper model: %s", exc)
    yield


app = FastAPI(title="whisper-server", version="1.0", lifespan=lifespan)


@app.get("/health")
def health():
    if app.state.model is not None:
        return {"status": "ok", "model": app.state.model_label}
    raise HTTPException(503, detail=f"model not loaded: {app.state.error or 'loading'}")


@app.post("/transcribe")
def transcribe(file: UploadFile = File(...), language: str = Form("en")):
    if app.state.model is None:
        raise HTTPException(503, detail=f"model not loaded: {app.state.error or 'loading'}")
    if not (file.filename or "").lower().endswith(".wav"):
        raise HTTPException(400, "expected a .wav upload")

    suffix = Path(file.filename or "audio.wav").suffix or ".wav"
    fd, tmp = tempfile.mkstemp(suffix=suffix, prefix="whisper_in_")
    try:
        with os.fdopen(fd, "wb") as out:
            while True:
                chunk = file.file.read(1 << 20)
                if not chunk:
                    break
                out.write(chunk)
        segments, info = app.state.model.transcribe(
            tmp,
            language=language or None,
            vad_filter=True,
            beam_size=5,
            condition_on_previous_text=True,
            temperature=[0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
        )
        segs = [
            {"start": round(s.start, 2), "end": round(s.end, 2), "text": s.text.strip()}
            for s in segments
        ]
        log.info("transcribe: %d segments, language=%s", len(segs), info.language)
        return {"segments": segs, "language": info.language}
    finally:
        try:
            os.remove(tmp)
        except OSError:
            pass


if __name__ == "__main__":
    import uvicorn

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%H:%M:%S",
    )
    log.info("whisper-server listening on %s:%d", HOST, PORT)
    uvicorn.run(app, host=HOST, port=PORT)