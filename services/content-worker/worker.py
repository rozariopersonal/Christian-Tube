"""Content search backfill worker.

Produces LLM-extracted "idea" chunks for English-language videos (Audio.com
audio -> captions/Parakeet transcript -> Qwen ideas -> e5-small embeddings)
and writes them to the VideoChunk table that powers content search.

Run loops keep entitlements honest: videos whose transcription is marked
'completed' without a matching content version or without any chunks are
re-queued, and stale 'processing' rows are released on boot.
"""

import argparse
import json
import logging
import os
import signal
import sys
import time
from dataclasses import dataclass, field

from llm import LLM, extract_ideas
from transcribe import ParakeetTranscriber, get_transcript, parse_duration

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("content-worker")


@dataclass
class Config:
    db_url: str = ""
    ollama_url: str = os.environ.get("OLLAMA_URL", "http://host.docker.internal:11434")
    ollama_model: str = os.environ.get("OLLAMA_MODEL", "qwen3:65b")
    content_version: int = int(os.environ.get("CONTENT_VERSION", "2"))
    poll_interval: int = int(os.environ.get("POLL_INTERVAL", "300"))
    batch_limit: int = int(os.environ.get("BATCH_LIMIT", "5"))
    max_retries: int = int(os.environ.get("MAX_RETRIES", "3"))
    max_transcript_chars: int = int(os.environ.get("MAX_TRANSCRIPT_CHARS", "0"))
    work_dir: str = os.environ.get("WORK_DIR", "/work")
    onnx_dir: str = os.environ.get("ONNX_DIR", "/model")
    priority_channel_ids: list[str] = field(
        default_factory=lambda: [
            c.strip()
            for c in os.environ.get("PRIORITY_CHANNEL_IDS", "UCpZG4Vl2tqg5cIfGMocI2Ag").split(",")
            if c.strip()
        ]
    )


def _embed_module():
    embedder_src = os.environ.get("EMBEDDER_SRC", "/opt/embedder")
    sys.path.insert(0, embedder_src)


class Database:
    def __init__(self, cfg: Config):
        import psycopg2  # noqa: E402
        from psycopg2.extras import RealDictCursor  # noqa: E402

        self.conn = psycopg2.connect(cfg.db_url)
        self.conn.autocommit = True
        self.cur = self.conn.cursor(cursor_factory=RealDictCursor)

    def ensure_schema(self):
        try:
            self.cur.execute('CREATE EXTENSION IF NOT EXISTS vector')
        except Exception as e:  # noqa: BLE001
            log.warning("extension step failed: %s", e)
        try:
            self.cur.execute(
                'ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "contentVersion" INTEGER DEFAULT 0'
            )
        except Exception as e:  # noqa: BLE001
            log.warning("contentVersion step failed: %s", e)
        try:
            self.cur.execute(
                """CREATE TABLE IF NOT EXISTS "VideoChunk" (
                     "id" SERIAL PRIMARY KEY,
                     "videoId" TEXT NOT NULL,
                     "seq" INTEGER NOT NULL,
                     "kind" TEXT NOT NULL DEFAULT 'idea',
                     "title" TEXT,
                     "content" TEXT NOT NULL,
                     "quoteText" TEXT,
                     "scriptureRefs" JSONB,
                     "startSec" DOUBLE PRECISION,
                     "endSec" DOUBLE PRECISION,
                     "source" TEXT NOT NULL DEFAULT 'caption',
                     "embedding" vector(384) NOT NULL,
                     "model" TEXT NOT NULL,
                     "version" INTEGER NOT NULL DEFAULT 0,
                     "digest" TEXT,
                     "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
                     "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
                     CONSTRAINT "VideoChunk_videoId_fkey"
                       FOREIGN KEY ("videoId") REFERENCES "Video"("id")
                       ON DELETE CASCADE ON UPDATE CASCADE
                   );
                   CREATE UNIQUE INDEX IF NOT EXISTS "VideoChunk_videoId_seq_key"
                     ON "VideoChunk"("videoId", "seq");
                   CREATE INDEX IF NOT EXISTS "VideoChunk_model_version_idx"
                     ON "VideoChunk"("model", "version");
                   CREATE INDEX IF NOT EXISTS "VideoChunk_embedding_hnsw_idx"
                     ON "VideoChunk" USING hnsw ("embedding" vector_cosine_ops)
                     WITH (m = 16, ef_construction = 64);"""
            )
        except Exception as e:  # noqa: BLE001
            log.warning("VideoChunk table step failed: %s", e)
        try:
            self.cur.execute(
                'ALTER TABLE "VideoChunk" ADD COLUMN IF NOT EXISTS "scriptureRefs" JSONB'
            )
        except Exception as e:  # noqa: BLE001
            log.warning("VideoChunk scriptureRefs step failed: %s", e)

    def release_stale_processing(self):
        try:
            self.cur.execute(
                """UPDATE "Video" SET "transcriptionStatus"='pending'
                   WHERE "transcriptionStatus"='processing'"""
            )
        except Exception as e:  # noqa: BLE001
            log.warning("release_stale_processing failed: %s", e)

    def requeue_stale_completed(self, target_version: int):
        try:
            self.cur.execute(
                """UPDATE "Video"
                   SET "transcriptionStatus"='pending',
                       "transcriptionRetryCount"=0,
                       "lastTranscriptionError"=NULL
                   WHERE "transcriptionStatus"='completed'
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
            """SELECT v.id, v.title, v.description, v."audioUrl", v.duration,
                      c.name AS channel
               FROM "Video" v
               JOIN "Channel" c ON c.id = v."channelId"
               WHERE c."isActive" = true
                 AND c.language = 'English'
                 AND v.type = 'VIDEO'
                 AND v."audioUploadStatus" = 'completed'
                 AND v."audioUrl" IS NOT NULL
                 AND (v."transcriptionStatus" IS NULL
                      OR v."transcriptionStatus" IN ('pending', 'failed'))
                 AND (v."transcriptionRetryCount" IS NULL
                      OR v."transcriptionRetryCount" < %s)
               ORDER BY
                 CASE WHEN v."channelId" = ANY(%s::text[]) THEN 0 ELSE 1 END,
                 v."publishedAt" DESC
               LIMIT %s""",
            (cfg.max_retries, cfg.priority_channel_ids, cfg.batch_limit),
        )
        return self.cur.fetchall()

    def mark_processing(self, video_id: str):
        self.cur.execute(
            """UPDATE "Video" SET "transcriptionStatus"='processing',
                      "transcriptionProgress"=5, "lastTranscriptionError"=NULL
               WHERE "id"=%s""",
            (video_id,),
        )

    def mark_completed(
        self,
        video_id: str,
        transcript: str,
        source: str,
        idea_count: int,
        max_sec: float,
        cfg: Config,
    ):
        detail = {
            "source": source,
            "ideas": idea_count,
            "maxSec": round(max_sec, 2),
            "contentVersion": cfg.content_version,
        }
        self.cur.execute(
            """UPDATE "Video" SET "transcriptionStatus"='completed',
                      "transcriptionProgress"=100,
                      "content"=%s,
                      "contentVersion"=%s,
                      "transcriptionDetail"=%s,
                      "lastTranscriptionError"=NULL,
                      "transcriptionRetryCount"=0
               WHERE "id"=%s""",
            (transcript, cfg.content_version, json.dumps(detail), video_id),
        )

    def mark_failed(self, video_id: str, error: str):
        self.cur.execute(
            """UPDATE "Video" SET "transcriptionStatus"='failed',
                      "lastTranscriptionError"=%s,
                      "transcriptionRetryCount"="transcriptionRetryCount"+1
               WHERE "id"=%s""",
            (error[:2000], video_id),
        )

    def clear_chunks(self, video_id: str):
        self.cur.execute('DELETE FROM "VideoChunk" WHERE "videoId"=%s', (video_id,))

    def save_chunks(self, video_id: str, ideas: list, vectors: list, source: str, cfg: Config, digest_fn):
        from model_contract import EMBEDDING_VERSION, MODEL_ID  # noqa: E402

        for seq, (idea, vector) in enumerate(zip(ideas, vectors)):
            vector_literal = f"[{','.join(str(round(float(x), 6)) for x in vector)}]"
            digest = digest_fn(idea["statement"])
            self.cur.execute(
                """INSERT INTO "VideoChunk"
                      ("videoId","seq","kind","title","content","quoteText",
                       "scriptureRefs","startSec","endSec","source","embedding","model","version","digest",
                       "createdAt","updatedAt")
                   VALUES (%s,%s,'idea',%s,%s,%s,%s,%s,%s,%s,%s::vector,%s,%s,%s,now(),now())
                   ON CONFLICT ("videoId","seq") DO UPDATE SET
                     "title"=EXCLUDED."title",
                     "content"=EXCLUDED."content",
                     "quoteText"=EXCLUDED."quoteText",
                     "scriptureRefs"=EXCLUDED."scriptureRefs",
                     "startSec"=EXCLUDED."startSec",
                     "endSec"=EXCLUDED."endSec",
                     "source"=EXCLUDED."source",
                     "embedding"=EXCLUDED."embedding",
                     "model"=EXCLUDED."model",
                     "version"=EXCLUDED."version",
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
                    vector_literal,
                    MODEL_ID,
                    EMBEDDING_VERSION,
                    digest,
                ),
            )

    def close(self):
        self.conn.close()


def process_video(db: Database, cfg: Config, row: dict, llm, transcriber, work_dir, embed_fn):
    from model_contract import PASSAGE_PREFIX, content_hash  # noqa: E402

    video_id = row["id"]
    log.info("Processing %s - %s (%s)", video_id, row["title"][:70], row.get("channel"))
    db.mark_processing(video_id)
    try:
        result = get_transcript(video_id, row["audioUrl"], work_dir, transcriber)
        max_sec = result.max_sec or (parse_duration(row.get("duration")) or 0.0)
        transcript = result.transcript
        if cfg.max_transcript_chars > 0 and len(transcript) > cfg.max_transcript_chars:
            log.info("  trimming transcript to %d chars (debug knob)", cfg.max_transcript_chars)
            transcript = transcript[: cfg.max_transcript_chars]
        ideas = extract_ideas(llm, transcript, max_sec)
        if not ideas:
            raise RuntimeError("LLM returned no ideas for this transcript")
        texts = [PASSAGE_PREFIX + i["statement"] for i in ideas]
        vectors = embed_fn(texts)
        if len(vectors) != len(ideas):
            raise RuntimeError("embedding count mismatch")
        db.clear_chunks(video_id)
        db.save_chunks(video_id, ideas, vectors, result.source, cfg, content_hash)
        db.mark_completed(video_id, result.transcript, result.source, len(ideas), max_sec, cfg)
        log.info(
            "  completed: %d ideas (%d chars, %s)",
            len(ideas),
            len(result.transcript),
            result.source,
        )
    except Exception as e:  # noqa: BLE001
        log.error("  failed %s: %s", video_id, e)
        try:
            db.mark_failed(video_id, str(e))
        except Exception as mark_err:  # noqa: BLE001
            log.error("  could not mark failed: %s", mark_err)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--once", action="store_true", help="Process one batch then exit")
    parser.add_argument("--no-captions", action="store_true", help="Force Parakeet ASR (skip captions)")
    args, _ = parser.parse_known_args()

    cfg = Config(
        db_url=(os.environ.get("DIRECT_URL") or os.environ.get("DATABASE_URL") or "").strip()
    )
    if not cfg.db_url:
        log.error("DIRECT_URL (or DATABASE_URL) is required")
        sys.exit(1)

    _embed_module()
    from model import embed_texts

    if args.no_captions:
        import transcribe as _t

        _t.USE_CAPTIONS = False

    os.makedirs(cfg.work_dir, exist_ok=True)
    db = Database(cfg)
    db.ensure_schema()
    db.release_stale_processing()

    llm = LLM(cfg.ollama_url, cfg.ollama_model)
    log.info("LLM: %s (%s)", cfg.ollama_model, cfg.ollama_url)

    transcriber = None  # lazily load NeMo only when captions are missing

    running = {"stop": False}

    def _stop(_sig, _frame):
        log.info("Shutdown signal received...")
        running["stop"] = True

    signal.signal(signal.SIGTERM, _stop)
    if hasattr(signal, "SIGINT"):
        signal.signal(signal.SIGINT, _stop)

    while not running["stop"]:
        db.requeue_stale_completed(cfg.content_version)
        rows = db.fetch_eligible(cfg)
        if not rows:
            if args.once:
                log.info("No eligible videos, exiting (--once).")
                break
            log.info("No pending English videos. Sleeping %ds...", cfg.poll_interval)
            for _ in range(cfg.poll_interval):
                if running["stop"]:
                    break
                time.sleep(1)
            continue

        log.info("Found %d eligible video(s).", len(rows))
        for row in rows:
            if running["stop"]:
                break
            if transcriber is None:
                transcriber = ParakeetTranscriber()
            try:
                process_video(db, cfg, row, llm, transcriber, cfg.work_dir, embed_texts)
            except Exception:  # noqa: BLE001
                pass  # already marked failed
        if args.once:
            break

    db.close()
    log.info("Content worker stopped.")


if __name__ == "__main__":
    main()