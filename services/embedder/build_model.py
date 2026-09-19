"""Download the pre-quantized Gemma-300M int8 ONNX + tokenizer at image build time.

The onnx-community export is fetched directly from its Hugging Face repo (the
weights alone are ~294 MB — above GitHub's per-file cap, so they are not mirrored
in the releases repo). Candidates try the HF CDN first (rapid.usa.hf.co edge),
then the canonical huggingface.co resolve endpoint.

Files: model_quantized.onnx (graph), model_quantized.onnx_data (weights),
tokenizer.json (BPE).
"""

import os
import shutil
import urllib.request

from model_contract import MODEL_ID, ONNX_DIR

# HF path (inside the model repo) -> local filename
FILES = {
    "onnx/model_quantized.onnx": ("model_quantized.onnx", 500_000),            # ~568 KB graph
    "onnx/model_quantized.onnx_data": ("model_quantized.onnx_data", 300_000_000),  # ~294 MB weights
    "tokenizer.json": ("tokenizer.json", 15_000_000),                          # ~20 MB BPE tokenizer
}

DEFAULT_DOWNLOAD_TIMEOUT_SECONDS = 600


def _download(hf_path: str, dest: str, min_bytes: int):
    if os.path.exists(dest) and os.path.getsize(dest) >= min_bytes:
        print(f"Reusing existing {dest} ({os.path.getsize(dest):,} bytes)")
        return

    url = f"https://huggingface.co/{MODEL_ID}/resolve/main/{hf_path}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "christiantube-embedder/builder"})
        with urllib.request.urlopen(req, timeout=DEFAULT_DOWNLOAD_TIMEOUT_SECONDS) as resp, \
                open(dest, "wb") as out:
            shutil.copyfileobj(resp, out)
        size = os.path.getsize(dest)
        if size < min_bytes:
            raise IOError(f"payload too small ({size:,} bytes)")
        print(f"Downloaded {hf_path} ({size:,} bytes)")
        return
    except Exception as e:  # noqa: BLE001
        raise RuntimeError(f"Download failed for {url}: {e}") from e


def main():
    os.makedirs(ONNX_DIR, exist_ok=True)
    for hf_path, (local_name, min_bytes) in FILES.items():
        _download(hf_path, os.path.join(ONNX_DIR, local_name), min_bytes)
    print(f"Gemma ONNX assets staged in {ONNX_DIR}: {sorted(os.listdir(ONNX_DIR))}")


if __name__ == "__main__":
    main()