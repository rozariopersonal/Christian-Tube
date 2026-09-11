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
from datetime import datetime
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

        query = f"""
            SELECT v.id, v.title, COALESCE(v."channelName", c.name, 'Unknown'), v."publishedAt", v.description, c.language
            FROM "Video" v
            JOIN "Channel" c ON c.id = v."channelId"
            WHERE v.type = 'VIDEO'
              AND (c."isActive" = true OR c."isActive" IS NULL)
              AND (v."audioUploadStatus" IS NULL OR v."audioUploadStatus" IN ({ph}))
              {retry_clause}
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

    def upload_audio(self, audio_file: Path, metadata: dict, collection_name: str | None = None) -> str:
        title = metadata.get("title", "Untitled Sermon")[:100]
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

        # 4. Associate with collection if requested
        if collection_name:
            col_id = self.get_or_create_collection(collection_name)
            if col_id:
                self.add_to_collection(col_id, str(audio_id))

        # 5. Update track metadata
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
        log.info("  successfully uploaded to Audio.com: %s", audio_url)
        return audio_url


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

    def upsert(self, path: str, content: str, message: str) -> None:
        sha: str | None = None
        get_resp = self._requests.get(self._url(path), headers=self.headers, timeout=20)
        if get_resp.status_code == 200:
            sha = get_resp.json().get("sha")

        encoded = base64.b64encode(content.encode("utf-8")).decode("ascii")
        payload: dict[str, Any] = {"message": message, "content": encoded}
        if sha:
            payload["sha"] = sha

        put_resp = self._requests.put(self._url(path), headers=self.headers, json=payload, timeout=30)
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
    """
    series_id = slugify(channel_name)
    series_title = channel_name.strip() or "General Sermons"
    series_lang = map_language(channel_lang)
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
            "category": "Sermons",
            "language": series_lang,
            "tracks": [],
        }

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
        if not existing_entry.get("coverUrl") and series_data.get("coverUrl"):
            existing_entry["coverUrl"] = series_data["coverUrl"]
    else:
        cat_data.append({
            "id": series_data["id"],
            "title": series_data["title"],
            "description": series_data["description"],
            "speaker": series_data["speaker"],
            "trackCount": series_data["trackCount"],
            "category": series_data["category"],
            "language": series_data["language"],
            "coverUrl": series_data.get("coverUrl"),
        })

    repo.upsert(
        catalog_path,
        json.dumps(cat_data, indent=2, ensure_ascii=False),
        f"audio catalog: sync series {series_id} ({series_data['trackCount']} tracks)",
    )
    log.info("  synced track with GitHub releases audio catalog (series: %s)", series_id)


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
            speaker = meta.get("uploader") or channel or "Unknown"
            duration = meta.get("duration") or 0
            thumbnail = meta.get("thumbnail") or f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"

            # 1. Upload to Audio.com (and link to channel collection)
            audio_url = audiocom.upload_audio(
                audio_file,
                {
                    "title": final_title,
                    "description": final_desc,
                    "tags": final_tags,
                },
                collection_name=channel,
            )

            # 2. Update GitHub Releases Audio Catalog under channel collection/series
            pub_date = published_at.isoformat() if hasattr(published_at, "isoformat") else str(published_at)
            series_id = slugify(channel)
            update_channel_audio_catalog(
                repo,
                channel_name=channel,
                channel_lang=channel_lang,
                track={
                    "id": video_id,
                    "title": final_title,
                    "seriesId": series_id,
                    "seriesTitle": channel,
                    "speaker": speaker,
                    "channelName": channel,
                    "youtubeVideoId": video_id,
                    "tags": final_tags,
                    "thumbnailUrl": thumbnail,
                    "publishedAt": pub_date,
                    "durationSeconds": int(duration),
                    "audioUrl": audio_url,
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
    args = parser.parse_args()

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    cfg = load_config(args)
    log.info("Starting YouTube Video Processor service (repo: %s)...", cfg.github_repo)

    db = Database(cfg.database_url)
    audiocom = AudioComClient(cfg.audio_com_token)
    repo = GitHubRepo(cfg.github_repo, cfg.github_token)

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
