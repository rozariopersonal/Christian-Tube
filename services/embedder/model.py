"""ONNX runtime wrapper shared by serve.py and worker.py.

Gemma-300M: the ONNX graph includes the pooling, dense projection and L2
normalization head, so outputs[1] (sentence_embedding) is already a unit-
length 768-dim vector.  No manual mean-pooling needed.
"""

from functools import lru_cache
from pathlib import Path

import numpy as np
from onnxruntime import GraphOptimizationLevel, InferenceSession, SessionOptions
from tokenizers import Tokenizer

from model_contract import MAX_TOKENS, ONNX_DIR


@lru_cache(maxsize=1)
def _load_tokenizer(onnx_dir=ONNX_DIR):
    path = Path(onnx_dir) / "tokenizer.json"
    if not path.exists():
        raise FileNotFoundError(f"No tokenizer.json found under {onnx_dir}")
    tokenizer = Tokenizer.from_file(str(path))
    tokenizer.enable_truncation(max_length=MAX_TOKENS)
    return tokenizer


@lru_cache(maxsize=1)
def _load_session(onnx_dir=ONNX_DIR):
    quantized = Path(onnx_dir) / "model_quantized.onnx"
    onnx_file = quantized if quantized.exists() else Path(onnx_dir) / "model.onnx"
    if not onnx_file.exists():
        raise FileNotFoundError(f"No ONNX model found under {onnx_dir}")
    options = SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    options.graph_optimization_level = GraphOptimizationLevel.ORT_ENABLE_ALL
    options.add_session_config_entry("session.memory_percent", "60")
    return InferenceSession(str(onnx_file), options, providers=["CPUExecutionProvider"])


@lru_cache(maxsize=1)
def load_model(onnx_dir=ONNX_DIR):
    return _load_session(onnx_dir), _load_tokenizer(onnx_dir)


def warmup(onnx_dir=ONNX_DIR):
    """Cheap startup warmup: tokenizer only. The ONNX session is loaded lazily on
    the first embed request so deploy-time memory stays within free-tier limits."""
    _load_tokenizer(onnx_dir)


def _tokenize(texts, tokenizer):
    encoded = tokenizer.encode_batch(texts, add_special_tokens=True)
    rows = [e.ids for e in encoded]
    width = max(len(row) for row in rows)
    shape = (len(rows), width)
    input_ids = np.full(shape, 0, dtype=np.int64)
    attention_mask = np.zeros(shape, dtype=np.int64)
    for i, row in enumerate(rows):
        input_ids[i, : len(row)] = row
        attention_mask[i, : len(row)] = 1
    return input_ids, attention_mask


def embed_texts(texts, onnx_dir=ONNX_DIR):
    session, tokenizer = load_model(onnx_dir)
    input_ids, attention_mask = _tokenize(texts, tokenizer)
    feed = {"input_ids": input_ids, "attention_mask": attention_mask}
    outputs = session.run(None, feed)
    # Gemma outputs [last_hidden_state, sentence_embedding].
    # sentence_embedding is already L2-normalized.
    vectors = outputs[1].astype("float32")
    return [v.tolist() for v in vectors]
