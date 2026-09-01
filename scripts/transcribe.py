#!/usr/bin/env python3
"""
transcribe.py — Local Whisper (faster-whisper) transcription for PrivateTube videos.

Downloads the audio for pending videos from YouTube (via yt-dlp), runs the Whisper
model locally on this machine, and writes the transcript back to the PostgreSQL
`Video` table (and optionally Cloudflare R2).

Resume / skip / stop behaviour (driven by the DB `transcriptionStatus` column):
  - `pending`  -> eligible, will be processed.
  - `processing` -> a previous run was interrupted mid-flight. Treated as eligible
    (resume) so the work is re-attempted rather than left dangling.
  - `completed` -> always skipped (unless `--redo` is passed).
  - `failed`    -> skipped by default; re-processed when `--retry-failed` is passed
    and `transcriptionRetryCount < --max-retries`.

Exit codes: 0 = finished, 2 = nothing to do / no videos matched.

Prerequisites (installed once on the machine):
    pip install faster-whisper yt-dlp psycopg2-binary python-dotenv
    ffmpeg must be on PATH (used by both yt-dlp and audio decoding here).
"""

from __future__ import annotations

import argparse
import logging
import os
import subprocess
import sys
import tempfile
import urllib.parse
import wave
from pathlib import Path

import numpy as np

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("transcribe")

# --------------------------------------------------------------------------- #
# Paths / config
# --------------------------------------------------------------------------- #
SCRIPT_DIR = Path(__file__).resolve().parent
BACKEND_DIR = SCRIPT_DIR.parent / "apps" / "backend"
ENV_FILE = BACKEND_DIR / ".env"

# Where models are cached (HF hub). Reuse across runs.
DEFAULT_MODEL_DIR = Path(
    os.environ.get("WHISPER_MODEL_DIR", str(Path.home() / ".cache" / "faster-whisper"))
)

MODEL_SIZE = "small"
DEVICE = "cpu"
COMPUTE_TYPE = "int8"  # CPU-int friendly; ~4x faster than float32 with little loss

# --------------------------------------------------------------------------- #
# .env parsing (no dependency on toolchain, mirrors the backend's own vars)
# --------------------------------------------------------------------------- #
def load_env(path: Path) -> dict:
    env: dict = {}
    if not path.exists():
        log.error("Env file not found: %s", path)
        return env
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        # strip inline comments for unquoted values
        if not (value.startswith('"') or value.startswith("'")):
            value = value.split("#", 1)[0].strip()
        if key:
            env[key] = value
    return env


# --------------------------------------------------------------------------- #
# Database
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
    """Drop non-libpq query params (e.g. Prisma-specific 'schema') that psycopg2 rejects."""
    parsed = urllib.parse.urlsplit(url)
    if not parsed.query:
        return url
    keep = []
    for kv in parsed.query.split("&"):
        if not kv:
            continue
        key = kv.split("=")[0]
        if key in LIBPQ_PARAMS:
            keep.append(kv)
    netloc = parsed.netloc
    # re-encode userinfo in netloc so we don't double-mangle it
    rebuilt = urllib.parse.urlunsplit(
        (parsed.scheme, netloc, parsed.path, "&".join(keep), parsed.fragment)
    )
    return rebuilt


class Database:
    def __init__(self, url: str):
        import psycopg2

        safe_url = sanitize_db_url(url)
        self.conn = psycopg2.connect(safe_url, connect_timeout=30)
        self.conn.autocommit = True
        self.cur = self.conn.cursor()

    def fetch_one(self, video_id: str) -> tuple | None:
        self.cur.execute(
            """SELECT v.id, v.title, v."channelName" FROM "Video" v WHERE v.id = %s""",
            (video_id,),
        )
        return self.cur.fetchone()

    def mark_processing(self, video_id: str) -> None:
        self.cur.execute(
            """UPDATE "Video" SET "transcriptionStatus"='processing',
               "transcriptionProgress"=5, "lastTranscriptionError"=NULL
               WHERE "id"=%s""",
            (video_id,),
        )

    def mark_progress(self, video_id: str, progress: int) -> None:
        self.cur.execute(
            """UPDATE "Video" SET "transcriptionProgress"=%s WHERE "id"=%s""",
            (progress, video_id),
        )

    def mark_completed(self, video_id: str, content: str) -> None:
        self.cur.execute(
            """UPDATE "Video" SET "transcriptionStatus"='completed',
               "content"=%s, "transcriptionProgress"=100, "lastTranscriptionError"=NULL
               WHERE "id"=%s""",
            (content, video_id),
        )

    def mark_failed(self, video_id: str, error: str) -> None:
        self.cur.execute(
            """UPDATE "Video" SET "transcriptionStatus"='failed',
               "lastTranscriptionError"=%s, "transcriptionRetryCount"="transcriptionRetryCount"+1
               WHERE "id"=%s""",
            (error[:2000], video_id),
        )

    def get_metadata(self, video_id: str) -> dict | None:
        self.cur.execute(
            """SELECT title, "channelName", "channelId", description
               FROM "Video" WHERE "id"=%s""",
            (video_id,),
        )
        row = self.cur.fetchone()
        if not row:
            return None
        return {
            "title": row[0],
            "channelName": row[1],
            "channelId": row[2],
            "description": row[3] or "",
        }

    def close(self) -> None:
        self.cur.close()
        self.conn.close()


# --------------------------------------------------------------------------- #
# Audio
# --------------------------------------------------------------------------- #
def find_ffmpeg() -> str:
    for name in ("ffmpeg", "ffmpeg.exe"):
        which = subprocess.run(
            ["where", name], capture_output=True, text=True
        )
        if which.returncode == 0:
            return which.stdout.splitlines()[0].strip()
    raise RuntimeError(
        "ffmpeg not found on PATH. yt-dlp and audio decoding both require it. "
        "Install ffmpeg and add it to PATH."
    )


def download_audio(video_id: str, out_dir: Path, workdir: Path) -> Path:
    """Download a video's audio track to a 16kHz mono WAV using yt-dlp.

    Returns path to the resulting .wav.
    """
    url = f"https://www.youtube.com/watch?v={video_id}"
    log.info("  downloading audio: %s", url)
    # ffmpeg must be visible to yt-dlp
    ffmpeg_dir = str(Path(find_ffmpeg()).parent)
    env = dict(os.environ)
    env["PATH"] = ffmpeg_dir + os.pathsep + env.get("PATH", "")

    cmd = [
        "yt-dlp",
        "--no-playlist",
        "--extract-audio",
        "--audio-format",
        "wav",
        "--audio-quality",
        "0",
        "--postprocessor-args",
        "-ar 16000 -ac 1",
        "-o",
        str(out_dir / f"{video_id}.%(ext)s"),
        url,
    ]
    result = subprocess.run(cmd, cwd=str(workdir), env=env, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"yt-dlp failed: {result.stderr.strip()[-500:]}")

    wav = out_dir / f"{video_id}.wav"
    if not wav.exists():
        # yt-dlp sometimes renames; find any matching wav
        matches = list(out_dir.glob(f"{video_id}.wav"))
        if not matches:
            raise RuntimeError("yt-dlp completed but no wav produced")
        wav = matches[0]
    return wav


def load_wav_to_float32(path: Path) -> np.ndarray:
    """Read a 16-bit mono WAV into a float32 numpy array (no PyAV dependency)."""
    with wave.open(str(path), "rb") as w:
        assert w.getnchannels() == 1, "expected mono audio"
        assert w.getsampwidth() == 2, "expected 16-bit audio"
        n = w.getnframes()
        data = w.readframes(n)
    return np.frombuffer(data, dtype=np.int16).astype(np.float32) / 32768.0


# --------------------------------------------------------------------------- #
# R2 upload (optional)
# --------------------------------------------------------------------------- #
def upload_to_r2(env: dict, video_id: str, content: str) -> None:
    if not all(env.get(k) for k in ("STORAGE_ENDPOINT", "STORAGE_ACCESS_KEY", "STORAGE_SECRET_KEY", "STORAGE_BUCKET")):
        log.info("  R2 not configured; skipping object-store upload (transcript kept in DB).")
        return
    try:
        import boto3
    except ImportError:
        log.warning("  boto3 not installed; skipping R2 upload (pip install boto3).")
        return

    client = boto3.client(
        "s3",
        endpoint_url=env["STORAGE_ENDPOINT"],
        region_name=env.get("STORAGE_REGION", "auto"),
        aws_access_key_id=env["STORAGE_ACCESS_KEY"],
        aws_secret_access_key=env["STORAGE_SECRET_KEY"],
    )
    key = f"transcripts/{video_id}.txt"
    client.put_object(Bucket=env["STORAGE_BUCKET"], Key=key, Body=content.encode("utf-8"), ContentType="text/plain")
    log.info("  uploaded transcript to R2: %s", key)


# --------------------------------------------------------------------------- #
# Whisper
# --------------------------------------------------------------------------- #
class Transcriber:
    def __init__(self, model_size: str, device: str, compute_type: str, model_dir: Path):
        from faster_whisper.transcribe import WhisperModel  # noqa: E402  (av-free import path)

        self.model = WhisperModel(
            model_size,
            device=device,
            compute_type=compute_type,
            download_root=str(model_dir),
        )
        log.info("Loaded Whisper model '%s' (%s/%s) from %s", model_size, device, compute_type, model_dir)

    def transcribe(self, audio: np.ndarray, language: str | None = "en") -> str:
        segments, info = self.model.transcribe(
            audio,
            language=language,
            vad_filter=True,
            beam_size=5,
            condition_on_previous_text=True,
            temperature=[0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
        )
        parts = []
        for seg in segments:
            s = f"[{fmt_ts(seg.start)} -> {fmt_ts(seg.end)}] {seg.text.strip()}"
            parts.append(s)
        return "\n".join(parts)


def fmt_ts(seconds: float) -> str:
    m, s = divmod(int(round(seconds)), 60)
    h, m = divmod(m, 60)
    if h:
        return f"{h:02d}:{m:02d}:{s:02d}"
    return f"{m:02d}:{s:02d}"


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Transcribe pending English videos with local Whisper and write to the DB.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--model", default=MODEL_SIZE, help="Whisper model size (tiny/base/small/medium/large-v3).")
    p.add_argument("--device", default=DEVICE, help="cuda or cpu.")
    p.add_argument("--compute-type", default=COMPUTE_TYPE, help="int8 / float32 / float16.")
    p.add_argument("--language", default="en", help="Whisper language code (None = auto-detect).")
    p.add_argument("--retry-failed", action="store_true", help="Include videos marked 'failed' (if under max-retries).")
    p.add_argument("--max-retries", type=int, default=3, help="Cap on re-processing failed videos.")
    p.add_argument("--redo", action="store_true", help="Re-transcribe videos already marked completed.")
    p.add_argument("--video-id", help="Transcribe a single specific video by YouTube ID (overrides batch).")
    p.add_argument("--dry-run", action="store_true", help="Only report what would be transcribed.")
    p.add_argument("--keep-audio", action="store_true", help="Keep downloaded wav files in the temp dir.")
    p.add_argument("--limit", type=int, default=10, help="Max videos to report/process.")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])

    env = load_env(ENV_FILE)
    # Allow an explicit DATABASE_URL env var to override the .env file (e.g. for testing).
    if os.environ.get("DATABASE_URL"):
        env["DATABASE_URL"] = os.environ["DATABASE_URL"]
    db_url = env.get("DATABASE_URL")
    if not db_url:
        log.error("DATABASE_URL missing from %s", ENV_FILE)
        return 1

    db = Database(db_url)
    try:
        if args.video_id:
            rows = [r for r in [db.fetch_one(args.video_id)] if r]
            if not rows:
                log.error("Video %s not found in database.", args.video_id)
                return 1
        else:
            statuses = ["pending", "processing"]
            if args.redo:
                statuses = ["pending", "processing", "completed", "failed"]
            elif args.retry_failed:
                statuses.append("failed")
            rows = _fetch_for_statuses(db, statuses, args.limit, args.max_retries)

        if not rows:
            log.info("No eligible videos found. Nothing to do.")
            return 2

        log.info("Selected %d video(s):", len(rows))
        for vid, title, ch in rows:
            log.info("  - %s | %s (%s)", vid, title, ch)

        if args.dry_run:
            log.info("DRY RUN — no changes made.")
            return 0

        workdir = Path(tempfile.mkdtemp(prefix="whisper_"))
        tmp_audio = workdir / "audio"
        tmp_audio.mkdir(exist_ok=True)

        try:
            for vid, title, ch in rows:
                _process_one(db, env, (vid, title, ch), args, workdir, tmp_audio)
        finally:
            if not args.keep_audio:
                import shutil

                shutil.rmtree(workdir, ignore_errors=True)
    finally:
        db.close()

    return 0


def _fetch_for_statuses(db, statuses: list, limit: int, max_retries: int):
    ph = ",".join(["%s"] * len(statuses))
    include_failed = "failed" in statuses
    where = f'v."transcriptionStatus" IN ({ph})'
    params: list = list(statuses)
    retry_clause = ""
    if include_failed:
        retry_clause = ' AND "transcriptionRetryCount" < %s'
        params.append(max_retries)
    db.cur.execute(
        f"""
        SELECT v.id, v.title, v."channelName"
        FROM "Video" v
        LEFT JOIN "Channel" c ON c.id = v."channelId"
        WHERE v.type = 'VIDEO'
          AND {where}{retry_clause}
          AND (c.language IS NULL OR c.language = '' OR LOWER(c.language) = 'en')
        ORDER BY v."publishedAt" DESC
        LIMIT %s
        """,
        params + [limit],
    )
    return db.cur.fetchall()


_ML_CACHE: dict = {}


def get_model(args) -> Transcriber:
    """Load (and cache) the Whisper model. Loading is lazy so --dry-run works offline."""
    key = (args.model, args.device, args.compute_type)
    if key not in _ML_CACHE:
        _ML_CACHE[key] = Transcriber(args.model, args.device, args.compute_type, DEFAULT_MODEL_DIR)
    return _ML_CACHE[key]


def _process_one(db, env, row, args, workdir, tmp_audio) -> None:
    vid, title, ch = row

    log.info(">> Processing %s — %s", vid, title)
    try:
        db.mark_processing(vid)
        wav = download_audio(vid, tmp_audio, workdir)
        audio = load_wav_to_float32(wav)
        log.info("  transcribed audio length: %.1f s", len(audio) / 16000)
        content = get_model(args).transcribe(audio, args.language)
        log.info("  transcript length: %d chars", len(content))

        db.mark_completed(vid, content)
        upload_to_r2(env, vid, content)
        log.info(">> Done: %s", vid)
    except Exception as e:  # noqa: BLE001
        log.error(">> Failed %s: %s", vid, e)
        db.mark_failed(vid, str(e))
        return


if __name__ == "__main__":
    sys.exit(main())
