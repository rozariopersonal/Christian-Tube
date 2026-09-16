# Transcription daemon: YouTube captions / Audio.com audio -> Parakeet ASR ->
# timestamped transcript written to Video.content. No LLM, no embeddings.
# Bakes the Parakeet weights so runtime is offline.
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

# CPU-only torch first: pre-installing from the CPU index prevents nemo_toolkit
# from pulling the GPU variant + 3.2 GB nvidia-* + 897 MB triton transitives.
COPY services/transcriber/requirements.txt .
RUN pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu torch torchaudio \
    && pip install --no-cache-dir -r requirements.txt

# Bake the Parakeet checkpoint into the image cache (offline at runtime)
RUN python -c "from nemo.collections.asr.models import ASRModel; ASRModel.from_pretrained('nvidia/parakeet-tdt-0.6b-v3')"

COPY services/transcriber/worker.py services/transcriber/transcribe.py services/transcriber/test_transcribe.py ./

ENV POLL_INTERVAL=300 \
    BATCH_LIMIT=5 \
    MAX_RETRIES=3 \
    CONTENT_VERSION=2

CMD ["python", "-u", "worker.py"]