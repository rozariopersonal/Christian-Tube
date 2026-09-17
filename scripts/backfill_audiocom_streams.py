#!/usr/bin/env python3
"""Backfill / refresh audio.com ``streamUrl`` values in the releases catalogs.

audio.com uploads are stored in the releases catalogs with an ``audioUrl`` that
points at the human-readable landing page (``https://audio.com/<id>``) and, when
it could be resolved, a ``streamUrl`` that is a *signed* S3 URL on
``s3.ustatik.com``. Signed URLs expire (``X-Amz-Expires=518400`` -> 6 days), so
tracks saved without a ``streamUrl``, and any track whose signature has expired,
will not stream in the app.

This script visits every track under ``releases/audio/series/*.json`` whose
``audioUrl`` is an audio.com page and re-resolves a fresh direct-stream URL via
``GET /v1/audio/view?id=<id>`` (the same endpoint the workers use in
``AudioComClient._resolve_stream_url``). Files are rewritten in place only when
a value actually changes (same serialization: UTF-8, ``ensure_ascii=False``,
indent 2, no trailing newline).

Usage:
    python scripts/backfill_audiocom_streams.py [--dry-run] [--refresh-all]
        [--file releases/audio/series/maasilla_valibam.json]
        [--min-ttl-hours 144] [--limit 10] [--token <AUDIO_COM_TOKEN>]

Token resolution order: ``--token``, then ``AUDIO_COM_TOKEN`` env var, then the
``.processor.env`` file in the repository root.

Run this before every data push so the signed URLs in the catalogs are fresh;
signed URLs otherwise expire ~6 days after they are issued from the audio.com
API.
"""

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import requests

API_BASE = "https://api.audio.com/v1"
AUDIO_COM_RE = re.compile(r"^https?://audio\.com/(\d{6,})/?$")
SERIES_DIR = Path(__file__).resolve().parent.parent / "releases" / "audio" / "series"
REPO_ROOT = Path(__file__).resolve().parent.parent

PRINT = print


def log(msg):
    PRINT(f"[backfill] {msg}")
    sys.stdout.flush()


def load_token(arg_token: str | None) -> str:
    token = arg_token
    if not token:
        token = os.environ.get("AUDIO_COM_TOKEN")
    if not token:
        for candidate in [REPO_ROOT / "envs" / "common.env", REPO_ROOT / ".processor.env"]:
            if candidate.exists():
                for line in candidate.read_text(encoding="utf-8").splitlines():
                    if line.startswith("AUDIO_COM_TOKEN="):
                        token = line.split("=", 1)[1].strip()
                        break
            if token:
                break
    if not token:
        raise SystemExit("AUDIO_COM_TOKEN is required (--token, env, or envs/common.env).")
    return token[7:].strip() if token.lower().startswith("bearer ") else token.strip()


def parse_expiry(stream_url: str) -> datetime | None:
    """Reads the S3 signature window from a signed URL, or None when unparseable."""
    try:
        qs = parse_qs(urlparse(stream_url).query)
        date_str = (qs.get("X-Amz-Date") or [""])[0]
        expires_s = (qs.get("X-Amz-Expires") or [""])[0]
        if not date_str or not expires_s.isdigit():
            return None
        signed = datetime.strptime(date_str, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
        return signed + timedelta(seconds=int(expires_s))
    except (ValueError, IndexError):
        return None


class AudioComClient:
    def __init__(self, token: str):
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
        }
        self.session = requests.Session()

    def resolve(self, audio_id: str, max_attempts: int = 3, delay: float = 2.0) -> str | None:
        for attempt in range(1, max_attempts + 1):
            try:
                resp = self.session.get(
                    f"{API_BASE}/audio/view?id={audio_id}",
                    headers=self.headers,
                    timeout=20,
                )
                if resp.status_code == 429:
                    time.sleep(min(30, delay * attempt * 5))
                    continue
                if resp.status_code == 200:
                    play = (resp.json() or {}).get("play") or {}
                    stream = play.get("url") or play.get("stream_url") or play.get("streamUrl")
                    if stream:
                        return stream
                elif resp.status_code not in (404,):
                    log(f"  view?id={audio_id} HTTP {resp.status_code}")
            except requests.RequestException as e:
                log(f"  view?id={audio_id} error: {e}")
            if attempt < max_attempts:
                time.sleep(delay)
        return None


def collect_tracks(file: Path):
    """Yields (index, track) for every audio.com track in a catalog file."""
    data = json.loads(file.read_text(encoding="utf-8"))
    tracks = data.get("tracks") or []
    for i, track in enumerate(tracks):
        match = AUDIO_COM_RE.match(str(track.get("audioUrl") or ""))
        if match:
            yield i, track, match.group(1)


def should_refresh(track: dict, min_ttl_hours: int, refresh_all: bool) -> tuple[bool, str]:
    stream = track.get("streamUrl") or ""
    if not stream:
        return True, "missing"
    if refresh_all:
        return True, "refresh-all"
    expiry = parse_expiry(stream)
    if expiry is None:
        return True, "unparseable"
    if expiry <= datetime.now(timezone.utc):
        return True, "expired"
    if min_ttl_hours > 0 and expiry <= datetime.now(timezone.utc) + timedelta(hours=min_ttl_hours):
        return True, f"expires-in-<{min_ttl_hours}h"
    return False, "ok"


def write_json(file: Path, data) -> bool:
    """Writes data back preserving release-file style. No trailing newline."""
    file.parent.mkdir(parents=True, exist_ok=True)
    tmp = file.with_suffix(file.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8", newline="") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.flush()
        os.fsync(f.fileno())
    tmp.replace(file)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="Report what would change without writing.")
    parser.add_argument("--refresh-all", action="store_true", help="Re-resolve every audio.com streamUrl, not only missing/expired.")
    parser.add_argument("--file", type=str, help="Process only this catalog file.")
    parser.add_argument("--min-ttl-hours", type=int, default=0,
                        help="Also refresh URLs expiring within this many hours (0 = only already-expired/missing).")
    parser.add_argument("--limit", type=int, default=0, help="Stop after resolving this many tracks (for testing).")
    parser.add_argument("--token", type=str, default=None, help="audio.com API token (overrides env/.processor.env).")
    args = parser.parse_args()

    client = AudioComClient(load_token(args.token))

    files = [Path(args.file)] if args.file else sorted(SERIES_DIR.glob("*.json"))
    do_files = [f for f in files if f.is_file() and f.suffix == ".json"]
    if not do_files:
        log("no catalog files matched")
        return 0

    overall = {"tracks": 0, "refreshed": 0, "failed": 0, "skipped": 0}
    resolutions = {}  # audio_id -> stream_url (dedupe repeated track-ids across catalogs)

    for file in do_files:
        try:
            data = json.loads(file.read_text(encoding="utf-8"))
        except Exception as e:
            log(f"skip {file.name}: unreadable ({e})")
            continue

        tracks = data.get("tracks")
        if not isinstance(tracks, list):
            log(f"skip {file.name}: no tracks array")
            continue

        changed = False
        file_stats = {"audiostream": 0, "refreshed": 0, "failed": 0, "skipped": 0}

        for i, track in enumerate(tracks):
            if not isinstance(track, dict):
                continue
            match = AUDIO_COM_RE.match(str(track.get("audioUrl") or ""))
            if not match:
                continue
            audio_id = match.group(1)
            file_stats["audiostream"] += 1
            overall["tracks"] += 1

            need, reason = should_refresh(track, args.min_ttl_hours, args.refresh_all)
            if not need:
                file_stats["skipped"] += 1
                overall["skipped"] += 1
                continue

            # Resolve once per unique audio_id; old uploads are already
            # transcoded so a bounded poll is more than enough.
            if audio_id not in resolutions:
                resolutions[audio_id] = client.resolve(audio_id, max_attempts=3, delay=2.0)
            stream = resolutions[audio_id]

            if stream:
                if track.get("streamUrl") != stream:
                    track["streamUrl"] = stream
                    changed = True
                file_stats["refreshed"] += 1
                overall["refreshed"] += 1
                log(f"{file.name}#{i} {track.get('id')} -> streamUrl ({reason})")
            else:
                file_stats["failed"] += 1
                overall["failed"] += 1
                log(f"{file.name}#{i} {track.get('id')} FAILED ({reason})")

            if args.limit and overall["refreshed"] + file_stats["failed"] >= args.limit:
                break

        if changed and not args.dry_run:
            write_json(file, data)
            log(f"wrote {file.name}")
        elif changed and args.dry_run:
            log(f"dry-run: would write {file.name}")
        else:
            log(f"no changes: {file.name}")

        PRINT(f"[backfill] {file.name}: audio.com={file_stats['audiostream']} "
              f"refreshed={file_stats['refreshed']} failed={file_stats['failed']} skipped={file_stats['skipped']}")

    PRINT(f"[backfill] DONE tracks={overall['tracks']} refreshed={overall['refreshed']} "
          f"failed={overall['failed']} skipped={overall['skipped']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())