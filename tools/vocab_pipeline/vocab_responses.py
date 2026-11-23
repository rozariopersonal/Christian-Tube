"""Validate vocabulary responses and retry only unresolved occurrences."""

import json
from collections import Counter


POS_ABBR_TO_FULL = {
    "n": "noun", "v": "verb", "adj": "adjective", "adv": "adverb",
    "pron": "pronoun", "part": "particle", "prep": "particle",
    "conj": "conjunction", "num": "numeral", "interj": "interjection",
}
DEFINITION_FIELDS = {
    "c": "canonical", "d": "definition_ta",
    "m": "modern_equivalent", "e": "english_word",
}
DEFINITION_LIMITS = {"c": 80, "d": 360, "m": 80, "e": 120}


def response_schema(requested=None):
    """Keep selection output small without reducing definition requirements."""
    schema = {
        "type": "object",
        "properties": {
            "definitions": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "i": {"type": "integer"},
                        "p": {"type": "string", "enum": list(POS_ABBR_TO_FULL)},
                        **{key: {"type": "string", "minLength": 1, "maxLength": DEFINITION_LIMITS[key]}
                           for key in DEFINITION_FIELDS},
                    },
                    "required": ["i", "p", *DEFINITION_FIELDS],
                    "additionalProperties": False,
                },
            },
            "selections": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "i": {"type": "integer"},
                        "id": {"type": ["integer", "null"]},
                    },
                    "required": ["i", "id"],
                    "additionalProperties": False,
                },
            },
        },
        "required": ["definitions", "selections"],
        "additionalProperties": False,
    }
    if requested is not None:
        for key, task in (("definitions", "define"), ("selections", "select")):
            indices = [item["i"] for item in requested if item["task"] == task]
            schema["properties"][key]["maxItems"] = len(indices)
            if indices:
                schema["properties"][key]["items"]["properties"]["i"]["enum"] = indices
    return schema


def validate_response(response, requested):
    """Accept complete, uniquely indexed items belonging to this request only."""
    definitions, selections = {}, {}
    if not isinstance(response, dict):
        return definitions, selections
    expected = {item["i"]: item for item in requested}
    for key, task in (("definitions", "define"), ("selections", "select")):
        entries = response.get(key, [])
        if not isinstance(entries, list):
            continue
        indices = Counter(item.get("i") for item in entries
                          if isinstance(item, dict) and type(item.get("i")) is int)
        for item in entries:
            if not isinstance(item, dict):
                continue
            idx = item.get("i")
            if type(idx) is not int or indices[idx] != 1:
                continue
            request = expected.get(idx)
            if request is None or request["task"] != task:
                continue
            if task == "select":
                word_id = item.get("id")
                allowed = {candidate["id"] for candidate in request["candidates"]}
                if type(word_id) is int and word_id in allowed:
                    selections[idx] = word_id
                continue
            pos = item.get("p")
            if not isinstance(pos, str) or pos not in POS_ABBR_TO_FULL:
                continue
            if any(not isinstance(item.get(field), str) or not item[field].strip()
                   or len(item[field].strip()) > DEFINITION_LIMITS[field]
                   for field in DEFINITION_FIELDS):
                continue
            definitions[idx] = {
                "pos": POS_ABBR_TO_FULL[pos],
                **{name: item[key].strip() for key, name in DEFINITION_FIELDS.items()},
            }
    return definitions, selections


def resolve_items(verse_text, missing, ambiguous, call, *, batch_size=6, attempts=3):
    """Retain validated results across attempts; never guess an unresolved item."""
    if batch_size < 1 or attempts < 1:
        raise ValueError("batch_size and attempts must be positive")
    items = [{"i": tok["i"], "w": tok["w"], "task": "define"}
             for tok in missing]
    items.extend({
        "i": tok["i"], "w": tok["w"], "task": "select",
        "candidates": [{
            "id": c["word_id"], "p": c["pos"],
            "c": c["canonical"], "d": c["definition_ta"],
        } for c in tok["candidates"]],
    } for tok in ambiguous)
    if len({item["i"] for item in items}) != len(items):
        raise ValueError("Each requested occurrence must have a unique index")
    definitions, selections = {}, {}
    for offset in range(0, len(items), batch_size):
        pending = items[offset:offset + batch_size]
        for attempt in range(attempts):
            if not pending:
                break
            # Tamil output can exceed English-oriented token estimates. Retry
            # smaller groups with more room per definition instead of repeating
            # the same truncated request. Every occurrence has at most 3 tries.
            groups = 2 ** attempt
            chunk_size = max(1, (len(pending) + groups - 1) // groups)
            next_pending = []
            for start in range(0, len(pending), chunk_size):
                requested = pending[start:start + chunk_size]
                prompt = (f"Verse Context:\n{verse_text}\n\nWords to analyze:\n"
                          + json.dumps(requested, ensure_ascii=False, separators=(",", ":")))
                definition_count = sum(item["task"] == "define" for item in requested)
                base = (max(500, definition_count * 250 + (len(requested) - definition_count) * 24)
                        if definition_count else max(128, len(requested) * 24))
                budget = min(2000, base * groups)
                response = call(prompt, num_predict=budget, schema=response_schema(requested))
                valid_defs, valid_selections = validate_response(response, requested)
                definitions.update(valid_defs)
                selections.update(valid_selections)
                next_pending.extend(item for item in requested
                                    if item["i"] not in definitions and item["i"] not in selections)
            pending = next_pending
    return definitions, selections
