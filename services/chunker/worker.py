"""Semantic Chunker Daemon: Groups sentences into VideoIdeas using sentence embeddings.

1. Reads sentences from Neon ("VideoSentence") whose embeddings are completed.
2. Reads vectors from Local Postgres ("SentenceEmbedding").
3. Detects idea boundaries using semantic cosine similarity valley detection.
4. Generates a concise title and summary for each idea via local Ollama.
5. Persists VideoIdea rows in Neon and updates VideoSentence.ideaId.
"""

import argparse
import json
import logging
import os
import signal
import sys
import time
import urllib.parse
from dataclasses import dataclass, field

import psycopg2

from llm import LLM, segment_sentences_by_similarity, summarize_idea

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("chunker")

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


@dataclass
class Config:
    db_url: str = ""
    local_db_url: str = ""
    ollama_url: str = os.environ.get("OLLAMA_URL", "http://host.docker.internal:11434")
    ollama_model: str = os.environ.get("OLLAMA_MODEL", "gemma3:4b")
    chunk_version: int = int(os.environ.get("CHUNK_VERSION", "2"))
    poll_interval: int = int(os.environ.get("POLL_INTERVAL", "300"))
    batch_limit: int = int(os.environ.get("BATCH_LIMIT", "10"))
    max_retries: int = int(os.environ.get("MAX_RETRIES", "3"))
    min_sentences_per_idea: int = int(os.environ.get("MIN_SENTENCES_PER_IDEA", "5"))
    max_sentences_per_idea: int = int(os.environ.get("MAX_SENTENCES_PER_IDEA", "25"))


class NeonDatabase:
    def __init__(self, url: str):
        self.conn = psycopg2.connect(sanitize_db_url(url), connect_timeout=30)
        self.conn.autocommit = True
        self.cur = self.conn.cursor()

    def release_stale_processing(self):
        try:
            self.cur.execute(
                """UPDATE "Video" SET "chunkStatus"='pending'
                   WHERE "chunkStatus"='processing'"""
            )
            if self.cur.rowcount:
                log.info("  released %d stale chunk 'processing' row(s)", self.cur.rowcount)
        except Exception as e:
            log.warning("release_stale_processing warning: %s", e)

    def fetch_eligible_videos(self, limit: int = 10):
        self.cur.execute(
            """
            SELECT v.id, v.title
            FROM "Video" v
            JOIN "Channel" c ON c.id = v."channelId"
            WHERE c."isActive" = true
              AND v."transcriptionStatus" = 'completed'
              AND (v."chunkStatus" IS NULL OR v."chunkStatus" IN ('pending', 'failed'))
              AND (v."chunkRetryCount" IS NULL OR v."chunkRetryCount" < 3)
              AND EXISTS (
                SELECT 1 FROM "VideoSentence" vs
                WHERE vs."videoId" = v.id
              )
              AND NOT EXISTS (
                SELECT 1 FROM "VideoSentence" vs
                WHERE vs."videoId" = v.id AND vs."embeddingStatus" != 'completed'
              )
            ORDER BY v."publishedAt" DESC
            LIMIT %s
            """,
            (limit,),
        )
        return self.cur.fetchall()

    def mark_processing(self, video_id: str):
        self.cur.execute(
            """UPDATE "Video" SET "chunkStatus"='processing', "chunkError"=NULL WHERE "id"=%s""",
            (video_id,),
        )

    def mark_completed(self, video_id: str, idea_count: int, version: int):
        self.cur.execute(
            """UPDATE "Video" SET "chunkStatus"='completed', "chunkError"=NULL,
                      "chunkRetryCount"=0, "contentVersion"=%s
               WHERE "id"=%s""",
            (version, video_id),
        )

    def mark_failed(self, video_id: str, error: str):
        self.cur.execute(
            """UPDATE "Video" SET "chunkStatus"='failed',
                      "chunkError"=%s,
                      "chunkRetryCount"=COALESCE("chunkRetryCount", 0) + 1
               WHERE "id"=%s""",
            (error[:2000], video_id),
        )

    def fetch_sentences(self, video_id: str) -> list[dict]:
        self.cur.execute(
            """
            SELECT id, seq, text, "startSec", "endSec"
            FROM "VideoSentence"
            WHERE "videoId" = %s
            ORDER BY seq ASC
            """,
            (video_id,),
        )
        rows = self.cur.fetchall()
        return [
            {
                "id": r[0],
                "seq": r[1],
                "text": r[2],
                "startSec": float(r[3]),
                "endSec": float(r[4]),
            }
            for r in rows
        ]

    def save_ideas_and_link_sentences(
        self, video_id: str, ideas_with_sentences: list[tuple[dict, list[dict]]]
    ) -> None:
        self.cur.execute('DELETE FROM "VideoIdea" WHERE "videoId" = %s', (video_id,))
        for seq, (idea_meta, sentences) in enumerate(ideas_with_sentences):
            idea_id = f"{video_id}_i{seq}"
            start_sec = sentences[0]["startSec"]
            end_sec = sentences[-1]["endSec"]
            sentence_count = len(sentences)
            title = idea_meta.get("title") or f"Idea {seq + 1}"
            summary = idea_meta.get("summary") or ""

            self.cur.execute(
                """
                INSERT INTO "VideoIdea"
                  ("id", "videoId", "seq", "title", "summary", "startSec", "endSec", "sentenceCount", "createdAt", "updatedAt")
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, now(), now())
                ON CONFLICT ("videoId", "seq") DO UPDATE SET
                  "title" = EXCLUDED."title",
                  "summary" = EXCLUDED."summary",
                  "startSec" = EXCLUDED."startSec",
                  "endSec" = EXCLUDED."endSec",
                  "sentenceCount" = EXCLUDED."sentenceCount",
                  "updatedAt" = now()
                """,
                (idea_id, video_id, seq, title, summary, start_sec, end_sec, sentence_count),
            )

            sentence_ids = [s["id"] for s in sentences]
            self.cur.execute(
                """UPDATE "VideoSentence" SET "ideaId" = %s WHERE id = ANY(%s)""",
                (idea_id, sentence_ids),
            )

    def close(self):
        try:
            self.cur.close()
            self.conn.close()
        except Exception:
            pass


class LocalDatabase:
    def __init__(self, url: str):
        self.conn = psycopg2.connect(sanitize_db_url(url), connect_timeout=30)
        self.conn.autocommit = True
        self.cur = self.conn.cursor()

    def fetch_embeddings(self, video_id: str) -> dict[str, list[float]]:
        self.cur.execute(
            """
            SELECT "sentenceId", "embedding"::text
            FROM "SentenceEmbedding"
            WHERE "videoId" = %s
            ORDER BY seq ASC
            """,
            (video_id,),
        )
        result: dict[str, list[float]] = {}
        for row in self.cur.fetchall():
            s_id, vec_str = row
            if vec_str:
                vec = json.loads(vec_str)
                result[s_id] = vec
        return result

    def close(self):
        try:
            self.cur.close()
            self.conn.close()
        except Exception:
            pass


def process_video_ideas(
    neon_db: NeonDatabase,
    local_db: LocalDatabase,
    cfg: Config,
    video_id: str,
    title: str,
    llm: LLM | None,
) -> None:
    neon_db.mark_processing(video_id)
    try:
        sentences = neon_db.fetch_sentences(video_id)
        if not sentences:
            raise RuntimeError(f"No sentences found for video {video_id}")

        embedding_map = local_db.fetch_embeddings(video_id)
        if len(embedding_map) < len(sentences):
            raise RuntimeError(
                f"Missing embeddings: {len(embedding_map)}/{len(sentences)} available"
            )

        vectors = [embedding_map[s["id"]] for s in sentences]

        # 1. Segment sentences into contiguous idea blocks
        groups = segment_sentences_by_similarity(
            sentences,
            vectors,
            min_sentences=cfg.min_sentences_per_idea,
            max_sentences=cfg.max_sentences_per_idea,
        )

        log.info(
            "Video %s (%s): %d sentences segmented into %d ideas",
            video_id,
            (title or "")[:50],
            len(sentences),
            len(groups),
        )

        # 2. Summarize each idea block
        ideas_with_sentences: list[tuple[dict, list[dict]]] = []
        for seq, group in enumerate(groups):
            meta = summarize_idea(llm, group)
            log.info("  Idea %d [%.1fs -> %.1fs, %d sents]: %s",
                     seq + 1, group[0]["startSec"], group[-1]["endSec"], len(group), meta["title"])
            ideas_with_sentences.append((meta, group))

        # 3. Persist VideoIdea and link sentences in Neon
        neon_db.save_ideas_and_link_sentences(video_id, ideas_with_sentences)
        neon_db.mark_completed(video_id, len(groups), cfg.chunk_version)
        log.info("Completed idea chunking for video %s (%d ideas saved)", video_id, len(groups))

    except Exception as e:
        log.error("Failed chunking video %s: %s", video_id, e)
        neon_db.mark_failed(video_id, str(e))
        raise


def main():
    parser = argparse.ArgumentParser(description="Semantic Idea Chunker Daemon")
    parser.add_argument("--once", action="store_true", help="Process one batch and exit")
    parser.add_argument("--poll-interval", type=int, default=300)
    parser.add_argument("--batch-limit", type=int, default=10)
    args = parser.parse_args()

    neon_url = (os.environ.get("DIRECT_URL") or os.environ.get("DATABASE_URL") or "").strip()
    if not neon_url:
        log.error("DIRECT_URL (or DATABASE_URL) is required in environment")
        sys.exit(1)

    local_url = os.environ.get(
        "LOCAL_DATABASE_URL",
        "postgresql://postgres:postgres@db:5432/christiantube?schema=public",
    ).strip()

    cfg = Config(
        db_url=neon_url,
        local_db_url=local_url,
        poll_interval=int(os.environ.get("POLL_INTERVAL", args.poll_interval)),
        batch_limit=int(os.environ.get("BATCH_LIMIT", args.batch_limit)),
    )

    neon_db = NeonDatabase(cfg.db_url)
    neon_db.release_stale_processing()

    local_db = LocalDatabase(cfg.local_db_url)

    llm = None
    try:
        llm = LLM(cfg.ollama_url, cfg.ollama_model)
        log.info("Ollama LLM configured: %s (%s)", cfg.ollama_model, cfg.ollama_url)
    except Exception as e:
        log.warning("Ollama LLM unavailable (%s). Will use heuristic summaries.", e)

    running = {"stop": False}

    def _stop(_sig, _frame):
        log.info("Shutdown signal received...")
        running["stop"] = True

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    log.info("Chunker started. Polling for videos with completed sentence embeddings...")

    while not running["stop"]:
        neon_db.release_stale_processing()
        rows = neon_db.fetch_eligible_videos(limit=cfg.batch_limit)
        if not rows:
            if args.once:
                log.info("No eligible videos, exiting (--once).")
                break
            log.info("No pending videos ready for idea chunking. Sleeping %ds...", cfg.poll_interval)
            for _ in range(cfg.poll_interval):
                if running["stop"]:
                    break
                time.sleep(1)
            continue

        log.info("Found %d video(s) ready for idea chunking.", len(rows))
        for row in rows:
            if running["stop"]:
                break
            video_id, title = row
            try:
                process_video_ideas(neon_db, local_db, cfg, video_id, title, llm)
            except Exception:
                pass

        if args.once:
            break

    neon_db.close()
    local_db.close()
    log.info("Chunker stopped.")


if __name__ == "__main__":
    main()