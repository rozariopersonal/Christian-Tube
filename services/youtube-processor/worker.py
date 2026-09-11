#!/usr/bin/env python3
"""
YouTube Video Processor for ChristianApp.

Monitors the ChristianApp PostgreSQL database, extracts audio from
active ChristianApp channel videos (strictly excluding shorts), uploads
them to Audio.com with rich metadata, and registers them in the public
GitHub Releases audio catalog.
"""

from __future__ import annotations

import argparse
import base64
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
from datetime import datetime, timezone
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
# Configuration
# --------------------------------------------------------------------------- #
class Config:
    def __init__(
        self,
        database_url: str,
        github_repo: str,
        github_token: str,
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
        purge_audiocom: bool = False,
    ):
        self.database_url = database_url
        self.github_repo = github_repo
        self.github_token = github_token
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
        self.purge_audiocom = purge_audiocom


def load_config(args: argparse.Namespace) -> Config:
    # Auto-load .processor.env if present
    for candidate in [Path(".processor.env"), Path("../.processor.env"), Path("../../.processor.env")]:
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

    def _env(name: str, default: str = "") -> str:
        return os.environ.get(name, default).strip()

    db_url = _env("DATABASE_URL")
    gh_token = _env("GITHUB_TOKEN")
    audio_token = _env("AUDIO_COM_TOKEN")

    if not db_url:
        log.error("DATABASE_URL is required in environment.")
        sys.exit(1)

    if not gh_token:
        log.error("GITHUB_TOKEN is required in environment (fine-grained PAT with Contents: read/write).")
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

    return Config(
        database_url=db_url,
        github_repo=_env("GITHUB_REPO", "rozariopersonal/Christian-Tube-Releases"),
        github_token=gh_token,
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

    def _ensure_schema(self) -> None:
        """Ensure audioUrl and audioUploadStatus columns exist on Video."""
        try:
            self.cur.execute("""
                ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "audioUrl" TEXT;
                ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "audioUploadStatus" TEXT DEFAULT 'pending';
                ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "audioRetryCount" INT DEFAULT 0;
                ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "audioLastError" TEXT;
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
        """
        statuses = ["pending"]
        include_failed = False
        if cfg.redo:
            statuses = ["pending", "completed", "failed"]
        elif cfg.retry_failed:
            statuses.append("failed")
            include_failed = True

        ph = ",".join(["%s"] * len(statuses))
        params: list[Any] = list(statuses)
        retry_clause = ""
        if include_failed:
            retry_clause = ' AND ("audioRetryCount" IS NULL OR "audioRetryCount" < %s)'
            params.append(cfg.max_retries)

        # Channel name filter (--channels flag)
        channel_clause = ""
        if cfg.channel_filters:
            channel_or = " OR ".join(["c.name ILIKE %s" for _ in cfg.channel_filters])
            channel_clause = f" AND ({channel_or})"
            params.extend([f"%{f}%" for f in cfg.channel_filters])

        query = f"""
            SELECT v.id, v.title, COALESCE(v."channelName", c.name, 'Unknown'), v."publishedAt", v.description, c.language
            FROM "Video" v
            JOIN "Channel" c ON c.id = v."channelId"
            WHERE v.type = 'VIDEO'
              AND (c."isActive" = true OR c."isActive" IS NULL)
              AND c.name NOT ILIKE '%%short%%'
              AND c.id != 'UC_ChristianTubeOfficial'
              AND v.title NOT ILIKE '%%#short%%'
              AND (v.description IS NULL OR v.description NOT ILIKE '%%#short%%')
              AND (v."duration" IS NULL OR (v."duration" != '0:00' AND v."duration" NOT LIKE '0:0%%'))
              AND (v."audioUploadStatus" IS NULL OR v."audioUploadStatus" IN ({ph}))
              {retry_clause}
              {channel_clause}
            ORDER BY v."publishedAt" DESC
            LIMIT %s
        """
        params.append(cfg.batch_limit)
        self.cur.execute(query, params)
        return self.cur.fetchall()

    def fetch_one(self, video_id: str) -> tuple | None:
        self.cur.execute(
            """SELECT v.id, v.title, COALESCE(v."channelName", c.name, 'Unknown'), v."publishedAt", v.description, c.language
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
               SET "audioUploadStatus"='completed', "audioUrl"=%s, "audioLastError"=NULL
               WHERE "id"=%s""",
            (audio_url, video_id),
        )

    def mark_failed(self, video_id: str, error: str) -> None:
        self.cur.execute(
            """UPDATE "Video"
               SET "audioUploadStatus"='failed',
                   "audioLastError"=%s,
                   "audioRetryCount"=COALESCE("audioRetryCount", 0) + 1
               WHERE "id"=%s""",
            (error[:2000], video_id),
        )

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
        """Finds if an audio track with this title already exists on Audio.com."""
        clean_target = title.strip().lower()
        if not hasattr(self, "_existing_audio_cache"):
            self._existing_audio_cache = {}
            try:
                page = 1
                while True:
                    resp = self._requests.get(
                        f"{self.api}/audio/list",
                        headers=self.headers,
                        params={"page": page, "limit": 100},
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
                        t = (item.get("title") or "").strip().lower()
                        aid = str(item.get("id", ""))
                        if t and aid and t not in self._existing_audio_cache:
                            self._existing_audio_cache[t] = aid
                    if len(items) < 100:
                        break
                    page += 1
            except Exception as e:
                log.warning("  failed to populate existing audio cache: %s", e)

        return self._existing_audio_cache.get(clean_target)

    def upload_audio(
        self,
        audio_file: Path,
        metadata: dict,
        collection_name: str | None = None,
        image_bytes: bytes | None = None,
    ) -> tuple[str, str | None]:
        """
        Uploads audio to Audio.com and returns (audio_url, stream_url).
        - audio_url:  human-readable landing page (https://audio.com/{id})
        - stream_url: direct CDN audio file URL for streaming (resolved after
                       transcoding), or None if transcoding hasn't completed.
        """
        title = metadata.get("title", "Untitled Sermon")[:100]

        # 0. Check if track with this title was already uploaded
        existing_id = self.find_existing_track_id(title)
        if existing_id:
            log.info("  track '%s' already exists on Audio.com (id: %s), reusing existing", title, existing_id)
            audio_url = f"https://audio.com/{existing_id}"
            stream_url = self._resolve_stream_url(existing_id)
            return audio_url, stream_url

        file_size = audio_file.stat().st_size
        mime = "audio/mpeg" if audio_file.suffix.lower() == ".mp3" else "audio/wav"

        log.info("  requesting presigned upload URL from Audio.com (%d bytes, %s)...", file_size, mime)

        # 1. Create audio entity & presigned URL
        resp = self._requests.post(
            f"{self.api}/audio/create",
            headers=self.headers,
            json={
                "title": title,
                "category": "podcast",
                "mime": mime,
                "size": file_size,
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

        # 6. Update track metadata
        log.info("  updating track metadata on Audio.com...")
        desc = (metadata.get("description") or "")[:2000]
        tags = (metadata.get("tags") or [])[:5]

        update_resp = self._requests.put(
            f"{self.api}/audio/{audio_id}",
            headers=self.headers,
            json={
                "title": title,
                "description": desc,
                "tags": tags,
                "isPublic": True,
            },
            timeout=30,
        )
        if update_resp.status_code not in (200, 204):
            log.warning("Audio.com metadata update warning: %s %s", update_resp.status_code, update_resp.text[:300])

        audio_url = f"https://audio.com/{audio_id}"

        # 7. Resolve direct stream URL (poll for transcoding completion)
        stream_url = self._resolve_stream_url(str(audio_id))

        log.info("  successfully uploaded to Audio.com: %s (stream: %s)", audio_url, stream_url or "pending")
        return audio_url, stream_url

    def _resolve_stream_url(self, audio_id: str, max_attempts: int = 10, delay: int = 3) -> str | None:
        """
        Polls the Audio.com API for the transcoded stream URL.
        Audio.com transcodes uploads asynchronously; the ``play.stream_url``
        field becomes available once processing finishes.
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
                    play = data.get("play") or {}
                    stream = play.get("url") or play.get("stream_url") or play.get("streamUrl")
                    if stream:
                        log.info("  resolved stream URL on attempt %d/%d", attempt, max_attempts)
                        return stream
            except Exception as e:
                log.warning("  stream URL resolve attempt %d failed: %s", attempt, e)

            if attempt < max_attempts:
                time.sleep(delay)

        log.warning("  could not resolve stream URL after %d attempts (transcoding may still be in progress)", max_attempts)
        return None

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


# --------------------------------------------------------------------------- #
# GitHub Releases Catalog
# --------------------------------------------------------------------------- #
class GitHubRepo:
    def __init__(self, repo: str, token: str):
        import requests

        self._requests = requests
        self.api = "https://api.github.com"
        self.repo = repo
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        }

    def _url(self, path: str) -> str:
        return f"{self.api}/repos/{self.repo}/contents/{urllib.parse.quote(path)}"

    def read_text_or_none(self, path: str) -> str | None:
        resp = self._requests.get(self._url(path), headers=self.headers, timeout=20)
        if resp.status_code == 404:
            return None
        resp.raise_for_status()
        data = resp.json()
        if data.get("encoding") == "base64" and data.get("content"):
            return base64.b64decode(data["content"]).decode("utf-8")
        return None

    def upsert(self, path: str, content: str, message: str, max_retries: int = 3) -> None:
        encoded = base64.b64encode(content.encode("utf-8")).decode("ascii")
        for attempt in range(max_retries):
            sha: str | None = None
            get_resp = self._requests.get(self._url(path), headers=self.headers, timeout=20)
            if get_resp.status_code == 200:
                sha = get_resp.json().get("sha")

            payload: dict[str, Any] = {"message": message, "content": encoded}
            if sha:
                payload["sha"] = sha

            put_resp = self._requests.put(self._url(path), headers=self.headers, json=payload, timeout=30)
            if put_resp.status_code in (200, 201):
                return
            if put_resp.status_code == 409 and attempt < max_retries - 1:
                time.sleep(1)
                continue
            put_resp.raise_for_status()


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
    keywords = ["song", "music", "hymn", "worship", "choir", "praise", "paadalgal", "padalgal", "geethangal", "keerthanai", "sangeet"]
    for kw in keywords:
        if kw in combined:
            return "Songs"
    return "General Sermons"


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



def update_channel_audio_catalog(
    repo: GitHubRepo,
    channel_name: str,
    channel_lang: str | None,
    track: dict,
) -> None:
    """
    Registers the uploaded audio track in the GitHub Releases catalog
    under a series/collection named after the channel.
    - Updates audio/series/{channel_slug}.json
    - Updates audio/catalog.json
    - Updates manifest.json with a bumped dataset revision (busts app & CDN cache)
    - Purges jsDelivr edge CDN cache for affected files
    """
    series_id = slugify(channel_name)
    series_title = channel_name.strip() or "General Sermons"
    series_lang = map_language(channel_lang)
    series_category = detect_category(channel_name)
    series_path = f"audio/series/{series_id}.json"

    raw_series = repo.read_text_or_none(series_path)
    if raw_series:
        try:
            series_data = json.loads(raw_series)
        except json.JSONDecodeError:
            series_data = None
    else:
        series_data = None

    if not series_data:
        series_data = {
            "id": series_id,
            "title": series_title,
            "description": f"Audio sermons and messages from {series_title}",
            "speaker": track.get("speaker") or series_title,
            "coverUrl": track.get("thumbnailUrl"),
            "trackCount": 0,
            "category": series_category,
            "language": series_lang,
            "tracks": [],
        }
    else:
        # Update category if it was missing or default
        if series_data.get("category", "General Sermons") == "General Sermons":
            series_data["category"] = series_category

    if series_data.get("category") == "Sermons":
        series_data["category"] = "General Sermons"

    # Ensure track fields reflect the series
    track["seriesId"] = series_id
    track["seriesTitle"] = series_title

    tracks = series_data.get("tracks", [])
    # Deduplicate by youtubeVideoId
    tracks = [t for t in tracks if t.get("youtubeVideoId") != track.get("youtubeVideoId")]
    tracks.insert(0, track)  # newest first
    series_data["tracks"] = tracks
    series_data["trackCount"] = len(tracks)
    if not series_data.get("coverUrl") and track.get("thumbnailUrl"):
        series_data["coverUrl"] = track.get("thumbnailUrl")

    repo.upsert(
        series_path,
        json.dumps(series_data, indent=2, ensure_ascii=False),
        f"audio catalog: add track {track.get('youtubeVideoId')} to {series_id}",
    )

    # Update audio/catalog.json
    catalog_path = "audio/catalog.json"
    raw_cat = repo.read_text_or_none(catalog_path)
    if raw_cat:
        try:
            cat_data = json.loads(raw_cat)
        except json.JSONDecodeError:
            cat_data = []
    else:
        cat_data = []

    # Clean up obsolete 'audiocom_uploads' placeholder if present
    cat_data = [s for s in cat_data if s.get("id") != "audiocom_uploads"]

    existing_entry = next((s for s in cat_data if s.get("id") == series_id), None)
    if existing_entry:
        existing_entry["trackCount"] = series_data["trackCount"]
        existing_entry["title"] = series_data["title"]
        existing_entry["speaker"] = series_data["speaker"]
        existing_entry["language"] = series_data["language"]
        existing_entry["category"] = series_data.get("category", series_category)
        if not existing_entry.get("coverUrl") and series_data.get("coverUrl"):
            existing_entry["coverUrl"] = series_data["coverUrl"]
    else:
        cat_data.append({
            "id": series_data["id"],
            "title": series_data["title"],
            "description": series_data["description"],
            "speaker": series_data["speaker"],
            "trackCount": series_data["trackCount"],
            "category": series_data.get("category", series_category),
            "language": series_data["language"],
            "coverUrl": series_data.get("coverUrl"),
        })

    repo.upsert(
        catalog_path,
        json.dumps(cat_data, indent=2, ensure_ascii=False),
        f"audio catalog: sync series {series_id} ({series_data['trackCount']} tracks)",
    )
    log.info("  synced track with GitHub releases audio catalog (series: %s)", series_id)

    # Bump manifest.json dataset revision so clients and CDNs get fresh data
    manifest_path = "manifest.json"
    raw_manifest = repo.read_text_or_none(manifest_path)
    if raw_manifest:
        try:
            manifest_data = json.loads(raw_manifest)
        except json.JSONDecodeError:
            manifest_data = {}
    else:
        manifest_data = {}

    new_rev = hex(int(time.time()))[2:]
    manifest_data["revision"] = new_rev
    manifest_data["updatedAt"] = datetime.now(timezone.utc).isoformat()

    repo.upsert(
        manifest_path,
        json.dumps(manifest_data, indent=2, ensure_ascii=False),
        f"manifest: bump revision to {new_rev}",
    )
    log.info("  bumped dataset revision to %s in manifest.json", new_rev)

    # Best-effort jsDelivr purge so changes are immediately live on edge CDN
    try:
        import requests
        repo_slug = repo.repo
        for p in [catalog_path, series_path, manifest_path]:
            requests.get(f"https://purge.jsdelivr.net/gh/{repo_slug}@main/{p}", timeout=5)
    except Exception as e:
        log.debug("  jsDelivr purge skipped: %s", e)


def is_short_content(title: str, desc: str, duration: int, width: int = 0, height: int = 0) -> bool:
    """
    Returns True if the video is detected as a YouTube Short.
    Criteria:
    - Duration <= 90 seconds (standard YouTube Short limit)
    - Vertical aspect ratio (height > width > 0)
    - Explicit hashtag (#short or #shorts)
    """
    if 0 < duration <= 90:
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
def process_video(db: Database, audiocom: AudioComClient, repo: GitHubRepo, cfg: Config, row: tuple) -> None:
    video_id, title, channel, published_at, db_desc, channel_lang = row
    log.info(">> Processing video: %s | %s (%s)", video_id, title, channel)

    db.mark_processing(video_id)
    try:
        with tempfile.TemporaryDirectory(prefix="proc_", dir=str(cfg.work_dir)) as tmp:
            tmp_path = Path(tmp)
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
            if is_short_content(final_title, final_desc, duration, width, height):
                log.info("  >> Skipping %s: detected as YouTube Short (duration: %ss, %sx%s)", video_id, duration, width, height)
                db.mark_short(video_id)
                return

            # Build rich Audio.com metadata tags (speaker, languages, channel)
            audio_tags = list(final_tags)
            for meta_tag in [speaker, primary_lang, secondary_lang, channel]:
                if meta_tag and meta_tag not in audio_tags:
                    audio_tags.append(meta_tag)

            # Build rich Audio.com description header
            lang_str = primary_lang
            if secondary_lang:
                lang_str += f" / {secondary_lang}"
            desc_header = f"Speaker: {speaker} | Language: {lang_str} | Channel: {channel}"
            rich_desc = f"{desc_header}\n\n{final_desc}" if final_desc else desc_header

            # 1. Upload to Audio.com (and link to channel collection)
            audio_url, stream_url = audiocom.upload_audio(
                audio_file,
                {
                    "title": final_title,
                    "description": rich_desc,
                    "tags": audio_tags,
                },
                collection_name=channel,
            )

            # 2. Update GitHub Releases Audio Catalog under channel collection/series
            pub_date = published_at.isoformat() if hasattr(published_at, "isoformat") else str(published_at)
            series_id = slugify(channel)
            update_channel_audio_catalog(
                repo,
                channel_name=channel,
                channel_lang=primary_lang,
                track={
                    "id": video_id,
                    "title": final_title,
                    "seriesId": series_id,
                    "seriesTitle": channel,
                    "speaker": speaker,
                    "language": primary_lang,
                    "secondaryLanguage": secondary_lang,
                    "channelName": channel,
                    "youtubeVideoId": video_id,
                    "tags": final_tags,
                    "thumbnailUrl": thumbnail,
                    "publishedAt": pub_date,
                    "durationSeconds": int(duration),
                    "audioUrl": audio_url,
                    "streamUrl": stream_url,
                },
            )

            # 3. Mark completed in DB
            db.mark_completed(video_id, audio_url)
            log.info(">> Successfully completed: %s", video_id)

    except Exception as e:
        log.error(">> Failed processing %s: %s", video_id, e)
        db.mark_failed(video_id, str(e))


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
    parser.add_argument("--retry-failed", action="store_true", help="Include failed videos")
    parser.add_argument("--limit", type=int, help="Override batch limit")
    parser.add_argument("--channels", type=str, help="Comma-separated channel name filter (ILIKE match, e.g. 'CFC,NCCF')")
    parser.add_argument("--purge-audiocom", action="store_true", help="Delete ALL existing Audio.com uploads before processing")
    args = parser.parse_args()

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    cfg = load_config(args)

    if cfg.channel_filters:
        log.info("Starting YouTube Video Processor (repo: %s, channels: %s)...", cfg.github_repo, cfg.channel_filters)
    else:
        log.info("Starting YouTube Video Processor service (repo: %s)...", cfg.github_repo)

    db = Database(cfg.database_url)
    audiocom = AudioComClient(cfg.audio_com_token)
    repo = GitHubRepo(cfg.github_repo, cfg.github_token)

    # Purge all Audio.com uploads if requested
    if cfg.purge_audiocom:
        log.info("=== PURGING ALL AUDIO.COM UPLOADS ===")
        audiocom.purge_all()
        log.info("=== PURGE COMPLETE ===")

    db.release_stale_processing()

    # Single video mode
    if cfg.video_id:
        row = db.fetch_one(cfg.video_id)
        if not row:
            log.error("Video ID %s not found in database.", cfg.video_id)
            sys.exit(1)
        process_video(db, audiocom, repo, cfg, row)
        return

    # Continuous polling loop
    while _running:
        videos = db.fetch_eligible_videos(cfg)
        if not videos:
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
            process_video(db, audiocom, repo, cfg, row)

        if cfg.once:
            break

    db.close()
    log.info("YouTube Video Processor stopped.")


if __name__ == "__main__":
    main()
