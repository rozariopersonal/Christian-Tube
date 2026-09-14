"""ONNX runtime wrapper shared by serve.py and worker.py."""

from functools import lru_cache
from pathlib import Path

import numpy as np
from onnxruntime import InferenceSession, SessionOptions
from transformers import AutoTokenizer

from model_contract import MAX_TOKENS, ONNX_DIR


@lru_cache(maxsize=1)
def load_model(onnx_dir=ONNX_DIR):
    quantized = Path(onnx_dir) / "model_quantized.onnx"
    onnx_file = quantized if quantized.exists() else Path(onnx_dir) / "model.onnx"
    if not onnx_file.exists():
        raise FileNotFoundError(f"No ONNX model found under {onnx_dir}")
    tokenizer = AutoTokenizer.from_pretrained(onnx_dir)
    options = SessionOptions()
    session = InferenceSession(str(onnx_file), options, providers=["CPUExecutionProvider"])
    return session, tokenizer


def _mean_pool(last_hidden_state, attention_mask):
    mask = np.expand_dims(np.asarray(attention_mask, dtype=last_hidden_state.dtype), axis=-1)
    summed = np.sum(last_hidden_state * mask, axis=1)
    counts = np.clip(np.sum(mask, axis=1), a_min=1e-9, a_max=None)
    return summed / counts


def embed_texts(texts, onnx_dir=ONNX_DIR):
    session, tokenizer = load_model(onnx_dir)
    tokenized = tokenizer(
        texts,
        padding=True,
        truncation=True,
        max_length=MAX_TOKENS,
        return_tensors="np",
    )
    input_names = {inp.name for inp in session.get_inputs()}
    feed = {}
    for name in input_names:
        if name in tokenized:
            feed[name] = tokenized[name]
        elif name == "token_type_ids":
            feed[name] = np.zeros_like(tokenized["input_ids"])
    outputs = session.run(None, feed)
    pooled = _mean_pool(outputs[0], tokenized["attention_mask"])
    norms = np.linalg.norm(pooled, axis=1, keepdims=True)
    norms[norms == 0] = 1.0
    vectors = pooled / norms
    return [v.astype("float32").tolist() for v in vectors]