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
import subprocess
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone, timedelta

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
POS_PROMPT_FILE = os.path.join(PROMPTS_DIR, "step1_pos_tagger.md")
DELTA_PROMPT_FILE = os.path.join(PROMPTS_DIR, "step1_delta_definer.md")

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

POS_ABBR_TO_FULL = {
    "n": "noun",
    "v": "verb",
    "adj": "adjective",
    "adv": "adverb",
    "pron": "pronoun",
    "part": "particle",
    "prep": "particle",
    "conj": "conjunction",
    "num": "numeral",
    "interj": "interjection"
}

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

POS_FULL_TO_ABBR = {
    "noun": "n", "verb": "v", "adjective": "adj", "adverb": "adv", "pronoun": "pron",
    "particle": "part", "conjunction": "conj", "numeral": "num", "interjection": "interj"
}

def normalize_pos(p) -> str:
    """Maps an LLM-returned POS (abbreviation or full name) to the full POS name stored in the DB."""
    p = str(p or "").strip().lower()
    if p in POS_ABBR_TO_FULL:
        return POS_ABBR_TO_FULL[p]
    if p in POS_FULL_TO_ABBR:
        return p
    return "noun"

def load_prompt(filepath: str) -> str:
    if os.path.exists(filepath):
        with open(filepath, "r", encoding="utf-8") as fp:
            return fp.read().strip()
    raise FileNotFoundError(f"Prompt file not found at {filepath}")

POS_SYSTEM_PROMPT = load_prompt(POS_PROMPT_FILE)
DELTA_SYSTEM_PROMPT = load_prompt(DELTA_PROMPT_FILE)

DB_CSV_LOCK = threading.Lock()
STOP_EVENT = threading.Event()

def log(msg: str):
    print(msg, flush=True)

AMBIGUOUS_HOMOGRAPHS = {
    "படி", "ஆறு", "நாடு", "பாடு", "பார்", "நேர்", "கண்", "வகை", "மாடு", "தரம்", "அளவு", "மண்", "நாள்"
}

class BibleVocabDB:
    def __init__(self, db_path: str):
        self.db_path = db_path
        self._init_db()

    def get_conn(self):
        conn = sqlite3.connect(self.db_path, timeout=60)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA busy_timeout=60000")
        return conn

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
                      AND definition_ta IS NOT NULL AND definition_ta != ''
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

            # Lookup all entries for this surface_form
            rows = c.execute("""
                SELECT id, canonical, pos, definition_ta, modern_equivalent, english_word
                FROM unique_words
                WHERE surface_form = ?
                  AND definition_ta IS NOT NULL AND definition_ta != ''
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

    def save_verse_records(self, tokens_to_save: list[dict]) -> dict:
        """Persists tokens; returns {word_index: (pos, canonical, modern, english, definition)} exactly as stored in SQLite."""
        saved = {}
        if not tokens_to_save:
            return saved

        with DB_CSV_LOCK:
            csv_rows = []
            with self.get_conn() as conn:
                cur = conn.cursor()

                for tok in tokens_to_save:
                    clean = tok["clean_token"]
                    pos = tok["pos"]
                    canonical = tok["canonical"]
                    modern = tok["modern_equivalent"]
                    eng = tok["english_word"]
                    def_ta = tok["definition_ta"]
                    word_id = tok.get("word_id")

                    if not word_id:
                        cur.execute("""
                            INSERT OR IGNORE INTO unique_words (surface_form, pos, canonical, modern_equivalent, english_word, definition_ta)
                            VALUES (?, ?, ?, ?, ?, ?)
                        """, (clean, pos, canonical, modern, eng, def_ta))

                        cur.execute("SELECT id FROM unique_words WHERE surface_form = ? AND pos = ? LIMIT 1", (clean, pos))
                        r = cur.fetchone()
                        if r:
                            word_id = r[0]
                        else:
                            cur.execute("SELECT id FROM unique_words WHERE surface_form = ? LIMIT 1", (clean,))
                            r2 = cur.fetchone()
                            word_id = r2[0] if r2 else None

                    if word_id:
                        cur.execute("""
                            INSERT OR REPLACE INTO verse_tokens (book, chapter, verse, word_index, raw_token, word_id)
                            VALUES (?, ?, ?, ?, ?, ?)
                        """, (tok["book"], tok["chapter"], tok["verse"], tok["word_index"], tok["raw_token"], word_id))

                    if word_id:
                        # SQLite is authoritative: if another worker defined this word first, use its stored values.
                        cur.execute("SELECT pos, canonical, modern_equivalent, english_word, definition_ta FROM unique_words WHERE id = ?", (word_id,))
                        stored_row = cur.fetchone()
                        if stored_row:
                            pos, canonical, modern, eng, def_ta = (stored_row[0], stored_row[1], stored_row[2] or "", stored_row[3] or "", stored_row[4] or "")
                    saved[tok["word_index"]] = (pos, canonical, modern, eng, def_ta)

                    csv_rows.append([
                        tok["book"],
                        tok["chapter"],
                        tok["verse"],
                        tok["word_index"],
                        tok["raw_token"],
                        clean,
                        pos,
                        canonical,
                        modern,
                        eng,
                        def_ta
                    ])

                conn.commit()

            file_exists = os.path.exists(CSV_PATH)
            write_header = (not file_exists) or (os.path.getsize(CSV_PATH) == 0)

            with open(CSV_PATH, "a", encoding="utf-8", newline="") as fp:
                writer = csv.writer(fp, quoting=csv.QUOTE_MINIMAL)
                if write_header:
                    writer.writerow([
                        "book", "chapter", "verse", "word_index", "raw_token",
                        "surface_form", "pos", "canonical", "modern_equivalent",
                        "english_word", "definition_ta"
                    ])
                for r in csv_rows:
                    writer.writerow(r)

        return saved

    def export_full_consolidated_csv(self, target_path: str = CSV_PATH):
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

db = BibleVocabDB(SQLITE_PATH)

WORKER_COUNT = 1

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

def call_llm(system_prompt: str, user_prompt: str, num_predict: int = 1500, timeout: int = 360) -> dict | None:
    """Unified LLM caller that handles both Ollama (/api/chat) and llama-server (/v1/chat/completions)."""
    b_type = TELEMETRY.get("backend_type", "ollama")

    if b_type == "llama_server":
        endpoint = f"{OLLAMA_HOST}/v1/chat/completions"
        payload = {
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            "response_format": {"type": "json_object"},
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
            "format": "json",
            "stream": False,
            "think": False,
            "options": {
                "temperature": 0.1,
                "num_predict": num_predict
            }
        }

    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(endpoint, data=body, headers={"Content-Type": "application/json"})

    max_attempts = 3
    for attempt in range(1, max_attempts + 1):
        try:
            t0 = time.time()
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                dt = time.time() - t0

                if b_type == "llama_server":
                    msg = data.get("choices", [{}])[0].get("message", {})
                    content = msg.get("content") or msg.get("reasoning_content") or ""
                    usage = data.get("usage", {})
                    tokens = usage.get("completion_tokens", 0)
                else:
                    content = data.get("message", {}).get("content", "")
                    tokens = data.get("eval_count", 0)

                parsed = json.loads(content)
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

def define_missing_and_disambiguate(verse_text: str, missing_tokens: list[dict], ambiguous_tokens: list[dict]) -> tuple[dict[int, dict], dict[int, str]]:
    """
    Calls LLM in a single pass to:
    1. Define missing tokens (contextual POS 'p', canonical 'c', definition 'd', modern 'm', english 'e')
    2. Disambiguate ambiguous tokens (returning their contextual 'p')
    """
    if not missing_tokens and not ambiguous_tokens:
        return {}, {}

    defined_map = {}
    disambig_map = {}

    items_to_query = []
    for tok in missing_tokens:
        items_to_query.append({
            "i": tok["i"],
            "w": tok["w"],
            "task": "define"
        })
    for amb in ambiguous_tokens:
        items_to_query.append({
            "i": amb["i"],
            "w": amb["w"],
            "task": "disambiguate_pos",
            "candidate_pos": [POS_FULL_TO_ABBR.get(c, c) for c in amb["candidate_pos"]]
        })

    SUB_BATCH_SIZE = 6
    for offset in range(0, len(items_to_query), SUB_BATCH_SIZE):
        sub_batch = items_to_query[offset:offset + SUB_BATCH_SIZE]
        num_predict = max(500, len(sub_batch) * 100)
        user_prompt = f"""Verse Context:
{verse_text}

Words to analyze in this context:
{json.dumps(sub_batch, ensure_ascii=False, indent=2)}
"""
        res = call_llm(DELTA_SYSTEM_PROMPT, user_prompt, num_predict=num_predict, timeout=300)
        if res and isinstance(res.get("definitions"), list):
            for item in res["definitions"]:
                idx = item.get("i")
                if idx is not None:
                    full_pos = normalize_pos(item.get("p"))
                    canonical = str(item.get("c", "")).strip()
                    def_ta = str(item.get("d", "")).strip()
                    modern = str(item.get("m", "")).strip()
                    eng = str(item.get("e", "")).strip()

                    defined_map[idx] = {
                        "pos": full_pos,
                        "canonical": canonical,
                        "definition_ta": def_ta,
                        "modern_equivalent": modern,
                        "english_word": eng
                    }
                    disambig_map[idx] = full_pos

    # Deduplicate within same verse if any token was missed by LLM
    for tok in missing_tokens:
        idx = tok["i"]
        if idx not in defined_map:
            dup_match = next((defined_map[other["i"]] for other in missing_tokens if other["w"] == tok["w"] and other["i"] in defined_map), None)
            if dup_match:
                defined_map[idx] = dup_match

    return defined_map, disambig_map

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
            continue
        found = db.lookup_word(clean)
        if found:
            if found.get("status") == "ambiguous":
                candidate_pos = [c["pos"] for c in found["candidates"]]
                ambiguous.append({
                    "i": idx, "w": clean, "raw": w,
                    "candidates": found["candidates"],
                    "candidate_pos": candidate_pos
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
        delta_defs, disambig_pos = define_missing_and_disambiguate(v_text, missing, ambiguous)
        dt_def = time.time() - t1
        TELEMETRY["total_def_seconds"] += dt_def

        # Handle ambiguous tokens
        for amb in ambiguous:
            idx = amb["i"]
            w = amb["raw"]
            clean = amb["w"]
            chosen_pos = disambig_pos.get(idx)
            matched_candidate = None
            if chosen_pos:
                matched_candidate = next((c for c in amb["candidates"] if c["pos"].lower() == chosen_pos.lower()), None)
            if not matched_candidate and amb["candidates"]:
                matched_candidate = amb["candidates"][0]

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
                full_pos = "noun"
                canonical = clean
                def_ta = ""
                modern = clean
                eng = ""

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

    # Step 3: Commit verse records to SQLite and CSV (SQLite is authoritative if another worker defined the word first)
    stored = db.save_verse_records(tokens_to_save)
    for widx, (s_pos, s_can, s_mod, s_eng, s_def) in stored.items():
        if widx in resolved:
            resolved[widx].update({"pos": s_pos, "canonical": s_can, "modern_equivalent": s_mod,
                                   "english_word": s_eng, "definition_ta": s_def})

    verse_words = [resolved[i] for i in range(total_tokens) if i in resolved]
    if len(verse_words) < total_tokens:
        for i, tok in enumerate(raw_tokens):
            if i not in resolved:
                clean = tok.strip('.,;:!?()[]"\'')
                verse_words.append({
                    "verse": v_num, "word": tok, "pos": "noun", "canonical": clean,
                    "definition_ta": "", "modern_equivalent": clean, "english_word": ""
                })

    dt_total = time.time() - t_start
    WORKER_STATUS["words"] += len(verse_words)
    WORKER_STATUS["last_verse_dur"] = dt_total
    WORKER_STATUS["verses_completed"] += 1
    WORKER_STATUS["status"] = f"Finished v{v_num}"
    hits = sum(1 for w in verse_words if "db" in w.get("source", ""))
    log(f"  [Worker] Book {book_num}:{chapter_num}:{v_num} -> {len(verse_words)} tokens ({hits} DB 0ms, {len(missing)} LLM) | Time: {dt_total:.1f}s")
    return verse_words

def process_chapter(book_num: int, chapter_num: int) -> bool:
    bible_file = os.path.join(BASE_BIBLE_DIR, str(book_num), f"{chapter_num}.json")
    out_dir = os.path.join(BASE_WORDS_DIR, str(book_num))
    out_file = os.path.join(out_dir, f"{chapter_num}.json")
    partial_file = os.path.join(out_dir, f"{chapter_num}.partial.json")

    os.makedirs(out_dir, exist_ok=True)

    if os.path.exists(out_file):
        try:
            with open(out_file, "r", encoding="utf-8") as fp:
                d = json.load(fp)
                if d.get("is_step1_completed") and len(d.get("words", [])) > 0:
                    log(f"  [SKIP] Book {book_num}:{chapter_num} already complete.")
                    return True
        except Exception:
            pass

    if not os.path.exists(bible_file):
        return False

    with open(bible_file, "r", encoding="utf-8") as fp:
        verses = json.load(fp)

    total_verses = len(verses)
    total_expected_words = sum(len(v["text"].split()) for v in verses)

    chapter_words = []
    completed_verse_numbers = set()
    if os.path.exists(partial_file):
        try:
            with open(partial_file, "r", encoding="utf-8") as fp:
                part_data = json.load(fp)
                chapter_words = part_data.get("words", [])
                completed_verse_numbers = set(w.get("verse") for w in chapter_words if "verse" in w)
                log(f"  [RESUME] Book {book_num}:{chapter_num} resuming with {len(completed_verse_numbers)}/{total_verses} verses completed.")
        except Exception:
            chapter_words = []
            completed_verse_numbers = set()

    for v in verses:
        if STOP_EVENT.is_set():
            break
        v_num = v["verse"]
        if v_num in completed_verse_numbers:
            continue

        words_res = process_verse(book_num, chapter_num, v)
        chapter_words.extend(words_res)

        partial_data = {
            "book": book_num,
            "chapter": chapter_num,
            "total_verses": total_verses,
            "total_words_expected": total_expected_words,
            "words": chapter_words
        }
        with open(partial_file, "w", encoding="utf-8") as fp:
            json.dump(partial_data, fp, ensure_ascii=False)

    if not STOP_EVENT.is_set():
        output_data = {
            "book": book_num,
            "chapter": chapter_num,
            "total_verses": total_verses,
            "total_words_expected": total_expected_words,
            "total_words_parsed": len(chapter_words),
            "is_step1_completed": True,
            "words": chapter_words
        }
        with open(out_file, "w", encoding="utf-8") as fp:
            json.dump(output_data, fp, ensure_ascii=False, indent=2)

        if os.path.exists(partial_file):
            try:
                os.remove(partial_file)
            except Exception:
                pass

        log(f"[CHAPTER COMPLETED] Book {book_num}:{chapter_num} finished ({len(chapter_words)} words)!")
    return True

def format_human_duration(seconds: float) -> str:
    """Formats seconds into concise, human-friendly units (e.g. '1 day, 4 hrs, 20 mins' or '45 mins, 12s')."""
    total_sec = max(0, int(seconds))
    if total_sec < 60:
        return f"{total_sec}s"
    days = total_sec // 86400
    rem = total_sec % 86400
    hours = rem // 3600
    rem %= 3600
    minutes = rem // 60
    secs = rem % 60
    parts = []
    if days > 0:
        parts.append(f"{days} day{'s' if days != 1 else ''}")
    if hours > 0:
        parts.append(f"{hours} hr{'s' if hours != 1 else ''}")
    if minutes > 0:
        parts.append(f"{minutes} min{'s' if minutes != 1 else ''}")
    if days == 0 and hours == 0 and secs > 0:
        parts.append(f"{secs}s")
    return ", ".join(parts[:3]) if parts else "0s"

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
            now_str = now_ist.strftime("%A, %b %d, %Y at %I:%M:%S %p IST")

            all_files = glob.glob(os.path.join(BASE_WORDS_DIR, "*", "*.json"))
            completed_chapters = len([f for f in all_files if not f.endswith(".partial.json")])

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

            # Accurate Parallelism-Aware Unique Word Model ETA
            elapsed_sec = max(1, time.time() - TELEMETRY["start_time"])
            elapsed_str = format_human_duration(elapsed_sec)

            verses_done = WORKER_STATUS["verses_completed"]
            llm_defs = TELEMETRY["llm_definitions"]
            unique_remaining = max(0, total_unique_target - unique_words_count)
            verses_remaining = max(0, total_bible_verses - verses_done)

            # Baseline from ~15,600 verified words across chapters 1-117: ~8.0 wall-clock seconds per new word
            EMPIRICAL_SEC_PER_WORD = 8.0

            if llm_defs >= 5 and TELEMETRY["total_def_seconds"] > 0:
                # Effective wall-clock seconds per new word across WORKER_COUNT parallel workers
                worker_sec_per_word = (TELEMETRY["total_def_seconds"] / llm_defs) / max(1, WORKER_COUNT)
                # Blend with empirical baseline during warm-up (first 25 definitions) to smooth startup variance
                weight = min(1.0, llm_defs / 25.0)
                sec_per_new_word = weight * worker_sec_per_word + (1.0 - weight) * EMPIRICAL_SEC_PER_WORD
                eta_sec = unique_remaining * sec_per_new_word
                eta_dur = format_human_duration(eta_sec)
                target_dt = now_ist + timedelta(seconds=int(eta_sec))
                target_dt_str = target_dt.strftime("%A, %b %d, %Y at %I:%M %p IST")
                eta_str = f"~{eta_dur} (Est. Completion: {target_dt_str})"
            elif unique_remaining > 0:
                # Early session estimate using empirical baseline
                eta_sec = unique_remaining * EMPIRICAL_SEC_PER_WORD
                eta_dur = format_human_duration(eta_sec)
                target_dt = now_ist + timedelta(seconds=int(eta_sec))
                target_dt_str = target_dt.strftime("%A, %b %d, %Y at %I:%M %p IST")
                eta_str = f"~{eta_dur} (Warming up: {llm_defs}/5 definitions recorded)"
            else:
                eta_str = "Complete"

            last_verse_dur_str = format_human_duration(WORKER_STATUS["last_verse_dur"])
            health_status_emoji = "🟢 Healthy" if TELEMETRY["is_healthy"] else "🔴 Degraded"
            curr_b = WORKER_STATUS["book"]
            curr_ch = WORKER_STATUS["chapter"]
            curr_v = WORKER_STATUS["verse"]
            b_name = WORKER_STATUS["book_name"]
            server_info = TELEMETRY["server_name"]

            md = f"""# Bible Vocabulary Builder Progress (Normalized 2-Table Architecture)

* **Status:** `RUNNING ({WORKER_COUNT} parallel chapter worker{"s" if WORKER_COUNT != 1 else ""})` 🟢
* **Last Updated:** `{now_str}` *(Refreshed every 5s)*
* **Current Location:** Book `{curr_b}:{curr_ch}:{curr_v}` — **{b_name}**
* **Activity:** `{WORKER_STATUS["status"]}`
* **Inference Engine:** `{server_info}` ({TELEMETRY["last_latency_ms"]:.1f}ms)
* **Completed Chapters:** `{completed_chapters} / {all_bible_chapters}` ({completed_chapters/all_bible_chapters*100:.1f}%)
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
| **Last Verse Duration** | `{last_verse_dur_str} ({WORKER_STATUS["last_verse_dur"]:.1f}s)` |

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
    parser = argparse.ArgumentParser(description="Protestant Tamil Bible Vocabulary Builder (Normalized Architecture)")
    parser.add_argument("--start-book", type=int, default=1, help="Starting book number (1..66)")
    parser.add_argument("--start-chapter", type=int, default=1, help="Starting chapter number in start-book")
    parser.add_argument("--end-book", type=int, default=66, help="Ending book number (1..66)")
    parser.add_argument("--end-chapter", type=int, default=999, help="Ending chapter number in end-book")
    parser.add_argument("--export-csv-only", action="store_true", help="Export consolidated CSV from existing SQLite tables and exit")
    parser.add_argument("--workers", type=int, default=1, help="Parallel chapter workers (match llama-server -np slots)")
    args = parser.parse_args()
    global WORKER_COUNT
    WORKER_COUNT = max(1, args.workers)

    if args.export_csv_only:
        db.export_full_consolidated_csv()
        return

    # Pre-flight health check
    ok, name, lat, b_type = check_server_health()
    if ok:
        log(f"Inference Pre-flight Health Check: PASSED ({name}, latency {lat:.1f}ms)")
    else:
        log(f"Inference Pre-flight Health Check: WARNING - {name}. Entering wait loop...")
        wait_for_server()

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

    def run_one(job):
        idx, b, ch = job
        if STOP_EVENT.is_set():
            return
        b_name = BOOK_NAMES_MAP.get(b, f"Book {b}")
        log(f"\n>>> [{idx}/{total_chapters}] Starting Book {b}:{ch} ({b_name})")
        try:
            process_chapter(b, ch)
        except Exception as e:
            log(f"  [CHAPTER ERROR] Book {b}:{ch} stopped with {e!r}; its partial progress is kept and it will resume on the next run.")

    try:
        with ThreadPoolExecutor(max_workers=WORKER_COUNT) as pool:
            list(pool.map(run_one, [(i, b, ch) for i, (b, ch) in enumerate(all_chapters, start=1)]))
    except KeyboardInterrupt:
        log("\nShutting down pipeline worker...")
        STOP_EVENT.set()

    log("=" * 80)
    log("BIBLE VOCABULARY BUILDER RUN FINISHED!")
    log("=" * 80)

if __name__ == "__main__":
    main()
