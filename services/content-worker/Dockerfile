# Content-search backfill worker: Audio.com audio -> captions/Parakeet ASR ->
# Qwen idea extraction -> e5-small embeddings -> VideoChunk rows.
# Bakes the e5-small ONNX model and the Parakeet weights so runtime is offline.
FROM python:3.12-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV HF_HOME=/hf

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      cmake \
      ffmpeg \
      git \
      libsndfile1 \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# NeMo first so Python resolution stays inside its pinned range; then move
# torch to the newest CPU build (matches services/embedder, which needs
# torch.int4 present for optimum's ONNX export helper).
COPY services/content-worker/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu torch torchaudio

# Shared embedding model (e5-small) -> int8 ONNX in /model
COPY services/embedder/model_contract.py /opt/embedder/
COPY services/embedder/model.py /opt/embedder/
COPY services/embedder/build_model.py /opt/embedder/
RUN ONNX_DIR=/model python /opt/embedder/build_model.py

# Bake the Parakeet checkpoint into the image cache (offline at runtime)
RUN python -c "from nemo.collections.asr.models import ASRModel; ASRModel.from_pretrained('nvidia/parakeet-tdt-0.6b-v3')"

COPY services/content-worker/worker.py services/content-worker/llm.py services/content-worker/transcribe.py ./

ENV ONNX_DIR=/model \
    EMBEDDER_SRC=/opt/embedder \
    POLL_INTERVAL=300 \
    BATCH_LIMIT=5 \
    MAX_RETRIES=3 \
    CONTENT_VERSION=2

CMD ["python", "-u", "worker.py"]