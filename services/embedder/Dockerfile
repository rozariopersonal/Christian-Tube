# ─── Stage 1: Download pre-quantized Gemma ONNX from Hugging Face ───────────
FROM python:3.11-slim AS builder

ARG EMBEDDING_MODEL=onnx-community/embeddinggemma-300m-ONNX
ARG EMBEDDING_DIM=768
ARG EMBEDDING_VERSION=3
ARG EMBEDDING_MAX_TOKENS=2048

ENV EMBEDDING_MODEL=$EMBEDDING_MODEL \
    EMBEDDING_DIM=$EMBEDDING_DIM \
    EMBEDDING_VERSION=$EMBEDDING_VERSION \
    EMBEDDING_MAX_TOKENS=$EMBEDDING_MAX_TOKENS

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

COPY services/embedder/model_contract.py services/embedder/build_model.py ./
RUN python -u build_model.py

# ─── Stage 2: Lean runtime (onnxruntime + tokenizers only) ───────────────────
FROM python:3.11-slim AS runner

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

COPY services/embedder/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY --from=builder /model /model
COPY services/embedder/model_contract.py services/embedder/model.py services/embedder/serve.py services/embedder/worker.py services/embedder/test_chunks.py ./

ENV ONNX_DIR=/model
ENV PORT=8000

EXPOSE 8000

CMD ["sh", "-c", "uvicorn serve:app --host 0.0.0.0 --port ${PORT:-8000}"]
