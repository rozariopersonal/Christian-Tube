#!/usr/bin/env python3
"""Lightweight Parakeet-TDT ASR inference runner.

Loads NVIDIA Parakeet-TDT once, transcribes audio chunks with native timestamps=True,
and outputs word timestamps JSON.

Usage:
  1. Pipe mode (Recommended - keeps model warm):
     python asr_runner.py --pipe
     Input:  {"audio": "/path/to/chunk.wav", "offset": 12.5}
     Output: {"success": true, "words": [{"word": "Hello", "start": 12.5, "end": 12.9}, ...]}

  2. Direct CLI mode:
     python asr_runner.py /path/to/chunk.wav --offset 12.5
"""

import argparse
import json
import logging
import os
import sys
import time

# Suppress NeMo / PyTorch / Lhotse chatter
os.environ["TF_CPP_MIN_LOG_LEVEL"] = "3"
logging.basicConfig(level=logging.ERROR)
for quiet in (
    "nemo_logger",
    "nemo",
    "pytorch_lightning",
    "lightning",
    "fabric",
    "absl",
    "onnx",
    "onnxruntime",
    "lhotse",
):
    logging.getLogger(quiet).setLevel(logging.CRITICAL)

try:
    from nemo.utils import logging as nemo_logging
    nemo_logging.set_verbosity(nemo_logging.ERROR)
except Exception:
    pass

try:
    import warnings
    warnings.filterwarnings("ignore")
except Exception:
    pass

try:
    from loguru import logger as _luru
    _luru.disable("nemo_logger")
except Exception:
    pass

PARAKEET_MODEL = os.environ.get("PARAKEET_MODEL", "nvidia/parakeet-tdt-0.6b-v3")


def load_model():
    from nemo.collections.asr.models import ASRModel
    t0 = time.time()
    sys.stderr.write(f"[asr_runner] Loading Parakeet model '{PARAKEET_MODEL}'...\n")
    sys.stderr.flush()
    model = ASRModel.from_pretrained(PARAKEET_MODEL)
    sys.stderr.write(f"[asr_runner] Model loaded in {time.time() - t0:.1f}s\n")
    sys.stderr.flush()
    return model


def transcribe_file(model, wav_path: str, offset: float = 0.0) -> list[dict]:
    if not os.path.exists(wav_path):
        raise FileNotFoundError(f"Audio file not found: {wav_path}")

    # Transcribe with native word timestamps
    hypotheses = model.transcribe([wav_path], timestamps=True, verbose=False)
    if not hypotheses:
        return []

    hyp = hypotheses[0]
    raw_words = []

    # Check for word-level timestamps on hypothesis
    if hasattr(hyp, "timestamp") and isinstance(hyp.timestamp, dict) and "word" in hyp.timestamp:
        raw_words = hyp.timestamp["word"]
    elif hasattr(hyp, "words"):
        raw_words = hyp.words

    words = []
    for item in raw_words:
        w_text = item.get("word") or item.get("text") or ""
        w_text = str(w_text).strip()
        if not w_text:
            continue

        w_start = round(float(item.get("start", 0.0)) + offset, 2)
        w_end = round(float(item.get("end", 0.0)) + offset, 2)
        words.append({
            "word": w_text,
            "start": w_start,
            "end": w_end,
        })

    return words


def run_pipe(model):
    """Processes requests over stdin/stdout."""
    sys.stdout.write("READY\n")
    sys.stdout.flush()

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        if line == "PING":
            sys.stdout.write("PONG\n")
            sys.stdout.flush()
            continue
        if line == "QUIT":
            break

        try:
            req = json.loads(line)
            audio_path = req["audio"]
            offset = float(req.get("offset", 0.0))

            words = transcribe_file(model, audio_path, offset)
            response = {"success": True, "words": words}
        except Exception as e:
            response = {"success": False, "error": str(e), "words": []}

        sys.stdout.write("RES:" + json.dumps(response) + "\n")
        sys.stdout.flush()


def main():
    parser = argparse.ArgumentParser(description="Parakeet ASR Runner")
    parser.add_argument("audio", nargs="?", help="Path to WAV audio file")
    parser.add_argument("--offset", type=float, default=0.0, help="Time offset in seconds")
    parser.add_argument("--pipe", action="store_true", help="Run in continuous pipe mode")
    args = parser.parse_args()

    model = load_model()

    if args.pipe:
        run_pipe(model)
    elif args.audio:
        words = transcribe_file(model, args.audio, args.offset)
        print(json.dumps(words, indent=2))
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
