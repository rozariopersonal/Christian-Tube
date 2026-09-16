"""Chunk daemon: Video.content -> LLM "idea" chunks -> VideoChunk rows.

Reads timestamped transcripts produced by the transcriber from the database,
runs Ollama idea extraction over the transcript windows, and writes the
structured ``VideoChunk`` rows WITHOUT vectors (``embeddingStatus='pending'``).

The embedding service fills in ``embedding``/``model``/``version`` asynchronously;
search gates on ``model``+``version`` equality so un-embedded chunks never rank.
"""

import argparse
import json
import logging
import os
import signal
import sys
import time
from dataclasses import dataclass, field

import psycopg2

from llm import LLM, extract_ideas, parse_timestamps_markers

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("chunker")


@dataclass
class Config:
    db_url: str = ""
    ollama_url: str = os.environ.get("OLLAMA_URL", "http://host.docker.internal:11434")
    ollama_model: str = os.environ.get("OLLAMA_MODEL", "gemma3:4b")
    chunk_version: int = int(os.environ.get("CHUNK_VERSION", "2"))
    poll_interval: int = int(os.environ.get("POLL_INTERVAL", "300"))
    batch_limit: int = int(os.environ.get("BATCH_LIMIT", "5"))
    max_retries: int = int(os.environ.get("MAX_RETRIES", "3"))
    max_transcript_chars: int = int(os.environ.get("MAX_TRANSCRIPT_CHARS", "0"))
    log_ideas: bool = os.environ.get("LOG_IDEAS", "false").lower() in ("1", "true", "yes")
    priority_channel_ids: list[str] = field(
        default_factory=lambda: [
            c.strip()
            for c in os.environ.get("PRIORITY_CHANNEL_IDS", "UCpZG4Vl2tqg5cIfGMocI2Ag").split(",")
            if c.strip()
        ]
    )


class Database:
    def __init__(self, cfg: Config):
        import psycopg2  # noqa: E402

        self.conn = psycopg2.connect(cfg.db_url)
        self.conn.autocommit = True
        self.cur = self.conn.cursor()
        self.ensure_schema()

    def ensure_schema(self):
        """Idempotent schema evolution for the chunk stage (safe to rerun)."""
        try:
            self.cur.execute(
                'ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "contentVersion" INTEGER DEFAULT 0'
            )
            self.cur.execute(
                'ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "chunkStatus" TEXT DEFAULT \'pending\''
            )
            self.cur.execute(
                'ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "chunkError" TEXT'
            )
            self.cur.execute(
                'ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "chunkRetryCount" INTEGER DEFAULT 0'
            )
        except Exception as e:  # noqa: BLE001
            log.warning("Video chunkStatus columns step failed: %s", e)
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
        except Exception as e:  # noqa: BLE001
            log.warning("VideoChunk embedding queue columns step failed: %s", e)

    def release_stale_processing(self):
        try:
            self.cur.execute(
                """UPDATE "Video" SET "chunkStatus"='pending'
                   WHERE "chunkStatus"='processing'"""
            )
            if self.cur.rowcount:
                log.info("  released %d stale chunk 'processing' row(s)", self.cur.rowcount)
        except Exception as e:  # noqa: BLE001
            log.warning("release_stale_processing failed: %s", e)

    def requeue_stale_completed(self, target_version: int):
        try:
            self.cur.execute(
                """UPDATE "Video"
                   SET "chunkStatus"='pending',
                       "chunkRetryCount"=0,
                       "chunkError"=NULL
                   WHERE "chunkStatus"='completed'
                     AND "transcriptionStatus"='completed'
                     AND (
                       "contentVersion" IS NULL
                       OR "contentVersion" < %s
                       OR NOT EXISTS (
                         SELECT 1 FROM "VideoChunk" vc
                         WHERE vc."videoId" = "Video"."id"
                       )
                     )""",
                (target_version,),
            )
        except Exception as e:  # noqa: BLE001
            log.warning("requeue_stale_completed failed: %s", e)

    def fetch_eligible(self, cfg: Config):
        self.cur.execute(
            """SELECT v.id, v.title, v."content", v."transcriptionDetail"
               FROM "Video" v
               JOIN "Channel" c ON c.id = v."channelId"
               WHERE c."isActive" = true
                 AND c.language = 'English'
                 AND v.type = 'VIDEO'
                 AND v."transcriptionStatus" = 'completed'
                 AND v."content" IS NOT NULL
                 AND (v."chunkStatus" IS NULL
                      OR v."chunkStatus" IN ('pending', 'failed'))
                 AND (v."chunkRetryCount" IS NULL
                      OR v."chunkRetryCount" < %s)
               ORDER BY
                 CASE WHEN v."channelId" = ANY(%s::text[]) THEN 0 ELSE 1 END,
                 v."publishedAt" DESC
               LIMIT %s""",
            (cfg.max_retries, cfg.priority_channel_ids, cfg.batch_limit),
        )
        return self.cur.fetchall()

    def mark_processing(self, video_id: str):
        self.cur.execute(
            """UPDATE "Video" SET "chunkStatus"='processing', "chunkError"=NULL
               WHERE "id"=%s""",
            (video_id,),
        )

    def mark_failed(self, video_id: str, error: str):
        self.cur.execute(
            """UPDATE "Video" SET "chunkStatus"='failed',
                      "chunkError"=%s,
                      "chunkRetryCount"="chunkRetryCount"+1
               WHERE "id"=%s""",
            (error[:2000], video_id),
        )

    def mark_completed(self, video_id: str, idea_count: int, cfg: Config):
        self.cur.execute(
            """UPDATE "Video" SET "chunkStatus"='completed',
                      "chunkError"=NULL,
                      "chunkRetryCount"=0,
                      "contentVersion"=%s
               WHERE "id"=%s""",
            (cfg.chunk_version, video_id),
        )

    def clear_chunks(self, video_id: str):
        self.cur.execute('DELETE FROM "VideoChunk" WHERE "videoId"=%s', (video_id,))

    def save_chunks(self, video_id: str, ideas: list, source: str):
        for seq, idea in enumerate(ideas):
            self.cur.execute(
                """INSERT INTO "VideoChunk"
                      ("videoId","seq","kind","title","content","quoteText",
                       "scriptureRefs","startSec","endSec","source","embeddingStatus","digest",
                       "createdAt","updatedAt")
                   VALUES (%s,%s,'idea',%s,%s,%s,%s,%s,%s,%s,'pending',%s,now(),now())
                   ON CONFLICT ("videoId","seq") DO UPDATE SET
                     "title"=EXCLUDED."title",
                     "content"=EXCLUDED."content",
                     "quoteText"=EXCLUDED."quoteText",
                     "scriptureRefs"=EXCLUDED."scriptureRefs",
                     "startSec"=EXCLUDED."startSec",
                     "endSec"=EXCLUDED."endSec",
                     "source"=EXCLUDED."source",
                     "embedding"=NULL,
                     "model"=NULL,
                     "version"=0,
                     "embeddingStatus"='pending',
                     "embeddingError"=NULL,
                     "embeddingRetryCount"=0,
                     "digest"=EXCLUDED."digest",
                     "updatedAt"=now()""",
                (
                    video_id,
                    seq,
                    idea["title"],
                    idea["statement"],
                    idea["quote"] or None,
                    json.dumps(idea.get("scriptures") or []),
                    idea["start_sec"],
                    idea["end_sec"],
                    source,
                    idea["digest"],
                ),
            )

    def close(self):
        self.conn.close()


def _chunk_source(detail_raw) -> str:
    try:
        detail = json.loads(detail_raw)
        return detail.get("source") or "caption"
    except Exception:  # noqa: BLE001
        return "caption"


def process_video(db: Database, cfg: Config, row, llm: LLM):
    video_id = row[0]
    title = row[1]
    content = row[2]
    detail_raw = row[3]
    db.mark_processing(video_id)
    try:
        if cfg.max_transcript_chars > 0 and len(content) > cfg.max_transcript_chars:
            log.info("  trimming transcript to %d chars (debug knob)", cfg.max_transcript_chars)
            content = content[: cfg.max_transcript_chars]
        max_sec = 0.0
        try:
            max_sec = float(json.loads(detail_raw).get("maxSec") or 0.0)
        except Exception:  # noqa: BLE001
            pass
        if not max_sec:
            max_sec = parse_timestamps_markers(content)
        log.info("Processing %s - %s (%d chars, max_sec=%.1f)",
                 video_id, (title or "")[:70], len(content), max_sec)

        ideas = extract_ideas(llm, content, max_sec)
        if not ideas:
            raise RuntimeError("LLM returned no ideas for this transcript")
        for idea in ideas:
            idea["digest"] = _norm_idea_digest(idea)

        source = _chunk_source(detail_raw)
        db.clear_chunks(video_id)
        db.save_chunks(video_id, ideas, source)
        db.mark_completed(video_id, len(ideas), cfg)
        if cfg.log_ideas:
            log.info("  ideas:\n%s", json.dumps(ideas, indent=2, ensure_ascii=False))
        log.info("  completed: %d ideas (%s)", len(ideas), source)
    except Exception as e:  # noqa: BLE001
        log.error("  failed %s: %s", video_id, e)
        try:
            db.mark_failed(video_id, str(e))
        except Exception as mark_err:  # noqa: BLE001
            log.error("  could not mark failed: %s", mark_err)
        raise


def _norm_idea_digest(idea: dict) -> str:
    """Matches the content-worker digest: sha256 of 'statement|'."""
    import hashlib  # noqa: E402

    statement = idea.get("statement") or ""
    return hashlib.sha256(f"{statement}|".encode("utf-8")).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--once", action="store_true", help="Process one batch then exit")
    args, _ = parser.parse_known_args()

    cfg = Config(
        db_url=(os.environ.get("DIRECT_URL") or os.environ.get("DATABASE_URL") or "").strip()
    )
    if not cfg.db_url:
        log.error("DIRECT_URL (or DATABASE_URL) is required")
        sys.exit(1)

    db = Database(cfg)
    db.release_stale_processing()

    llm = LLM(cfg.ollama_url, cfg.ollama_model)
    log.info("LLM: %s (%s)", cfg.ollama_model, cfg.ollama_url)

    running = {"stop": False}

    def _stop(_sig, _frame):
        log.info("Shutdown signal received...")
        running["stop"] = True

    signal.signal(signal.SIGTERM, _stop)
    if hasattr(signal, "SIGINT"):
        signal.signal(signal.SIGINT, _stop)

    while not running["stop"]:
        db.requeue_stale_completed(cfg.chunk_version)
        rows = db.fetch_eligible(cfg)
        if not rows:
            if args.once:
                log.info("No eligible videos, exiting (--once).")
                break
            log.info("No pending chunk builds. Sleeping %ds...", cfg.poll_interval)
            for _ in range(cfg.poll_interval):
                if running["stop"]:
                    break
                time.sleep(1)
            continue

        log.info("Found %d eligible video(s).", len(rows))
        for row in rows:
            if running["stop"]:
                break
            try:
                process_video(db, cfg, row, llm)
            except Exception:  # noqa: BLE001
                pass  # already marked failed
        if args.once:
            break

    db.close()
    log.info("Chunker stopped.")


if __name__ == "__main__":
    main()