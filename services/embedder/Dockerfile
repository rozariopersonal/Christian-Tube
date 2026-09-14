# ─── Stage 1: Export & int8-quantize the model (torch+optimum only live here) ─
# Build context is the repository root (Render builds from there; see docker-compose).
FROM python:3.11-slim AS builder

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
COPY services/embedder/model_contract.py services/embedder/model.py services/embedder/serve.py services/embedder/worker.py ./

ENV ONNX_DIR=/model
ENV PORT=8000

EXPOSE 8000

CMD ["sh", "-c", "uvicorn serve:app --host 0.0.0.0 --port ${PORT:-8000}"]