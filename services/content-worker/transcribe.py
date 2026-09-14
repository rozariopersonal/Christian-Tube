"""Transcription for the content-worker.

Audio comes from the ready-made Audio.com URL already stored on the video row
(`audioUrl`). Captions are tried first (YouTube subs for the video id); when
they are unavailable the audio is transcribed locally with NVIDIA Parakeet
(NeMo). Everything degrades gracefully to a timestamp-less transcript if NEITHER
yields timestamps.
"""

import logging
import os
import re
import shutil
import subprocess
import time

log = logging.getLogger("content-worker.transcribe")

PARAKEET_MODEL = os.environ.get("PARAKEET_MODEL", "nvidia/parakeet-tdt-0.6b-v3")
USE_CAPTIONS = os.environ.get("USE_CAPTIONS", "true").lower() != "false"
CAPTIONS_TIMEOUT = int(os.environ.get("CAPTIONS_TIMEOUT", "120"))

_FFMPEG = shutil.which("ffmpeg")


# --------------------------------------------------------------------------- #
# Timestamp parsing / formatting
# --------------------------------------------------------------------------- #
def fmt_ts(sec: float) -> str:
    sec = max(0, int(float(sec)))
    m, s = divmod(sec, 60)
    h, m = divmod(m, 60)
    if h:
        return f"{h:d}:{m:02d}:{s:02d}"
    return f"{m:02d}:{s:02d}"


def parse_duration(duration: str | None) -> float | None:
    if not duration:
        return None
    d = str(duration).strip()
    m = re.match(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", d, re.IGNORECASE)
    if m:
        h, mi, s = (int(x or 0) for x in m.groups())
        return float(h * 3600 + mi * 60 + s)
    parts = [float(p) for p in re.findall(r"\d+(?:\.\d+)?", d)]
    if not parts:
        return None
    if len(parts) == 1:
        return parts[0]
    total = 0.0
    for p in parts:
        total = total * 60 + p
    return total


def _ts_to_sec(raw: str) -> float:
    parts = [float(p) for p in raw.replace(",", ".").split(":")]
    total = 0.0
    for p in parts:
        total = total * 60 + p
    return total


# --------------------------------------------------------------------------- #
# Captions-first (yt-dlp)
# --------------------------------------------------------------------------- #
def _parse_vtt(text: str) -> list[dict]:
    cues: list[dict] = []
    for block in re.split(r"\n\s*\n", text):
        lines = [ln for ln in block.splitlines() if ln and not ln.startswith(("WEBVTT", "Kind:", "Language:"))]
        time_lines = [ln for ln in lines if "-->" in ln]
        if not time_lines:
            continue
        start, _, end = time_lines[0].partition("-->")
        body = " ".join(
            re.sub(r"<[^>]+>", "", ln).replace("&nbsp;", " ")
            for ln in lines
            if "-->" not in ln
        ).strip()
        if body:
            cues.append({"start": _ts_to_sec(start.strip().split()[0]), "end": _ts_to_sec(end.strip().split()[0]), "text": body})
    return cues


def _parse_srt(text: str) -> list[dict]:
    cues: list[dict] = []
    for block in re.split(r"\n\s*\n", text.strip()):
        lines = [ln for ln in block.splitlines()]
        if len(lines) < 2 or "-->" not in lines[1]:
            continue
        start, _, end = lines[1].partition("-->")
        body = " ".join(lines[2:]).strip()
        if body:
            cues.append({"start": _ts_to_sec(start.strip()), "end": _ts_to_sec(end.strip()), "text": body})
    return cues


def extract_captions(video_id: str, work_dir) -> list[dict]:
    """Try to fetch YouTube subtitles for the video. Empty list => none found."""
    tmp = os.path.join(work_dir, "caps")
    os.makedirs(tmp, exist_ok=True)
    try:
        import yt_dlp  # noqa: E402

        opts = {
            "skip_download": True,
            "writesubtitles": True,
            "writeautomaticsub": True,
            "subtitleslangs": ["en.*"],
            "subtitlesformat": "vtt/srt",
            "keepvideo": False,
            "paths": {"home": tmp},
            "outtmpl": video_id + ".%(ext)s",
            "quiet": True,
            "no_warnings": True,
            "noplaylist": True,
            "socket_timeout": 30,
        }
        with yt_dlp.YoutubeDL(opts) as ydl:
            ydl.download([f"https://www.youtube.com/watch?v={video_id}"])
    except Exception as e:  # noqa: BLE001
        log.warning("  caption download failed: %s", e)
        return []

    segments: list[dict] = []
    for name in sorted(os.listdir(tmp)):
        if not name.startswith(video_id):
            continue
        path = os.path.join(tmp, name)
        try:
            text = open(path, encoding="utf-8-sig").read()
        except Exception:  # noqa: BLE001
            continue
        cues = _parse_vtt(text) if name.lower().endswith(".vtt") else _parse_srt(text)
        if cues:
            segments = cues
            break
    shutil.rmtree(tmp, ignore_errors=True)
    return segments


# --------------------------------------------------------------------------- #
# Audio from Audio.com + ffmpeg -> wav
# --------------------------------------------------------------------------- #
def _extract_audio_id(audio_url: str) -> str | None:
    m = re.search(r"(\d{6,})/?$", audio_url.strip().rstrip("/"))
    return m.group(1) if m else None


def resolve_stream_url(page_url: str, token: str, timeout: int = 30) -> str:
    """Resolves an Audio.com landing page to its direct CDN stream URL."""
    import requests  # noqa: E402

    audio_id = _extract_audio_id(page_url)
    if not audio_id:
        return page_url  # already a direct URL
    headers = {"Authorization": f"Bearer {token}"}
    resp = requests.get(
        f"https://api.audio.com/v1/audio/view?id={audio_id}",
        headers=headers,
        timeout=timeout,
    )
    resp.raise_for_status()
    play = resp.json().get("play") or {}
    stream = play.get("url") or play.get("stream_url") or play.get("streamUrl")
    if not stream:
        raise RuntimeError(f"Audio.com stream not resolvable for {page_url}")
    return stream


def download_audio(audio_url: str, dest: str, token: str = "", timeout: int = 300) -> bool:
    import requests  # noqa: E402

    try:
        resource = audio_url
        if token and "audio.com/" in audio_url:
            resource = resolve_stream_url(audio_url, token)
        with requests.get(resource, stream=True, timeout=timeout) as r:
            r.raise_for_status()
            with open(dest, "wb") as f:
                shutil.copyfileobj(r.raw, f, length=1024 * 256)
        return os.path.getsize(dest) > 0
    except Exception as e:  # noqa: BLE001
        log.warning("  audio download failed: %s", e)
        return False


def to_wav(mp3_path: str, wav_path: str) -> bool:
    if not _FFMPEG:
        log.error("  ffmpeg not found; cannot decode audio")
        return False
    cmd = [_FFMPEG, "-y", "-i", mp3_path, "-ar", "16000", "-ac", "1", "-f", "wav", wav_path]
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=600)
    except Exception as e:  # noqa: BLE001
        log.warning("  ffmpeg failed: %s", e)
        return False
    return proc.returncode == 0 and os.path.exists(wav_path)


# --------------------------------------------------------------------------- #
# Parakeet (NeMo) ASR
# --------------------------------------------------------------------------- #
class ParakeetTranscriber:
    """NVIDIA Parakeet-TDT transcription with window timestamps."""

    WINDOW_SEC = 20.0

    def __init__(self, model_id: str = PARAKEET_MODEL):
        from nemo.collections.asr.models import ASRModel  # noqa: E402

        started = time.time()
        self.model = ASRModel.from_pretrained(model_id)
        log.info("Parakeet '%s' loaded in %.1fs", model_id, time.time() - started)

    def transcribe(self, wav_path: str) -> list[dict]:
        """Transcribes in fixed 20s windows so every segment has a timestamp."""
        try:
            waveform, sr = self._load_wav(wav_path)
        except Exception as e:  # noqa: BLE001
            log.warning("  wav load failed: %s", e)
            return []
        total = waveform.shape[-1] / sr
        win = int(self.WINDOW_SEC * sr)
        segments: list[dict] = []
        for start in range(0, waveform.shape[-1], win):
            chunk = waveform[start : start + win]
            try:
                text = self._decode(chunk)
            except Exception as e:  # noqa: BLE001
                log.warning("  window decode failed at %.0fs: %s", start / sr, e)
                text = None
            if text and text.strip():
                segments.append(
                    {
                        "start": round(start / sr, 1),
                        "end": round(min((start + win) / sr, total), 1),
                        "text": text.strip(),
                    }
                )
        return segments

    def _decode(self, chunk) -> str:
        result = self.model.transcribe([chunk], batch_size=1, verbose=False)
        item = result[0]
        if hasattr(item, "text"):
            return item.text
        return str(item).strip()

    @staticmethod
    def _load_wav(wav_path: str):
        import soundfile  # noqa: E402
        import torch  # noqa: E402

        data, sr = soundfile.read(wav_path, dtype="float32")
        if data.ndim > 1:
            data = data.mean(axis=1)
        return torch.from_numpy(data), sr


# --------------------------------------------------------------------------- #
# Orchestration
# --------------------------------------------------------------------------- #
def build_transcript(segments: list[dict]) -> str:
    lines = []
    for seg in segments:
        s = seg["start"]
        e = seg.get("end")
        ts = fmt_ts(s or 0)
        if e is not None:
            ts += f" {fmt_ts(e)}"
        lines.append(f"[{ts}] {seg['text'].strip()}")
    return "\n".join(lines)


class TranscriptResult:
    def __init__(self, source: str, segments: list[dict], transcript: str):
        self.source = source
        self.segments = segments
        self.transcript = transcript
        self.max_sec = max((s.get("end") or s.get("start") or 0 for s in segments), default=0)


def get_transcript(video_id: str, audio_url: str, work_dir, transcriber: ParakeetTranscriber | None) -> TranscriptResult:
    """Captions-first, Parakeet fallback. Never raises for a partial transcript."""
    audio_token = os.environ.get("AUDIO_COM_TOKEN", "")
    if USE_CAPTIONS:
        caps = extract_captions(video_id, work_dir)
        if caps:
            log.info("  used YouTube captions (%d cues)", len(caps))
            return TranscriptResult("caption", caps, build_transcript(caps))

    if not audio_url:
        raise RuntimeError("no audioUrl and no captions available")

    mp3 = os.path.join(work_dir, f"{video_id}.mp3")
    wav = os.path.join(work_dir, f"{video_id}.wav")
    try:
        if not download_audio(audio_url, mp3, audio_token):
            raise RuntimeError("audio download failed")
        if not to_wav(mp3, wav):
            raise RuntimeError("audio decode failed")
        if transcriber is None:
            raise RuntimeError("no ASR transcriber configured")
        segs = transcriber.transcribe(wav)
        if not segs or not any(s.get("text") for s in segs):
            raise RuntimeError("Parakeet returned an empty transcript")
        log.info("  used Parakeet ASR (%d segments)", len(segs))
        return TranscriptResult("parakeet", segs, build_transcript(segs))
    finally:
        for p in (mp3, wav):
            try:
                os.remove(p)
            except FileNotFoundError:
                pass
            except OSError:
                pass