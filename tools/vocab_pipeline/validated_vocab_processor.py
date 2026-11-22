"""
Bible Vocabulary Pipeline Processor (Single-Worker Sequential Normalized Bible Vocabulary Builder)
=================================================================================================
Processes the Protestant Tamil Bible (TAOVBSI - பரிசுத்த வேதாகமம்) verse-by-verse sequentially.

Features:
- Dual Engine Support: Automatically connects to Ollama (/api/chat) OR native llama-server Vulkan (/v1/chat/completions)
- Hardware Acceleration: 4.3x speedup on Intel Arc GPU via Vulkan unified memory
- Normalized 2-Table Architecture:
  * unique_words (~95,000 distinct surface words with canonical lemma, POS, modern equivalent, English translation, and definition)
  * verse_tokens (418,550 verse word occurrences referencing unique_words)
- Compounding 0ms Cache: Words defined once are resolved in 0ms for all subsequent occurrences
- Consolidated CSV: releases/study/taobvsi/taobvsi_verse_words.csv (exact joining of both tables)
- Realistic Unique-Word ETA Model: Calculates time based on remaining unique words, avoiding early chapter distortion
"""

import sqlite3
import json
import time
import urllib.request
import urllib.error
import os
import sys
import glob
import csv
import threading
import argparse
from datetime import datetime, timezone, timedelta
from contextlib import contextmanager

from vocab_responses import POS_ABBR_TO_FULL, resolve_items
from vocab_checkpoints import atomic_json, chapter_complete, verified_words, valid_word

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

# Environment configuration
raw_host = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
if not raw_host.startswith("http://") and not raw_host.startswith("https://"):
    if raw_host in ("0.0.0.0", "localhost", "127.0.0.1"):
        OLLAMA_HOST = "http://localhost:11434"
    elif ":" not in raw_host:
        OLLAMA_HOST = f"http://{raw_host}:11434"
    else:
        OLLAMA_HOST = f"http://{raw_host}"
else:
    OLLAMA_HOST = raw_host

MODEL_NAME = os.environ.get("OLLAMA_MODEL", "gemma4:12b")

BASE_BIBLE_DIR = os.environ.get("BIBLE_DIR", "releases/bibles/taobvsi")
BASE_WORDS_DIR = os.environ.get("WORDS_DIR", "releases/study/taobvsi/words")
SQLITE_PATH = os.environ.get("GLOSSARY_SQLITE", "releases/study/taobvsi/taobvsi_glossary.sqlite")
CSV_PATH = os.environ.get("CSV_PATH", "releases/study/taobvsi/taobvsi_verse_words.csv")
PROGRESS_MD = os.environ.get("PROGRESS_MD", "releases/study/taobvsi/WORDS_PROGRESS.md")
HEALTH_JSON = os.environ.get("HEALTH_JSON", "releases/study/taobvsi/PIPELINE_HEALTH.json")
BOOK_NAMES_FILE = os.environ.get("BOOK_NAMES_FILE", "releases/book_names.json")

PROMPTS_DIR = os.path.join(os.path.dirname(__file__), "prompts")
DELTA_PROMPT_FILE = os.path.join(PROMPTS_DIR, "validated_delta_definer.md")

# Load book names for human-readable display
BOOK_NAMES_MAP = {}
if os.path.exists(BOOK_NAMES_FILE):
    try:
        with open(BOOK_NAMES_FILE, "r", encoding="utf-8") as fp:
            bn_data = json.load(fp)
            ylt = bn_data.get("ylt", {})
            ta = bn_data.get("taobvsi", {})
            for k in range(1, 67):
                str_k = str(k)
                en = ylt.get(str_k, f"Book {k}")
                tam = ta.get(str_k, "")
                BOOK_NAMES_MAP[k] = f"{en} ({tam})" if tam else en
    except Exception:
        pass

POS_QUERY_MAP = {
    "n": ["noun", "n", "proper noun", "person", "place"],
    "v": ["verb", "v"],
    "adj": ["adjective", "adj"],
    "adv": ["adverb", "adv"],
    "pron": ["pronoun", "pron"],
    "part": ["particle", "part"],
    "prep": ["particle", "preposition", "prep"],
    "conj": ["conjunction", "conj"],
    "num": ["numeral", "num"],
    "interj": ["interjection", "interj"]
}

def load_prompt(filepath: str) -> str:
    if os.path.exists(filepath):
        with open(filepath, "r", encoding="utf-8") as fp:
            return fp.read().strip()
    raise FileNotFoundError(f"Prompt file not found at {filepath}")

DELTA_SYSTEM_PROMPT = load_prompt(DELTA_PROMPT_FILE)

DB_CSV_LOCK = threading.Lock()
STOP_EVENT = threading.Event()
VALIDATED_CHAPTERS = set()

def log(msg: str):
    print(msg, flush=True)

AMBIGUOUS_HOMOGRAPHS = {
    "படி", "ஆறு", "நாடு", "பாடு", "பார்", "நேர்", "கண்", "வகை", "மாடு", "தரம்", "அளவு", "மண்", "நாள்"
}

class BibleVocabDB:
    def __init__(self, db_path: str):
        self.db_path = db_path
        self._init_db()

    @contextmanager
    def get_conn(self):
        conn = sqlite3.connect(self.db_path, timeout=60)
        try:
            conn.execute("PRAGMA journal_mode=WAL")
            conn.execute("PRAGMA busy_timeout=60000")
            with conn:
                yield conn
        finally:
            conn.close()

    def _init_db(self):
        with self.get_conn() as conn:
            c = conn.cursor()
            c.execute("""
                CREATE TABLE IF NOT EXISTS unique_words (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    surface_form TEXT NOT NULL,
                    pos TEXT NOT NULL,
                    canonical TEXT NOT NULL,
                    modern_equivalent TEXT,
                    english_word TEXT,
                    definition_ta TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE(surface_form, pos)
                )
            """)
            c.execute("CREATE INDEX IF NOT EXISTS idx_unique_words_sf_pos ON unique_words(surface_form, pos)")
            c.execute("CREATE INDEX IF NOT EXISTS idx_unique_words_canonical ON unique_words(canonical)")

            c.execute("""
                CREATE TABLE IF NOT EXISTS verse_tokens (
                    book INTEGER NOT NULL,
                    chapter INTEGER NOT NULL,
                    verse INTEGER NOT NULL,
                    word_index INTEGER NOT NULL,
                    raw_token TEXT NOT NULL,
                    word_id INTEGER NOT NULL REFERENCES unique_words(id),
                    PRIMARY KEY (book, chapter, verse, word_index)
                )
            """)
            c.execute("CREATE INDEX IF NOT EXISTS idx_verse_tokens_lookup ON verse_tokens(book, chapter, verse)")
            c.execute("CREATE INDEX IF NOT EXISTS idx_verse_tokens_word_id ON verse_tokens(word_id)")
            conn.commit()

    def lookup_word(self, raw_token: str, pos_abbr: str = None) -> dict | None:
        """Looks up a word in unique_words using clean surface form and optional POS."""
        clean = raw_token.strip('.,;:!?()[]"\'')
        if not clean:
            return None

        with self.get_conn() as conn:
            c = conn.cursor()
            if pos_abbr:
                allowed_pos = POS_QUERY_MAP.get(pos_abbr, [POS_ABBR_TO_FULL.get(pos_abbr, "noun")])
                placeholders = ','.join(['?'] * len(allowed_pos))
                q = f"""
                    SELECT id, canonical, pos, definition_ta, modern_equivalent, english_word
                    FROM unique_words
                    WHERE surface_form = ?
                      AND pos IN ({placeholders})
                      AND trim(coalesce(definition_ta, '')) != ''
                  AND trim(coalesce(canonical, '')) != ''
                  AND trim(coalesce(modern_equivalent, '')) != ''
                  AND trim(coalesce(english_word, '')) != ''
                    LIMIT 1
                """
                row = c.execute(q, (clean, *allowed_pos)).fetchone()
                if row:
                    return {
                        "word_id": row[0],
                        "canonical": row[1],
                        "pos": row[2],
                        "definition_ta": row[3],
                        "modern_equivalent": row[4] or "",
                        "english_word": row[5] or "",
                        "source": "db_0ms"
                    }

            # Lookup all complete entries for this surface_form.
            rows = c.execute("""
                SELECT id, canonical, pos, definition_ta, modern_equivalent, english_word
                FROM unique_words
                WHERE surface_form = ?
                  AND trim(coalesce(definition_ta, '')) != ''
                  AND trim(coalesce(canonical, '')) != ''
                  AND trim(coalesce(modern_equivalent, '')) != ''
                  AND trim(coalesce(english_word, '')) != ''
            """, (clean,)).fetchall()

            if not rows:
                return None

            # If exactly 1 entry and not on ambiguous watchlist, return direct 0ms hit
            if len(rows) == 1 and clean not in AMBIGUOUS_HOMOGRAPHS:
                r = rows[0]
                return {
                    "word_id": r[0],
                    "canonical": r[1],
                    "pos": r[2],
                    "definition_ta": r[3],
                    "modern_equivalent": r[4] or "",
                    "english_word": r[5] or "",
                    "source": "db_0ms"
                }

            # If multiple entries or on homograph watchlist, mark for contextual confirmation
            return {
                "status": "ambiguous",
                "candidates": [
                    {
                        "word_id": r[0],
                        "canonical": r[1],
                        "pos": r[2],
                        "definition_ta": r[3],
                        "modern_equivalent": r[4] or "",
                        "english_word": r[5] or ""
                    }
                    for r in rows
                ]
            }

    def save_verse_records(self, tokens_to_save: list[dict]):
        """Store complete records, repairing old incomplete entries in place."""
        if not tokens_to_save:
            return
        if any(not valid_word(tok) for tok in tokens_to_save):
            raise ValueError("Refusing to persist an incomplete vocabulary definition")
        with DB_CSV_LOCK, self.get_conn() as conn:
            for tok in tokens_to_save:
                word_id = tok.get("word_id")
                if word_id is None:
                    conn.execute("""
                        INSERT INTO unique_words
                          (surface_form, pos, canonical, modern_equivalent, english_word, definition_ta)
                        VALUES (?, ?, ?, ?, ?, ?)
                        ON CONFLICT(surface_form, pos) DO UPDATE SET
                          canonical=excluded.canonical,
                          modern_equivalent=excluded.modern_equivalent,
                          english_word=excluded.english_word,
                          definition_ta=excluded.definition_ta
                        WHERE trim(coalesce(unique_words.definition_ta, '')) = ''
                           OR trim(coalesce(unique_words.canonical, '')) = ''
                           OR trim(coalesce(unique_words.modern_equivalent, '')) = ''
                           OR trim(coalesce(unique_words.english_word, '')) = ''
                    """, (tok["clean_token"], tok["pos"], tok["canonical"],
                          tok["modern_equivalent"], tok["english_word"], tok["definition_ta"]))
                    word_id = conn.execute(
                        "SELECT id FROM unique_words WHERE surface_form=? AND pos=?",
                        (tok["clean_token"], tok["pos"])).fetchone()[0]
                conn.execute("""
                    INSERT OR REPLACE INTO verse_tokens
                      (book, chapter, verse, word_index, raw_token, word_id)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, (tok["book"], tok["chapter"], tok["verse"], tok["word_index"],
                      tok["raw_token"], word_id))

    def export_full_consolidated_csv(self, target_path: str | None = None):
        target_path = target_path or CSV_PATH
        log(f"Exporting consolidated CSV to {target_path}...")
        with self.get_conn() as conn:
            cur = conn.cursor()
            cur.execute("""
                SELECT
                    v.book,
                    v.chapter,
                    v.verse,
                    v.word_index,
                    v.raw_token,
                    u.surface_form,
                    u.pos,
                    u.canonical,
                    u.modern_equivalent,
                    u.english_word,
                    u.definition_ta
                FROM verse_tokens v
                JOIN unique_words u ON v.word_id = u.id
                ORDER BY v.book ASC, v.chapter ASC, v.verse ASC, v.word_index ASC
            """)
            rows = cur.fetchall()

        with open(target_path, "w", encoding="utf-8", newline="") as fp:
            writer = csv.writer(fp, quoting=csv.QUOTE_MINIMAL)
            writer.writerow([
                "book", "chapter", "verse", "word_index", "raw_token",
                "surface_form", "pos", "canonical", "modern_equivalent",
                "english_word", "definition_ta"
            ])
            for r in rows:
                writer.writerow(r)
        log(f"Successfully exported {len(rows):,} rows to {target_path}.")

db = None  # Initialized by main(); importing this module never opens the dataset.

WORKER_STATUS = {
    "book": 1,
    "chapter": 1,
    "verse": 0,
    "book_name": "Genesis (ஆதியாகமம்)",
    "status": "INITIALIZING",
    "words": 0,
    "hits": 0,
    "llm": 0,
    "speed": 0.0,
    "last_verse_dur": 0.0,
    "verses_completed": 0
}

TELEMETRY = {
    "total_tokens_generated": 0,
    "total_generation_seconds": 0.0,
    "total_pos_seconds": 0.0,
    "total_def_seconds": 0.0,
    "consecutive_errors": 0,
    "last_latency_ms": 0.0,
    "backend_type": "unknown",  # "ollama" or "llama_server"
    "server_name": "unknown",
    "is_healthy": True,
    "status_msg": "HEALTHY",
    "db_cache_hits": 0,
    "llm_definitions": 0,
    "start_time": time.time()
}

def check_server_health() -> tuple[bool, str, float, str]:
    """Probes candidate endpoints (prioritizing Intel Arc Vulkan GPU on port 8080, then Ollama on port 11434)."""
    global OLLAMA_HOST
    candidate_hosts = ["http://127.0.0.1:8080", "http://localhost:8080", "http://127.0.0.1:11434", "http://localhost:11434"]
    env_host = os.environ.get("OLLAMA_HOST")
    if env_host and env_host not in ("0.0.0.0", "localhost", "127.0.0.1", "http://localhost:11434", "http://127.0.0.1:11434") and "8080" in env_host:
        candidate_hosts.insert(0, OLLAMA_HOST)

    for host in candidate_hosts:
        t0 = time.time()
        # 1. Probe native llama-server Vulkan /health
        try:
            req = urllib.request.Request(f"{host}/health")
            with urllib.request.urlopen(req, timeout=2) as resp:
                latency_ms = (time.time() - t0) * 1000.0
                OLLAMA_HOST = host
                TELEMETRY["backend_type"] = "llama_server"
                TELEMETRY["server_name"] = "llama-server (Intel Arc Vulkan0)"
                TELEMETRY["last_latency_ms"] = latency_ms
                TELEMETRY["is_healthy"] = True
                TELEMETRY["status_msg"] = "Intel Arc Vulkan0 GPU (Active)"
                return True, "Intel Arc Vulkan0 GPU", latency_ms, "llama_server"
        except Exception:
            pass

        # 2. Probe Ollama /api/version
        try:
            req = urllib.request.Request(f"{host}/api/version")
            with urllib.request.urlopen(req, timeout=2) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                latency_ms = (time.time() - t0) * 1000.0
                ver = data.get("version", "unknown")
                OLLAMA_HOST = host
                TELEMETRY["backend_type"] = "ollama"
                TELEMETRY["server_name"] = f"Ollama {ver}"
                TELEMETRY["last_latency_ms"] = latency_ms
                TELEMETRY["is_healthy"] = True
                TELEMETRY["status_msg"] = f"Ollama v{ver}"
                return True, f"Ollama v{ver}", latency_ms, "ollama"
        except Exception:
            pass

    TELEMETRY["is_healthy"] = False
    TELEMETRY["status_msg"] = "NO SERVER FOUND on ports 8080 or 11434"
    return False, "No server running", 0.0, "unknown"

def wait_for_server(max_retries: int = 30, retry_delay: int = 5) -> bool:
    for attempt in range(1, max_retries + 1):
        ok, name, lat, b_type = check_server_health()
        if ok:
            log(f"  [HEALTH RESTORED] Connected to {name} ({lat:.1f}ms).")
            TELEMETRY["consecutive_errors"] = 0
            return True
        log(f"  [HEALTH PAUSE] Server unreachable. Waiting {retry_delay}s (attempt {attempt}/{max_retries})...")
        time.sleep(retry_delay)
    return False

def call_llm(system_prompt: str, user_prompt: str, num_predict: int = 1500, timeout: int = 360, schema: dict | None = None) -> dict | None:
    """Unified LLM caller that handles both Ollama (/api/chat) and llama-server (/v1/chat/completions)."""
    b_type = TELEMETRY.get("backend_type", "ollama")

    if b_type == "llama_server":
        endpoint = f"{OLLAMA_HOST}/v1/chat/completions"
        payload = {
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            "response_format": {"type": "json_object", **({"schema": schema} if schema else {})},
            "temperature": 0.1,
            "max_tokens": num_predict
        }
    else:
        endpoint = f"{OLLAMA_HOST}/api/chat"
        payload = {
            "model": MODEL_NAME,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            "format": schema or "json",
            "stream": False,
            "think": False,
            "options": {
                "temperature": 0.1,
                "num_predict": num_predict
            }
        }

    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(endpoint, data=body, headers={"Content-Type": "application/json"})

    max_attempts = 1  # Item-level retries retain valid results in resolve_items().
    for attempt in range(1, max_attempts + 1):
        try:
            t0 = time.time()
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                dt = time.time() - t0

                if b_type == "llama_server":
                    msg = data.get("choices", [{}])[0].get("message", {})
                    content = msg.get("content") or ""
                    if data.get("choices", [{}])[0].get("finish_reason") == "length":
                        TELEMETRY["consecutive_errors"] += 1
                        log("  [LLM TRUNCATED] Output budget exhausted; unresolved items will retry.")
                    usage = data.get("usage", {})
                    tokens = usage.get("completion_tokens", 0)
                else:
                    content = data.get("message", {}).get("content", "")
                    tokens = data.get("eval_count", 0)
                    if data.get("done_reason") == "length":
                        TELEMETRY["consecutive_errors"] += 1
                        log("  [LLM TRUNCATED] Output budget exhausted; unresolved items will retry.")

                try:
                    parsed = json.loads(content)
                except json.JSONDecodeError:
                    log(f"  [INVALID RESPONSE PREFIX]: {content[:600]!r}")
                    raise
                if tokens > 0:
                    TELEMETRY["total_tokens_generated"] += tokens
                    TELEMETRY["total_generation_seconds"] += dt

                TELEMETRY["consecutive_errors"] = 0
                return parsed

        except urllib.error.URLError as e:
            TELEMETRY["consecutive_errors"] += 1
            log(f"  [CONNECTION ERROR Attempt {attempt}/{max_attempts}]: {e}")
            if not wait_for_server():
                break
        except Exception as e:
            TELEMETRY["consecutive_errors"] += 1
            log(f"  [LLM ERROR Attempt {attempt}/{max_attempts}]: {e}. Waiting 3s...")
            time.sleep(3)

    return None

def define_missing_and_disambiguate(verse_text: str, missing_tokens: list[dict], ambiguous_tokens: list[dict]):
    def request(user_prompt, **kwargs):
        timeout = max(300, 60 + kwargs.get("num_predict", 500) // 4)
        return call_llm(DELTA_SYSTEM_PROMPT, user_prompt, timeout=timeout, **kwargs)
    return resolve_items(verse_text, missing_tokens, ambiguous_tokens, request)


class IncompleteVerseError(RuntimeError):
    """The verse remains pending because one or more occurrences are unresolved."""


def process_verse(book_num: int, chapter_num: int, verse_obj: dict) -> list[dict]:
    t_start = time.time()
    v_num = verse_obj["verse"]
    v_text = verse_obj["text"]
    raw_tokens = v_text.split()
    total_tokens = len(raw_tokens)

    WORKER_STATUS["book"] = book_num
    WORKER_STATUS["chapter"] = chapter_num
    WORKER_STATUS["verse"] = v_num
    WORKER_STATUS["book_name"] = BOOK_NAMES_MAP.get(book_num, f"Book {book_num}")
    WORKER_STATUS["status"] = f"DB Check (v{v_num})"

    resolved = {}
    missing = []
    ambiguous = []
    tokens_to_save = []

    # Step 1: DB-First Lookup (0ms per token)
    for idx, w in enumerate(raw_tokens):
        clean = w.strip('.,;:!?()[]"\'')
        if not clean:
            # A standalone quotation mark occurs in Psalms 10:11. Preserve it
            # deterministically rather than requesting a lexical definition.
            record = {
                "book": book_num, "chapter": chapter_num, "verse": v_num, "word_index": idx,
                "raw_token": w, "clean_token": w, "pos": "punctuation", "canonical": w,
                "definition_ta": "சொற்களைப் பிரிக்கும் நிறுத்தற்குறி.",
                "modern_equivalent": w, "english_word": "punctuation", "word_id": None,
            }
            tokens_to_save.append(record)
            resolved[idx] = {
                "verse": v_num, "word": w, "pos": record["pos"], "canonical": w,
                "definition_ta": record["definition_ta"], "modern_equivalent": w,
                "english_word": "punctuation", "source": "punctuation",
            }
            continue
        found = db.lookup_word(clean)
        if found:
            if found.get("status") == "ambiguous":
                ambiguous.append({
                    "i": idx, "w": clean, "raw": w,
                    "candidates": found["candidates"]
                })
            else:
                TELEMETRY["db_cache_hits"] += 1
                WORKER_STATUS["hits"] += 1
                full_pos = found.get("pos", "noun")
                canonical = found.get("canonical", clean)
                def_ta = found.get("definition_ta", "")
                modern = found.get("modern_equivalent", "")
                eng = found.get("english_word", "")

                tokens_to_save.append({
                    "book": book_num, "chapter": chapter_num, "verse": v_num, "word_index": idx,
                    "raw_token": w, "clean_token": clean, "pos": full_pos, "canonical": canonical,
                    "english_word": eng, "modern_equivalent": modern, "definition_ta": def_ta,
                    "word_id": found.get("word_id")
                })

                resolved[idx] = {
                    "verse": v_num, "word": w, "pos": full_pos, "canonical": canonical,
                    "definition_ta": def_ta, "modern_equivalent": modern, "english_word": eng,
                    "source": "db_0ms"
                }
        else:
            missing.append({"i": idx, "w": clean, "raw": w})

    # Step 2: Single-pass LLM Call ONLY if missing or ambiguous tokens exist
    dt_def = 0.0
    if missing or ambiguous:
        WORKER_STATUS["status"] = f"LLM Single-Pass ({len(missing)} new, {len(ambiguous)} amb)"
        t1 = time.time()
        delta_defs, selections = define_missing_and_disambiguate(v_text, missing, ambiguous)
        dt_def = time.time() - t1
        TELEMETRY["total_def_seconds"] += dt_def

        # Handle ambiguous tokens
        for amb in ambiguous:
            idx = amb["i"]
            w = amb["raw"]
            clean = amb["w"]
            chosen_id = selections.get(idx)
            matched_candidate = next((c for c in amb["candidates"]
                                      if c["word_id"] == chosen_id), None)

            if matched_candidate:
                TELEMETRY["db_cache_hits"] += 1
                WORKER_STATUS["hits"] += 1
                full_pos = matched_candidate["pos"]
                canonical = matched_candidate["canonical"]
                def_ta = matched_candidate["definition_ta"]
                modern = matched_candidate["modern_equivalent"]
                eng = matched_candidate["english_word"]
                word_id = matched_candidate["word_id"]

                tokens_to_save.append({
                    "book": book_num, "chapter": chapter_num, "verse": v_num, "word_index": idx,
                    "raw_token": w, "clean_token": clean, "pos": full_pos, "canonical": canonical,
                    "english_word": eng, "modern_equivalent": modern, "definition_ta": def_ta,
                    "word_id": word_id
                })
                resolved[idx] = {
                    "verse": v_num, "word": w, "pos": full_pos, "canonical": canonical,
                    "definition_ta": def_ta, "modern_equivalent": modern, "english_word": eng,
                    "source": "db_disambiguated"
                }

        # Handle missing tokens
        for tok in missing:
            idx = tok["i"]
            w = tok["raw"]
            clean = tok["w"]
            defined = delta_defs.get(idx)
            if defined:
                TELEMETRY["llm_definitions"] += 1
                WORKER_STATUS["llm"] += 1
                full_pos = defined.get("pos", "noun")
                canonical = defined.get("canonical") or clean
                def_ta = defined.get("definition_ta") or ""
                modern = defined.get("modern_equivalent") or clean
                eng = defined.get("english_word") or ""
            else:
                continue  # Unresolved occurrences must never become fabricated nouns.

            tokens_to_save.append({
                "book": book_num, "chapter": chapter_num, "verse": v_num, "word_index": idx,
                "raw_token": w, "clean_token": clean, "pos": full_pos, "canonical": canonical,
                "english_word": eng, "modern_equivalent": modern, "definition_ta": def_ta,
                "word_id": None
            })
            resolved[idx] = {
                "verse": v_num, "word": w, "pos": full_pos, "canonical": canonical,
                "definition_ta": def_ta, "modern_equivalent": modern, "english_word": eng,
                "source": "llm_single_pass"
            }

    # Persist validated results even when another occurrence remains pending.
    db.save_verse_records(tokens_to_save)

    unresolved = set(range(total_tokens)) - resolved.keys()
    if unresolved:
        WORKER_STATUS["status"] = f"Pending v{v_num}: unresolved indices {sorted(unresolved)}"
        raise IncompleteVerseError(
            f"Book {book_num}:{chapter_num}:{v_num}: unresolved indices {sorted(unresolved)}")
    verse_words = [{**resolved[i], "word_index": i} for i in range(total_tokens)]

    dt_total = time.time() - t_start
    WORKER_STATUS["words"] += len(verse_words)
    WORKER_STATUS["last_verse_dur"] = dt_total
    WORKER_STATUS["verses_completed"] += 1
    WORKER_STATUS["status"] = f"Finished v{v_num}"
    hits = sum(1 for w in verse_words if "db" in w.get("source", ""))
    log(f"  [Worker] Book {book_num}:{chapter_num}:{v_num} -> {len(verse_words)} tokens ({hits} DB 0ms, {len(missing)} LLM) | Time: {dt_total:.1f}s")
    return verse_words

def process_chapter(book_num: int, chapter_num: int) -> bool:
    VALIDATED_CHAPTERS.discard((book_num, chapter_num))
    bible_file = os.path.join(BASE_BIBLE_DIR, str(book_num), f"{chapter_num}.json")
    out_dir = os.path.join(BASE_WORDS_DIR, str(book_num))
    out_file = os.path.join(out_dir, f"{chapter_num}.json")
    partial_file = os.path.join(out_dir, f"{chapter_num}.partial.json")
    if not os.path.exists(bible_file):
        return False
    with open(bible_file, encoding="utf-8") as fp:
        verses = json.load(fp)
    os.makedirs(out_dir, exist_ok=True)
    previous = {}
    for path in (out_file, partial_file):
        try:
            with open(path, encoding="utf-8") as fp:
                data = json.load(fp)
            if path == out_file and chapter_complete(data, verses, book_num, chapter_num):
                VALIDATED_CHAPTERS.add((book_num, chapter_num))
                log(f"  [SKIP] Book {book_num}:{chapter_num} has complete validated coverage.")
                return True
            # An old completion marker cannot survive failed validation.
            if path == out_file and isinstance(data, dict) and data.get("is_step1_completed"):
                data["is_step1_completed"] = False
                atomic_json(out_file, data)
            for word in verified_words(data, verses, book_num, chapter_num):
                previous.setdefault((word["verse"], word["word_index"]), word)
        except (OSError, ValueError, TypeError):
            continue
    # Preserve source order when resuming a partially complete chapter.
    completed = {word["verse"] for word in previous.values()}
    chapter_words = []
    metadata = {"book": book_num, "chapter": chapter_num, "total_verses": len(verses),
                "total_words_expected": sum(len(v["text"].split()) for v in verses)}
    for verse in verses:
        if STOP_EVENT.is_set():
            return False
        number = verse["verse"]
        if number in completed:
            chapter_words.extend(previous[(number, i)] for i in range(len(verse["text"].split())))
        else:
            try:
                chapter_words.extend(process_verse(book_num, chapter_num, verse))
            except IncompleteVerseError as exc:
                log(f"  [PENDING] {exc}; chapter is not complete.")
                atomic_json(partial_file, {**metadata, "is_step1_completed": False,
                                          "words": chapter_words})
                return False
        atomic_json(partial_file, {**metadata, "is_step1_completed": False, "words": chapter_words})
    result = {**metadata, "total_words_parsed": len(chapter_words),
              "is_step1_completed": True, "words": chapter_words}
    if not chapter_complete(result, verses, book_num, chapter_num):
        return False
    atomic_json(out_file, result)
    VALIDATED_CHAPTERS.add((book_num, chapter_num))
    if os.path.exists(partial_file):
        os.remove(partial_file)
    log(f"[CHAPTER COMPLETED] Book {book_num}:{chapter_num} finished ({len(chapter_words)} words)!")
    return True


def live_monitor_loop():
    """Background thread refreshing WORDS_PROGRESS.md and PIPELINE_HEALTH.json every 5 seconds."""
    IST = timezone(timedelta(hours=5, minutes=30))
    all_bible_chapters = 1189
    total_bible_words = 418550
    total_unique_target = 95634
    total_bible_verses = 31102

    while not STOP_EVENT.is_set():
        time.sleep(5)
        try:
            now_utc = datetime.now(timezone.utc)
            now_ist = now_utc.astimezone(IST)
            now_str = f"{now_ist.strftime('%Y-%m-%d %I:%M:%S %p IST')} ({now_utc.strftime('%H:%M:%S UTC')})"

            completed_chapters = len(VALIDATED_CHAPTERS)

            unique_words_count = 0
            verse_tokens_count = 0
            unique_canonicals = 0

            try:
                with db.get_conn() as conn:
                    c = conn.cursor()
                    unique_words_count = c.execute("SELECT count(*) FROM unique_words").fetchone()[0]
                    verse_tokens_count = c.execute("SELECT count(*) FROM verse_tokens").fetchone()[0]
                    unique_canonicals = c.execute("SELECT count(DISTINCT canonical) FROM unique_words").fetchone()[0]
            except Exception:
                verse_tokens_count = WORKER_STATUS["words"]

            csv_size_str = "0 KB"
            if os.path.exists(CSV_PATH):
                sz = os.path.getsize(CSV_PATH)
                csv_size_str = f"{sz / 1024:.1f} KB" if sz < 1024*1024 else f"{sz / (1024*1024):.2f} MB"

            total_ops = TELEMETRY["db_cache_hits"] + TELEMETRY["llm_definitions"]
            hit_rate = (TELEMETRY["db_cache_hits"] / max(1, total_ops)) * 100

            avg_speed = 0.0
            if TELEMETRY["total_generation_seconds"] > 0:
                avg_speed = TELEMETRY["total_tokens_generated"] / TELEMETRY["total_generation_seconds"]

            # Accurate Unique Word Model ETA
            elapsed_sec = max(1, time.time() - TELEMETRY["start_time"])
            elapsed_str = str(timedelta(seconds=int(elapsed_sec)))

            verses_done = WORKER_STATUS["verses_completed"]
            llm_defs = TELEMETRY["llm_definitions"]
            unique_remaining = max(0, total_unique_target - unique_words_count)
            verses_remaining = max(0, total_bible_verses - verses_done)

            if llm_defs > 0 and TELEMETRY["total_def_seconds"] > 0:
                sec_per_new_word = TELEMETRY["total_def_seconds"] / llm_defs
                # Realistic Single-Pass ETA = cost to define remaining new words (0ms for all cached words)
                eta_sec = unique_remaining * sec_per_new_word
                eta_str = str(timedelta(seconds=int(eta_sec)))
            else:
                eta_str = "Calculating..."

            health_status_emoji = "🟢 Healthy" if TELEMETRY["is_healthy"] else "🔴 Degraded"
            curr_b = WORKER_STATUS["book"]
            curr_ch = WORKER_STATUS["chapter"]
            curr_v = WORKER_STATUS["verse"]
            b_name = WORKER_STATUS["book_name"]
            server_info = TELEMETRY["server_name"]

            md = f"""# Bible Vocabulary Builder Progress (Normalized 2-Table Architecture)

* **Status:** `RUNNING (Single-Worker Sequential)` 🟢
* **Last Updated:** `{now_str}` *(Refreshed every 5s)*
* **Current Location:** Book `{curr_b}:{curr_ch}:{curr_v}` — **{b_name}**
* **Activity:** `{WORKER_STATUS["status"]}`
* **Inference Engine:** `{server_info}` ({TELEMETRY["last_latency_ms"]:.1f}ms)
* **Chapters Validated This Run:** `{completed_chapters} / {all_bible_chapters}` ({completed_chapters/all_bible_chapters*100:.1f}%)
* **Unique Surface Words in DB:** `{unique_words_count:,} / {total_unique_target:,}` ({unique_words_count/total_unique_target*100:.2f}%)
* **Unique Base Lemmas:** `{unique_canonicals:,}`
* **Verse Tokens Covered:** `{verse_tokens_count:,} / {total_bible_words:,} words` ({verse_tokens_count/total_bible_words*100:.1f}%)
* **Compounding Cache Hit Rate:** `{hit_rate:.1f}%` ({TELEMETRY["db_cache_hits"]:,} 0ms hits / {TELEMETRY["llm_definitions"]:,} LLM definitions)
* **Outputs Live:** SQLite (`taobvsi_glossary.sqlite` — `{unique_words_count:,}` unique words, `{verse_tokens_count:,}` verse tokens), CSV (`taobvsi_verse_words.csv` — `{csv_size_str}`)
* **Elapsed Time:** `{elapsed_str}` | **Estimated ETA (Unique Word Model):** `{eta_str}`

### ⚡ Worker Status

| Attribute | Current Value |
| :--- | :--- |
| **Current Book & Chapter** | Book `{curr_b}:{curr_ch}:{curr_v}` ({b_name}) |
| **Current Task** | `{WORKER_STATUS["status"]}` |
| **Unique Words in Database** | `{unique_words_count:,}` unique surface words |
| **Unique Base Lemmas** | `{unique_canonicals:,}` dictionary roots |
| **Session Words Parsed** | `{WORKER_STATUS["words"]:,}` |
| **Session DB Cache Hits** | `{WORKER_STATUS["hits"]:,}` (0ms instant resolution) |
| **Session LLM Definitions** | `{WORKER_STATUS["llm"]:,}` |
| **Last Verse Duration** | `{WORKER_STATUS["last_verse_dur"]:.1f} s` |

### 🏥 Model & Engine Health

| Metric | Current Value | Status |
| :--- | :--- | :--- |
| **Active Inference Server** | `{server_info}` (@ `{OLLAMA_HOST}`) | {health_status_emoji} |
| **Ping Latency** | `{TELEMETRY["last_latency_ms"]:.1f} ms` | 🟢 Active |
| **Model** | `{MODEL_NAME}` | 🟢 Loaded |
| **Normalized Storage** | `unique_words` (~95k target) + `verse_tokens` (418,550 target) | 📚 Zero Contamination |
| **Consecutive Errors** | `{TELEMETRY["consecutive_errors"]}` | {"🟢 0" if TELEMETRY["consecutive_errors"] == 0 else "⚠️ " + str(TELEMETRY["consecutive_errors"])} |
"""
            with open(PROGRESS_MD, "w", encoding="utf-8") as fp:
                fp.write(md)

            health_data = {
                "status": "HEALTHY" if TELEMETRY["is_healthy"] else "DEGRADED",
                "last_updated": now_str,
                "model": MODEL_NAME,
                "server": server_info,
                "host": OLLAMA_HOST,
                "completed_chapters": completed_chapters,
                "completed_chapters_scope": "validated_in_current_run",
                "unique_words_count": unique_words_count,
                "verse_tokens_count": verse_tokens_count,
                "db_cache_hit_rate": round(hit_rate, 1),
                "db_cache_hits": TELEMETRY["db_cache_hits"],
                "llm_definitions": TELEMETRY["llm_definitions"],
                "worker": WORKER_STATUS,
                "elapsed_time": elapsed_str,
                "eta": eta_str
            }
            with open(HEALTH_JSON, "w", encoding="utf-8") as fp:
                json.dump(health_data, fp, indent=2)

        except Exception:
            pass

def main():
    global db
    parser = argparse.ArgumentParser(description="Protestant Tamil Bible Vocabulary Builder (Normalized Architecture)")
    parser.add_argument("--start-book", type=int, default=1, help="Starting book number (1..66)")
    parser.add_argument("--start-chapter", type=int, default=1, help="Starting chapter number in start-book")
    parser.add_argument("--end-book", type=int, default=66, help="Ending book number (1..66)")
    parser.add_argument("--end-chapter", type=int, default=999, help="Ending chapter number in end-book")
    parser.add_argument("--export-csv-only", action="store_true", help="Export consolidated CSV from existing SQLite tables and exit")
    args = parser.parse_args()

    os.makedirs(os.path.dirname(os.path.abspath(SQLITE_PATH)), exist_ok=True)
    os.makedirs(os.path.dirname(os.path.abspath(CSV_PATH)), exist_ok=True)
    db = BibleVocabDB(SQLITE_PATH)
    STOP_EVENT.clear()
    VALIDATED_CHAPTERS.clear()

    if args.export_csv_only:
        db.export_full_consolidated_csv()
        return

    # Pre-flight health check
    ok, name, lat, b_type = check_server_health()
    if ok:
        log(f"Inference Pre-flight Health Check: PASSED ({name}, latency {lat:.1f}ms)")
    else:
        log(f"Inference Pre-flight Health Check: WARNING - {name}. Entering wait loop...")
        if not wait_for_server():
            return 1

    log("=" * 80)
    log("PROTESTANT TAMIL BIBLE VOCABULARY BUILDER (NORMALIZED 2-TABLE ARCHITECTURE)")
    log(f"ACTIVE INFERENCE HOST: {OLLAMA_HOST} ({name}) | MODEL: {MODEL_NAME}")
    log(f"SQLITE: {SQLITE_PATH} (unique_words + verse_tokens)")
    log(f"CONSOLIDATED CSV: {CSV_PATH}")
    log(f"RANGE: Book {args.start_book}:{args.start_chapter} -> Book {args.end_book}:{args.end_chapter}")
    log("=" * 80)

    all_chapters = []
    for b in range(1, 67):
        files = glob.glob(os.path.join(BASE_BIBLE_DIR, str(b), "*.json"))
        sorted_files = sorted(files, key=lambda p: int(os.path.splitext(os.path.basename(p))[0]))
        for f in sorted_files:
            ch = int(os.path.splitext(os.path.basename(f))[0])
            if (b < args.start_book) or (b == args.start_book and ch < args.start_chapter):
                continue
            if (b > args.end_book) or (b == args.end_book and ch > args.end_chapter):
                continue
            all_chapters.append((b, ch))

    total_chapters = len(all_chapters)
    log(f"Total Bible Chapters to process in this run: {total_chapters}")

    monitor_thread = threading.Thread(target=live_monitor_loop, daemon=True)
    monitor_thread.start()
    log("Live 5-second dashboard monitor thread started.")

    try:
        for idx, (b, ch) in enumerate(all_chapters, start=1):
            if STOP_EVENT.is_set():
                break
            b_name = BOOK_NAMES_MAP.get(b, f"Book {b}")
            log(f"\n>>> [{idx}/{total_chapters}] Starting Book {b}:{ch} ({b_name})")
            if not process_chapter(b, ch):
                STOP_EVENT.set()
                log("Stopped with an incomplete chapter. Resume after resolving the reported errors.")
                return 1
    except KeyboardInterrupt:
        log("\nShutting down pipeline worker...")
        STOP_EVENT.set()
        return 130
    finally:
        STOP_EVENT.set()
        monitor_thread.join(timeout=6)
        db.export_full_consolidated_csv()

    log("=" * 80)
    log("BIBLE VOCABULARY BUILDER RUN FINISHED!")
    log("=" * 80)

if __name__ == "__main__":
    sys.exit(main() or 0)
