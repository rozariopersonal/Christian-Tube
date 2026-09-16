# ─── Stage 1: Export & int8-quantize the model (torch+optimum only live here) ─
# Build context is the repository root (Render builds from there; see docker-compose).
FROM python:3.11-slim AS builder

# Model contract baked into the image at build time; the runtime worker/serve
# receive the same values via environment and MUST match.
ARG EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
ARG EMBEDDING_DIM=384
ARG EMBEDDING_VERSION=2
ARG EMBEDDING_MAX_TOKENS=256

ENV EMBEDDING_MODEL=$EMBEDDING_MODEL \
    EMBEDDING_DIM=$EMBEDDING_DIM \
    EMBEDDING_VERSION=$EMBEDDING_VERSION \
    EMBEDDING_MAX_TOKENS=$EMBEDDING_MAX_TOKENS

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

COPY services/embedder/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu torch \
    && pip install --no-cache-dir "optimum[onnxruntime]>=1.19"

COPY services/embedder/model_contract.py services/embedder/build_model.py ./
RUN python -u build_model.py

# ─── Stage 2: Lean runtime (onnxruntime + transformers tokenizers only) ──────
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