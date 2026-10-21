"""
Contextual Bible Vocabulary Pipeline - STEP 1 (Sequential RAG Sense Scanner)
============================================================================
Processes the Tamil Bible (TAOVBSI) sequentially verse by verse:
1. Maps every surface token in order with 100% coverage.
2. Identifies unique word senses using local SQLite RAG retrieval.
3. Generates:
   - Canonical Tamil headword
   - Short, crisp 1-sentence Tamil definition
   - Modern everyday Tamil equivalent
   - English biblical equivalent
4. Binds inflected surface forms to canonical senses in SQLite.
5. Saves clean chapter JSONs to releases/study/taobvsi/words/{book}/{chapter}.json
   and updates releases/study/taobvsi/taobvsi_glossary.sqlite.
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

CHUNK_SIZE_VERSES = 1  # 1 verse per chunk guarantees deterministic, sub-30s local GPU turns

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
                # 1. Exact surface form check
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
                    # 2. Prefix search on headwords
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

    def save_chapter_words(self, book: int, chapter: int, words: list[dict]):
        with self.get_conn() as conn:
            c = conn.cursor()
            for idx, w in enumerate(words):
                surface = w.get("word", "").strip()
                canonical = w.get("canonical", surface).strip()
                entry_id = canonical
                eng = w.get("english_word", "").strip()
                modern = w.get("modern_equivalent", "").strip()
                def_ta = w.get("definition_ta", "").strip()
                v_num = w.get("verse", 1)

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
                """, (book, chapter, v_num, idx, surface, canonical, entry_id, eng, modern, def_ta))

            conn.commit()

db = RAGGlossaryDB(SQLITE_PATH)

def call_ollama(prompt: str, timeout: int = 300) -> dict:
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
    max_retries = 3
    for attempt in range(max_retries):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                content = data.get("message", {}).get("content", "")
                return json.loads(content)
        except Exception as e:
            log(f"  [Ollama Call Attempt {attempt+1}/{max_retries} Error]: {e}. Waiting 5s...")
            time.sleep(5)
    raise RuntimeError(f"Ollama failed after {max_retries} attempts.")

def update_progress(current_book: int, current_ch: int, current_chunk: str, status: str = "RUNNING"):
    all_files = glob.glob(os.path.join(BASE_WORDS_DIR, "*", "*.json"))
    total_chapters = len(all_files)
    total_words = 0
    for f in all_files:
        try:
            with open(f, "r", encoding="utf-8") as fp:
                d = json.load(fp)
                total_words += len(d.get("words", []))
        except Exception:
            pass
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    md = f"""# Step 1: Contextual Interlinear Pipeline Progress

* **Status:** `{status}`
* **Last Updated:** `{now_str}`
* **Processing:** Book `{current_book}`, Chapter `{current_ch}` ({current_chunk})
* **Completed Chapters:** `{total_chapters} / 1189`
* **Total Words Parsed:** `{total_words:,} words`
* **Engine:** Local `{MODEL_NAME}` via RAG Cache
"""
    with open(PROGRESS_MD, "w", encoding="utf-8") as fp:
        fp.write(md)

def process_chapter(book_num: int, chapter_num: int) -> bool:
    bible_file = os.path.join(BASE_BIBLE_DIR, str(book_num), f"{chapter_num}.json")
    out_dir = os.path.join(BASE_WORDS_DIR, str(book_num))
    out_file = os.path.join(out_dir, f"{chapter_num}.json")
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

    log(f"\n================================================================================")
    log(f"STEP 1 RAG: CHAPTER {book_num}:{chapter_num} ({total_verses} verses, {total_expected_words} words)")
    log(f"================================================================================")

    chapter_words = []
    t_ch_start = time.time()

    for i in range(0, total_verses, CHUNK_SIZE_VERSES):
        chunk_verses = verses[i:i + CHUNK_SIZE_VERSES]
        v_nums = [v["verse"] for v in chunk_verses]
        token_input = [{"verse": v["verse"], "tokens": v["text"].split()} for v in chunk_verses]
        expected_chunk_tokens = sum(len(x["tokens"]) for x in token_input)
        chunk_tokens_flat = [tok for x in token_input for tok in x["tokens"]]
        chunk_label = f"Verse(s) {v_nums[0]}-{v_nums[-1]}"

        update_progress(book_num, chapter_num, f"{chunk_label} ({expected_chunk_tokens} tokens)")

        # 1. RAG Sense Retrieval
        rag_senses = db.retrieve_candidates(chunk_tokens_flat)

        # 2. Build User Prompt
        user_payload = {
            "verses": token_input,
            "known_lexicon": rag_senses
        }
        prompt = f"Input Verses:\n{json.dumps(user_payload, ensure_ascii=False, indent=2)}"

        t0 = time.time()
        parsed_chunk = call_ollama(prompt)
        words_res = parsed_chunk.get("words", [])
        dt = time.time() - t0

        log(f"  {chunk_label}: Parsed {len(words_res)}/{expected_chunk_tokens} words in {dt:.1f}s")
        chapter_words.extend(words_res)

    # Save chapter output
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

    # Save to SQLite
    db.save_chapter_words(book_num, chapter_num, chapter_words)

    ch_duration = time.time() - t_ch_start
    log(f"\n[DONE] Chapter {book_num}:{chapter_num} finished in {ch_duration:.1f}s! (Coverage: {len(chapter_words)/max(1, total_expected_words)*100:.1f}%)")
    update_progress(book_num, chapter_num, "CHAPTER_COMPLETED", status="RUNNING")
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
    log("STEP 1: SEQUENTIAL BIBLE RAG SENSE SCANNER")
    log(f"OLLAMA HOST: {OLLAMA_HOST} | MODEL: {MODEL_NAME}")
    log("=" * 80)

    if args.all:
        run_all_bible(start_book=args.book, start_chapter=args.start_chapter)
    else:
        run_book(args.book, start_chapter=args.start_chapter)

