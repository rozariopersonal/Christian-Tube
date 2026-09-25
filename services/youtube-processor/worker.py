#!/usr/bin/env python3
"""
YouTube Video Processor for ChristianApp.

Monitors the ChristianApp PostgreSQL database, extracts audio from
active ChristianApp channel videos (eligibility per the SQL in
eligible_videos.sql), uploads them to Audio.com with rich metadata, and
registers them directly in the Neon audio catalog (AudioSeries/AudioTrack)
so the DB-first mobile app picks them up on its next query.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import re
import signal
import subprocess
import sys
import tempfile
import time
import urllib.parse
from pathlib import Path
from typing import Any

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("youtube-processor")


# --------------------------------------------------------------------------- #
# Permanent-failure classification
# --------------------------------------------------------------------------- #
# A failure matching ANY marker is terminal: the source video is gone/walled on
# YouTube, so re-downloading will never succeed. Marking it 'dead' stops the
# daily retry loop from burning attempts on it forever. Everything else keeps
# the per-day budget (transient throttles, JS-runtime hiccups, etc.).
PERMANENT_ERROR_MARKERS: tuple[str, ...] = (
    "this video is not available",
    "video unavailable",
    "has been removed by the uploader",
    "this video has been removed",
    "this video is private",
    "video is private",
    "private video",
    "sign in to confirm your age",
    "video is age-restricted",
    "not available in your country",
    "may not be available in your country",
    "content is not available",
    "unsupported url",
    "this video does not exist",
    "the video is currently unavailable",
    "invalid video id",
    "video id not found",
    "no video id",
    "video not found",
    "isn't available for playback",
    "playback on other websites",
    "watch on youtube",
    "copyright",
    "taken down",
)


def is_permanent_failure(error_text: str) -> bool:
    """True when the error indicates the source video can never be re-downloaded."""
    if not error_text:
        return False
    lowered = error_text.lower()
    return any(marker in lowered for marker in PERMANENT_ERROR_MARKERS)


# --------------------------------------------------------------------------- #
# Configuration
# --------------------------------------------------------------------------- #
class Config:
    def __init__(
        self,
        database_url: str,
        audio_com_token: str,
        work_dir: Path,
        poll_interval: int = 300,
        batch_limit: int = 5,
        max_retries: int = 3,
        redo: bool = False,
        retry_failed: bool = False,
        once: bool = False,
        video_id: str | None = None,
        channel_filters: list[str] | None = None,
        priority_channel_ids: list[str] | None = None,
        purge_audiocom: bool = False,
    ):
        self.database_url = database_url
        self.audio_com_token = audio_com_token
        self.work_dir = work_dir
        self.poll_interval = poll_interval
        self.batch_limit = batch_limit
        self.max_retries = max_retries
        self.redo = redo
        self.retry_failed = retry_failed
        self.once = once
        self.video_id = video_id
        self.channel_filters = channel_filters
        self.priority_channel_ids = priority_channel_ids
        self.purge_audiocom = purge_audiocom


def load_config(args: argparse.Namespace) -> Config:
    # Auto-load env files if present
    env_dirs = [Path("envs"), Path("../envs"), Path("../../envs"), Path(".")]
    for ed in env_dirs:
        for fname in ["common.env", "neon.env", "local.env", ".processor.env"]:
            candidate = ed / fname
            if candidate.exists():
                try:
                    with open(candidate, "r", encoding="utf-8") as f:
                        for line in f:
                            line = line.strip()
                            if line and not line.startswith("#") and "=" in line:
                                k, v = line.split("=", 1)
                                os.environ.setdefault(k.strip(), v.strip())
                except Exception:
                    pass

    def _env(name: str, default: str = "") -> str:
        return os.environ.get(name, default).strip()

    db_url = _env("DATABASE_URL")
    audio_token = _env("AUDIO_COM_TOKEN")

    if not db_url:
        log.error("DATABASE_URL is required in environment.")
        sys.exit(1)

    if not audio_token:
        log.error("AUDIO_COM_TOKEN is required in environment.")
        sys.exit(1)

    work_dir = Path(_env("WORK_DIR", "/work" if os.path.exists("/work") else "./scratch_work"))
    work_dir.mkdir(parents=True, exist_ok=True)

    # Parse channel filters (comma-separated CLI flag or CHANNELS env var)
    channel_filters = None
    raw_channels = getattr(args, 'channels', None) or _env("CHANNELS")
    if raw_channels:
        channel_filters = [c.strip() for c in raw_channels.split(',') if c.strip()]

    # Parse priority channel IDs (comma-separated PRIORITY_CHANNEL_IDS env var)
    priority_channel_ids = None
    raw_priority = _env("PRIORITY_CHANNEL_IDS")
    if raw_priority:
        priority_channel_ids = [c.strip() for c in raw_priority.split(",") if c.strip()]

    return Config(
        database_url=db_url,
        audio_com_token=audio_token,
        work_dir=work_dir,
        poll_interval=int(_env("POLL_INTERVAL", "300")),
        batch_limit=int(args.limit or _env("BATCH_LIMIT", "5")),
        max_retries=int(_env("MAX_RETRIES", "3")),
        redo=args.redo,
        retry_failed=args.retry_failed,
        once=args.once,
        video_id=args.video_id or None,
        channel_filters=channel_filters,
        priority_channel_ids=priority_channel_ids,
        purge_audiocom=getattr(args, 'purge_audiocom', False),
    )


# --------------------------------------------------------------------------- #
# Database Layer
# --------------------------------------------------------------------------- #
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


class Database:
    def __init__(self, url: str):
        import psycopg2

        self.conn = psycopg2.connect(sanitize_db_url(url), connect_timeout=30)
        self.conn.autocommit = True
        self.cur = self.conn.cursor()
        self._ensure_schema()

    def _eligible_sql(self) -> str:
        """Reads the eligible-videos query from disk so it can be edited at any time."""
        env_path = os.environ.get("ELIGIBLE_SQL_PATH", "").strip()
        path = Path(env_path) if env_path else Path(__file__).resolve().parent / "eligible_videos.sql"
        try:
            return path.read_text(encoding="utf-8")
        except OSError as e:
            raise RuntimeError(f"Could not read eligible-videos SQL from {path}: {e}")

    def _ensure_schema(self) -> None:
        """Ensure audioUrl/upload columns on Video and the audio catalog tables exist.

        The audio catalog is authored directly in PostgreSQL by this worker, so
        it ensures AudioSeries/AudioTrack are present even on a database that
        has not run Prisma migrations yet. Table bodies mirror prisma/schema.prisma.
        """
        try:
            self.cur.execute("""
                ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "audioUrl" TEXT;
                ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "audioUploadStatus" TEXT DEFAULT 'pending';
                ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "audioRetryCount" INT DEFAULT 0;
                ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "audioLastRetryAt" TIMESTAMPTZ;
                ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "audioLastError" TEXT;
            """)
            self.cur.execute("""
                CREATE TABLE IF NOT EXISTS "AudioSeries" (
                    "id" TEXT PRIMARY KEY,
                    "title" TEXT NOT NULL,
                    "description" TEXT,
                    "speaker" TEXT,
                    "category" TEXT,
                    "language" TEXT,
                    "coverUrl" TEXT,
                    "channelId" TEXT,
                    "trackCount" INTEGER NOT NULL DEFAULT 0,
                    "latestPublishedAt" TIMESTAMPTZ,
                    "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    "createdAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
                );
                CREATE TABLE IF NOT EXISTS "AudioTrack" (
                    "id" TEXT PRIMARY KEY,
                    "seriesId" TEXT NOT NULL,
                    "title" TEXT NOT NULL,
                    "speaker" TEXT,
                    "durationSeconds" INTEGER NOT NULL DEFAULT 0,
                    "audioUrl" TEXT NOT NULL,
                    "streamUrl" TEXT,
                    "fallbackUrl" TEXT,
                    "ifCoverUrl" TEXT,
                    "thumbnailUrl" TEXT,
                    "youtubeVideoId" TEXT,
                    "publishedAt" TIMESTAMPTZ,
                    "scriptureBook" TEXT,
                    "scriptureChapter" INTEGER,
                    "scriptureVerse" INTEGER,
                    "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    "createdAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
                );
            """)
        except Exception as e:
            log.warning("Schema check note: %s", e)

    def close(self) -> None:
        try:
            self.cur.close()
            self.conn.close()
        except Exception:
            pass

    def fetch_eligible_videos(self, cfg: Config) -> list[tuple]:
        """
        Fetch long-form videos (type='VIDEO') from active ChristianApp channels
        that have not yet been uploaded to Audio.com.

        Failed videos are retried daily: each calendar day a failed video gets up
        to ``max_retries`` attempts, then its per-day counter resets (via
        `audioLastRetryAt`) so it is retried again the next day — indefinitely
        until an attempt passes.
        """
        statuses = ["pending", "failed"]
        if cfg.redo:
            statuses = ["pending", "completed", "failed"]

        ph = ",".join(["%s"] * len(statuses))
        params: list[Any] = list(statuses)

        # Query lives in eligible_videos.sql (hot-reloadable) so it can be
        # edited at any time without a code change.
        sql_template = self._eligible_sql()

        # Per-day retry gate: a failed video is eligible when it has budget left
        # TODAY, or its last attempt was a previous calendar day (counter resets).
        retry_clause = """
            AND (
              COALESCE(v."audioUploadStatus", '') <> 'failed'
              OR COALESCE(v."audioLastRetryAt", '-infinity'::timestamptz)::date < CURRENT_DATE
              OR COALESCE(v."audioRetryCount", 0) < %s
            )"""
        if "{retry_clause}" in sql_template:
            params.append(cfg.max_retries)

        # Channel name filter (--channels flag)
        channel_clause = ""
        if cfg.channel_filters:
            channel_or = " OR ".join(["c.name ILIKE %s" for _ in cfg.channel_filters])
            channel_clause = f" AND ({channel_or})"
            params.extend([f"%{f}%" for f in cfg.channel_filters])

        # Channel ordering:
        #   1. Priority channels first (CFC India by default).
        #   2. Tamil channels, then English channels; each largest video-count first.
        #   3. Within a channel, most recently uploaded first.
        priority_clause = ""
        if cfg.priority_channel_ids:
            priority_clause = ' CASE WHEN v."channelId" = ANY(%s::text[]) THEN 0 ELSE 1 END,'
            params.append(cfg.priority_channel_ids)

        query = (
            sql_template
            .replace("{status_ph}", ph)
            .replace("{retry_clause}", retry_clause)
            .replace("{channel_clause}", channel_clause)
            .replace("{priority_clause}", priority_clause)
        )
        params.append(cfg.batch_limit)
        # Guard against a mismatch so a bad edit fails loudly instead of with a
        # cryptic IndexError from psycopg2. Counts single-placeholder markers
        # while ignoring doubled percents (literal "%").
        if len(re.findall(r"(?<!%)%s", query)) != len(params):
            raise RuntimeError(
                f"eligible_videos.sql: expected {len(params)} parameter marker(s), "
                f"found {len(re.findall(r'(?<!%)%s', query))} in the query. "
                "Check the SQL for stray markers in comment lines, or a token mismatch."
            )
        self.cur.execute(query, params)
        return self.cur.fetchall()

    def fetch_one(self, video_id: str) -> tuple | None:
        self.cur.execute(
            """SELECT v.id, v.title, COALESCE(v."channelName", c.name, 'Unknown'), v."publishedAt", v.description, c.language, v."channelId", v."duration", v."thumbnail"
               FROM "Video" v
               LEFT JOIN "Channel" c ON c.id = v."channelId"
               WHERE v.id=%s""",
            (video_id,),
        )
        return self.cur.fetchone()

    def mark_processing(self, video_id: str) -> None:
        self.cur.execute(
            """UPDATE "Video"
               SET "audioUploadStatus"='processing', "audioLastError"=NULL
               WHERE "id"=%s""",
            (video_id,),
        )

    def mark_completed(self, video_id: str, audio_url: str) -> None:
        self.cur.execute(
            """UPDATE "Video"
               SET "audioUploadStatus"='completed', "audioUrl"=%s, "audioLastError"=NULL,
                   "audioRetryCount"=0, "audioLastRetryAt"=NULL
               WHERE "id"=%s""",
            (audio_url, video_id),
        )

    def batch_mark_completed(self, items: list[tuple[str, str]]) -> None:
        if not items:
            return
        from psycopg2.extras import execute_values
        execute_values(
            self.cur,
            """UPDATE "Video" AS v
               SET "audioUploadStatus"='completed',
                   "audioUrl"=data.audio_url,
                   "audioLastError"=NULL,
                   "audioRetryCount"=0,
                   "audioLastRetryAt"=NULL
               FROM (VALUES %s) AS data(video_id, audio_url)
               WHERE v."id" = data.video_id""",
            items,
        )

    def mark_failed(self, video_id: str, error: str, permanent: bool = False) -> None:
        # A permanent failure ("This video is not available", private, removed,
        # region-blocked, ...) is terminal: it gets status 'dead' and is never
        # picked again. Transient failures keep the daily-retry budget.
        status = "'dead'" if permanent else "'failed'"
        self.cur.execute(
            f"""UPDATE "Video"
               SET "audioUploadStatus"={status},
                   "audioLastError"=%s,
                   "audioLastRetryAt"=NOW(),
                   "audioRetryCount"=CASE
                     WHEN COALESCE("audioLastRetryAt", '-infinity'::timestamptz)::date < CURRENT_DATE THEN 1
                     ELSE COALESCE("audioRetryCount", 0) + 1
                   END
               WHERE "id"=%s""",
            (error[:2000], video_id),
        )

    def find_audio_track(self, series_id: str, youtube_video_id: str) -> dict | None:
        """Looks up an already-registered audio track for a series/video.

        Replaces the old Git-based dedupe: the audio catalog is now authored
        directly in PostgreSQL, so "have we uploaded this video already?" is
        answered here instead of in the releases repository JSON.
        """
        self.cur.execute(
            """SELECT "audioUrl" FROM "AudioTrack"
               WHERE "seriesId"=%s AND "youtubeVideoId"=%s LIMIT 1""",
            (series_id, youtube_video_id),
        )
        row = self.cur.fetchone()
        return {"audioUrl": row[0]} if row else None

    def audio_id_referenced(self, audio_id: str) -> bool:
        """Returns True when any AudioTrack already references this Audio.com id.

        Guards title-based reuse: a matched Audio.com audio must not be wired to
        a second video unless it is still an orphan (unreferenced).
        """
        if not audio_id:
            return False
        self.cur.execute(
            """SELECT 1 FROM "AudioTrack" WHERE "audioUrl" LIKE %s LIMIT 1""",
            (f"%audio.com/{audio_id}%",),
        )
        return self.cur.fetchone() is not None

    def referenced_audio_ids(self) -> set[str]:
        """Returns the set of Audio.com ids currently referenced by any AudioTrack."""
        self.cur.execute(
            """SELECT "audioUrl" FROM "AudioTrack" WHERE "audioUrl" LIKE 'https://audio.com/%'""",
        )
        ids: set[str] = set()
        for (u,) in self.cur.fetchall():
            aid = "".join(ch for ch in u.split("audio.com/")[-1] if ch.isdigit())
            if aid:
                ids.add(aid)
        return ids

    def delete_audio_track(self, series_id: str, youtube_video_id: str) -> bool:
        """Removes a dead catalogue track row (Audio.com audio no longer exists).

        Returns True when a row was actually deleted. The caller must then
        re-upload the audio and register a fresh track.
        """
        self.cur.execute(
            """DELETE FROM "AudioTrack"
               WHERE "seriesId"=%s AND "youtubeVideoId"=%s""",
            (series_id, youtube_video_id),
        )
        deleted = self.cur.rowcount > 0
        if deleted:
            self.cur.execute(
                """UPDATE "AudioSeries" SET
                     "trackCount"=(SELECT COUNT(*) FROM "AudioTrack" WHERE "seriesId"=%s),
                     "latestPublishedAt"=(SELECT MAX("publishedAt") FROM "AudioTrack" WHERE "seriesId"=%s),
                     "updatedAt"=NOW()
                   WHERE "id"=%s""",
                (series_id, series_id, series_id),
            )
        return deleted

    def upsert_audio_series_and_track(
        self,
        *,
        series_id: str,
        series_title: str,
        series_description: str,
        series_speaker: str,
        series_category: str,
        series_language: str,
        cover_url: str | None,
        channel_id: str | None,
        published_at: Any,
        track: dict[str, Any],
    ) -> None:
        """Registers (or refreshes) an uploaded track and its series in Neon.

        Series row is upserted first, then the track, then the series counts are
        recomputed from the AudioTrack rows so trackCount/latestPublishedAt are
        always derived from the DB, not from a stale JSON snapshot. Idempotent:
        re-processing a video overwrites its single AudioTrack row.
        """
        self.cur.execute(
            """INSERT INTO "AudioSeries"
                 ("id","title","description","speaker","category","language",
                  "coverUrl","channelId","trackCount","latestPublishedAt",
                  "updatedAt","createdAt")
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,0,%s, NOW(), NOW())
               ON CONFLICT ("id") DO UPDATE SET
                 "title"=EXCLUDED."title",
                 "description"=EXCLUDED."description",
                 "speaker"=COALESCE("AudioSeries"."speaker", EXCLUDED."speaker"),
                 "category"=EXCLUDED."category",
                 "language"=EXCLUDED."language",
                 "coverUrl"=COALESCE("AudioSeries"."coverUrl", EXCLUDED."coverUrl"),
                 "channelId"=EXCLUDED."channelId",
                 "updatedAt"=NOW()""",
            (
                series_id,
                series_title,
                series_description,
                series_speaker,
                series_category,
                series_language,
                cover_url,
                channel_id,
                published_at,
            ),
        )
        self.cur.execute(
            """INSERT INTO "AudioTrack"
                 ("id","seriesId","title","speaker","durationSeconds",
                  "audioUrl","streamUrl","thumbnailUrl","youtubeVideoId",
                  "publishedAt","updatedAt","createdAt")
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s, NOW(), NOW())
               ON CONFLICT ("id") DO UPDATE SET
                 "seriesId"=EXCLUDED."seriesId",
                 "title"=EXCLUDED."title",
                 "speaker"=EXCLUDED."speaker",
                 "durationSeconds"=EXCLUDED."durationSeconds",
                 "audioUrl"=EXCLUDED."audioUrl",
                 "streamUrl"=EXCLUDED."streamUrl",
                 "thumbnailUrl"=EXCLUDED."thumbnailUrl",
                 "youtubeVideoId"=EXCLUDED."youtubeVideoId",
                 "publishedAt"=EXCLUDED."publishedAt",
                 "updatedAt"=NOW()""",
            (
                track["id"],
                series_id,
                track["title"],
                track.get("speaker"),
                int(track.get("durationSeconds") or 0),
                track["audioUrl"],
                track.get("streamUrl"),
                track.get("thumbnailUrl"),
                track.get("youtubeVideoId"),
                track.get("publishedAt"),
            ),
        )
        self.cur.execute(
            """UPDATE "AudioSeries" SET
                 "trackCount"=(SELECT COUNT(*) FROM "AudioTrack" WHERE "seriesId"=%s),
                 "latestPublishedAt"=(SELECT MAX("publishedAt") FROM "AudioTrack" WHERE "seriesId"=%s),
                 "updatedAt"=NOW()
               WHERE "id"=%s""",
            (series_id, series_id, series_id),
        )
        log.info("  registered track %s with Neon audio catalog (series: %s)", track["id"], series_id)

    def mark_short(self, video_id: str) -> None:
        """Marks a video as a short and ignores it from future audio processing."""
        self.cur.execute(
            """UPDATE "Video"
               SET "type"='SHORT',
                   "audioUploadStatus"='ignored',
                   "audioLastError"='Ignored: YouTube Short detected'
               WHERE "id"=%s""",
            (video_id,),
        )

    def release_stale_processing(self) -> None:
        self.cur.execute(
            """UPDATE "Video"
               SET "audioUploadStatus"='pending'
               WHERE "audioUploadStatus"='processing'"""
        )
        if self.cur.rowcount:
            log.info("Reset %d stale processing video(s) back to 'pending'", self.cur.rowcount)


# --------------------------------------------------------------------------- #
# Audio.com Client
# --------------------------------------------------------------------------- #
def norm_title(title: str | None) -> str:
    """Normalizes a title for Audio.com title-based dedupe matching."""
    if not title:
        return ""
    t = title.strip()
    # Strip YouTube-style suffixes: " (v12345)", " [720p]", trailing ids
    t = re.sub(r"\s*\(\s*[a-z0-9_-]{4,}\s*\)\s*$", "", t, flags=re.I)
    t = re.sub(r"\s*\[[^\]]*\]\s*$", "", t)
    t = re.sub(r"\s+", " ", t)
    return t.lower()


def clean_audiocom_tags(tags, limit: int = 5, max_len: int = 40) -> list[str]:
    """Audio.com accepts at most ``limit`` tags, each at most ``max_len`` chars.

    YouTube channel names and descriptions often exceed that length (or are
    empty), so tags are truncated/deduplicated here before the create call.
    """
    cleaned: list[str] = []
    for t in tags or []:
        s = str(t).strip()
        if not s:
            continue
        if len(s) > max_len:
            s = s[:max_len].rstrip()
        if s and s not in cleaned:
            cleaned.append(s)
        if len(cleaned) >= limit:
            break
    return cleaned


class AudioComClient:
    def __init__(self, token: str):
        import requests

        clean_token = token[7:].strip() if token.lower().startswith("bearer ") else token.strip()
        self._requests = requests
        self.token = clean_token
        self.api = "https://api.audio.com/v1"
        self.headers = {
            "Authorization": f"Bearer {clean_token}",
            "Accept": "application/json",
        }
        self._collection_cache: dict[str, str] = {}

    def get_or_create_collection(self, title: str) -> str | None:
        """
        Finds or creates an Audio.com collection matching the channel title.
        Returns the collection ID string or None on failure.
        """
        clean_title = title.strip()[:100]
        if not clean_title:
            return None
        lower_title = clean_title.lower()
        if lower_title in self._collection_cache:
            return self._collection_cache[lower_title]

        try:
            # 1. Check existing collections
            resp = self._requests.get(f"{self.api}/collection/list", headers=self.headers, timeout=20)
            if resp.status_code == 200:
                for col in (resp.json() or []):
                    c_title = col.get("title", "").strip()
                    c_id = str(col.get("id"))
                    self._collection_cache[c_title.lower()] = c_id
                    if c_title.lower() == lower_title:
                        return c_id

            # 2. Create collection if not found
            create_resp = self._requests.post(
                f"{self.api}/collection/create",
                headers=self.headers,
                json={"title": clean_title},
                timeout=20,
            )
            if create_resp.status_code in (200, 201):
                col_data = create_resp.json()
                col_id = str(col_data.get("id"))
                self._collection_cache[lower_title] = col_id
                log.info("  created new Audio.com collection '%s' (id: %s)", clean_title, col_id)
                return col_id
            else:
                log.warning("  failed to create Audio.com collection '%s': %s", clean_title, create_resp.text[:200])
        except Exception as e:
            log.warning("  get_or_create_collection error: %s", e)
        return None

    def add_to_collection(self, collection_id: str, audio_id: str) -> None:
        """Adds an audio track to a collection."""
        try:
            resp = self._requests.post(
                f"{self.api}/collection/item/add?id={collection_id}",
                headers=self.headers,
                json={"audio": str(audio_id)},
                timeout=20,
            )
            if resp.status_code in (200, 201, 204):
                log.info("  added track %s to Audio.com collection %s", audio_id, collection_id)
            else:
                log.warning("  add to collection warning: %s %s", resp.status_code, resp.text[:200])
        except Exception as e:
            log.warning("  add_to_collection error: %s", e)

    def upload_audio_image(self, audio_id: str, image_bytes: bytes, mime: str = "image/jpeg") -> bool:
        """Uploads cover artwork for an audio track to Audio.com."""
        try:
            resp = self._requests.post(
                f"{self.api}/audio/image/create?id={audio_id}",
                headers=self.headers,
                json={"mime": mime, "size": len(image_bytes)},
                timeout=20,
            )
            if resp.status_code in (200, 201):
                data = resp.json()
                upload_url = data.get("url")
                success_hook = data.get("success")
                if upload_url:
                    put_resp = self._requests.put(upload_url, data=image_bytes, timeout=30)
                    if put_resp.status_code in (200, 201, 204):
                        if success_hook:
                            try:
                                self._requests.post(success_hook, timeout=10)
                            except Exception:
                                pass
                        log.info("  uploaded cover image to Audio.com track %s", audio_id)
                        return True
            else:
                log.warning("  audio/image/create warning (%s): %s", resp.status_code, resp.text[:200])
        except Exception as e:
            log.warning("  failed to upload track image to Audio.com: %s", e)
        return False

    def upload_collection_image(self, collection_id: str, image_bytes: bytes, mime: str = "image/jpeg") -> bool:
        """Uploads cover artwork for a collection to Audio.com."""
        try:
            resp = self._requests.post(
                f"{self.api}/collection/image/create?id={collection_id}",
                headers=self.headers,
                json={"mime": mime, "size": len(image_bytes)},
                timeout=20,
            )
            if resp.status_code in (200, 201):
                data = resp.json()
                upload_url = data.get("url")
                success_hook = data.get("success")
                if upload_url:
                    put_resp = self._requests.put(upload_url, data=image_bytes, timeout=30)
                    if put_resp.status_code in (200, 201, 204):
                        if success_hook:
                            try:
                                self._requests.post(success_hook, timeout=10)
                            except Exception:
                                pass
                        log.info("  uploaded cover image to Audio.com collection %s", collection_id)
                        return True
            else:
                log.warning("  collection/image/create warning (%s): %s", resp.status_code, resp.text[:200])
        except Exception as e:
            log.warning("  failed to upload collection image to Audio.com: %s", e)
        return False

    def find_existing_track_id(self, title: str) -> str | None:
        """Finds the first candidate audio id for this title, if any."""
        ids = self.find_existing_title_ids(title)
        return ids[0] if ids else None

    def find_existing_title_ids(self, title: str) -> list[str]:
        """Returns ALL Audio.com track ids whose title matches this one.

        Multiple audios can share a title (re-uploads, cross-posts), so callers
        must iterate candidates and pick one that is not already referenced by
        another Neon track (see audio_id_referenced).
        """
        clean_target = norm_title(title)
        if not clean_target:
            return []
        if not hasattr(self, "_existing_audio_cache"):
            self._existing_audio_cache: dict[str, list[str]] = {}
            try:
                page = 1
                while True:
                    resp = self._requests.get(
                        f"{self.api}/audio/list",
                        headers=self.headers,
                        params={"page": page, "limit": 50},
                        timeout=20,
                    )
                    if resp.status_code != 200:
                        break
                    items = resp.json()
                    if isinstance(items, dict):
                        items = items.get("data") or items.get("audios") or items.get("items") or []
                    if not items:
                        break
                    for item in items:
                        t = norm_title(item.get("title"))
                        aid = str(item.get("id", ""))
                        if t and aid and aid not in self._existing_audio_cache.setdefault(t, []):
                            self._existing_audio_cache[t].append(aid)
                    if len(items) < 50:
                        break
                    page += 1
            except Exception as e:
                log.warning("  failed to populate existing audio cache: %s", e)

        return self._existing_audio_cache.get(clean_target, [])

    def upload_audio(
        self,
        audio_file: Path,
        metadata: dict,
        collection_name: str | None = None,
        image_bytes: bytes | None = None,
        referenced_ids: set[str] | None = None,
    ) -> tuple[str, str | None]:
        """
        Uploads audio to Audio.com and returns (audio_url, stream_url).
        - audio_url:  human-readable landing page (https://audio.com/{id})
        - stream_url: direct CDN audio file URL for streaming (resolved after
                       transcoding), or None if transcoding hasn't completed.

        ``referenced_ids`` (optional): Audio.com ids already claimed by another
        Neon track. A title-matched candidate is reused only when it is NOT in
        this set, so two videos never share one audio upload.
        """
        title = metadata.get("title", "Untitled Sermon")[:100]

        # 0. Check if an unreferenced track with this title was already uploaded
        candidates = self.find_existing_title_ids(title)
        if referenced_ids is None:
            referenced_ids = set()
        for existing_id in candidates:
            if existing_id in referenced_ids:
                continue
            audio_url = f"https://audio.com/{existing_id}"
            if not self.is_audio_live(audio_url):
                continue
            log.info("  track '%s' already exists on Audio.com (id: %s), reusing existing", title, existing_id)
            stream_url = self._resolve_stream_url(existing_id)
            return audio_url, stream_url

        file_size = audio_file.stat().st_size
        mime = "audio/mpeg" if audio_file.suffix.lower() == ".mp3" else "audio/wav"

        log.info("  requesting presigned upload URL from Audio.com (%d bytes, %s)...", file_size, mime)

        # 1. Create audio entity & presigned URL. Audio.com has no post-create
        # metadata route (audio/{id} 404s), so all track metadata must be sent
        # here at creation time.
        desc = (metadata.get("description") or "")[:500]
        tags = clean_audiocom_tags(metadata.get("tags"))
        resp = self._requests.post(
            f"{self.api}/audio/create",
            headers=self.headers,
            json={
                "title": title,
                "category": "podcast",
                "mime": mime,
                "size": file_size,
                "description": desc,
                "tags": tags,
                "is_listed": True,
            },
            timeout=30,
        )
        if resp.status_code not in (200, 201):
            raise RuntimeError(f"Audio.com create failed: {resp.status_code} {resp.text[:300]}")

        create_data = resp.json()
        upload_url = create_data.get("url")
        success_hook = create_data.get("success")
        audio_info = create_data.get("audio") or {}
        audio_id = audio_info.get("id")

        if not upload_url or not audio_id:
            raise RuntimeError(f"Audio.com response missing url or audio id: {create_data}")

        # 2. Upload raw audio bytes to presigned URL
        file_size_mb = file_size / (1024 * 1024)
        log.info("  uploading %.2f MB to Audio.com storage...", file_size_mb)
        with open(audio_file, "rb") as f:
            upload_resp = self._requests.put(upload_url, data=f, timeout=600)
            if upload_resp.status_code not in (200, 201, 204):
                raise RuntimeError(f"Audio.com storage PUT failed: {upload_resp.status_code} {upload_resp.text[:300]}")

        # 3. Report success hook
        if success_hook:
            try:
                self._requests.post(success_hook, timeout=30)
            except Exception as e:
                log.warning("  success hook warning: %s", e)

        # 4. Upload track cover artwork if available
        if image_bytes:
            self.upload_audio_image(str(audio_id), image_bytes)

        # 5. Associate with collection if requested
        if collection_name:
            col_id = self.get_or_create_collection(collection_name)
            if col_id:
                self.add_to_collection(col_id, str(audio_id))
                if image_bytes:
                    self.upload_collection_image(col_id, image_bytes)

        # 6. Track metadata is set at create time (see step 1); there is no
        #    Audio.com update route, so no follow-up metadata call is made.

        audio_url = f"https://audio.com/{audio_id}"

        # 7. Resolve direct stream URL (poll for transcoding completion)
        stream_url = self._resolve_stream_url(str(audio_id))

        log.info("  successfully uploaded to Audio.com: %s (stream: %s)", audio_url, stream_url or "pending")
        return audio_url, stream_url

    def _resolve_stream_url(self, audio_id: str, max_attempts: int = 10, delay: int = 3) -> str | None:
        """
        Polls the Audio.com API for the transcoded stream URL.

        Audio.com transcodes uploads asynchronously. The preferred source of the
        stream is ``transcodings[].url`` (present once processing finishes); the
        legacy ``play.url`` field is NULL for older uploads, so it cannot be
        relied on as a primary source. Falls back to the original source file
        URL when no transcode is available yet, and retries up to max_attempts.
        """
        for attempt in range(1, max_attempts + 1):
            try:
                resp = self._requests.get(
                    f"{self.api}/audio/view?id={audio_id}",
                    headers=self.headers,
                    timeout=15,
                )
                if resp.status_code == 200:
                    data = resp.json()
                    transcodings = data.get("transcodings") or data.get("sources") or []
                    # Prefer an mp3 transcode (>192kbps preferred, any mp3 ok).
                    stream = None
                    for t in transcodings:
                        if (t.get("format") or "").lower() == "mp3":
                            stream = t.get("url")
                            break
                    if not stream:
                        play = data.get("play") or {}
                        stream = (play.get("url") or play.get("stream_url") or play.get("streamUrl"))
                    if stream:
                        log.info("  resolved stream URL on attempt %d/%d", attempt, max_attempts)
                        return stream
            except Exception as e:
                log.warning("  stream URL resolve attempt %d failed: %s", attempt, e)

            if attempt < max_attempts:
                time.sleep(delay)

        log.warning("  could not resolve stream URL after %d attempts (transcoding may still be in progress)", max_attempts)
        return None

    def is_audio_live(self, audio_url: str) -> bool:
        """
        Checks whether an Audio.com URL points at an audio that still exists.

        Used before reusing a catalog entry: the Neon track may reference an
        audio id that has since been deleted on Audio.com (404). A deleted
        audio must be re-uploaded, not silently reused.
        """
        if not audio_url or "audio.com/" not in audio_url:
            return False
        audio_id = audio_url.split("audio.com/")[-1].split("?")[0]
        audio_id = "".join(ch for ch in audio_id if ch.isdigit())
        if not audio_id:
            return False
        try:
            resp = self._requests.get(
                f"{self.api}/audio/view?id={audio_id}",
                headers=self.headers,
                timeout=15,
            )
            return resp.status_code == 200
        except Exception as e:
            log.warning("  live-check for audio %s failed: %s", audio_id, e)
            return False

    def purge_all(self) -> int:
        """
        Deletes ALL audio uploads and collections from the Audio.com account.
        Returns the total number of audio tracks deleted.
        """
        deleted = 0

        # 1. Delete all audio tracks
        log.info("Fetching all Audio.com uploads for deletion...")
        try:
            # List all audio
            page = 1
            audio_ids: list[str] = []
            while True:
                resp = self._requests.get(
                    f"{self.api}/audio/list",
                    headers=self.headers,
                    params={"page": page, "limit": 100},
                    timeout=20,
                )
                if resp.status_code != 200:
                    log.warning("  audio/list returned %s, stopping enumeration", resp.status_code)
                    break
                items = resp.json()
                if not items:
                    break
                if isinstance(items, dict):
                    items = items.get("data") or items.get("audios") or items.get("items") or []
                for item in items:
                    aid = str(item.get("id", ""))
                    if aid:
                        audio_ids.append(aid)
                if len(items) < 100:
                    break
                page += 1

            log.info("  found %d audio track(s) to delete", len(audio_ids))
            for aid in audio_ids:
                try:
                    dr = self._requests.post(
                        f"{self.api}/audio/delete?id={aid}",
                        headers=self.headers,
                        timeout=15,
                    )
                    if dr.status_code in (200, 204):
                        deleted += 1
                        log.info("  deleted audio %s (%d/%d)", aid, deleted, len(audio_ids))
                    else:
                        log.warning("  failed to delete audio %s: %s", aid, dr.status_code)
                except Exception as e:
                    log.warning("  error deleting audio %s: %s", aid, e)

        except Exception as e:
            log.error("  error listing Audio.com uploads: %s", e)

        # 2. Delete all collections
        try:
            resp = self._requests.get(f"{self.api}/collection/list", headers=self.headers, timeout=20)
            if resp.status_code == 200:
                collections = resp.json() or []
                log.info("  found %d collection(s) to delete", len(collections))
                for col in collections:
                    cid = str(col.get("id", ""))
                    if cid:
                        try:
                            dr = self._requests.post(
                                f"{self.api}/collection/delete?id={cid}",
                                headers=self.headers,
                                timeout=15,
                            )
                            if dr.status_code in (200, 204):
                                log.info("  deleted collection %s", cid)
                            else:
                                log.warning("  failed to delete collection %s: %s", cid, dr.status_code)
                        except Exception as e:
                            log.warning("  error deleting collection %s: %s", cid, e)
        except Exception as e:
            log.error("  error listing Audio.com collections: %s", e)

        self._collection_cache.clear()
        log.info("Audio.com purge complete: %d audio track(s) deleted", deleted)
        return deleted


def slugify(text: str) -> str:
    """Creates a clean URL-safe slug for series IDs."""
    cleaned = re.sub(r"[^a-zA-Z0-9]+", "_", text.strip().lower()).strip("_")
    return cleaned or "misc"


def map_language(lang_code: str | None) -> str:
    """Maps ISO language codes to readable names matching AudioSeries convention."""
    if not lang_code:
        return "English"
    code = lang_code.lower().strip()
    mapping = {
        "en": "English",
        "ta": "Tamil",
        "te": "Telugu",
        "hi": "Hindi",
        "ml": "Malayalam",
        "kn": "Kannada",
        "mr": "Marathi",
        "es": "Spanish",
        "fr": "French",
        "de": "German",
        "pt": "Portuguese",
        "ru": "Russian",
        "zh": "Chinese",
    }
    return mapping.get(code, code.capitalize())


def detect_category(channel_name: str) -> str:
    combined = channel_name.lower()
    keywords = [
        "song", "music", "hymn", "worship", "choir", "praise",
        "paadalgal", "padalgal", "geethangal", "keerthanai", "sangeet",
        "valibam", "மாசில்லா",
    ]
    for kw in keywords:
        if kw in combined:
            return "Songs"
    return "YouTube"


def detect_languages(title: str, description: str, default_lang: str = "English") -> tuple[str, str | None]:
    """
    Detects primary and secondary (translation) languages from title and description.
    Returns: (primary_lang, secondary_lang) e.g. ('Tamil', 'English') or ('English', None).
    """
    text = f"{title or ''}\n{description or ''}"
    lower = text.lower()

    # 1. Check explicit translation / bilingual patterns
    bilingual_patterns = [
        (r'tamil[-/\s&]+english|english[-/\s&]+tamil|\[tamil-english\]', 'Tamil', 'English'),
        (r'hindi[-/\s&]+english|english[-/\s&]+hindi|\[hindi-english\]', 'Hindi', 'English'),
        (r'telugu[-/\s&]+english|english[-/\s&]+telugu', 'Telugu', 'English'),
        (r'malayalam[-/\s&]+english|english[-/\s&]+malayalam', 'Malayalam', 'English'),
        (r'kannada[-/\s&]+english|english[-/\s&]+kannada', 'Kannada', 'English'),
        (r'spanish[-/\s&]+english|english[-/\s&]+spanish', 'Spanish', 'English'),
    ]
    for pattern, lang1, lang2 in bilingual_patterns:
        if re.search(pattern, lower):
            return lang1, lang2

    # 2. Check translation mentions in text
    translation_match = re.search(r'\b(tamil|hindi|telugu|malayalam|kannada|spanish)\s+(?:translation|audio|dubbed|dubbing)\b', lower)
    if translation_match:
        trans_lang = translation_match.group(1).capitalize()
        return trans_lang, 'English'

    # 3. Unicode script detection
    tamil_chars = len(re.findall(r'[\u0B80-\u0BFF]', text))
    hindi_chars = len(re.findall(r'[\u0900-\u097F]', text))
    telugu_chars = len(re.findall(r'[\u0C00-\u0C7F]', text))
    malayalam_chars = len(re.findall(r'[\u0D00-\u0D7F]', text))
    kannada_chars = len(re.findall(r'[\u0C80-\u0CFF]', text))
    latin_words = len(re.findall(r'[a-zA-Z]{3,}', text))

    script_counts = {
        'Tamil': tamil_chars,
        'Hindi': hindi_chars,
        'Telugu': telugu_chars,
        'Malayalam': malayalam_chars,
        'Kannada': kannada_chars,
    }
    
    top_script, top_score = max(script_counts.items(), key=lambda x: x[1])

    if top_score >= 5:
        # Substantial Indic script found
        secondary = "English" if latin_words >= 3 else None
        return top_script, secondary

    # 4. Check single language keyword in romanized text
    if any(kw in lower for kw in ['tamil', 'tamizh']):
        return 'Tamil', None if 'english' not in lower else 'English'
    if 'hindi' in lower:
        return 'Hindi', None if 'english' not in lower else 'English'
    if 'telugu' in lower:
        return 'Telugu', None if 'english' not in lower else 'English'
    if 'malayalam' in lower:
        return 'Malayalam', None if 'english' not in lower else 'English'
    if 'kannada' in lower:
        return 'Kannada', None if 'english' not in lower else 'English'
    if any(kw in lower for kw in ['spanish', 'español']):
        return 'Spanish', None if 'english' not in lower else 'English'

    return default_lang or "English", None


# --------------------------------------------------------------------------- #
# Speaker Extraction & Canonical Mapping
# --------------------------------------------------------------------------- #
KNOWN_SPEAKERS_MAP = {
    # Poonen Family
    "zac poonen": "Zac Poonen",
    "zac poone": "Zac Poonen",
    "zac ponnen": "Zac Poonen",
    "zac pooen": "Zac Poonen",
    "bro zac": "Zac Poonen",
    "bro. zac": "Zac Poonen",
    "brother zac": "Zac Poonen",
    "சகரியா பூணன்": "Zac Poonen",
    "சகரியா  பூணன்": "Zac Poonen",
    "annie poonen": "Annie Poonen",
    "dr. annie poonen": "Annie Poonen",
    "dr annie poonen": "Annie Poonen",
    "sister annie poonen": "Annie Poonen",
    "ஆனி பூணன்": "Annie Poonen",
    "santosh poonen": "Santosh Poonen",
    "santhosh poonen": "Santosh Poonen",
    "சந்தோஷ் பூணன்": "Santosh Poonen",
    "sandeep poonen": "Sandeep Poonen",
    "சந்தீப் பூணன்": "Sandeep Poonen",
    "sanjay poonen": "Sanjay Poonen",
    "sunil poonen": "Sunil Poonen",

    # CFC Bangalore Elders & Speakers
    "charles banna": "Charles Banna",
    "john pereira": "John Pereira",
    "ஜான் பெரேரா": "John Pereira",
    "danish thomas": "Danish Thomas",
    "suresh abraham": "Suresh Abraham",
    "paul williams": "Paul Williams",
    "ian robson": "Ian Robson",
    "இயன் ராப்சன்": "Ian Robson",

    # Chennai & Tamil Nadu CFC Elders & Speakers
    "sam varghese": "Sam Varghese",
    "sam vaeghese": "Sam Varghese",
    "sam vargese": "Sam Varghese",
    "சாம் வர்கீஸ்": "Sam Varghese",
    "jesudoss": "Jesudoss",
    "ஜேசுதாஸ்": "Jesudoss",
    "michael": "Michael",
    "mishael jesuraj": "Michael",
    "மைகேல்": "Michael",
    "மைக்கேல்": "Michael",
    "vincent": "Vincent",
    "vincent wilson": "Vincent",
    "வின்சென்ட்": "Vincent",
    "chellaiah": "Chellaiah",
    "chellaiya": "Chellaiah",
    "செல்லையா": "Chellaiah",
    "prakasam": "Prakasam",
    "arputha prakasam": "Prakasam",
    "பிரகாசம்": "Prakasam",
    "அற்புத பிரகாசம்": "Prakasam",
    "victor ramanathan": "Victor Ramanathan",
    "bro victor": "Victor Ramanathan",
    "bro. victor": "Victor Ramanathan",
    "விக்டர்": "Victor Ramanathan",
    "francis": "Francis",
    "பிரான்சிஸ்": "Francis",
    "parisutham": "Parisutham",
    "பரிசுத்தம்": "Parisutham",
    "deivaprakash": "Deivaprakash",
    "devaprakash": "Deivaprakash",
    "deivaprakasam": "Deivaprakash",
    "தெய்வபிரகாஷ்": "Deivaprakash",
    "தெய்வப்பிரகாஷ்": "Deivaprakash",
    "தெய்வபிரகாசம்": "Deivaprakash",
    "mathaiya": "Mathaiya",
    "mathiya": "Mathaiya",
    "மாத்தையா": "Mathaiya",
    "antony jackson": "Antony Jackson",
    "bobby antony": "Bobby Antony",
    "charles antony": "Charles Antony",
    "chuck antony": "Charles Antony",
    "thavaseelan": "Thavaseelan",
    "jeyaseelan": "Jeyaseelan",
    "தவசீலன்": "Thavaseelan",
    "finney": "Finney",
    "ஃபின்னி": "Finney",
    "பின்னி": "Finney",
    "srinivasan": "Srinivasan",
    "சீனிவாசன்": "Srinivasan",
    "prabahar": "Prabahar",
    "prabhakar": "Prabahar",
    "robert prabhakar": "Prabahar",
    "பிரபாகர்": "Prabahar",
    "ezekiaraj": "Ezekiaraj",
    "ezekia raj": "Ezekiaraj",
    "எசேக்கியராஜ்": "Ezekiaraj",
    "எசேக்கியாராஜ்": "Ezekiaraj",
    "joyson silva": "Joyson Silva",
    "joyson": "Joyson Silva",
    "ஜாய்சன் சில்வா": "Joyson Silva",
    "ஜாய்சன்": "Joyson Silva",
    "joji samuel": "Joji Samuel",
    "geoji samuel": "Joji Samuel",
    "geoji t samuel": "Joji Samuel",
    "joji t samuel": "Joji Samuel",
    "ஜியோஜி சாமுவேல்": "Joji Samuel",
    "calvin": "Calvin",
    "prabhu joshua": "Prabhu Joshua",
    "spn raj": "SPN Raj",
    "raja kannan": "Raja Kannan",
    "இராஜா கண்ணண்": "Raja Kannan",
    "rajesh pon samuel": "Rajesh Pon Samuel",
    "rizanth francis": "Rizanth Francis",
    "rizanth": "Rizanth Francis",
    "janardhanan": "Janardhanan",
    "janarthanan": "Janardhanan",
    "jayakumar": "Jayakumar",
    "ஜெயக்குமார்": "Jayakumar",
    "jayaprakash": "Jayaprakash",
    "ஜெயபிரகாஷ்": "Jayaprakash",
    "joby joseph": "Joby Joseph",
    "john polo": "John Polo",
    "ஜான் போலோ": "John Polo",
    "jose jacob": "Jose Jacob",
    "juvanis": "Juvanis",
    "யுவானிஸ்": "Juvanis",
    "mathew thomas": "Mathew Thomas",
    "matthew thomas": "Mathew Thomas",
    "palanisamy": "Palanisamy",
    "பழனிச்சாமி": "Palanisamy",
    "settu": "Settu",
    "சேட்டு": "Settu",
    "sundaresan": "Sundaresan",

    # Regional Indian CFC Elders
    "joseph kuruvilla": "Joseph Kuruvilla",
    "abraham isac": "Abraham Isac",
    "abraham isaac": "Abraham Isac",
    "ஆபிரகாம் ஐசக்": "Abraham Isac",
    "abraham varghese": "Abraham Varghese",
    "samuel": "Samuel",
    "bro samuel": "Samuel",
    "சாமுவேல்": "Samuel",
    "vedaiyan": "Vedaiyan",
    "bro vedaiyan": "Vedaiyan",

    # RLCF & NCCF (US)
    "ajay chakravarthy": "Ajay Chakravarthy",
    "அஜய் சக்ரவர்த்தி": "Ajay Chakravarthy",
    "olu talabi": "Olu Talabi",
    "david bertsch": "David Bertsch",
    "jeremy utley": "Jeremy Utley",
    "bobby mcdonald": "Bobby McDonald",
    "wenhai pan": "Wenhai Pan",
    "taylor seaton": "Taylor Seaton",
    "andrei pavlov": "Andrei Pavlov",
    "senthil thangaraj": "Senthil Thangaraj",
    "santhosh selvaraj": "Santhosh Selvaraj",
    "arnaldo brasil": "Arnaldo Brasil",

    # Songwriters & Authors
    "abraham plammootil": "Abraham Plammootil",
    "graham kendrick": "Graham Kendrick",
    "don moen": "Don Moen",
    "robin mark": "Robin Mark",
    "brian doerksen": "Brian Doerksen",
    "don francisco": "Don Francisco",
    "paul washer": "Paul Washer",
    "billy graham": "Billy Graham",
    "பில்லி கிரஹாம்": "Billy Graham",
}

KNOWN_SPEAKERS_SORTED = sorted(KNOWN_SPEAKERS_MAP.keys(), key=lambda x: len(x), reverse=True)

BLACKLIST_TERMS = {
    'holy spirit', 'jesus christ', 'word of god', 'bible study', 'sunday service',
    'sunday message', 'cfc india', 'cfc bangalore', 'christian fellowship',
    'fellowship church', 'gods word', 'daily devotion', 'morning devotion',
    'youth meeting', 'church service', 'conference message', 'special meeting',
    'tamil message', 'hindi message', 'telugu message', 'malayalam message',
    'english message', 'nccf church', 'rlcf church', 'new covenant', 'river of life',
    'cfc live', 'live stream', 'part', 'chapter', 'verse', 'session', 'godly life',
    'spiritual life', 'new covenant life', 'old covenant', 'new testament', 'old testament',
    'full sermon', 'full message', 'clip message', 'tamil christian song', 'the great commandment',
    'sharing time', 'brothers sharing', 'church sharing', 'bread breaking', 'main message',
    'family meeting', 'child dedication', 'youth camp songs', 'special sunday meeting',
    'wednesday meeting', 'sunday special meeting', 'wednesday special meeting',
    'all that jesus taught', 'through the bible', 'devotion to christ', 'title', 'subject', 'topic', 'series'
}

STOP_WORDS = {
    'and', 'in', 'the', 'of', 'for', 'with', 'at', 'on', 'to', 'from', 'by', 'as',
    'during', 'while', 'when', 'after', 'before', 'about', 'over', 'under', 'into', 'upon', 'through',
    'part', 'session', 'chapter', 'verse', 'message', 'sermon', 'sharing', 'service',
    'meeting', 'live', 'stream', 'video', 'tamil', 'english', 'hindi', 'telugu', 'malayalam',
    'today', 'day', 'date', 'place', 'church', 'fellowship', 'sunday', 'wednesday',
    'speaks', 'spoke', 'teaching', 'study', 'answers', 'questions', 'qa', 'q&a', 'title', 'subject', 'topic', 'series'
}

HEURISTIC_PATTERNS = [
    re.compile(r'(?:Bro\.?|Brother|Br\.|Dr\.|Pastor|Pr\.|Sister|Sis\.|சகோ\.?|சகோதரர்|சகோதரி)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,2}|[\u0B80-\u0BFF]+(?:\s+[\u0B80-\u0BFF]+){0,2})'),
    re.compile(r'(?:Speaker:?|by)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,2}|[\u0B80-\u0BFF]+(?:\s+[\u0B80-\u0BFF]+){1,2})', re.I),
    re.compile(r'[-|–—]\s*([A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,2})\s*$', re.M),
    re.compile(r'\|\s*([A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,2})\s*$', re.M),
]


def clean_extracted_name(raw: str) -> str:
    cleaned = re.sub(r'^(?:Bro\.?|Brother|Br\.|Dr\.|Pastor|Pr\.|Sister|Sis\.|சகோ\.?|சகோதரர்|சகோதரி)\s*', '', raw, flags=re.I).strip()
    cleaned = re.sub(r'[\r\n\t]+', ' ', cleaned).strip()
    cleaned = re.sub(r'\s*[-|–—:,]\s*$', '', cleaned).strip()
    return cleaned


def extract_speaker(title: str, description: str, default_speaker: str) -> str:
    """
    Extracts the speaker name from title/description:
    1. Checks for known speakers (and transliterations/aliases).
    2. If no known match, uses heuristic pattern extraction for any person name.
    3. Falls back to default_speaker (uploader or channel name).
    """
    title = title or ""
    description = description or ""
    title_lower = title.lower()
    desc_lower = description.lower()

    # 1. Match known speakers in title
    for key in KNOWN_SPEAKERS_SORTED:
        pattern = r'(?:\b|_)' + re.escape(key) + r'(?:\b|_)' if re.match(r'^[a-z0-9\s\.]+$', key) else re.escape(key)
        if re.search(pattern, title_lower):
            return KNOWN_SPEAKERS_MAP[key]

    # 2. Match known speakers in description
    for key in KNOWN_SPEAKERS_SORTED:
        pattern = r'(?:\b|_)' + re.escape(key) + r'(?:\b|_)' if re.match(r'^[a-z0-9\s\.]+$', key) else re.escape(key)
        if re.search(pattern, desc_lower):
            return KNOWN_SPEAKERS_MAP[key]

    # 3. Heuristic Person Name Extraction from Title, then Description
    for text in [title, description]:
        for p in HEURISTIC_PATTERNS:
            for m in p.finditer(text):
                candidate = clean_extracted_name(m.group(1))
                if len(candidate) >= 3 and candidate.lower() not in BLACKLIST_TERMS:
                    # Trim trailing / leading stop words
                    parts = candidate.split()
                    while parts and parts[-1].lower() in STOP_WORDS:
                        parts.pop()
                    while parts and parts[0].lower() in STOP_WORDS:
                        parts.pop(0)

                    if 1 <= len(parts) <= 3:
                        trimmed_name = ' '.join(parts)
                        if trimmed_name.lower() in BLACKLIST_TERMS:
                            continue
                        # Check words are capitalized or Tamil
                        if all(p[0].isupper() or ord(p[0]) > 127 for p in parts if p):
                            if not any(p.lower() in STOP_WORDS for p in parts):
                                return trimmed_name.title() if trimmed_name.isascii() else trimmed_name

    return default_speaker


def is_short_content(
    title: str,
    desc: str,
    duration: int,
    width: int = 0,
    height: int = 0,
    is_song_channel: bool = False,
) -> bool:
    """
    Returns True if the video is detected as a YouTube Short.
    Criteria:
    - Duration <= 90 seconds (standard YouTube Short limit) - skipped for song channels
    - Vertical aspect ratio (height > width > 0)
    - Explicit hashtag (#short or #shorts)
    """
    if not is_song_channel and 0 < duration <= 90:
        return True
    if height > 0 and width > 0 and height > width:
        return True
    combined = f"{title} {desc}".lower()
    if "#short" in combined or "#shorts" in combined:
        return True
    return False


# --------------------------------------------------------------------------- #
# Audio Extraction
# --------------------------------------------------------------------------- #
def extract_audio(video_id: str, out_dir: Path) -> tuple[Path, dict]:
    """
    Extracts high-quality MP3 audio and video metadata using yt-dlp.
    """
    url = f"https://www.youtube.com/watch?v={video_id}"
    log.info("  extracting audio from %s...", url)

    cmd = [
        "yt-dlp",
        "--no-playlist",
        "--extract-audio",
        "--audio-format", "mp3",
        "--audio-quality", "0",
        "--write-info-json",
        "-o", str(out_dir / f"{video_id}.%(ext)s"),
        url,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"yt-dlp extraction failed: {result.stderr.strip()[-500:]}")

    mp3_path = out_dir / f"{video_id}.mp3"
    if not mp3_path.exists():
        matches = list(out_dir.glob(f"{video_id}*.mp3"))
        if not matches:
            raise RuntimeError(f"yt-dlp finished but no mp3 file found in {out_dir}")
        mp3_path = matches[0]

    metadata: dict[str, Any] = {}
    info_path = mp3_path.with_suffix(".info.json")
    if not info_path.exists():
        # Check original video_id pattern
        candidate = out_dir / f"{video_id}.info.json"
        if candidate.exists():
            info_path = candidate

    if info_path.exists():
        try:
            with open(info_path, "r", encoding="utf-8") as f:
                info = json.load(f)
                metadata = {
                    "title": info.get("title", ""),
                    "description": info.get("description", ""),
                    "tags": info.get("tags", []),
                    "duration": int(info.get("duration", 0)),
                    "thumbnail": info.get("thumbnail") or f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg",
                    "uploader": info.get("uploader", ""),
                    "width": int(info.get("width") or 0),
                    "height": int(info.get("height") or 0),
                }
        except Exception as e:
            log.warning("  failed to parse info.json: %s", e)

    return mp3_path, metadata


# --------------------------------------------------------------------------- #
# Processing Orchestration
# --------------------------------------------------------------------------- #
def parse_duration_seconds(dur: str | None) -> int:
    """Parses DB duration text ('52:26', '1:14:33') into seconds."""
    if not dur:
        return 0
    parts = str(dur).strip().split(":")
    try:
        nums = [int(p) for p in parts if p != ""]
    except ValueError:
        return 0
    if not nums:
        return 0
    total = 0
    for n in nums:
        total = total * 60 + n
    return total


def process_video(db: Database, audiocom: AudioComClient, cfg: Config, row: tuple) -> None:
    video_id, title, channel, published_at, db_desc, channel_lang, channel_id, db_duration, db_thumbnail = row
    log.info(">> Processing video: %s | %s (%s)", video_id, title, channel)

    db.mark_processing(video_id)
    try:
        series_id = slugify(channel)

        # Skip YouTube Shorts up-front when possible (DB title hint) so we don't
        # download audio for content that would be discarded anyway.
        db_title = (title or "").strip()
        if db_title and ("#short" in db_title.lower() or "#shorts" in db_title.lower()):
            log.info("  >> Skipping %s: short hashtag in title",
                     video_id)
            db.mark_short(video_id)
            return

        with tempfile.TemporaryDirectory(prefix="proc_", dir=str(cfg.work_dir)) as tmp:
            tmp_path = Path(tmp)

            # 0. Check if the track is already in the Neon audio catalog
            #    BEFORE doing any download or upload.
            existing_track = db.find_audio_track(series_id, video_id)
            if existing_track:
                if audiocom.is_audio_live(existing_track["audioUrl"]):
                    log.info("  >> Track %s already in the Neon audio catalog (%s). Reusing.",
                             video_id, existing_track["audioUrl"])
                    return (video_id, existing_track["audioUrl"])
                log.warning("  >> Track %s references deleted Audio.com audio (%s). Removing and re-uploading.",
                            video_id, existing_track["audioUrl"])
                db.delete_audio_track(series_id, video_id)

            # 1. Title-match against Audio.com BEFORE downloading the audio:
            #    if an upload with this title already exists and is not wired to
            #    another track, register it directly from DB metadata and skip
            #    the download+upload entirely.
            referenced_ids = db.referenced_audio_ids()
            matched_id = None
            for candidate_id in audiocom.find_existing_title_ids(title or ""):
                if candidate_id in referenced_ids:
                    continue
                if not audiocom.is_audio_live(f"https://audio.com/{candidate_id}"):
                    log.warning("  >> Title match %s points at deleted Audio.com audio (%s). Skipping.",
                                title, candidate_id)
                    continue
                matched_id = candidate_id
                break

            if matched_id:
                audio_url = f"https://audio.com/{matched_id}"
                stream_url = audiocom._resolve_stream_url(matched_id)
                speaker = extract_speaker(title, db_desc, channel or "Unknown")
                primary_lang, _ = detect_languages(title or "", db_desc, map_language(channel_lang))
                thumbnail = db_thumbnail or f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"
                pub_date = published_at if isinstance(published_at, str) or hasattr(published_at, "isoformat") else None
                log.info("  >> Found existing Audio.com upload '%s' (id: %s). Registering track without download.",
                         title, matched_id)
                db.upsert_audio_series_and_track(
                    series_id=series_id,
                    series_title=channel.strip() or "General Sermons",
                    series_description=f"Audio sermons and messages from {channel.strip() or 'General Sermons'}",
                    series_speaker=speaker,
                    series_category=detect_category(channel),
                    series_language=map_language(primary_lang),
                    cover_url=thumbnail,
                    channel_id=channel_id,
                    published_at=pub_date,
                    track={
                        "id": video_id,
                        "title": title,
                        "speaker": speaker,
                        "youtubeVideoId": video_id,
                        "thumbnailUrl": thumbnail,
                        "publishedAt": pub_date,
                        "durationSeconds": parse_duration_seconds(db_duration),
                        "audioUrl": audio_url,
                        "streamUrl": stream_url,
                    },
                )
                if channel.strip():
                    col_id = audiocom.get_or_create_collection(channel.strip())
                    if col_id:
                        audiocom.add_to_collection(col_id, str(matched_id))
                log.info(">> Successfully completed (reused existing upload): %s", video_id)
                return (video_id, audio_url)

            # 2. No match: download the audio from YouTube.
            audio_file, meta = extract_audio(video_id, tmp_path)

            final_title = meta.get("title") or title or "Untitled Audio"
            final_desc = meta.get("description") or db_desc or ""
            final_tags = meta.get("tags") or []
            default_speaker = meta.get("uploader") or channel or "Unknown"
            speaker = extract_speaker(final_title, final_desc, default_speaker)
            primary_lang, secondary_lang = detect_languages(final_title, final_desc, map_language(channel_lang))
            duration = meta.get("duration") or 0
            thumbnail = meta.get("thumbnail") or f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"
            width = meta.get("width", 0)
            height = meta.get("height", 0)

            # Skip YouTube Shorts
            is_song = detect_category(channel) == "Songs"
            if is_short_content(final_title, final_desc, duration, width, height, is_song_channel=is_song):
                log.info("  >> Skipping %s: detected as YouTube Short (duration: %ss, %sx%s)", video_id, duration, width, height)
                db.mark_short(video_id)
                return

            # Build rich Audio.com metadata tags (speaker, languages, channel)
            audio_tags = list(final_tags)
            for meta_tag in [speaker, primary_lang, secondary_lang, channel]:
                if meta_tag and meta_tag not in audio_tags:
                    audio_tags.append(meta_tag)

            # 3. Upload to Audio.com (and link to channel collection). The
            #    upload path re-checks title dedupe as a final safety net and
            #    only reuses an orphan (unreferenced) upload.
            audio_url, stream_url = audiocom.upload_audio(
                audio_file,
                {
                    "title": final_title,
                    "description": video_id,
                    "tags": audio_tags,
                },
                collection_name=channel,
                referenced_ids=referenced_ids,
            )

            # 4. Register the track and its series directly in PostgreSQL (Neon)
            pub_date = published_at if isinstance(published_at, str) or hasattr(published_at, "isoformat") else None
            series_title = channel.strip() or "General Sermons"
            db.upsert_audio_series_and_track(
                series_id=series_id,
                series_title=series_title,
                series_description=f"Audio sermons and messages from {series_title}",
                series_speaker=speaker,
                series_category=detect_category(channel),
                series_language=map_language(primary_lang),
                cover_url=thumbnail,
                channel_id=channel_id,
                published_at=pub_date,
                track={
                    "id": video_id,
                    "title": final_title,
                    "speaker": speaker,
                    "youtubeVideoId": video_id,
                    "thumbnailUrl": thumbnail,
                    "publishedAt": pub_date,
                    "durationSeconds": int(duration),
                    "audioUrl": audio_url,
                    "streamUrl": stream_url,
                },
            )

            log.info(">> Successfully completed: %s", video_id)
            return (video_id, audio_url)

    except Exception as e:
        err = str(e)
        permanent = is_permanent_failure(err)
        log.error(">> Failed processing %s: %s%s", video_id, "PERMANENT " if permanent else "", err)
        db.mark_failed(video_id, err, permanent=permanent)
        return None


# --------------------------------------------------------------------------- #
# Main Entry Point
# --------------------------------------------------------------------------- #
_running = True


def handle_signal(sig, frame):
    global _running
    log.info("Received signal %s, stopping gracefully...", sig)
    _running = False


def main():
    parser = argparse.ArgumentParser(description="YouTube Video Processor for ChristianApp")
    parser.add_argument("--video-id", help="Process a single YouTube video ID")
    parser.add_argument("--once", action="store_true", help="Process one batch and exit")
    parser.add_argument("--redo", action="store_true", help="Re-process completed videos")
    parser.add_argument("--retry-failed", action="store_true", help="(Deprecated: failed videos are always retried daily)")
    parser.add_argument("--limit", type=int, help="Override batch limit")
    parser.add_argument("--channels", type=str, help="Comma-separated channel name filter (ILIKE match, e.g. 'CFC,NCCF')")
    parser.add_argument("--purge-audiocom", action="store_true", help="Delete ALL existing Audio.com uploads before processing")
    args = parser.parse_args()

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    cfg = load_config(args)

    if cfg.channel_filters:
        log.info("Starting YouTube Video Processor (channels: %s)...", cfg.channel_filters)
    else:
        log.info("Starting YouTube Video Processor service...")

    db = Database(cfg.database_url)
    audiocom = AudioComClient(cfg.audio_com_token)

    # Purge all Audio.com uploads if requested
    if cfg.purge_audiocom:
        log.info("=== PURGING ALL AUDIO.COM UPLOADS ===")
        audiocom.purge_all()
        log.info("=== PURGE COMPLETE ===")

    db.release_stale_processing()

    completed_buffer: list[tuple[str, str]] = []

    def flush_batch():
        if not completed_buffer:
            return
        log.info("Flushing batch: %d video(s) to Neon DB...", len(completed_buffer))
        db.batch_mark_completed(completed_buffer)
        log.info("Batch of %d video(s) successfully marked completed in DB.", len(completed_buffer))
        completed_buffer.clear()

    # Single video mode
    if cfg.video_id:
        row = db.fetch_one(cfg.video_id)
        if not row:
            log.error("Video ID %s not found in database.", cfg.video_id)
            sys.exit(1)
        res = process_video(db, audiocom, cfg, row)
        if res:
            db.mark_completed(res[0], res[1])
        return

    # Continuous polling loop
    try:
        while _running:
            videos = db.fetch_eligible_videos(cfg)
            if not videos:
                flush_batch()
                if cfg.once:
                    log.info("No eligible videos found, exiting (--once).")
                    break
                log.info("No pending videos from ChristianApp channels. Sleeping %ds...", cfg.poll_interval)
                for _ in range(cfg.poll_interval):
                    if not _running:
                        break
                    time.sleep(1)
                continue

            log.info("Found %d video(s) to process.", len(videos))
            for row in videos:
                if not _running:
                    break
                res = process_video(db, audiocom, cfg, row)
                if res:
                    completed_buffer.append(res)
                    if len(completed_buffer) >= cfg.batch_limit:
                        flush_batch()

            flush_batch()
            if cfg.once:
                break
    finally:
        flush_batch()
        db.close()
        log.info("YouTube Video Processor stopped.")


if __name__ == "__main__":
    main()
