FROM python:3.12-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV HF_HOME=/hf

# Install system dependencies, ffmpeg, and Node.js
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      cmake \
      curl \
      ffmpeg \
      git \
      libsndfile1 \
      ca-certificates \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 1. Install CPU torch & NeMo toolkit
COPY tools/transcriber/requirements.txt .
RUN pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu torch torchaudio \
    && pip install --no-cache-dir -r requirements.txt

# 2. Bake the Parakeet model weights into the Docker image cache
RUN python -c "from nemo.collections.asr.models import ASRModel; ASRModel.from_pretrained('nvidia/parakeet-tdt-0.6b-v3')"

# 3. Install Node.js dependencies
COPY tools/transcriber/package.json tools/transcriber/tsconfig.json ./
RUN npm install

# 4. Copy application source and tests
COPY tools/transcriber/src ./src
COPY tools/transcriber/tests ./tests

ENV POLL_INTERVAL=300 \
    BATCH_LIMIT=5 \
    MAX_RETRIES=3 \
    CONTENT_VERSION=2 \
    WORK_DIR=/work \
    PYTHON_BIN=python

CMD ["npm", "start"]
