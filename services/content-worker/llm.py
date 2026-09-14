"""Ollama (Qwen) idea extraction for video transcripts.

The transcript is split into overlapping windows so long sermons fit the
model context. Each window yields JSON ideas; windows are merged and
near-duplicate quotes are dropped. No API keys are involved - the model runs
locally (Docker reaches the host via OLLAMA_URL).
"""

import json
import logging
import os
import re
import time

log = logging.getLogger("content-worker.llm")

# Transcript windows of ~6000 chars with ~800 chars of overlap.
WINDOW_CHARS = int(os.environ.get("OLLAMA_WINDOW_CHARS", "6000"))
WINDOW_OVERLAP = int(os.environ.get("OLLAMA_WINDOW_OVERLAP", "800"))
OLLAMA_TIMEOUT = int(os.environ.get("OLLAMA_TIMEOUT", "900"))

SYSTEM_PROMPT = (
    "You are an expert sermon analyst. You receive a timestamped transcript of a "
    "Christian sermon. Extract the ideas, thoughts and concepts the speaker "
    "communicated. Rules:\n"
    "- Return ONLY valid JSON, no markdown, no commentary.\n"
    "- Each idea is one self-contained thought or concept (3-8 sentences max).\n"
    "- The statement must be readable standalone without the transcript.\n"
    "- The quote must be the EXACT verbatim text from the transcript.\n"
    "- start_sec/end_sec are the SECOND offsets where the idea begins and ends, "
    "derived from the [MM:SS] markers in the transcript.\n"
    "- Include the scripture references and people mentioned in the keywords.\n"
    '- JSON shape: {"ideas":[{"title":"...","statement":"...","quote":"...","start_sec":123,"end_sec":144,"keywords":["..."]}]}\n'
    "Return 4 to 8 ideas."
)


def parse_timestamps_markers(transcript: str) -> float:
    """Largest end timestamp seen in [MM:SS -> MM:SS] markers (seconds)."""
    max_sec = 0.0
    for m in re.finditer(r"\[(\d{1,2}):(\d{2})\s*->\s*(\d{1,2}):(\d{2})\]", transcript):
        end = int(m.group(3)) * 60 + int(m.group(4))
        max_sec = max(max_sec, float(end))
    return max_sec


def _windowize(text: str) -> list[str]:
    if len(text) <= WINDOW_CHARS:
        return [text]
    windows: list[str] = []
    start = 0
    while start < len(text):
        end = min(start + WINDOW_CHARS, len(text))
        if end < len(text):
            # extend to the next line so we do not cut mid-sentence
            nl = text.find("\n", max(end - 200, start))
            if nl != -1:
                end = nl
        windows.append(text[start:end])
        if end >= len(text):
            break
        start = max(end - WINDOW_OVERLAP, start + 1)
    return windows


class LLM:
    def __init__(self, url: str, model: str, timeout: int = OLLAMA_TIMEOUT):
        import requests  # noqa: E402

        self._requests = requests
        self.url = url.rstrip("/")
        self.base = f"{self.url}/v1/chat/completions"
        self.model = model
        self.timeout = timeout

    def chat_json(self, system: str, user: str) -> dict:
        payload = {
            "model": self.model,
            "stream": False,
            "temperature": 0.1,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "response_format": {"type": "json_object"},
        }
        last_err: Exception | None = None
        for attempt in range(1, 4):
            try:
                resp = self._requests.post(
                    self.base,
                    json=payload,
                    timeout=self.timeout,
                )
                resp.raise_for_status()
                content = resp.json()["choices"][0]["message"]["content"]
                return json.loads(content)
            except Exception as e:  # noqa: BLE001
                last_err = e
                log.warning("  Ollama call attempt %d/3 failed: %s", attempt, e)
                if attempt < 3:
                    time.sleep(min(10 * attempt, 30))
        raise last_err or RuntimeError("Ollama call failed after retries")


def _norm_idea(idea: dict, max_sec: float) -> dict | None:
    statement = (idea.get("statement") or "").strip()
    if not statement:
        statement = (idea.get("title") or "").strip()
    if not statement:
        return None
    title = (idea.get("title") or statement[:80]).strip()
    quote = (idea.get("quote") or "").strip()
    start = idea.get("start_sec")
    end = idea.get("end_sec")
    try:
        start = float(start)
    except (TypeError, ValueError):
        start = None
    try:
        end = float(end)
    except (TypeError, ValueError):
        end = None
    if end is None:
        end = start + 60 if start is not None else None
    if start is None or end is None:
        start = end = None
    start = max(0.0, min(start, max_sec)) if start is not None else None
    end = max(0.0, min(end, max_sec)) if end is not None else None
    if start is not None and end is not None and end < start:
        start, end = end, start
    keywords = [str(k).strip() for k in (idea.get("keywords") or []) if str(k).strip()]
    return {
        "title": title,
        "statement": statement,
        "quote": quote,
        "start_sec": start,
        "end_sec": end,
        "keywords": keywords,
    }


def extract_ideas(llm: LLM, transcript: str, max_sec: float) -> list[dict]:
    ideas: list[dict] = []
    seen_quotes: set[str] = set()
    for window in _windowize(transcript):
        user = (
            f"Transcript (timestamps in seconds markers):\n\n{window}\n\n"
            "Extract the ideas as JSON."
        )
        data = llm.chat_json(SYSTEM_PROMPT, user)
        raw = data.get("ideas") or []
        for idea in raw:
            norm = _norm_idea(idea, max_sec)
            if not norm:
                continue
            key = (norm["quote"] or norm["statement"])[:120]
            if key in seen_quotes:
                continue
            seen_quotes.add(key)
            ideas.append(norm)
    # Prefer idea order from transcript windows; cap to a sane maximum
    return ideas[:50]