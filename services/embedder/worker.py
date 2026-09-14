#!/usr/bin/env python3
"""Video embedding backfill worker.

Polls the PostgreSQL database for videos whose embedding is pending/outdated,
embeds title+description through the shared int8 ONNX model, and stores the
vector in the VideoEmbedding table. Mirrors services/youtube-processor/worker.py.
"""

from __future__ import annotations

import argparse
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
    EMBEDDING_VERSION,
    MODEL_ID,
    ONNX_DIR,
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
    def __init__(self, database_url, poll_interval=300, batch_limit=32, max_retries=3,
                 redo=False, retry_failed=False, once=False):
        self.database_url = database_url
        self.poll_interval = poll_interval
        self.batch_limit = batch_limit
        self.max_retries = max_retries
        self.redo = redo
        self.retry_failed = retry_failed
        self.once = once


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

    return Config(
        database_url=db_url,
        poll_interval=int(os.environ.get("POLL_INTERVAL", args.poll_interval)),
        batch_limit=int(os.environ.get("BATCH_LIMIT", args.batch_limit)),
        max_retries=int(os.environ.get("MAX_RETRIES", args.max_retries)),
        redo=args.redo,
        retry_failed=args.retry_failed,
        once=args.once,
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
                ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "embeddingStatus" TEXT DEFAULT 'pending';
                ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "embeddingVersion" INTEGER DEFAULT 0;
                ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "embeddingHash" TEXT;
                ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "embeddingError" TEXT;
                ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "embeddingRetryCount" INTEGER DEFAULT 0;
            """)
        except Exception as e:
            log.warning("Ensure Video embedding columns note: %s", e)

        try:
            self.cur.execute("""
                CREATE TABLE IF NOT EXISTS "VideoEmbedding" (
                    "videoId" TEXT NOT NULL PRIMARY KEY,
                    "embedding" vector(384) NOT NULL,
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

    def release_stale_processing(self):
        try:
            self.cur.execute(
                """UPDATE "Video" SET "embeddingStatus"='pending'
                   WHERE "embeddingStatus"='processing'"""
            )
        except Exception:
            pass

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
            retry_clause = ' AND ("embeddingRetryCount" IS NULL OR "embeddingRetryCount" < %s)'
            params.append(cfg.max_retries)

        query = f"""
            SELECT v.id, v.title, v.description
            FROM "Video" v
            WHERE ("embeddingStatus" IS NULL OR "embeddingStatus" IN ({ph}))
            {retry_clause}
            ORDER BY v."publishedAt" DESC
            LIMIT %s
        """
        params.append(cfg.batch_limit)
        self.cur.execute(query, params)
        return self.cur.fetchall()

    def mark_processing(self, video_id: str):
        self.cur.execute(
            """UPDATE "Video" SET "embeddingStatus"='processing', "embeddingError"=NULL
               WHERE "id"=%s""",
            (video_id,),
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
            """UPDATE "Video"
               SET "embeddingStatus"='completed',
                   "embeddingVersion"=%s,
                   "embeddingHash"=%s,
                   "embeddingRetryCount"=0,
                   "embeddingError"=NULL
               WHERE "id"=%s""",
            (version, digest, video_id),
        )

    def mark_failed(self, video_id: str, error: str):
        self.cur.execute(
            """UPDATE "Video"
               SET "embeddingStatus"='failed',
                   "embeddingError"=%s,
                   "embeddingRetryCount"=COALESCE("embeddingRetryCount",0)+1
               WHERE "id"=%s""",
            (error[:500], video_id),
        )

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
        db.cur.execute('SELECT "embeddingStatus", "embeddingHash" FROM "Video" WHERE "id"=%s', (video_id,))
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


def main():
    parser = argparse.ArgumentParser(description="ChristianTube video embedding worker")
    parser.add_argument("--once", action="store_true", help="Process one batch and exit")
    parser.add_argument("--redo", action="store_true", help="Re-embed completed videos when content changed")
    parser.add_argument("--retry-failed", action="store_true", help="Include previously failed videos")
    parser.add_argument("--poll-interval", type=int, default=300)
    parser.add_argument("--batch-limit", type=int, default=32)
    parser.add_argument("--max-retries", type=int, default=3)
    args = parser.parse_args()

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    cfg = load_config(args)
    db = Database(cfg.database_url)
    db.release_stale_processing()
    db._ensure_schema()

    log.info("Embedder started (model=%s, version=%d, once=%s, redo=%s, retry_failed=%s)",
             MODEL_ID, EMBEDDING_VERSION, cfg.once, cfg.redo, cfg.retry_failed)

    while _running:
        rows = db.fetch_eligible(cfg)
        if not rows:
            if cfg.once:
                log.info("No eligible videos, exiting (--once).")
                break
            log.info("No pending videos. Sleeping %ds...", cfg.poll_interval)
            for _ in range(cfg.poll_interval):
                if not _running:
                    break
                time.sleep(1)
            continue

        log.info("Found %d eligible video(s).", len(rows))
        for row in rows:
            if not _running:
                break
            process_video(db, cfg, row)

        if cfg.once:
            break

    db.close()
    log.info("Embedder stopped.")


if __name__ == "__main__":
    main()