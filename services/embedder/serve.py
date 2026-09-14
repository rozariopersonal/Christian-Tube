"""FastAPI embedding inference service (deployed to Render as a free web service)."""

import os
import time

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel

from model import embed_texts, warmup
from model_contract import EMBEDDING_DIM, EMBEDDING_VERSION, MODEL_ID

app = FastAPI(title="ChristianTube Embeddings")

AUTH_TOKEN = os.environ.get("EMBEDDING_AUTH_TOKEN", "")


class EmbedRequest(BaseModel):
    text: str
    texts: list[str] | None = None


class EmbedBatchRequest(BaseModel):
    texts: list[str]


def _check_auth(authorization: str | None):
    if not AUTH_TOKEN:
        return
    if authorization != f"Bearer {AUTH_TOKEN}":
        raise HTTPException(status_code=401, detail="Unauthorized")


@app.on_event("startup")
def _warmup():
    warmup()


@app.get("/health")
def health():
    return {"status": "ok", "model": MODEL_ID, "dim": EMBEDDING_DIM, "version": EMBEDDING_VERSION}


@app.post("/embed")
def embed(request: EmbedRequest, authorization: str | None = Header(default=None)):
    _check_auth(authorization)
    text = (request.text or "").strip()
    if not text:
        raise HTTPException(status_code=422, detail="text is required")
    started = time.perf_counter()
    [vector] = embed_texts([text])
    return {
        "embedding": vector,
        "dim": len(vector),
        "model": MODEL_ID,
        "version": EMBEDDING_VERSION,
        "latency_ms": round((time.perf_counter() - started) * 1000, 2),
    }


@app.post("/embed-batch")
def embed_batch(request: EmbedBatchRequest, authorization: str | None = Header(default=None)):
    _check_auth(authorization)
    texts = [t for t in (request.texts or []) if (t or "").strip()]
    if not texts:
        raise HTTPException(status_code=422, detail="texts is required")
    return {
        "embeddings": embed_texts(texts),
        "dim": EMBEDDING_DIM,
        "model": MODEL_ID,
        "version": EMBEDDING_VERSION,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8000")))