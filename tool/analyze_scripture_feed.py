#!/usr/bin/env python3
"""
analyze_scripture_feed.py — Agentic pipeline that classifies meditation-worthy
Bible verses.

The existing words feed (releases/scriptures.json, ~19,906 entries) was
auto-generated from Nave's Topical Bible CSV parsing (generate-100k.js) and is
mostly junk — person/place names, verse numbers, and cross-reference strings
survived as "categories". It is useless for a "read & meditate" feed.

This pipeline replaces that source of truth. For every chapter of the Bible it:

  1. Reads the chapter text from a local Bible (default: KJV, public domain) at
     releases/bibles/{version}/{bookNum}/{chapter}.json.
  2. Sends the chapter to a local LLM (Ollama, default qwen2.5:7b) with a
     structured prompt that asks it to extract the *verse ranges* a reader
     could actually meditate on: direct words of God, prophecies, promises,
     commands, wisdom sayings, Jesus' words, core doctrinal/comfort passages.
  3. The LLM returns strict JSON (start/end verse + a category from a fixed
     taxonomy + a short theme + SPECK flags + a verbatim `quote` of the start
     verse). Quote verification: we confirm the quote's words actually sit in
     the numbered verse, correcting the reference when the model picks the
     wrong number (e.g. "enmity... seed" in Gen 3:15 but start:14) and dropping
     passages whose quote matches no verse. We validate ranges against the
     chapter, dedupe, and emit a clean {book,chapter,startVerse,endVerse,
     referenceLabel,category,tags,theme,speck} record.

Output:
  --out-file  the regenerated scriptures.json (default: apps/backend/data/scriptures.json)
  --chunks    if set, also regenerate the words_feed chunk tree (daily, by_letter,
              topics, manifest) next to the out file.

Resume: progress is cached per chapter (--cache-dir). Re-running skips already
analyzed chapters unless --redo.

Example:
  python tool/analyze_scripture_feed.py \
      --bible-version kjv --bible-dir releases/bibles \
      --out-file apps/backend/data/scriptures.json \
      --cache-dir .cache/scripture_feed \
      --books 19 20 ...            # run a subset
  python tool/analyze_scripture_feed.py --clear-cache    # wipe per-chapter cache
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import re
import sys
import time
from pathlib import Path

import requests

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("analyze_scripture_feed")

# --------------------------------------------------------------------------- #
# Config
# --------------------------------------------------------------------------- #
RepoRoot = Path(__file__).resolve().parent.parent
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")
OLLAMA_MODEL = os.environ.get("SCRIPTURE_LLM", "qwen2.5:7b")
NUM_CTX = int(os.environ.get("SCRIPTURE_LLM_CTX", "8192"))
# Number of sentence units sent per LLM call. Sent as one numbered list; the
# model returns one verdict per unit.
BATCH_UNITS = int(os.environ.get("SCRIPTURE_LLM_BATCH", "10"))

# Category taxonomy. Keep it small and semantic enough to feel curated.
CATEGORY_TAXONOMY = {
    "words_of_god": "Direct words spoken by God (Yahweh/Lord).",
    "jesus_words": "Words spoken by Jesus, including the red-letter sayings.",
    "prophecy": "Prophecy about the Messiah, the nations, or future events.",
    "promise": "An explicit promise of God to bless, keep, redeem, or restore.",
    "commandment": "An explicit moral/spiritual command or instruction to obey.",
    "wisdom": "A proverb, adage, or wisdom saying worth memorizing.",
    "doctrine": "A core statement of truth / belief about God, Christ, salvation.",
    "comfort": "A verse of comfort, hope, encouragement, or assurance.",
    "warning": "A solemn warning, exhortation to repent, or consequence of sin.",
    "prayer": "A prayer, petition, or model for prayer.",
    "praise": "A verse of praise, worship, thanksgiving, or doxology.",
    "parable": "A parable or extended illustrative teaching (usually with a key verse).",
    "salvation": "A gospel/salvation passage (faith, grace, eternal life, redemption).",
    "divine_action": "God (Father, Son, or Spirit) acting — creation, redemption, rescue, deliverance, healing, provision, judgment, covenant-making, giving the Spirit, raising the dead. Verse records what God DID or DOES.",
    "consecration": "Commitment, holiness, separation, or wholehearted devotion.",
}
CATEGORIES = list(CATEGORY_TAXONOMY.keys())
CATEGORY_JOINED = ", ".join(CATEGORIES)

# SPECK Bible-study method (Navigator quiet-time acronym). Every selected
# verse may also be flagged with any of these letters it mostly illustrates:
#   S — Sin to confess or avoid
#   P — Promise to claim
#   E — Example to follow
#   C — Command to obey
#   K — Knowledge about God (who He is / what He is like)
#
# Grounding: the classic Navigator SPECK grid for personal quiet time, read
# here in the spirit of A.W. Tozer ("What comes into our minds when we think
# about God is the most important thing about us") and of Zac Poonen's
# verse-by-verse teaching that the Word is a mirror for the inner life — a
# passage is meditation-worthy when it moves the reader to confess, claim,
# follow, obey, or know. K is the foundation: you can only confidently confess
# a sin, claim a promise, follow an example, and obey a command in the measure
# you know who God is. Not every passage contains every letter; most contain
# two or three at most.
SPECK_TAGS = ["S", "P", "E", "C", "K"]
SPECK_MEANINGS = {
    "S": "Sin to confess or avoid",
    "P": "Promise to claim",
    "E": "Example to follow",
    "C": "Command to obey",
    "K": "Knowledge about God",
}
SPECK_GUIDE = {
    "S": (
        "An attitude, motive, word, or act the text exposes as sin or spiritual "
        "danger — something the reader must confess, repent of, or flee from "
        "(greed, pride, unbelief, idolatry, compromise, un-forgiveness, "
        "disobedience). The verbatim text itself must carry the sin (a warning, "
        "or an ungodly act/word). Tag S when confession of that sin IS the "
        "meditation that verse is meant to produce."
    ),
    "P": (
        "A divine pledge the reader can claim in faith — a covenantal promise "
        "God makes, whether of forgiveness, provision, guidance, presence, "
        "strength, or salvation. A promise is something GOD binds HIMSELF to, "
        "not a general truth about the world. The text must contain an "
        "explicit future blessing, oath, covenant, or assurance the reader "
        "can stand on (e.g., 'I will be with you', 'you will receive'). Tag P "
        "only for a genuine, claimable promise."
    ),
    "E": (
        "A person's words, choices, or habits that model godly living and are "
        "worth imitating (faith, humility, patience, boldness, prayer, "
        "servanthood, endurance — the example of Christ, David, Paul, the "
        "early church). The reader asks: whose example am I called to follow "
        "here? Negative examples that warn us NOT to repeat a behavior are "
        "also E (an example to avoid), if the text portrays them as such."
    ),
    "C": (
        "A direct, actionable command — something God tells the reader TO DO "
        "or TO STOP DOING (obey My voice, love your neighbor, do not fear, "
        "repent, forgive, believe, watch, pray). The imperative spirit must be "
        "in the text itself, not inferred. Tag C when the verse's own words "
        "are a call to obedience that the reader can actually perform."
    ),
    "K": (
        "Truth about WHO GOD IS or what He is like — His character, attributes, "
        "ways, holiness, love, sovereignty, justice, mercy, faithfulness, "
        "eternality — revealed by the verse. Tozer's test: did this verse "
        "expand my true knowledge of God? Tag K whenever the verse mainly "
        "reveals God Himself (not merely something about people or events). "
        "K may coincide with P, S, C — but tag K only when the verse genuinely "
        "deepens knowledge of God's nature.\n"
        "K ALSO covers WHAT GOD DOES — a verse that records God acting (His "
        "works, deeds, interventions, providence) reveals Him just as truly "
        "as one describing His nature. Verse of divine action: prefer K on "
        "top of any other letters."
    ),
}

# Background presets available in the app (see chunk_web_assets / app).
BG_PRESETS = [
    "mountain_dawn", "ocean_calm", "desert_dusk",
    "forest_sun", "starry_night",
]

SYSTEM_PROMPT = (
    "You are a careful, faithful Bible reader who curates a daily 'read & "
    "meditate' scripture feed. You are shown a numbered LIST of SENTENCE UNITS "
    "from a Bible chapter. Each unit is one complete thought — one or more "
    "consecutive verses that form a full sentence (a yes/no decision on a "
    "card). For EVERY unit in the list you MUST give an explicit verdict: is "
    "this unit genuinely worth meditating on today — the living words of "
    "Scripture (timeless truth, a direct divine utterance, a promise, a "
    "command, a warning, an inspiring declaration) — or is it excluded "
    "narrative/administrative filler (pure story detail, genealogy, census "
    "lists, measurements, ceremonial minutiae, travel logistics, "
    "burial/geography, plain description of what happened)?\n\n"
    "INCLUDE — if the unit's OWN words are timeless truth or application "
    "(note the *timeless* test — would a reader still be moved by it as "
    "devotional truth 2000 years later, independent of who/when/where?):\n"
    "- promises, commands, warnings, doctrine, prayers, praise, prophecy, "
    "Jesus' words, direct words of God, salvation truth, comfort, wisdom, "
    "consecration, parables, beatitudes, benedictions.\n"
    "- Psalms, Proverbs, the Gospels' teaching, Romans and the epistles' "
    "teaching, Revelation: include nearly every verse.\n"
    "- REVELATION OF GOD = ALWAYS INCLUDE. Any unit that records an ACTION "
    "of God — the Father, the Son (Christ), or the Holy Spirit — is extract-"
    "worthy, whatever its story-form: creation, deliverance (Red Sea, "
    "conquest), healing, provision (manna, rain, water from the rock), "
    "judgment (plagues, flood, Sodom), covenant-making, resurrection, sending "
    "the Spirit, Jesus' works/miracles, the Spirit's works. God's deeds are "
    "timeless revelation of who He is. Report such units under category "
    "'divine_action' when the divine deed is the unit's main charge, and "
    "tag K (knowledge of God through His works). Do NOT exclude a story verse "
    "merely because it is written as history — if God is the subject or actor, "
    "it belongs in the feed.\n\n"
    "EXCLUDE — pure narrative/administrative filler whose words are only "
    "'what happened' with NO divine actor, whose words are only human history "
    "(even if it recounts a command given to one person on one occasion):\n"
    "- genealogy and census (names, ages, 'X lived N years and begat Y', "
    "'X died and was buried'), measurements and dimensions, temple/tabernacle "
    "construction specs, counts of animals/offerings, lists of cities or "
    "tribal allotments.\n"
    "- human historical recounts of journeys, battles, treaties, census-"
    "taking, offerings dedicated, and 'this is how it came about' narration "
    "that simply relates HUMAN events with no divine subject.\n"
    "- a command issued to a specific leader at one moment (e.g. 'go possess "
    "the land', 'turn back to the wilderness', 'number the people') is NOT "
    "timeless unless its principle applies to every reader — ask: can the "
    "reader perform this today? BUT if the same unit also narrates GOD's "
    "action, the verse is INCLUDED regardless (see divine-action rule above).\n"
    "- family lines, birth records, and cultural detail with no devotional "
    "charge.\n\n"
    "Calibrate like a good devotion editor: a psalm, proverb, or teaching "
    "chapter yields most units; a genealogy or census chapter yields 0-2; a "
    "narrative-chronology chapter yields at least its genuinely timeless lines "
    "PLUS every unit where God is the subject or actor.\n"
    "- For every INCLUDED unit give: ONE best category, a short theme label "
    "(6 words max), and SPECK meditation-angle letters. For excluded units, "
    "report include=false and give NO extra fields.\n\n"
    "SELECTED categories (use only these, exactly):\n"
    + "\n".join(f"  {c}: {CATEGORY_TAXONOMY[c]}" for c in CATEGORIES)
    + "\n\nSPECK flags — for an included unit, list which of these five "
    "quiet-time meditation angles its OWN words most genuinely lead the reader "
    "to (2-3 at most; empty is fine — never pad). We can confess, claim, follow, "
    "and obey only in the measure we KNOW God, so where a unit reveals God's "
    "character, prefer K on top of other letters (Tozer's test: does this "
    "expand my true knowledge of God?).\n"
    "    S = Sin to confess or avoid — an attitude/motive/act the unit exposes "
    "as sin or spiritual danger, so the reader repents and turns from it.\n"
    "    P = Promise to claim — a pledge GOD binds Himself to (forgiveness, "
    "provision, presence, strength, salvation), which the reader can stand on.\n"
    "    E = Example to follow — a person's godly words/choices worth imitating "
    "(Christ, David, Paul, the saints); negative examples to avoid also count.\n"
    "    C = Command to obey — a direct, actionable call to do or stop doing "
    "something, which the reader can actually perform.\n"
    "    K = Knowledge about God — truth about WHO GOD IS and what He is like "
    "(His holiness, love, sovereignty, faithfulness); prefer K when a unit "
    "mainly reveals God.\n\n"
    "ATTRIBUTION: 'jesus_words' is reserved for words spoken BY Jesus. Words by "
    "John the Baptist, angels, prophets, or other speakers belong to their real "
    "category (prophecy, warning, salvation, comfort, etc.), never 'jesus_words'. "
    "Do not classify narrative as 'consecration' merely because it describes a "
    "historical event or burial.\n\n"
    "CRITICAL accuracy rule — unit ids are the source of truth. Each unit is "
    "prefixed with a label U1, U2, ... (U for Unit), one per unit in the list. "
    "For each unit, report ITS label as the id (the part after 'U', as an "
    "integer). The team binds each verdict to that exact unit. Never skip a "
    "unit, never invent an id, never duplicate one.\n"
    "- Respond with valid JSON ONLY, no markdown fences. Schema:\n"
    '{"verdicts":[{"id":1,"include":true,"category":"<one category>",'
    '"theme":"short label","speck":["S","P"]},'
    '{"id":2,"include":false}]}\n'
    "There must be EXACTLY ONE verdict object for every unit in the list, "
    "every time — returning fewer means the list is incomplete and unusable."
)

USER_PROMPT_TEMPLATE = (
    "Bible reference: {bookName} {chapter} (KJV)\n"
    "Sentence units to judge, one verdict each (you must cover EVERY unit). "
    "Each unit is [startVerse]-[endVerse] followed by the text:\n{units}\n\n"
    "Return one JSON verdict per unit as instructed."
)


def _parse_json_response(raw: str) -> object:
    """Parse model JSON output tolerantly.

    Llama-family models occasionally emit markdown fences, trailing
    commentary after the JSON document, or a truncated document. Try strict
    parse first; otherwise strip fences and salvage the longest balanced
    object/list prefix.
    """
    raw = raw.strip()
    if not raw:
        raise ValueError("Empty model output")
    try:
        return json.loads(raw)
    except ValueError:
        pass
    # Strip ```json ... ``` fences if present.
    if raw.startswith("```"):
        raw = re.sub(r"^```[a-zA-Z]*\s*", "", raw)
        raw = re.sub(r"\s*```$", "", raw).strip()
        try:
            return json.loads(raw)
        except ValueError:
            pass
    # Salvage the longest valid JSON prefix starting at the first { or [.
    start = None
    for ch, cand in (("{", ["{"]), ("[", ["["])):
        idx = raw.find(ch)
        if start is None or (idx != -1 and (start == -1 or idx < start)):
            start = idx
    if start is None or start == -1:
        raise ValueError(f"No JSON object/list found in: {raw[:200]!r}")
    depth = 0
    in_str = False
    esc = False
    end = -1
    for i in range(start, len(raw)):
        c = raw[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            continue
        if c == '"':
            in_str = True
        elif c in "{[":
            depth += 1
        elif c in "}]":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end == -1:
        raise ValueError(f"Unbalanced JSON in: {raw[:200]!r}")
    for e in range(end, start, -1):
        try:
            return json.loads(raw[start:e])
        except ValueError:
            continue
    raise ValueError(f"Unparseable JSON in: {raw[:200]!r}")


def load_env(path: Path) -> dict:
    env: dict = {}
    if not path.exists():
        return env
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        env[key.strip()] = value.strip().strip('"').strip("'")
    return env


# --------------------------------------------------------------------------- #
# Bible reading
# --------------------------------------------------------------------------- #
BOOK_NAMES = [
    "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy", "Joshua",
    "Judges", "Ruth", "1 Samuel", "2 Samuel", "1 Kings", "2 Kings",
    "1 Chronicles", "2 Chronicles", "Ezra", "Nehemiah", "Esther", "Job",
    "Psalms", "Proverbs", "Ecclesiastes", "Song of Songs", "Isaiah",
    "Jeremiah", "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel", "Amos",
    "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk", "Zephaniah", "Haggai",
    "Zechariah", "Malachi", "Matthew", "Mark", "Luke", "John", "Acts",
    "Romans", "1 Corinthians", "2 Corinthians", "Galatians", "Ephesians",
    "Philippians", "Colossians", "1 Thessalonians", "2 Thessalonians",
    "1 Timothy", "2 Timothy", "Titus", "Philemon", "Hebrews", "James",
    "1 Peter", "2 Peter", "1 John", "2 John", "3 John", "Jude", "Revelation",
]


def book_name(number: int) -> str:
    return BOOK_NAMES[number - 1]


def read_chapter(bible_dir: Path, version: str, book: int, chapter: int) -> list[dict]:
    """Return [{'verse':N,'text':str}]. Raises if missing."""
    p = bible_dir / version / str(book) / f"{chapter}.json"
    data = json.loads(p.read_text(encoding="utf-8"))
    verses = []
    for row in data:
        obj = row if isinstance(row, dict) else {"verse": 0, "text": str(row)}
        verses.append({"verse": int(obj["verse"]), "text": str(obj.get("text", "")).strip()})
    return verses


def render_units(units: list[dict]) -> str:
    """Render sentence units as 'U<n>. [start-end] text' joined with spaces.

    A unit's text is its verses' texts joined by a single space (the KJV split
    mid-sentence, so re-joining reconstructs the original sentence).  The U<n>
    labels are contiguous per batch (U1..Uk) and deliberately do NOT look like
    verse numbers, so the model reports ids U1..Uk exactly once each.
    """
    lines = []
    for n, u in enumerate(units, 1):
        joined = " ".join(v["text"] for v in u["verses"])
        lines.append(f"U{n}. [verses {u['start']}-{u['end']}] {joined}")
    return "\n".join(lines)


# Sentence end: KJV verses frequently split a sentence mid-way ("..." thou art",
# ending in ':', ',', ';'). A verse "ends a sentence" only if it closes on ".?!'
# (ignoring trailing quotes/brackets).
SENTENCE_ENDINGS = {".", "?", "!"}


def ends_sentence(text: str) -> bool:
    t = text.rstrip()
    while t and t[-1] in "\"')]}":
        t = t[:-1].rstrip()
    return bool(t) and t[-1] in SENTENCE_ENDINGS


def _clause_end(text: str) -> bool:
    """True if `text` ends on a strong clause boundary (: or ;)."""
    t = text.rstrip()
    while t and t[-1] in "\"')]}":
        t = t[:-1].rstrip()
    return bool(t) and t[-1] in (":", ";")


def make_sentence_units(verses: list[dict], max_span: int = 5) -> list[dict]:
    """Partition `verses` into sentence-complete units.

    A unit is [start..end] of consecutive verses whose LAST verse ends a
    sentence (`.?!`), i.e. one full thought. Units partition the chapter: they
    never overlap and together cover every verse exactly once — so a card's
    reference is its unit's range and no bleed/dedup is ever needed.

    Guardrail: if a sentence runs longer than `max_span` verses (KJV chained
    clauses), cut at the last strong clause boundary (`;`/`:`) within the cap
    rather than shipping a 15-verse card.
    """
    units: list[dict] = []
    i, n = 0, len(verses)
    while i < n:
        j = i
        while j < n and not ends_sentence(verses[j]["text"]):
            j += 1
        if j >= n:
            # Trailing thought never closes; take the remainder.
            j = n - 1
        elif j - i + 1 > max_span:
            # Overlong sentence: cut at last clause boundary before the cap.
            cut = i
            for k in range(i, j + 1):
                if k > i and _clause_end(verses[k]["text"]):
                    cut = k
            if cut > i:
                j = cut
            else:
                # No clause boundary: hard-cut at the cap rather than a huge
                # card. The next unit continues the stray mid-sentence clause.
                j = i + max_span - 1
        units.append({"start": verses[i]["verse"], "end": verses[j]["verse"]})
        i = j + 1
    return units


# --------------------------------------------------------------------------- #
# LLM
# --------------------------------------------------------------------------- #
class LLM:
    def __init__(self, url: str, model: str, timeout: int = 600):
        self.url = url.rstrip("/")
        self.model = model
        self.timeout = timeout
        self._session = requests.Session()

    def ensure(self) -> None:
        tags = self._session.get(f"{self.url}/api/tags", timeout=15)
        tags.raise_for_status()
        have = {m.get("name") for m in tags.json().get("models", [])}
        if self.model in have:
            log.info("LLM '%s' ready.", self.model)
            return
        log.info("Pulling model %s (first run)...", self.model)
        pull = self._session.post(
            f"{self.url}/api/pull", json={"name": self.model}, stream=True, timeout=None
        )
        pull.raise_for_status()

    def generate_json(self, user: str) -> dict:
        payload = {
            "model": self.model,
            "stream": False,
            "keep_alive": "5m",
            "format": "json",
            "options": {"num_ctx": NUM_CTX, "temperature": 0.1, "num_predict": 4096},
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user},
            ],
        }
        url = f"{self.url}/api/chat"
        last: Exception | None = None
        for attempt in range(1, 4):
            try:
                resp = self._session.post(url, json=payload, timeout=self.timeout)
                resp.raise_for_status()
                raw = resp.json().get("message", {}).get("content", "")
                parsed = _parse_json_response(raw)
                if isinstance(parsed, dict) and isinstance(parsed.get("verdicts"), list):
                    return parsed
                if isinstance(parsed, dict) and isinstance(parsed.get("passages"), list):
                    return parsed
                # sometimes model wraps an array under a top-level key
                if isinstance(parsed, list):
                    return {"verdicts": parsed}
                raise ValueError(f"Unexpected shape: {list(parsed) if isinstance(parsed, dict) else type(parsed)}")
            except (requests.exceptions.Timeout, requests.exceptions.ConnectionError,
                    requests.exceptions.HTTPError, ValueError) as e:
                last = e
                log.warning("LLM call attempt %d/3 failed: %s", attempt, e)
                if attempt < 3:
                    time.sleep(2 * attempt)
        raise RuntimeError(f"LLM failed after retries: {last}")


# --------------------------------------------------------------------------- #
# Validation / normalization
# --------------------------------------------------------------------------- #
def normalize_verdicts(raw: dict, units: list[dict]) -> list[dict]:
    """Validate & normalize the LLM's per-unit verdict list.

    Verdict ids are the contiguous unit labels U1..Uk of the batch (index+1).
    Each unit's `[start..end]` is the card's reference — no bleed, no
    resolution, no overlap (units partition the chapter).

    Coverage is enforced: a missing / duplicated / invalid id means the model
    truncated its answer, which must NOT be silently treated as 'exclude' (that
    is exactly how famous verses get lost).  Raise ValueError so the caller
    retries the batch.
    """
    expected = list(range(1, len(units) + 1))
    verdicts = [v for v in raw.get("verdicts", []) if isinstance(v, dict)]
    got = [v.get("id") for v in verdicts]
    # Small models sometimes pad a trailing verdict for a non-existent unit
    # id above the batch (e.g. id 2 when only U1 exists, marked exclude).
    # Filter out-of-range ids out BEFORE coverage checking — a verdict for a
    # unit we did not send cannot reorder or truncate the list, so dropping it
    # is safe. In-range ids must still appear exactly once each.
    kept: list[dict] = []
    for v in verdicts:
        vid = v.get("id")
        if isinstance(vid, int) and 1 <= vid <= len(units):
            kept.append(v)
    got = [v.get("id") for v in kept]
    if len(got) != len(expected):
        raise ValueError(f"Coverage: got {len(got)} verdicts, expected {len(expected)}")
    bad = [i for i in expected if got.count(i) != 1]
    if bad:
        raise ValueError(f"Coverage: ids {bad} missing/duplicated")
    out: list[dict] = []
    for v in kept:
        vid = v["id"]
        if not isinstance(vid, int) or not (1 <= vid <= len(units)):
            continue
        u = units[vid - 1]
        if not v.get("include"):
            continue
        category = str(v.get("category", "")).strip().lower()
        if category not in CATEGORY_TAXONOMY:
            norm = category.replace(" ", "_")
            if norm not in CATEGORY_TAXONOMY:
                continue
            category = norm
        theme = str(v.get("theme", "")).strip() or ""
        speck = []
        for letter in v.get("speck") or []:
            s_ = str(letter).strip().upper()
            if s_ in SPECK_TAGS and s_ not in speck:
                speck.append(s_)
        out.append(
            {
                "start": u["start"],
                "end": u["end"],
                "category": category,
                "theme": theme[:80],
                "speck": speck,
            }
        )
    return sorted(out, key=lambda p: (p["start"], p["end"]))


# --------------------------------------------------------------------------- #
# Caching / persistence
# --------------------------------------------------------------------------- #
def cache_path(cache_dir: Path, book: int, chapter: int) -> Path:
    return cache_dir / f"b{book:02d}_c{chapter:03d}.json"


def load_cache(cache_dir: Path, book: int, chapter: int) -> dict | None:
    if cache_dir is None:
        return None
    p = cache_path(cache_dir, book, chapter)
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return None


def write_cache(cache_dir: Path, book: int, chapter: int, data: dict) -> None:
    if cache_dir is None:
        return
    p = cache_path(cache_dir, book, chapter)
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(data), encoding="utf-8")
    os.replace(tmp, p)


def reference_label(book: int, chapter: int, start: int, end: int, name: str | None = None) -> str:
    b = name or book_name(book)
    return f"{b} {chapter}:{start}" + (f"-{end}" if end != start else "")


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Agentic per-chapter extraction of meditation-worthy Bible verses."
    )
    p.add_argument("--bible-dir", default=str(RepoRoot / "releases" / "bibles"))
    p.add_argument("--bible-version", default="kjv")
    p.add_argument("--out-file", default=str(RepoRoot / "apps/backend/data/scriptures.json"))
    p.add_argument("--cache-dir", default=str(RepoRoot / ".cache/scripture_feed"))
    p.add_argument("--chunks", action="store_true",
                   help="Also regenerate words_feed chunk tree next to out-file.")
    p.add_argument("--books", type=int, nargs="+", default=None,
                   help="Restrict to these book numbers (1-66).")
    p.add_argument("--chapters", type=int, nargs="+", default=None,
                   help="Restrict to these chapter numbers (with --books).")
    p.add_argument("--redo", action="store_true", help="Re-analyze cached chapters too.")
    p.add_argument("--clear-cache", action="store_true", help="Delete the cache dir and exit.")
    p.add_argument("--dry-run", action="store_true",
                   help="Analyze but do not write the final out-file (still caches).")
    return p.parse_args(argv)


def chapter_plan(bible_dir: Path, version: str, books_arg, chapters_arg) -> list[tuple[int, int]]:
    plan = []
    books_path = bible_dir / version / "books.json"
    books = json.loads(books_path.read_text(encoding="utf-8"))
    for entry in books:
        bnum = int(entry["bookNumber"])
        chaps = int(entry["chapters"])
        if books_arg and bnum not in books_arg:
            continue
        for c in range(1, chaps + 1):
            if chapters_arg and c not in chapters_arg:
                continue
            plan.append((bnum, c))
    return plan


def emit_scripture(path, chapters_results: list[dict], version: str, dry_run: bool) -> None:
    import random

    rng = random.Random(0)  # deterministic preset assignment
    records = []
    for ch in chapters_results:
        book = ch["book"]
        chapter = ch["chapter"]
        name = ch.get("bookName") or book_name(book)
        for pas in ch["passages"]:
            cat = pas["category"]
            speck = list(pas.get("speck") or [])
            end = pas["end"]
            # tags := category + any SPECK letters (as speck:S etc) + meditation.
            tags = [cat, "meditation"] + [f"speck:{s}" for s in speck]
            records.append(
                {
                    "engine": "scripture",
                    "bookNumber": book,
                    "bookName": name,
                    "chapter": chapter,
                    "startVerse": pas["start"],
                    "endVerse": end,
                    "referenceLabel": reference_label(
                        book, chapter, pas["start"], end,
                        BOOK_NAMES[book - 1],  # canonical full name
                    ),
                    "verseMappings": {},
                    "category": cat,
                    "tags": tags,
                    "speck": speck,
                    "theme": pas.get("theme", ""),
                    "backgroundPreset": rng.choice(BG_PRESETS),
                    "isFeatured": False,
                }
            )
    records.sort(key=lambda r: (r["bookNumber"], r["chapter"], r["startVerse"], r["endVerse"]))
    if dry_run:
        log.info("[dry-run] would write %d records to %s", len(records), path)
        return
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(records, indent=2), encoding="utf-8")
    log.info("Wrote %d records to %s", len(records), path)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    cache_dir = Path(args.cache_dir) if args.cache_dir else None
    if args.clear_cache:
        if cache_dir and cache_dir.exists():
            import shutil

            shutil.rmtree(cache_dir)
            log.info("Cleared cache dir %s", cache_dir)
        return 0

    bible_dir = Path(args.bible_dir)
    version = args.bible_version

    llm = LLM(OLLAMA_URL, OLLAMA_MODEL)
    if not args.dry_run:
        llm.ensure()

    plan = chapter_plan(bible_dir, version, args.books, args.chapters)
    log.info("Planning to analyze %d chapters (book subset=%s).", len(plan), args.books)

    if cache_dir:
        cache_dir.mkdir(parents=True, exist_ok=True)

    results = []
    for idx, (book, chapter) in enumerate(plan, 1):
        cached = load_cache(cache_dir, book, chapter)
        if cached is not None and not args.redo:
            results.append(cached)
            continue
        verses = read_chapter(bible_dir, version, book, chapter)
        if not verses:
            log.warning("  empty chapter %s %d", book_name(book), chapter)
            continue
        # Partition the chapter into sentence-complete units (each unit is one
        # full thought = one possible card). Units partition [1..N] exactly, so
        # references are known before the model runs and can never overlap.
        units = make_sentence_units(verses)
        for u in units:
            u["verses"] = verses[u["start"] - 1: u["end"]]
        passages: list[dict] = []
        unit_total = len(units)
        failed = 0
        for ui in range(0, unit_total, BATCH_UNITS):
            batch = units[ui: ui + BATCH_UNITS]
            user = USER_PROMPT_TEMPLATE.format(
                bookName=book_name(book),
                chapter=chapter,
                units=render_units(batch),
            )
            batch_passes: list[dict] | None = None
            last: Exception | None = None
            for attempt_b in range(1, 4):
                try:
                    raw = llm.generate_json(user)
                    batch_passes = normalize_verdicts(raw, batch)
                    break
                except (RuntimeError, ValueError) as e:
                    last = e
                    log.warning("  %s %d units %d-%d attempt %d/3 failed: %s",
                                book_name(book), chapter, batch[0]["start"],
                                batch[-1]["end"], attempt_b, e)
            if batch_passes is None:
                failed += 1
                log.error("  FAILED %s %d units %d-%d: %s",
                          book_name(book), chapter, batch[0]["start"], batch[-1]["end"], last)
                continue
            passages.extend(batch_passes)
        if failed:
            # Do not cache an incomplete chapter — it will be retried on the
            # next run (device-lost, coverage misses, and transient failures
            # are common on iGPU and with small models).
            log.warning("  INCOMPLETE %s %d (%d/%d batches failed) — skipping cache",
                        book_name(book), chapter, failed,
                        (unit_total + BATCH_UNITS - 1) // BATCH_UNITS)
            continue
        # Units partition the verse range, so passages are already mutually
        # non-overlapping; just order them.
        passages.sort(key=lambda p: (p["start"], p["end"]))
        dedup = passages
        result = {
            "book": book,
            "bookName": book_name(book),
            "chapter": chapter,
            "passages": dedup,
        }
        write_cache(cache_dir, book, chapter, result)
        results.append(result)
        if idx % 5 == 0 or len(plan) <= 15:
            log.info("[%d/%d] %s %d (%d units) -> %d passage(s)",
                     idx, len(plan), book_name(book), chapter, unit_total, len(dedup))

    emit_scripture(args.out_file, results, version, args.dry_run)

    if args.chunks:
        log.info("chunk generation not wired yet — run tool/chunk_web_assets.js next.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
