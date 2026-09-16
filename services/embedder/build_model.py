"""Download + stage the embedding model from the releases repo at Docker build time.

Unlike the MiniLM path (which exported via optimum + quantized), Gemma-300M
ships as a pre-quantized ONNX in the Christian-Tube-Releases repo.  This
script downloads the three required files into ONNX_DIR so model.py can
load them at runtime.
"""

import os
import shutil
import sys
import urllib.request
from pathlib import Path

from model_contract import ONNX_DIR

# Releases repo layout: all ML assets live under ml/embeddinggemma/
_RELEASES_RAW = "https://raw.githubusercontent.com/{repo}/main/ml/embeddinggemma/{name}"
_RELEASES_CDN = "https://cdn.jsdelivr.net/gh/{repo}@main/ml/embeddinggemma/{name}"

_REPO = os.environ.get(
    "RELEASES_REPO",
    "rozariopersonal/Christian-Tube-Releases",
)

_FILES = [
    "model_quantized.onnx",
    "model_quantized.onnx_data",
    "tokenizer.json",
]


def _download(name: str, dest: Path):
    """Download a single file from the releases repo (CDN first, raw fallback)."""
    url_cdn = _RELEASES_CDN.format(repo=_REPO, name=name)
    url_raw = _RELEASES_RAW.format(repo=_REPO, name=name)
    for url in (url_cdn, url_raw):
        try:
            print(f"  Downloading {name} from {url}")
            urllib.request.urlretrieve(url, str(dest))
            print(f"  Saved {dest} ({dest.stat().st_size / 1e6:.1f} MB)")
            return
        except Exception as exc:
            print(f"  Failed ({exc}), trying fallback")
    raise RuntimeError(f"Could not download {name} from any source")


def main():
    onnx_dir = Path(os.environ.get("ONNX_BUILD_DIR", ONNX_DIR))
    if onnx_dir.exists():
        shutil.rmtree(onnx_dir)
    onnx_dir.mkdir(parents=True, exist_ok=True)

    for name in _FILES:
        _download(name, onnx_dir / name)

    print(f"Model staged into {onnx_dir}: {sorted(p.name for p in onnx_dir.iterdir())}")


if __name__ == "__main__":
    main()
