"""FastAPI embedding inference + semantic moment search service.

Deployed to Render (embed endpoint) or Docker (search endpoint on :8686).
When LOCAL_DATABASE_URL is configured, /search returns exact moment hits from
the sentence embedding corpus using HNSW halfvec ANN with the query: prefix.
"""

import os
import time

import psycopg2
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel

from model import embed_texts, warmup
from model_contract import (
    EMBEDDING_DIM,
    EMBEDDING_VERSION,
    MODEL_ID,
    query_text,
)

app = FastAPI(title="ChristianTube Embeddings")

AUTH_TOKEN = os.environ.get("EMBEDDING_AUTH_TOKEN", "")
LOCAL_DATABASE_URL = os.environ.get("LOCAL_DATABASE_URL", "")


# ──────────────────────────────────────────────────────────────────────────────
# Request / response models
# ──────────────────────────────────────────────────────────────────────────────

class EmbedRequest(BaseModel):
    text: str
    texts: list[str] | None = None


class EmbedBatchRequest(BaseModel):
    texts: list[str]


class SearchRequest(BaseModel):
    query: str
    video_id: str | None = None
    limit: int = 10


class MomentResult(BaseModel):
    sentenceId: str
    videoId: str
    seq: int
    startSec: float | None
    endSec: float | None
    text: str | None
    score: float


class SearchResponse(BaseModel):
    results: list[MomentResult]
    count: int


# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

def _check_auth(authorization: str | None):
    if not AUTH_TOKEN:
        return
    if authorization != f"Bearer {AUTH_TOKEN}":
        raise HTTPException(status_code=401, detail="Unauthorized")


def _local_db_conn():
    if not LOCAL_DATABASE_URL:
        return None
    try:
        conn = psycopg2.connect(LOCAL_DATABASE_URL, connect_timeout=5)
        conn.autocommit = True
        return conn
    except Exception as exc:
        raise HTTPException(503, detail=f"Search DB unavailable: {exc}")


@app.on_event("startup")
def _warmup():
    warmup()


# ──────────────────────────────────────────────────────────────────────────────
# Embedding endpoints (unchanged)
# ──────────────────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {
        "status": "ok",
        "model": MODEL_ID,
        "dim": EMBEDDING_DIM,
        "version": EMBEDDING_VERSION,
        "search_enabled": bool(LOCAL_DATABASE_URL),
    }


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


# ──────────────────────────────────────────────────────────────────────────────
# Semantic moment search
# ──────────────────────────────────────────────────────────────────────────────

@app.post("/search", response_model=SearchResponse)
def search(request: SearchRequest, authorization: str | None = Header(default=None)):
    """Global semantic search over sentence embeddings.

    The query is embedded with the query: prefix (matching the passage: prefix
    used by the worker) via the same EmbeddingGemma-300M model/version.
    Returns exact moments (videoId + seq + timestamps) ranked by cosine
    similarity using the halfvec HNSW index.
    """
    if not LOCAL_DATABASE_URL:
        raise HTTPException(503, detail="Search unavailable: LOCAL_DATABASE_URL not configured")

    _check_auth(authorization)

    q_raw = (request.query or "").strip()
    if not q_raw:
        raise HTTPException(422, detail="query is required")

    limit = min(max(request.limit, 1), 50)

    q_vec = embed_texts([query_text(q_raw)])[0]

    conn = _local_db_conn()
    try:
        cur = conn.cursor()
        params: list = [q_vec]
        if request.video_id:
            params.extend([request.video_id, q_vec, limit])
            cur.execute(
                """SELECT "sentenceId", "videoId", seq, "startSec", "endSec", "text",
                          1 - ("embedding_half" <=> %s::halfvec) AS score
                   FROM "SentenceEmbedding"
                   WHERE "videoId" = %s
                   ORDER BY "embedding_half" <=> %s::halfvec
                   LIMIT %s""",
                params,
            )
        else:
            params.extend([q_vec, limit])
            cur.execute(
                """SELECT "sentenceId", "videoId", seq, "startSec", "endSec", "text",
                          1 - ("embedding_half" <=> %s::halfvec) AS score
                   FROM "SentenceEmbedding"
                   ORDER BY "embedding_half" <=> %s::halfvec
                   LIMIT %s""",
                params,
            )

        rows = cur.fetchall()
        cur.close()
    finally:
        conn.close()

    return SearchResponse(
        results=[
            MomentResult(
                sentenceId=r[0],
                videoId=r[1],
                seq=r[2],
                startSec=r[3],
                endSec=r[4],
                text=r[5],
                score=round(float(r[6]), 4),
            )
            for r in rows
        ],
        count=len(rows),
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8000")))
