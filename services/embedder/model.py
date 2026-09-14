"""ONNX runtime wrapper shared by serve.py and worker.py."""

from functools import lru_cache
from pathlib import Path

import numpy as np
from onnxruntime import GraphOptimizationLevel, InferenceSession, SessionOptions
from tokenizers import Tokenizer

from model_contract import MAX_TOKENS, ONNX_DIR

_PAD_TOKEN_ID = 1  # XLM-Roberta special ids: <s>=0, <pad>=1, </s>=2, <unk>=3


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
    input_ids = np.full(shape, _PAD_TOKEN_ID, dtype=np.int64)
    attention_mask = np.zeros(shape, dtype=np.int64)
    for i, row in enumerate(rows):
        input_ids[i, : len(row)] = row
        attention_mask[i, : len(row)] = 1
    return input_ids, attention_mask


def _mean_pool(last_hidden_state, attention_mask):
    mask = np.expand_dims(np.asarray(attention_mask, dtype=last_hidden_state.dtype), axis=-1)
    summed = np.sum(last_hidden_state * mask, axis=1)
    counts = np.clip(np.sum(mask, axis=1), a_min=1e-9, a_max=None)
    return summed / counts


def embed_texts(texts, onnx_dir=ONNX_DIR):
    session, tokenizer = load_model(onnx_dir)
    input_ids, attention_mask = _tokenize(texts, tokenizer)
    input_names = {inp.name for inp in session.get_inputs()}
    feed = {"input_ids": input_ids, "attention_mask": attention_mask}
    for name in input_names:
        if name == "token_type_ids":
            feed[name] = np.zeros_like(input_ids)
    outputs = session.run(None, feed)
    pooled = _mean_pool(outputs[0], attention_mask)
    norms = np.linalg.norm(pooled, axis=1, keepdims=True)
    norms[norms == 0] = 1.0
    vectors = pooled / norms
    return [v.astype("float32").tolist() for v in vectors]