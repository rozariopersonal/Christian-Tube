#!/usr/bin/env python3
"""Transcription daemon: captions-first / Parakeet ASR -> Transcription table.

Polls the database for English videos that lack a transcript, tries YouTube
captions first, and falls back to Audio.com audio decoded with ffmpeg and
transcribed by NVIDIA Parakeet (NeMo). The timestamped transcript is written to
the ``Transcription`` table and the row's transcription status is marked
``completed`` on the shared ``VideoPipelineStatus`` row (``transcription`` JSONB).

This service ONLY transcribes. Chunking (LLM idea extraction) and embedding are
separate daemons that consume the transcript straight from the database:
    services/transcriber  -> Transcription                    (this daemon)
    services/chunker      -> Transcription -> VideoChunk rows (no vectors)
    services/embedder     -> VideoChunk.embedding (async fill-in)
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

from transcribe import ParakeetTranscriber, get_transcript, parse_duration

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("transcriber")


@dataclass
class Config:
    db_url: str = ""
    content_version: int = int(os.environ.get("CONTENT_VERSION", "2"))
    poll_interval: int = int(os.environ.get("POLL_INTERVAL", "300"))
    batch_limit: int = int(os.environ.get("BATCH_LIMIT", "5"))
    max_retries: int = int(os.environ.get("MAX_RETRIES", "3"))
    work_dir: str = os.environ.get("WORK_DIR", "/work")
    use_captions: bool = os.environ.get("USE_CAPTIONS", "true").lower() != "false"
    priority_channel_ids: list[str] = field(
        default_factory=lambda: [
            c.strip()
            for c in os.environ.get("PRIORITY_CHANNEL_IDS", "UCpZG4Vl2tqg5cIfGMocI2Ag").split(",")
            if c.strip()
        ]
    )


class Database:
    def __init__(self, db_url: str):
        self.conn = psycopg2.connect(db_url)
        self.conn.autocommit = True
        self.cur = self.conn.cursor()
        self.ensure_schema()

    def ensure_schema(self):
        steps = [
            (
                "VideoPipelineStatus table",
                """CREATE TABLE IF NOT EXISTS "VideoPipelineStatus" (
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
                   );""",
            ),
            (
                "Transcription table",
                """CREATE TABLE IF NOT EXISTS "Transcription" (
                     "videoId" TEXT NOT NULL PRIMARY KEY,
                     "content" TEXT NOT NULL,
                     "source" TEXT NOT NULL DEFAULT 'parakeet',
                     "contentVersion" INTEGER NOT NULL DEFAULT 0,
                     "wordCount" INTEGER,
                     "segmentCount" INTEGER,
                     "maxSec" DOUBLE PRECISION,
                     "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
                     "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
                     CONSTRAINT "Transcription_videoId_fkey"
                       FOREIGN KEY ("videoId") REFERENCES "Video"("id")
                       ON DELETE CASCADE ON UPDATE CASCADE
                   );
                   CREATE INDEX IF NOT EXISTS "Transcription_contentVersion_idx"
                     ON "Transcription"("contentVersion");""",
            ),
        ]
        for name, sql in steps:
            try:
                self.cur.execute(sql)
            except Exception as e:  # noqa: BLE001
                log.warning("%s step failed: %s", name, e)

    def release_stale_processing(self):
        try:
            self.cur.execute(
                """UPDATE "VideoPipelineStatus"
                   SET "transcription" = COALESCE("transcription", '{}'::jsonb) || '{"status":"pending"}'::jsonb,
                       "updatedAt" = CURRENT_TIMESTAMP
                   WHERE "transcription"->>'status' = 'processing'"""
            )
            if self.cur.rowcount:
                log.info("  released %d stale 'processing' row(s)", self.cur.rowcount)
        except Exception as e:  # noqa: BLE001
            log.warning("release_stale_processing failed: %s", e)

    def fetch_eligible(self, cfg: Config):
        self.cur.execute(
            """SELECT v.id, v.title, v.description, v."audioUrl", v.duration
               FROM "Video" v
               JOIN "Channel" c ON c.id = v."channelId"
               LEFT JOIN "VideoPipelineStatus" s ON s."videoId" = v.id
               WHERE c."isActive" = true
                 AND c.language = 'English'
                 AND v.type = 'VIDEO'
                 AND COALESCE(s.ingest->>'status', 'pending') = 'completed'
                 AND v."audioUrl" IS NOT NULL
                 AND (COALESCE(s.transcription->>'status', 'pending') IS NULL
                      OR COALESCE(s.transcription->>'status', 'pending') IN ('pending', 'failed'))
                 AND (NULLIF(s.transcription->>'retryCount', '')::integer IS NULL
                      OR NULLIF(s.transcription->>'retryCount', '')::integer < %s)
               ORDER BY
                 CASE WHEN v."channelId" = ANY(%s::text[]) THEN 0 ELSE 1 END,
                 v."publishedAt" DESC
               LIMIT %s""",
            (cfg.max_retries, cfg.priority_channel_ids, cfg.batch_limit),
        )
        return self.cur.fetchall()

    def mark_processing(self, video_id: str):
        self.cur.execute(
            """INSERT INTO "VideoPipelineStatus" ("videoId", "transcription", "updatedAt")
               VALUES (%s, %s::jsonb, CURRENT_TIMESTAMP)
               ON CONFLICT ("videoId") DO UPDATE SET
                 "transcription" = COALESCE("VideoPipelineStatus"."transcription", '{}'::jsonb) || EXCLUDED."transcription",
                 "updatedAt" = CURRENT_TIMESTAMP""",
            (video_id, json.dumps({"status": "processing", "progress": 5, "lastError": None})),
        )

    def mark_completed(self, video_id: str, transcript: str, source: str, max_sec: float, cfg: Config):
        detail = {
            "source": source,
            "maxSec": round(max_sec, 2),
            "contentVersion": cfg.content_version,
        }
        self.cur.execute(
            """INSERT INTO "Transcription"
                 ("videoId", "content", "source", "contentVersion", "maxSec", "createdAt", "updatedAt")
               VALUES (%s, %s, %s, %s, %s, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
               ON CONFLICT ("videoId") DO UPDATE SET
                 "content"=EXCLUDED."content",
                 "source"=EXCLUDED."source",
                 "contentVersion"=EXCLUDED."contentVersion",
                 "maxSec"=EXCLUDED."maxSec",
                 "updatedAt"=CURRENT_TIMESTAMP""",
            (video_id, transcript, source, cfg.content_version, round(max_sec, 2)),
        )
        self.cur.execute(
            """INSERT INTO "VideoPipelineStatus" ("videoId", "contentVersion", "transcription", "chunk", "updatedAt")
               VALUES (%s, %s, %s::jsonb, %s::jsonb, CURRENT_TIMESTAMP)
               ON CONFLICT ("videoId") DO UPDATE SET
                 "contentVersion" = EXCLUDED."contentVersion",
                 "transcription" = COALESCE("VideoPipelineStatus"."transcription", '{}'::jsonb) || EXCLUDED."transcription",
                 "chunk" = COALESCE("VideoPipelineStatus"."chunk", '{}'::jsonb) || EXCLUDED."chunk",
                 "updatedAt" = CURRENT_TIMESTAMP""",
            (video_id, cfg.content_version,
             json.dumps({"status": "completed", "progress": 100, "retryCount": 0, "detail": detail, "lastError": None}),
             json.dumps({"status": "pending", "error": None, "retryCount": 0})),
        )

    def mark_failed(self, video_id: str, error: str):
        self.cur.execute(
            """INSERT INTO "VideoPipelineStatus" ("videoId", "transcription", "updatedAt")
               VALUES (%s, jsonb_build_object('status', 'failed', 'lastError', %s, 'retryCount', 1), CURRENT_TIMESTAMP)
               ON CONFLICT ("videoId") DO UPDATE SET
                 "transcription" = jsonb_build_object(
                   'status', 'failed',
                   'lastError', %s,
                   'retryCount', COALESCE(NULLIF("VideoPipelineStatus"."transcription"->>'retryCount', '')::integer, 0) + 1),
                 "updatedAt" = CURRENT_TIMESTAMP""",
            (video_id, error[:2000], error[:2000]),
        )

    def close(self):
        self.conn.close()


def process_video(db: Database, cfg: Config, row: tuple, transcriber: ParakeetTranscriber):
    video_id, title, _desc, audio_url, duration = row
    try:
        db.mark_processing(video_id)
        log.info("Processing %s - %s", video_id, (title or "")[:70])
        result = get_transcript(video_id, audio_url, cfg.work_dir, transcriber)
        max_sec = result.max_sec or (parse_duration(duration) or 0.0)
        db.mark_completed(video_id, result.transcript, result.source, max_sec, cfg)
        log.info(
            "  completed: %d chars via %s (max_sec=%.1f)",
            len(result.transcript),
            result.source,
            max_sec,
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

    if args.no_captions:
        import transcribe as _t

        _t.USE_CAPTIONS = False

    os.makedirs(cfg.work_dir, exist_ok=True)
    db = Database(cfg.db_url)
    db.release_stale_processing()

    transcriber = None  # lazily load NeMo only when captions are missing

    running = {"stop": False}

    def _stop(_sig, _frame):
        log.info("Shutdown signal received...")
        running["stop"] = True

    signal.signal(signal.SIGTERM, _stop)
    if hasattr(signal, "SIGINT"):
        signal.signal(signal.SIGINT, _stop)

    while not running["stop"]:
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
                process_video(db, cfg, row, transcriber)
            except Exception:  # noqa: BLE001
                pass  # already marked failed
        if args.once:
            break

    db.close()
    log.info("Transcriber stopped.")


if __name__ == "__main__":
    main()