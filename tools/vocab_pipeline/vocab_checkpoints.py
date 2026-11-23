"""Validate chapter coverage and write crash-safe JSON checkpoints."""

import json
import os
import tempfile
from pathlib import Path

from vocab_responses import POS_ABBR_TO_FULL


REQUIRED_FIELDS = ("canonical", "definition_ta", "modern_equivalent", "english_word")


def valid_word(word):
    if not isinstance(word, dict):
        return False
    raw = word.get("word", word.get("raw_token"))
    punctuation = (word.get("pos") == "punctuation" and isinstance(raw, str)
                   and bool(raw) and not raw.strip('.,;:!?()[]"\''))
    return (isinstance(word, dict)
            and isinstance(word.get("pos"), str)
            and (word["pos"] in POS_ABBR_TO_FULL.values() or punctuation)
            and all(isinstance(word.get(key), str) and word[key].strip()
                    for key in REQUIRED_FIELDS))


def verified_words(data, verses, book, chapter):
    """Reuse only whole verses whose fields, token order and source text match."""
    if (not isinstance(data, dict) or type(data.get("book")) is not int
            or type(data.get("chapter")) is not int
            or data["book"] != book or data["chapter"] != chapter):
        return []
    words = data.get("words")
    if not isinstance(words, list):
        return []
    verified = []
    for verse in verses:
        candidates = [word for word in words if isinstance(word, dict)
                      and type(word.get("verse")) is int and word["verse"] == verse["verse"]]
        tokens = verse["text"].split()
        if len(candidates) != len(tokens):
            continue
        if all(valid_word(word) and word.get("word") == raw
               and ("word_index" not in word or type(word["word_index"]) is int
                    and word["word_index"] == idx)
               for idx, (word, raw) in enumerate(zip(candidates, tokens))):
            verified.extend({**word, "word_index": idx} for idx, word in enumerate(candidates))
    return verified


def chapter_complete(data, verses, book, chapter):
    if not isinstance(data, dict) or data.get("is_step1_completed") is not True:
        return False
    expected = sum(len(verse["text"].split()) for verse in verses)
    words = data.get("words", [])
    verified = verified_words(data, verses, book, chapter)
    return (isinstance(words, list) and len(words) == expected and len(verified) == expected
            and [(word.get("verse"), word.get("word")) for word in words]
            == [(word["verse"], word["word"]) for word in verified])


def atomic_json(path, data):
    """Replace a checkpoint only after its complete contents reach disk."""
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=target.parent,
                                         prefix=target.name + ".", suffix=".tmp", delete=False) as fp:
            temporary = fp.name
            json.dump(data, fp, ensure_ascii=False, indent=2)
            fp.flush()
            os.fsync(fp.fileno())
        os.replace(temporary, target)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)
