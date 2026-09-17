"""Semantic idea segmentation and Ollama concept summarization.

Segments transcript sentences into contiguous idea blocks using cosine similarity
valleys between consecutive sentence embeddings (from Local Postgres).
Each segmented idea block is then summarized by Ollama (gemma3:4b).
"""

import json
import logging
import os
import re
import time

log = logging.getLogger("chunker.llm")

OLLAMA_TIMEOUT = int(os.environ.get("OLLAMA_TIMEOUT", "90"))

SUMMARIZE_PROMPT = (
    "You are an expert sermon analyst. You receive a contiguous block of sentences "
    "from a Christian sermon. Summarize the core teaching and thought expressed.\n"
    "Rules:\n"
    "- Return ONLY valid JSON, no markdown fences, no conversational text.\n"
    "- title: A clear, descriptive 4-7 word concept title.\n"
    "- summary: A 1-2 sentence concise standalone summary of what the speaker is teaching.\n"
    '- JSON shape: {"title": "...", "summary": "..."}\n'
)


def _robust_json_loads(text: str) -> dict:
    """Parse an LLM JSON reply tolerating markdown fences and trailing commas."""
    text = (text or "").strip()
    fenced = re.search(r"```(?:json)?\s*(.*?)```", text, re.DOTALL)
    if fenced:
        text = fenced.group(1).strip()
    start = text.find("{")
    if start == -1:
        raise ValueError("no JSON object found in model reply")
    depth = 0
    in_str = False
    esc = False
    end = -1
    for i in range(start, len(text)):
        ch = text[i]
        if esc:
            esc = False
            continue
        if in_str and ch == "\\":
            esc = True
            continue
        if ch == '"':
            in_str = not in_str
            continue
        if in_str:
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = i
                break
    if end == -1:
        raise ValueError("unbalanced JSON braces in model reply")
    block = text[start : end + 1]
    block = re.sub(r",\s*([}\]])", r"\1", block)
    return json.loads(block)


class LLM:
    def __init__(self, url: str, model: str, timeout: int = OLLAMA_TIMEOUT):
        import requests

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
        for attempt in range(1, 3):
            try:
                resp = self._requests.post(
                    self.base,
                    json=payload,
                    timeout=self.timeout,
                )
                resp.raise_for_status()
                content = resp.json()["choices"][0]["message"]["content"]
                return _robust_json_loads(content)
            except Exception as e:
                log.warning("  Ollama call attempt %d/2 failed: %s", attempt, e)
                if attempt < 2:
                    time.sleep(2)
        raise RuntimeError("Ollama call failed after retries")


def cosine_similarity(v1: list[float], v2: list[float]) -> float:
    """Cosine similarity between two vectors (vectors are already L2 normalized)."""
    if not v1 or not v2 or len(v1) != len(v2):
        return 0.0
    return float(sum(a * b for a, b in zip(v1, v2)))


def segment_sentences_by_similarity(
    sentences: list[dict],
    embeddings: list[list[float]],
    min_sentences: int = 5,
    max_sentences: int = 25,
) -> list[list[dict]]:
    """Segment a sequence of sentences into contiguous idea blocks using similarity valleys."""
    n = len(sentences)
    if n <= min_sentences:
        return [sentences]

    # Calculate consecutive pairwise cosine similarity
    sims = [cosine_similarity(embeddings[i], embeddings[i + 1]) for i in range(n - 1)]

    # 3-window moving average smoothing to avoid spurious 1-sentence noise
    smoothed: list[float] = []
    for i in range(len(sims)):
        window = sims[max(0, i - 1) : min(len(sims), i + 2)]
        smoothed.append(sum(window) / len(window))

    # Identify candidate split points
    splits: list[int] = []
    last_split = 0

    for i in range(len(smoothed)):
        current_len = (i + 1) - last_split
        # Must have at least min_sentences
        if current_len < min_sentences:
            continue

        # Force split if reached max_sentences
        if current_len >= max_sentences:
            splits.append(i + 1)
            last_split = i + 1
            continue

        # Check for valley (local minimum)
        is_valley = True
        if i > 0 and sims[i] > sims[i - 1]:
            is_valley = False
        if i < len(sims) - 1 and sims[i] >= sims[i + 1]:
            is_valley = False

        # If it is a valley and below similarity threshold
        if is_valley and sims[i] < 0.75:
            splits.append(i + 1)
            last_split = i + 1

    # Ensure tail is captured
    if not splits or splits[-1] < n:
        splits.append(n)

    # Assemble groups
    groups: list[list[dict]] = []
    prev = 0
    for s_idx in splits:
        group = sentences[prev:s_idx]
        if group:
            groups.append(group)
        prev = s_idx

    # If the last group is too small (< min_sentences) and there are prior groups, merge it
    if len(groups) > 1 and len(groups[-1]) < min_sentences:
        small_tail = groups.pop()
        groups[-1].extend(small_tail)

    return groups


def summarize_idea(llm: LLM | None, sentences: list[dict]) -> dict:
    """Summarize an idea group using Ollama with a fast heuristic fallback."""
    passage = " ".join(s.get("text", "") for s in sentences).strip()
    first_sentence = sentences[0].get("text", "").strip() if sentences else "Sermon Segment"

    fallback = {
        "title": first_sentence[:60].strip(),
        "summary": passage[:200].strip(),
    }

    if not llm or len(passage) < 20:
        return fallback

    user_prompt = f"Passage to summarize:\n\n{passage[:2000]}\n\nReturn JSON title and summary."
    try:
        data = llm.chat_json(SUMMARIZE_PROMPT, user_prompt)
        title = (data.get("title") or fallback["title"]).strip().strip('"')
        summary = (data.get("summary") or fallback["summary"]).strip().strip('"')
        return {"title": title[:100], "summary": summary[:500]}
    except Exception as e:
        log.warning("  Ollama summarization fallback used: %s", e)
        return fallback