"""ONNX runtime wrapper shared by serve.py and worker.py (EmbeddingGemma-300M).

The onnx-community int8 export exposes two outputs: `last_hidden_state`
(batch, seq, 768) and `sentence_embedding` (batch, 768) — the latter is already
mean-pooled, projected and L2-normalized inside the graph, so no manual pooling
is required. `last_hidden_state` mean-pooling is kept only as a fallback.
"""

from functools import lru_cache
from pathlib import Path

import numpy as np
from onnxruntime import GraphOptimizationLevel, InferenceSession, SessionOptions
from tokenizers import Tokenizer

from model_contract import MAX_TOKENS, ONNX_DIR

_PAD_TOKEN_ID = 0  # gemma: pad=0, bos=2, eos=1 (tokenizer adds <bos>/<eos> via special tokens)


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


def _l2_normalize(vectors):
    norms = np.linalg.norm(vectors, axis=1, keepdims=True)
    norms[norms == 0] = 1.0
    return vectors / norms


def embed_texts(texts, onnx_dir=ONNX_DIR):
    session, tokenizer = load_model(onnx_dir)
    input_ids, attention_mask = _tokenize(texts, tokenizer)
    outputs = session.run(None, {"input_ids": input_ids, "attention_mask": attention_mask})

    out_index = {o.name: i for i, o in enumerate(session.get_outputs())}
    if "sentence_embedding" in out_index:
        pooled = outputs[out_index["sentence_embedding"]]
    elif len(outputs) > 1:
        pooled = outputs[1]
    else:
        pooled = _mean_pool(outputs[0], attention_mask)

    return [v.astype("float32").tolist() for v in _l2_normalize(pooled)]