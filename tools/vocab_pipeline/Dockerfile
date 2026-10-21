FROM python:3.12-slim

WORKDIR /app

ENV PYTHONUNBUFFERED=1
ENV OLLAMA_HOST=http://host.docker.internal:11434
ENV OLLAMA_MODEL=gemma4:12b

# Install dependencies (only standard library urllib and sqlite3 used, but adding common utils)
RUN pip install --no-cache-dir requests

# Copy pipeline scripts & prompts
COPY rag_step1_processor.py /app/rag_step1_processor.py
COPY prompts /app/prompts

# Entrypoint default runs all or specific book via arguments
ENTRYPOINT ["python", "-u", "/app/rag_step1_processor.py"]
CMD ["--all", "--book", "1", "--start-chapter", "1"]

