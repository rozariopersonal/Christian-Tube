#!/usr/bin/env python3
"""Video embedding backfill worker.

Polls the PostgreSQL database for videos whose embedding is pending/outdated,
embeds title+description through the shared int8 ONNX model, and stores the
vector in the VideoEmbedding table. Mirrors services/youtube-processor/worker.py.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import signal
import sys
import time
import urllib.parse
from pathlib import Path

import psycopg2

from model import embed_texts
from model_contract import (
    EMBEDDING_DIM,
    EMBEDDING_VERSION,
    MODEL_ID,
    ONNX_DIR,
    PASSAGE_PREFIX,
    content_hash,
    passage_text,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("embedder")

_running = True


def handle_signal(signum, frame):
    global _running
    _running = False


LIBPQ_PARAMS = {
    "host", "port", "dbname", "user", "password", "sslmode", "sslcert",
    "sslkey", "sslrootcert", "sslcrl", "sslcrldir", "connect_timeout",
    "application_name", "fallback_application_name", "client_encoding",
    "options", "keepalives", "keepalives_idle", "keepalives_interval",
    "keepalives_count", "target_session_attrs", "channel_binding",
    "replication", "gssencmode", "krbsrvname", "gsslib", "service",
    "requiressl", "sslcompression",
}


def sanitize_db_url(url: str) -> str:
    parsed = urllib.parse.urlsplit(url)
    if not parsed.query:
        return url
    q = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
    keep = [f"{k}={v[0]}" for k, v in q.items() if k.lower() in LIBPQ_PARAMS]
    return urllib.parse.urlunsplit(
        (parsed.scheme, parsed.netloc, parsed.path, "&".join(keep), parsed.fragment)
    )


class Config:
    def __init__(self, database_url, local_database_url="", poll_interval=300, batch_limit=32, max_retries=3,
                 redo=False, retry_failed=False, once=False, embed_chunks=False,
                 chunk_batch_limit=32):
        self.database_url = database_url
        self.local_database_url = local_database_url
        self.poll_interval = poll_interval
        self.batch_limit = batch_limit
        self.max_retries = max_retries
        self.redo = redo
        self.retry_failed = retry_failed
        self.once = once
        self.embed_chunks = embed_chunks
        self.chunk_batch_limit = chunk_batch_limit


def load_config(args: argparse.Namespace) -> Config:
    for candidate in [Path(".embedder.env"), Path("../.embedder.env"), Path("../../.embedder.env")]:
        if candidate.exists():
            try:
                with open(candidate, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith("#") and "=" in line:
                            k, v = line.split("=", 1)
                            os.environ.setdefault(k.strip(), v.strip())
                break
            except Exception:
                pass

    db_url = os.environ.get("DIRECT_URL") or os.environ.get("DATABASE_URL", "").strip()
    if not db_url:
        log.error("DATABASE_URL (or DIRECT_URL) is required in environment.")
        sys.exit(1)

    local_db_url = os.environ.get("LOCAL_DATABASE_URL", "postgresql://postgres:postgres@db:5432/christiantube?schema=public").strip()

    return Config(
        database_url=db_url,
        local_database_url=local_db_url,
        poll_interval=int(os.environ.get("POLL_INTERVAL", args.poll_interval)),
        batch_limit=int(os.environ.get("BATCH_LIMIT", args.batch_limit)),
        max_retries=int(os.environ.get("MAX_RETRIES", args.max_retries)),
        redo=args.redo,
        retry_failed=args.retry_failed,
        once=args.once,
        embed_chunks=args.embed_chunks,
        chunk_batch_limit=int(os.environ.get("EMBED_CHUNK_BATCH", args.embed_chunk_batch)),
    )


class Database:
    def __init__(self, url: str):
        self.conn = psycopg2.connect(sanitize_db_url(url), connect_timeout=30)
        self.conn.autocommit = True
        self.cur = self.conn.cursor()
        self._ensure_schema()

    def _ensure_schema(self):
        # Run the bootstrap in isolated steps so one failure (e.g. a Neon
        # extension/DDL quirk) cannot silently skip the table/index creation.
        try:
            self.cur.execute("CREATE EXTENSION IF NOT EXISTS vector;")
        except Exception as e:
            log.warning("Ensure pgvector extension note: %s", e)

        try:
            self.cur.execute("""
                CREATE TABLE IF NOT EXISTS "VideoPipelineStatus" (
                  "videoId" TEXT NOT NULL PRIMARY KEY,
                  "contentVersion" INTEGER NOT NULL DEFAULT 0,
                  "ingest" JSONB NOT NULL DEFAULT '{}'::jsonb,
                  "transcription" JSONB NOT NULL DEFAULT '{}'::jsonb,
                  "chunk" JSONB NOT NULL DEFAULT '{}'::jsonb,
                  "embedding" JSONB NOT NULL DEFAULT '{}'::jsonb,
                  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
                  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
                  CONSTRAINT "VideoPipelineStatus_videoId_fkey"
                    FOREIGN KEY ("videoId") REFERENCES "Video"("id")
                    ON DELETE CASCADE ON UPDATE CASCADE
                );
                CREATE INDEX IF NOT EXISTS "VideoPipelineStatus_embedding_status_idx"
                  ON "VideoPipelineStatus" ((embedding->>'status'))
                  WHERE embedding->>'status' IN ('pending', 'failed');
            """)
        except Exception as e:
            log.warning("Ensure VideoPipelineStatus table note: %s", e)

        try:
            self.cur.execute(f"""
                CREATE TABLE IF NOT EXISTS "VideoEmbedding" (
                    "videoId" TEXT NOT NULL PRIMARY KEY,
                    "embedding" vector({EMBEDDING_DIM}) NOT NULL,
                    "model" TEXT NOT NULL,
                    "version" INTEGER NOT NULL DEFAULT 0,
                    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    CONSTRAINT "VideoEmbedding_videoId_fkey"
                        FOREIGN KEY ("videoId") REFERENCES "Video"("id")
                        ON DELETE CASCADE ON UPDATE CASCADE
                );
            """)
        except Exception as e:
            log.error("Could not create VideoEmbedding table: %s", e)
            raise

        try:
            self.cur.execute(
                'CREATE INDEX IF NOT EXISTS "VideoEmbedding_version_idx" '
                'ON "VideoEmbedding"("version");'
            )
            self.cur.execute(
                'CREATE INDEX IF NOT EXISTS "VideoEmbedding_embedding_hnsw_idx" '
                'ON "VideoEmbedding" USING hnsw ("embedding" vector_cosine_ops) '
                'WITH (m = 16, ef_construction = 64);'
            )
        except Exception as e:
            log.warning("Ensure VideoEmbedding indexes note: %s", e)

        self.cur.execute(
            """SELECT to_regclass('public."VideoEmbedding"') AS tbl"""
        )
        if self.cur.fetchone()[0] is None:
            raise RuntimeError(
                'VideoEmbedding table is missing after schema bootstrap'
            )

        self._ensure_chunk_queue_columns()

    def _ensure_chunk_queue_columns(self):
        """VideoChunk is created by the transcriber/chunker/backend bootstrap;
        the embedder only guarantees the queue columns it writes to."""
        try:
            self.cur.execute(
                'ALTER TABLE "VideoChunk" ALTER COLUMN "embedding" DROP NOT NULL'
            )
            self.cur.execute(
                'ALTER TABLE "VideoChunk" ALTER COLUMN "model" DROP NOT NULL'
            )
            self.cur.execute(
                'ALTER TABLE "VideoChunk" ADD COLUMN IF NOT EXISTS "embeddingStatus" TEXT DEFAULT \'pending\''
            )
            self.cur.execute(
                'ALTER TABLE "VideoChunk" ADD COLUMN IF NOT EXISTS "embeddingError" TEXT'
            )
            self.cur.execute(
                'ALTER TABLE "VideoChunk" ADD COLUMN IF NOT EXISTS "embeddingRetryCount" INTEGER DEFAULT 0'
            )
            self.cur.execute(
                'CREATE INDEX IF NOT EXISTS "VideoChunk_embedding_status_idx" '
                'ON "VideoChunk"("embeddingStatus") '
                'WHERE "embeddingStatus" IS DISTINCT FROM \'completed\''
            )
        except Exception as e:
            log.warning("Ensure VideoChunk embedding queue note: %s", e)

    def release_stale_processing(self):
        try:
            self.cur.execute(
                """UPDATE "VideoPipelineStatus"
                   SET "embedding" = COALESCE("embedding", '{}'::jsonb) || '{"status":"pending"}'::jsonb,
                       "updatedAt" = CURRENT_TIMESTAMP
                   WHERE "embedding"->>'status' = 'processing'"""
            )
        except Exception:
            pass

    def requeue_orphaned_completed(self):
        """Videos claiming 'completed' without a VideoEmbedding row (e.g. after
        a table wipe) are re-queued so the backfill repairs coverage."""
        try:
            self.cur.execute(
                """INSERT INTO "VideoPipelineStatus" ("videoId", "embedding", "updatedAt")
                   SELECT v.id, jsonb_build_object('status', 'pending'), CURRENT_TIMESTAMP
                   FROM "Video" v
                   LEFT JOIN "VideoPipelineStatus" s ON s."videoId" = v.id
                   WHERE COALESCE(s.embedding->>'status', 'pending') = 'completed'
                     AND NOT EXISTS (
                       SELECT 1 FROM "VideoEmbedding" ve
                       WHERE ve."videoId" = v.id
                     )
                   ON CONFLICT ("videoId") DO UPDATE SET
                     "embedding" = COALESCE("VideoPipelineStatus"."embedding", '{}'::jsonb)
                                    || '{"status":"pending","error":null,"hash":null}'::jsonb,
                     "updatedAt" = CURRENT_TIMESTAMP"""
            )
        except Exception as e:
            log.warning("Orphaned-completed requeue note: %s", e)

    def fetch_eligible(self, cfg: Config):
        statuses = ["pending"]
        if cfg.retry_failed:
            statuses.append("failed")
        if cfg.redo:
            statuses.append("completed")

        ph = ",".join(["%s"] * len(statuses))
        params: list = list(statuses)
        retry_clause = ""
        if cfg.retry_failed and "failed" in statuses:
            retry_clause = (" AND (NULLIF(s.embedding->>'retryCount', '')::integer IS NULL"
                            "   OR NULLIF(s.embedding->>'retryCount', '')::integer < %s)")
            params.append(cfg.max_retries)

        query = f"""
            SELECT v.id, v.title, v.description
            FROM "Video" v
            LEFT JOIN "VideoPipelineStatus" s ON s."videoId" = v.id
            WHERE (COALESCE(s.embedding->>'status', 'pending') IS NULL
                   OR COALESCE(s.embedding->>'status', 'pending') IN ({ph}))
            {retry_clause}
            ORDER BY v."publishedAt" DESC
            LIMIT %s
        """
        params.append(cfg.batch_limit)
        self.cur.execute(query, params)
        return self.cur.fetchall()

    def mark_processing(self, video_id: str):
        self.cur.execute(
            """INSERT INTO "VideoPipelineStatus" ("videoId", "embedding", "updatedAt")
               VALUES (%s, %s::jsonb, CURRENT_TIMESTAMP)
               ON CONFLICT ("videoId") DO UPDATE SET
                 "embedding" = COALESCE("VideoPipelineStatus"."embedding", '{}'::jsonb) || EXCLUDED."embedding",
                 "updatedAt" = CURRENT_TIMESTAMP""",
            (video_id, json.dumps({"status": "processing", "error": None})),
        )

    def upsert_embedding(self, video_id: str, vector: list, model: str, version: int):
        self.cur.execute(
            """
            INSERT INTO "VideoEmbedding" ("videoId","embedding","model","version","createdAt","updatedAt")
            VALUES (%s, %s::vector, %s, %s, now(), now())
            ON CONFLICT ("videoId") DO UPDATE SET
                "embedding"=EXCLUDED."embedding",
                "model"=EXCLUDED."model",
                "version"=EXCLUDED."version",
                "updatedAt"=now()
            """,
            (video_id, vector, model, version),
        )

    def mark_completed(self, video_id: str, version: int, digest: str):
        self.cur.execute(
            """INSERT INTO "VideoPipelineStatus" ("videoId", "embedding", "updatedAt")
               VALUES (%s, %s::jsonb, CURRENT_TIMESTAMP)
               ON CONFLICT ("videoId") DO UPDATE SET
                 "embedding" = COALESCE("VideoPipelineStatus"."embedding", '{}'::jsonb) || EXCLUDED."embedding",
                 "updatedAt" = CURRENT_TIMESTAMP""",
            (video_id, json.dumps({
                "status": "completed",
                "version": version,
                "hash": digest,
                "retryCount": 0,
                "error": None,
            })),
        )

    def mark_failed(self, video_id: str, error: str):
        self.cur.execute(
            """INSERT INTO "VideoPipelineStatus" ("videoId", "embedding", "updatedAt")
               VALUES (%s, jsonb_build_object('status', 'failed', 'error', %s, 'retryCount', 1), CURRENT_TIMESTAMP)
               ON CONFLICT ("videoId") DO UPDATE SET
                 "embedding" = jsonb_build_object(
                   'status', 'failed',
                   'error', %s,
                   'retryCount', COALESCE(NULLIF("VideoPipelineStatus"."embedding"->>'retryCount', '')::integer, 0) + 1),
                 "updatedAt" = CURRENT_TIMESTAMP""",
            (video_id, error[:500], error[:500]),
        )

    # ------------------------------------------------------------------ #
    # VideoChunk embedding queue
    # ------------------------------------------------------------------ #
    def release_stale_chunk_processing(self):
        try:
            self.cur.execute(
                """UPDATE "VideoChunk" SET "embeddingStatus"='pending'
                   WHERE "embeddingStatus"='processing'"""
            )
        except Exception:
            pass

    def fetch_eligible_chunks(self, cfg: Config):
        statuses = ["pending", "failed"]
        if cfg.redo:
            statuses.append("completed")
        ph = ",".join(["%s"] * len(statuses))
        params: list = list(statuses)
        retry_clause = ' AND (vc."embeddingRetryCount" IS NULL OR vc."embeddingRetryCount" < %s)'
        params.append(cfg.max_retries)
        self.cur.execute(
            f"""
            SELECT vc.id, vc."videoId", vc.content
            FROM "VideoChunk" vc
            JOIN "Video" v ON v.id = vc."videoId"
            JOIN "Channel" c ON c.id = v."channelId"
            WHERE c."isActive" = true
              AND (vc."embeddingStatus" IS NULL OR vc."embeddingStatus" IN ({ph}))
              {retry_clause}
            ORDER BY vc.id ASC
            LIMIT %s
            """,
            (*params, cfg.chunk_batch_limit),
        )
        return self.cur.fetchall()

    def mark_chunk_processing(self, chunk_id: int):
        self.cur.execute(
            """UPDATE "VideoChunk" SET "embeddingStatus"='processing', "embeddingError"=NULL
               WHERE "id"=%s""",
            (chunk_id,),
        )

    def mark_chunk_completed(self, chunk_id: int, vector: list, model: str, version: int):
        vector_literal = f"[{','.join(str(round(float(x), 6)) for x in vector)}]"
        self.cur.execute(
            """UPDATE "VideoChunk"
               SET "embeddingStatus"='completed',
                   "embedding"=%s::vector,
                   "model"=%s,
                   "version"=%s,
                   "embeddingRetryCount"=0,
                   "embeddingError"=NULL,
                   "updatedAt"=now()
               WHERE "id"=%s""",
            (vector_literal, model, version, chunk_id),
        )

    def mark_chunk_failed(self, chunk_id: int, error: str):
        self.cur.execute(
            """UPDATE "VideoChunk"
               SET "embeddingStatus"='failed',
                   "embeddingError"=%s,
                   "embeddingRetryCount"=COALESCE("embeddingRetryCount",0)+1
               WHERE "id"=%s""",
            (error[:500], chunk_id),
        )

    # ------------------------------------------------------------------ #
    # VideoSentence embedding queue
    # ------------------------------------------------------------------ #
    def release_stale_sentence_processing(self):
        try:
            self.cur.execute(
                """UPDATE "VideoSentence" SET "embeddingStatus"='pending'
                   WHERE "embeddingStatus"='processing'"""
            )
        except Exception:
            pass

    def fetch_eligible_sentences(self, limit: int = 128):
        self.cur.execute(
            """
            SELECT id, "videoId", seq, text
            FROM "VideoSentence"
            WHERE "embeddingStatus" = 'pending'
            ORDER BY "videoId", seq
            LIMIT %s
            """,
            (limit,),
        )
        return self.cur.fetchall()

    def mark_sentences_processing(self, sentence_ids: list[str]):
        if not sentence_ids:
            return
        self.cur.execute(
            """UPDATE "VideoSentence" SET "embeddingStatus"='processing' WHERE id = ANY(%s)""",
            (sentence_ids,),
        )

    def mark_sentences_completed(self, sentence_ids: list[str]):
        if not sentence_ids:
            return
        self.cur.execute(
            """UPDATE "VideoSentence" SET "embeddingStatus"='completed' WHERE id = ANY(%s)""",
            (sentence_ids,),
        )

    def mark_sentences_failed(self, sentence_ids: list[str]):
        if not sentence_ids:
            return
        self.cur.execute(
            """UPDATE "VideoSentence" SET "embeddingStatus"='failed' WHERE id = ANY(%s)""",
            (sentence_ids,),
        )

    def close(self):
        try:
            self.cur.close()
            self.conn.close()
        except Exception:
            pass


class LocalVectorDatabase:
    def __init__(self, url: str):
        self.conn = psycopg2.connect(sanitize_db_url(url), connect_timeout=30)
        self.conn.autocommit = True
        self.cur = self.conn.cursor()
        self._ensure_schema()

    def _ensure_schema(self):
        try:
            self.cur.execute("CREATE EXTENSION IF NOT EXISTS vector;")
        except Exception as e:
            log.warning("Local pgvector extension note: %s", e)
        try:
            self.cur.execute(f"""
                CREATE TABLE IF NOT EXISTS "SentenceEmbedding" (
                    "sentenceId" TEXT PRIMARY KEY,
                    "videoId" TEXT NOT NULL,
                    "seq" INTEGER NOT NULL,
                    "embedding" vector({EMBEDDING_DIM}) NOT NULL,
                    "model" TEXT NOT NULL,
                    "version" INTEGER NOT NULL DEFAULT {EMBEDDING_VERSION},
                    "createdAt" TIMESTAMPTZ DEFAULT now()
                );
                CREATE INDEX IF NOT EXISTS "SentenceEmbedding_videoId_idx" ON "SentenceEmbedding"("videoId");
                CREATE INDEX IF NOT EXISTS "SentenceEmbedding_hnsw_idx" ON "SentenceEmbedding" USING hnsw ("embedding" vector_cosine_ops);
            """)
        except Exception as e:
            log.warning("Local SentenceEmbedding table schema note: %s", e)

    def save_sentence_embeddings(self, items: list[tuple]):
        if not items:
            return
        from psycopg2.extras import execute_values
        query = """
            INSERT INTO "SentenceEmbedding" ("sentenceId", "videoId", "seq", "embedding", "model", "version")
            VALUES %s
            ON CONFLICT ("sentenceId") DO UPDATE SET
                "embedding" = EXCLUDED."embedding",
                "model" = EXCLUDED."model",
                "version" = EXCLUDED."version"
        """
        template = "(%s, %s, %s, %s::vector, %s, %s)"
        execute_values(self.cur, query, items, template=template)

    def close(self):
        try:
            self.cur.close()
            self.conn.close()
        except Exception:
            pass


def process_video(db: Database, cfg: Config, row) -> None:
    video_id, title, description = row
    digest = content_hash(title, description)

    if cfg.redo:
        db.cur.execute(
            'SELECT "embedding"->>\'status\' AS status, "embedding"->>\'hash\' AS hash '
            'FROM "VideoPipelineStatus" WHERE "videoId"=%s',
            (video_id,),
        )
        existing = db.cur.fetchone()
        if existing and existing[0] == "completed" and existing[1] == digest:
            return

    db.mark_processing(video_id)

    try:
        [vector] = embed_texts([passage_text(title, description)], onnx_dir=ONNX_DIR)
        db.upsert_embedding(video_id, vector, MODEL_ID, EMBEDDING_VERSION)
        db.mark_completed(video_id, EMBEDDING_VERSION, digest)
        log.info("Embedded %s (%d dims)", video_id, len(vector))
    except Exception as e:
        log.error("Failed to embed %s: %s", video_id, e)
        db.mark_failed(video_id, str(e))


def chunk_passage(content: str) -> str:
    """Text embedded for a VideoChunk: the shared 'passage:' prefix over the statement."""
    return PASSAGE_PREFIX + (content or "").strip()


def process_chunk(db: Database, cfg: Config, row) -> None:
    chunk_id, video_id, content = row
    try:
        db.mark_chunk_processing(chunk_id)
        [vector] = embed_texts([chunk_passage(content)], onnx_dir=ONNX_DIR)
        db.mark_chunk_completed(chunk_id, vector, MODEL_ID, EMBEDDING_VERSION)
        log.info("Embedded chunk %s (video %s, %d dims)", chunk_id, video_id, len(vector))
    except Exception as e:
        log.error("Failed to embed chunk %s (%s): %s", chunk_id, video_id, e)
        try:
            db.mark_chunk_failed(chunk_id, str(e))
        except Exception as mark_err:  # noqa: BLE001
            log.error("Could not mark chunk %s failed: %s", chunk_id, mark_err)


def process_sentences_batch(neon_db: Database, local_db: LocalVectorDatabase, rows: list) -> int:
    if not rows:
        return 0
    sentence_ids = [r[0] for r in rows]
    neon_db.mark_sentences_processing(sentence_ids)
    try:
        texts = [PASSAGE_PREFIX + (r[3] or "").strip() for r in rows]
        vectors = embed_texts(texts, onnx_dir=ONNX_DIR)

        items = []
        for row, vec in zip(rows, vectors):
            sentence_id, video_id, seq, _ = row
            vec_str = f"[{','.join(str(round(float(x), 6)) for x in vec)}]"
            items.append((sentence_id, video_id, seq, vec_str, MODEL_ID, EMBEDDING_VERSION))

        local_db.save_sentence_embeddings(items)
        neon_db.mark_sentences_completed(sentence_ids)
        log.info("Embedded %d sentences into local DB (Video %s)", len(items), rows[0][1])
        return len(items)
    except Exception as e:
        log.error("Failed to embed sentences batch: %s", e)
        neon_db.mark_sentences_failed(sentence_ids)
        raise


def main():
    parser = argparse.ArgumentParser(description="ChristianTube video embedding worker")
    parser.add_argument("--once", action="store_true", help="Process one batch and exit")
    parser.add_argument("--redo", action="store_true", help="Re-embed completed videos when content changed")
    parser.add_argument("--retry-failed", action="store_true", help="Include previously failed videos")
    parser.add_argument("--embed-chunks", action="store_true",
                        help="Also embed pending VideoChunk rows (env EMBED_CHUNKS=1)")
    parser.add_argument("--embed-chunk-batch", type=int, default=32)
    parser.add_argument("--poll-interval", type=int, default=300)
    parser.add_argument("--batch-limit", type=int, default=32)
    parser.add_argument("--max-retries", type=int, default=3)
    args = parser.parse_args()

    args.embed_chunks = args.embed_chunks or os.environ.get("EMBED_CHUNKS", "").lower() in ("1", "true", "yes")

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    cfg = load_config(args)
    db = Database(cfg.database_url)
    db.release_stale_processing()
    db._ensure_schema()

    local_db = LocalVectorDatabase(cfg.local_database_url)

    log.info("Embedder started (model=%s, version=%d, local_db=%s, once=%s, redo=%s)",
             MODEL_ID, EMBEDDING_VERSION, cfg.local_database_url.split("@")[-1], cfg.once, cfg.redo)

    while _running:
        worked = False

        # 1. High-priority: Embed pending sentences into Local DB
        db.release_stale_sentence_processing()
        sentence_batch = db.fetch_eligible_sentences(limit=128)
        if sentence_batch:
            log.info("Found %d pending sentence(s) to embed.", len(sentence_batch))
            worked = True
            try:
                process_sentences_batch(db, local_db, sentence_batch)
            except Exception as e:
                log.error("Sentence batch processing failed: %s", e)

        # 2. Embed videos (title + description)
        db.requeue_orphaned_completed()
        rows = db.fetch_eligible(cfg)
        if rows:
            log.info("Found %d eligible video(s).", len(rows))
            worked = True
            for row in rows:
                if not _running:
                    break
                process_video(db, cfg, row)

        # 3. Optional: Embed legacy chunks if enabled
        if cfg.embed_chunks:
            db.release_stale_chunk_processing()
            chunks = db.fetch_eligible_chunks(cfg)
            if chunks:
                log.info("Found %d eligible chunk(s).", len(chunks))
                worked = True
                for chunk in chunks:
                    if not _running:
                        break
                    process_chunk(db, cfg, chunk)

        if not worked:
            if cfg.once:
                log.info("No eligible items, exiting (--once).")
                break
            log.info("No pending items. Sleeping %ds...", cfg.poll_interval)
            for _ in range(cfg.poll_interval):
                if not _running:
                    break
                time.sleep(1)

        if cfg.once:
            break

    db.close()
    local_db.close()
    log.info("Embedder stopped.")


if __name__ == "__main__":
    main()