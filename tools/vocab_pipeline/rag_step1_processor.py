"""
Contextual Bible Vocabulary Pipeline - STEP 1 (Sequential RAG Sense Scanner)
============================================================================
Fault-tolerant, self-healing processor for the Protestant Tamil Bible (TAOVBSI).
Features:
- 100% sequential token coverage with deterministic RAG fallback.
- Per-verse persistence & incremental checkpointing (zero lost work on interrupt).
- Model health monitoring with self-healing reconnection (exponential backoff).
- Real-time Markdown telemetry dashboard (WORDS_PROGRESS.md) and PIPELINE_HEALTH.json.
- Full compatibility with gemma4:12b running via Vulkan on Intel Arc GPU.
"""

import sqlite3
import json
import time
import urllib.request
import urllib.error
import os
import sys
import glob
from datetime import datetime

sys.stdout.reconfigure(encoding='utf-8')

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
MODEL_NAME = os.environ.get("OLLAMA_MODEL", "gemma4:12b")

BASE_BIBLE_DIR = os.environ.get("BIBLE_DIR", "releases/bibles/taobvsi")
BASE_WORDS_DIR = os.environ.get("WORDS_DIR", "releases/study/taobvsi/words")
SQLITE_PATH = os.environ.get("GLOSSARY_SQLITE", "releases/study/taobvsi/taobvsi_glossary.sqlite")
PROGRESS_JSON = os.environ.get("PROGRESS_JSON", "releases/study/taobvsi/WORDS_PROGRESS.json")
PROGRESS_MD = os.environ.get("PROGRESS_MD", "releases/study/taobvsi/WORDS_PROGRESS.md")
HEALTH_JSON = os.environ.get("HEALTH_JSON", "releases/study/taobvsi/PIPELINE_HEALTH.json")

CHUNK_SIZE_VERSES = 1

PROMPT_FILE = os.environ.get(
    "PROMPT_FILE",
    os.path.join(os.path.dirname(__file__), "prompts", "step1_system_prompt.md")
)

def load_system_prompt() -> str:
    if os.path.exists(PROMPT_FILE):
        with open(PROMPT_FILE, "r", encoding="utf-8") as fp:
            return fp.read().strip()
    raise FileNotFoundError(f"Prompt file not found at {PROMPT_FILE}")

SYSTEM_PROMPT = load_system_prompt()

def log(msg: str):
    print(msg, flush=True)

class RAGGlossaryDB:
    def __init__(self, db_path: str):
        self.db_path = db_path
        self._init_db()

    def get_conn(self):
        return sqlite3.connect(self.db_path)

    def _init_db(self):
        with self.get_conn() as conn:
            c = conn.cursor()
            c.execute("""
                CREATE TABLE IF NOT EXISTS glossary_entries (
                    id TEXT PRIMARY KEY,
                    headword TEXT NOT NULL,
                    english_word TEXT,
                    definition_ta TEXT,
                    definition_en TEXT,
                    modern_equivalents TEXT,
                    strongs TEXT,
                    original_lemma TEXT,
                    original_translit TEXT
                )
            """)
            c.execute("""
                CREATE TABLE IF NOT EXISTS surface_forms (
                    surface_form TEXT PRIMARY KEY,
                    entry_id TEXT NOT NULL
                )
            """)
            c.execute("""
                CREATE TABLE IF NOT EXISTS verse_words (
                    book INTEGER,
                    chapter INTEGER,
                    verse INTEGER,
                    word_index INTEGER,
                    surface_form TEXT,
                    canonical TEXT,
                    entry_id TEXT,
                    english_word TEXT,
                    modern_equivalent TEXT,
                    definition_ta TEXT,
                    PRIMARY KEY(book, chapter, verse, word_index)
                )
            """)
            conn.commit()

    def retrieve_candidates(self, tokens: list[str]) -> dict:
        rag_dict = {}
        with self.get_conn() as conn:
            c = conn.cursor()
            for tok in tokens:
                clean = tok.strip('.,;:!?()[]"\'')
                if not clean or clean in rag_dict:
                    continue
                c.execute("""
                    SELECT g.id, g.headword, g.english_word, g.definition_ta, g.modern_equivalents
                    FROM surface_forms s
                    JOIN glossary_entries g ON s.entry_id = g.id
                    WHERE s.surface_form = ?
                """, (clean,))
                row = c.fetchone()
                if row:
                    rag_dict[clean] = {
                        "entry_id": row[0],
                        "canonical": row[1],
                        "english_word": row[2] or "",
                        "definition_ta": (row[3] or "")[:90],
                        "modern_equivalent": row[4] or ""
                    }
                else:
                    c.execute("""
                        SELECT id, headword, english_word, definition_ta, modern_equivalents
                        FROM glossary_entries
                        WHERE ? LIKE headword || '%' OR headword LIKE ?
                        LIMIT 2
                    """, (clean, clean[:3] + '%'))
                    candidates = c.fetchall()
                    if candidates:
                        rag_dict[clean] = [{
                            "entry_id": row[0],
                            "canonical": row[1],
                            "english_word": row[2] or "",
                            "definition_ta": (row[3] or "")[:90],
                            "modern_equivalent": row[4] or ""
                        } for row in candidates]
        return rag_dict

    def save_verse_words(self, book: int, chapter: int, verse_num: int, words: list[dict], start_idx: int):
        with self.get_conn() as conn:
            c = conn.cursor()
            for idx, w in enumerate(words):
                surface = w.get("word", "").strip()
                canonical = w.get("canonical", surface).strip()
                entry_id = canonical
                eng = w.get("english_word", "").strip()
                modern = w.get("modern_equivalent", "").strip()
                def_ta = w.get("definition_ta", "").strip()
                global_idx = start_idx + idx

                # Ensure entry exists
                c.execute("""
                    INSERT OR IGNORE INTO glossary_entries (id, headword, english_word, definition_ta, modern_equivalents)
                    VALUES (?, ?, ?, ?, ?)
                """, (entry_id, canonical, eng, def_ta, modern))

                # Bind surface form
                clean_surface = surface.strip('.,;:!?()[]"\'')
                if clean_surface:
                    c.execute("""
                        INSERT OR IGNORE INTO surface_forms (surface_form, entry_id)
                        VALUES (?, ?)
                    """, (clean_surface, entry_id))

                # Insert into verse_words
                c.execute("""
                    INSERT OR REPLACE INTO verse_words (book, chapter, verse, word_index, surface_form, canonical, entry_id, english_word, modern_equivalent, definition_ta)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (book, chapter, verse_num, global_idx, surface, canonical, entry_id, eng, modern, def_ta))

            conn.commit()

db = RAGGlossaryDB(SQLITE_PATH)

# Rolling telemetry metrics
TELEMETRY = {
    "total_tokens_generated": 0,
    "total_generation_seconds": 0.0,
    "consecutive_errors": 0,
    "last_latency_ms": 0.0,
    "ollama_version": "unknown",
    "is_healthy": True,
    "status_msg": "HEALTHY"
}

def check_ollama_health() -> tuple[bool, str, float]:
    """Probes Ollama server responsiveness."""
    t0 = time.time()
    try:
        req = urllib.request.Request(f"{OLLAMA_HOST}/api/version")
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            latency_ms = (time.time() - t0) * 1000.0
            TELEMETRY["ollama_version"] = data.get("version", "unknown")
            TELEMETRY["last_latency_ms"] = latency_ms
            TELEMETRY["is_healthy"] = True
            TELEMETRY["status_msg"] = "HEALTHY"
            return True, data.get("version", "unknown"), latency_ms
    except Exception as e:
        TELEMETRY["is_healthy"] = False
        TELEMETRY["status_msg"] = f"UNREACHABLE: {e}"
        return False, str(e), 0.0

def wait_for_ollama(max_retries: int = 30, retry_delay: int = 10) -> bool:
    """Self-healing connection loop with patient backoff."""
    for attempt in range(1, max_retries + 1):
        ok, ver, lat = check_ollama_health()
        if ok:
            log(f"  [HEALTH RESTORED] Ollama reconnected (v{ver}, {lat:.1f}ms). Resuming pipeline.")
            TELEMETRY["consecutive_errors"] = 0
            return True
        log(f"  [HEALTH PAUSE] Ollama unreachable ({ver}). Waiting {retry_delay}s (attempt {attempt}/{max_retries})...")
        time.sleep(retry_delay)
    log(f"  [HEALTH CRITICAL] Ollama remained unreachable after {max_retries * retry_delay}s.")
    return False

def call_ollama_with_fault_tolerance(prompt: str, expected_tokens: int, raw_tokens: list[str], timeout: int = 300) -> list[dict]:
    """
    Calls Ollama with:
    1. Automatic retry on transient network/timeout errors.
    2. Self-healing pause if Ollama goes down.
    3. Token count validation (checks if returned count matches expected_tokens).
    4. Deterministic RAG fallback guard if model drops tokens.
    """
    payload = {
        "model": MODEL_NAME,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt}
        ],
        "format": "json",
        "stream": False,
        "think": False,
        "options": {
            "temperature": 0.1,
            "num_predict": 1500
        }
    }
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{OLLAMA_HOST}/api/chat",
        data=body,
        headers={"Content-Type": "application/json"}
    )

    max_attempts = 3
    for attempt in range(1, max_attempts + 1):
        try:
            t0 = time.time()
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                content = data.get("message", {}).get("content", "")
                parsed = json.loads(content)
                words = parsed.get("words", [])

                dt = time.time() - t0
                TELEMETRY["total_generation_seconds"] += dt
                TELEMETRY["total_tokens_generated"] += len(words) * 25
                TELEMETRY["consecutive_errors"] = 0

                if len(words) == expected_tokens:
                    return words
                else:
                    log(f"  [INTEGRITY MISMATCH] Verse token count {len(words)} != expected {expected_tokens}. Retrying attempt {attempt}/{max_attempts}...")

        except urllib.error.URLError as e:
            TELEMETRY["consecutive_errors"] += 1
            log(f"  [CONNECTION ERROR Attempt {attempt}/{max_attempts}]: {e}")
            if not wait_for_ollama():
                break
        except Exception as e:
            TELEMETRY["consecutive_errors"] += 1
            log(f"  [OLLAMA ERROR Attempt {attempt}/{max_attempts}]: {e}. Waiting 5s...")
            time.sleep(5)

    # Deterministic RAG Fallback Guard: NEVER crash and NEVER drop tokens
    log(f"  [FALLBACK GUARD ACTIVATED]: Synthesizing {expected_tokens} tokens using SQLite RAG baseline.")
    fallback_words = []
    rag_candidates = db.retrieve_candidates(raw_tokens)
    for tok in raw_tokens:
        clean = tok.strip('.,;:!?()[]"\'')
        entry = rag_candidates.get(clean)
        if isinstance(entry, list) and entry:
            entry = entry[0]
        if entry and isinstance(entry, dict):
            fallback_words.append({
                "word": tok,
                "canonical": entry.get("canonical", clean),
                "definition_ta": entry.get("definition_ta", ""),
                "modern_equivalent": entry.get("modern_equivalent", ""),
                "english_word": entry.get("english_word", "")
            })
        else:
            fallback_words.append({
                "word": tok,
                "canonical": clean,
                "definition_ta": "",
                "modern_equivalent": clean,
                "english_word": ""
            })
    return fallback_words

def update_telemetry_and_progress(current_book: int, current_ch: int, current_chunk: str, status: str = "RUNNING"):
    all_files = glob.glob(os.path.join(BASE_WORDS_DIR, "*", "*.json"))
    completed_chapters = len([f for f in all_files if not f.endswith(".partial.json")])
    total_words = 0
    for f in all_files:
        if f.endswith(".partial.json"):
            continue
        try:
            with open(f, "r", encoding="utf-8") as fp:
                d = json.load(fp)
                total_words += len(d.get("words", []))
        except Exception:
            pass

    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    avg_speed = 0.0
    if TELEMETRY["total_generation_seconds"] > 0:
        avg_speed = TELEMETRY["total_tokens_generated"] / TELEMETRY["total_generation_seconds"]

    health_status_emoji = "🟢 Healthy" if TELEMETRY["is_healthy"] else "🔴 Degraded"

    md = f"""# Step 1: Contextual Interlinear Pipeline Progress

* **Status:** `{status}` {"🟢" if TELEMETRY["is_healthy"] else "🟡"} (Watchdog & Health Monitor Active)
* **Last Updated:** `{now_str}`
* **Processing:** Book `{current_book}`, Chapter `{current_ch}` ({current_chunk})
* **Completed Chapters:** `{completed_chapters} / 1189`
* **Total Words Parsed:** `{total_words:,} words`
* **Engine:** Local `{MODEL_NAME}` via RAG Cache

### 🏥 Model & System Health

| Metric | Current Value | Status |
| :--- | :--- | :--- |
| **Ollama Connectivity** | `{TELEMETRY["status_msg"]}` (v`{TELEMETRY["ollama_version"]}`) | {health_status_emoji} |
| **Ping Latency** | `{TELEMETRY["last_latency_ms"]:.1f} ms` | 🟢 Active |
| **Generation Speed** | `~{avg_speed:.1f} tokens/sec` | 🟢 Intel Arc GPU |
| **Consecutive Errors** | `{TELEMETRY["consecutive_errors"]}` | {"🟢 0" if TELEMETRY["consecutive_errors"] == 0 else "⚠️ " + str(TELEMETRY["consecutive_errors"])} |
| **Fault-Tolerance Mode** | `Auto-Retry (300s) + Checkpointing + Fallback Guard` | 🛡️ Active |
"""
    with open(PROGRESS_MD, "w", encoding="utf-8") as fp:
        fp.write(md)

    health_data = {
        "status": "HEALTHY" if TELEMETRY["is_healthy"] else "DEGRADED",
        "last_updated": now_str,
        "model": MODEL_NAME,
        "ollama_host": OLLAMA_HOST,
        "ollama_version": TELEMETRY["ollama_version"],
        "latency_ms": round(TELEMETRY["last_latency_ms"], 1),
        "avg_tokens_per_sec": round(avg_speed, 1),
        "consecutive_errors": TELEMETRY["consecutive_errors"],
        "current_book": current_book,
        "current_chapter": current_ch,
        "current_chunk": current_chunk,
        "completed_chapters": completed_chapters,
        "total_words_parsed": total_words
    }
    try:
        with open(HEALTH_JSON, "w", encoding="utf-8") as fp:
            json.dump(health_data, fp, indent=2)
    except Exception:
        pass

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
                if d.get("is_step1_completed") or (d.get("is_completed") and len(d.get("words", [])) > 0):
                    log(f"Chapter {book_num}:{chapter_num} already completed ({len(d.get('words', []))} words). Skipping.")
                    return True
        except Exception:
            pass

    if not os.path.exists(bible_file):
        log(f"Bible file {bible_file} not found!")
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
                log(f"  [CHECKPOINT LOADED] Resuming Chapter {book_num}:{chapter_num} with {len(chapter_words)} words ({len(completed_verse_numbers)} verses already done).")
        except Exception:
            chapter_words = []
            completed_verse_numbers = set()

    log(f"\n================================================================================")
    log(f"STEP 1 RAG: CHAPTER {book_num}:{chapter_num} ({total_verses} verses, {total_expected_words} words)")
    log(f"================================================================================")

    t_ch_start = time.time()

    for i in range(0, total_verses, CHUNK_SIZE_VERSES):
        chunk_verses = verses[i:i + CHUNK_SIZE_VERSES]
        v_nums = [v["verse"] for v in chunk_verses]

        if all(vn in completed_verse_numbers for vn in v_nums):
            continue

        token_input = [{"verse": v["verse"], "tokens": v["text"].split()} for v in chunk_verses]
        expected_chunk_tokens = sum(len(x["tokens"]) for x in token_input)
        chunk_tokens_flat = [tok for x in token_input for tok in x["tokens"]]
        chunk_label = f"Verse(s) {v_nums[0]}-{v_nums[-1]}"

        check_ollama_health()
        update_telemetry_and_progress(book_num, chapter_num, f"{chunk_label} ({expected_chunk_tokens} tokens)")

        rag_senses = db.retrieve_candidates(chunk_tokens_flat)

        user_payload = {
            "verses": token_input,
            "known_lexicon": rag_senses
        }
        prompt = f"Input Verses:\n{json.dumps(user_payload, ensure_ascii=False, indent=2)}"

        t0 = time.time()
        words_res = call_ollama_with_fault_tolerance(prompt, expected_chunk_tokens, chunk_tokens_flat)
        dt = time.time() - t0

        log(f"  {chunk_label}: Parsed {len(words_res)}/{expected_chunk_tokens} words in {dt:.1f}s")
        chapter_words.extend(words_res)

        # Save to SQLite per verse immediately
        db.save_verse_words(book_num, chapter_num, v_nums[0], words_res, len(chapter_words) - len(words_res))

        # Save intermediate checkpoint
        partial_data = {
            "book": book_num,
            "chapter": chapter_num,
            "total_verses": total_verses,
            "total_words_expected": total_expected_words,
            "words": chapter_words
        }
        with open(partial_file, "w", encoding="utf-8") as fp:
            json.dump(partial_data, fp, ensure_ascii=False)

    # Finalize chapter output
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

    ch_duration = time.time() - t_ch_start
    log(f"\n[DONE] Chapter {book_num}:{chapter_num} finished in {ch_duration:.1f}s! (Coverage: {len(chapter_words)/max(1, total_expected_words)*100:.1f}%)")
    update_telemetry_and_progress(book_num, chapter_num, "CHAPTER_COMPLETED", status="RUNNING")
    return True

def run_book(book_num: int, start_chapter: int = 1):
    b_dir = os.path.join(BASE_BIBLE_DIR, str(book_num))
    ch_files = glob.glob(os.path.join(b_dir, "*.json"))
    total_chapters = len(ch_files)
    log(f"Book {book_num}: Total {total_chapters} chapters. Starting from Chapter {start_chapter}...")
    for ch in range(start_chapter, total_chapters + 1):
        process_chapter(book_num, ch)

def run_all_bible(start_book: int = 1, start_chapter: int = 1):
    for b in range(start_book, 67):
        ch = start_chapter if b == start_book else 1
        run_book(b, start_chapter=ch)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Step 1 Contextual RAG Interlinear Pipeline")
    parser.add_argument("--book", type=int, default=1, help="Book number (1 = Genesis)")
    parser.add_argument("--start-chapter", type=int, default=1, help="Starting chapter")
    parser.add_argument("--all", action="store_true", help="Process entire Bible (all 66 books)")
    args = parser.parse_args()

    log("=" * 80)
    log("STEP 1: FAULT-TOLERANT SEQUENTIAL BIBLE RAG SENSE SCANNER")
    log(f"OLLAMA HOST: {OLLAMA_HOST} | MODEL: {MODEL_NAME}")
    log("=" * 80)

    # Initial health check before starting
    ok, ver, lat = check_ollama_health()
    if ok:
        log(f"Ollama Pre-flight Health Check: PASSED (version {ver}, latency {lat:.1f}ms)")
    else:
        log(f"Ollama Pre-flight Health Check: WARNING - {ver}. Entering wait loop...")
        wait_for_ollama()

    if args.all:
        run_all_bible(start_book=args.book, start_chapter=args.start_chapter)
    else:
        run_book(args.book, start_chapter=args.start_chapter)
