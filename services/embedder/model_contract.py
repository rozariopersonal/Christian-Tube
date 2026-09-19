"""Shared embedding model contract between the worker (index) and the serve (query).

Both sides MUST use the identical model, dimension, version and prefixing so
index vectors and query vectors live in the same space.

Model: EmbeddingGemma-300M (onnx-community pre-quantized int8 export, 768-d,
sentence_embedding output already pooled + L2-normalized).
"""

import hashlib
import os

MODEL_ID = os.environ.get("EMBEDDING_MODEL", "onnx-community/embeddinggemma-300m-ONNX")
EMBEDDING_DIM = int(os.environ.get("EMBEDDING_DIM", "768"))
EMBEDDING_VERSION = int(os.environ.get("EMBEDDING_VERSION", "3"))
MAX_TOKENS = int(os.environ.get("EMBEDDING_MAX_TOKENS", "2048"))
ONNX_DIR = os.environ.get("ONNX_DIR", "/model")

# Gemma prompt conventions (Gemini-style instruction prefixes):
#   queries   -> "task: search result | query: <query>"
#   documents -> "title: none | text: <passage>"
PASSAGE_PREFIX = "title: none | text: "
QUERY_PREFIX = "task: search result | query: "


def passage_text(title, description=None):
    parts = [title or ""]
    if description:
        parts.append(description.strip())
    return PASSAGE_PREFIX + " ".join(p for p in parts if p)


def query_text(raw):
    return QUERY_PREFIX + (raw or "").strip()


def content_hash(title, description=None):
    return hashlib.sha256(f"{title or ''}|{description or ''}".encode("utf-8")).hexdigest()