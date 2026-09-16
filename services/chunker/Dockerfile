# Chunk daemon: reads transcripts from the DB, extracts LLM idea chunks via
# Ollama, writes VideoChunk rows WITHOUT vectors (embedding deferred to the
# embedding service). No heavy model layers -> a tiny, fast-rebuilding image.
FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY services/chunker/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY services/chunker/worker.py services/chunker/llm.py services/chunker/test_llm.py ./

ENV POLL_INTERVAL=300 \
    BATCH_LIMIT=5 \
    MAX_RETRIES=3 \
    CHUNK_VERSION=2

CMD ["python", "-u", "worker.py"]