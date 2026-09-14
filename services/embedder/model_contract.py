"""Shared embedding model contract between the worker (index) and the serve (query).

Both sides MUST use the identical model, dimension, version and prefixing so
index vectors and query vectors live in the same space.
"""

import hashlib
import os

MODEL_ID = os.environ.get("EMBEDDING_MODEL", "intfloat/multilingual-e5-small")
EMBEDDING_DIM = int(os.environ.get("EMBEDDING_DIM", "384"))
EMBEDDING_VERSION = int(os.environ.get("EMBEDDING_VERSION", "1"))
MAX_TOKENS = int(os.environ.get("EMBEDDING_MAX_TOKENS", "512"))
ONNX_DIR = os.environ.get("ONNX_DIR", "/model")

PASSAGE_PREFIX = "passage: "
QUERY_PREFIX = "query: "


def passage_text(title, description=None):
    parts = [title or ""]
    if description:
        parts.append(description.strip())
    return PASSAGE_PREFIX + " ".join(p for p in parts if p)


def query_text(raw):
    return QUERY_PREFIX + (raw or "").strip()


def content_hash(title, description=None):
    return hashlib.sha256(f"{title or ''}|{description or ''}".encode("utf-8")).hexdigest()