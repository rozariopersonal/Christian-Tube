#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_parallel_lexicon_workers.py

PASS 2 of the 2-Pass Architecture (Streaming, Fault-Tolerant, Batch-of-10):
1. Claims 10 pending words at a time from 'taobvsi_glossary_queue.sqlite'.
2. Automatic fault tolerance & crash recovery:
   - Resets any stale 'in_progress' jobs on startup and periodically.
   - Per-word transaction safety: completed words are committed immediately.
   - If a word fails after retries, it is safely restored to 'pending'.
3. Continuous parallel operation alongside Pass 1:
   - If queue catches up with Pass 1, sleeps and waits for next chapter.
   - When Pass 1 completes and all words are finished, exits cleanly.
4. Generates full classical Protestant Strong's definitions with Zac Poonen notes.
"""

import os
import sys
import json
import time
import socket
import sqlite3
import argparse
import threading
import urllib.request
import urllib.error
from typing import Dict, List, Set, Any, Optional
from concurrent.futures import ThreadPoolExecutor, as_completed

# Force IPv4
_orig_getaddrinfo = socket.getaddrinfo
def _ipv4_getaddrinfo(*args, **kwargs):
    responses = _orig_getaddrinfo(*args, **kwargs)
    return [r for r in responses if r[0] == socket.AF_INET]
socket.getaddrinfo = _ipv4_getaddrinfo

sys.stdout.reconfigure(encoding="utf-8")

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", ".."))

if CURRENT_DIR not in sys.path:
    sys.path.insert(0, CURRENT_DIR)

from run_bible_glossary_gemini import FULL_ENTRY_PROMPT, DEFAULT_OLLAMA_MODEL, OLLAMA_CHAT_URL, GEMINI_API_URL

QUEUE_DB = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "taobvsi_glossary_queue.sqlite")
ENRICHED_DB = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "taobvsi_glossary_enriched.sqlite")
BOOK_NAMES_FILE = os.path.join(PROJECT_ROOT, "releases", "book_names.json")
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "glossary_additions")
os.makedirs(OUTPUT_DIR, exist_ok=True)

db_lock = threading.Lock()
json_lock = threading.Lock()


def load_book_names() -> Dict[int, str]:
    if os.path.exists(BOOK_NAMES_FILE):
        try:
            with open(BOOK_NAMES_FILE, "r", encoding="utf-8") as f:
                return {int(k): v for k, v in json.load(f)["taobvsi"].items()}
        except Exception:
            pass
    return {1: "ஆதியாகமம்"}


class LexiconWorker:
    def __init__(self, engine: str = "ollama", model_name: str = DEFAULT_OLLAMA_MODEL):
        self.engine = engine.lower()
        self.model_name = model_name
        self.book_names = load_book_names()

    def query_model(self, lemma: str, reference: str, surface_form: str, pos: Optional[str] = None, max_retries: int = 3) -> Optional[Dict[str, Any]]:
        pos_line = f"Part of Speech: {pos}\n" if pos else ""
        user_prompt = (
            f"Base Lemma: {lemma}\n"
            f"{pos_line}"
            f"Surface Form in Scripture: {surface_form}\n"
            f"Scripture Reference: {reference}\n\n"
            "Task:\n"
            "Produce the complete classical Protestant enriched lexical entry as valid JSON adhering to all guidelines.\n"
            f"Rule 1: 'headword' MUST strictly be '{lemma}' (do not alter, truncate, or re-lemmatize).\n"
            "Rule 2 (Classical Protestant Register): Use ONLY classical Protestant Tamil vocabulary across all fields (definition_ta, notes, original_lexical_definition):\n"
            "  * Bible/Scripture: ALWAYS use 'வேதம்' / 'வேதத்தில்' (NEVER use 'விவிலியம்', 'மறைநூல்', or 'பைபிள்').\n"
            "  * Godhead: ALWAYS use 'தேவன்' (Elohim) and 'பரிசுத்த ஆவியானவர்' (NEVER 'கடவுள்'/'இறைவன்' for Elohim, and NEVER 'தூய ஆவியார்').\n"
            "  * Holiness & Saints: ALWAYS use 'பரிசுத்தம்'/'பரிசுத்தவான்கள்' (NEVER 'புனிதம்'/'புனிதர்கள்').\n"
            "  * Salvation & Gospel: ALWAYS use 'இரட்சிப்பு'/'இரட்சகர்' (NEVER 'மீட்பு'/'மீட்பர்'), 'சுவிசேஷம்' (NEVER 'நற்செய்தி'), 'ஞானஸ்நானம்' (NEVER 'திருமுழுக்கு').\n"
            "  * Ministry & Offices: ALWAYS use 'ஆசாரியன்' (NEVER 'குரு'), 'அப்போஸ்தலர்' (NEVER 'திருத்தூதர்'), 'பரலோகம்' (NEVER 'விண்ணகம்').\n"
            "Do NOT require full verse text."
        )

        for attempt in range(max_retries):
            try:
                if self.engine == "ollama":
                    payload = {
                        "model": self.model_name,
                        "messages": [
                            {"role": "system", "content": FULL_ENTRY_PROMPT},
                            {"role": "user", "content": user_prompt}
                        ],
                        "stream": False,
                        "format": "json",
                        "think": False,
                        "keep_alive": "24h",
                        "options": {
                            "temperature": 0.1,
                            "num_ctx": 4096,
                            "num_predict": 1024
                        }
                    }
                    body = json.dumps(payload).encode("utf-8")
                    req = urllib.request.Request(OLLAMA_CHAT_URL, data=body, headers={"Content-Type": "application/json"})
                    with urllib.request.urlopen(req, timeout=300) as resp:
                        res = json.loads(resp.read().decode("utf-8"))
                        raw_text = res.get("message", {}).get("content", "").strip()
                        if not raw_text:
                            raw_text = res.get("message", {}).get("thinking", "").strip()
                        if "```json" in raw_text:
                            raw_text = raw_text.split("```json")[-1].split("```")[0].strip()
                        elif raw_text.startswith("```"):
                            raw_text = raw_text.split("```")[1].strip()

                        parsed = json.loads(raw_text, strict=False)
                        if isinstance(parsed, dict) and "definition_ta" in parsed:
                            parsed["headword"] = lemma
                            for k in ["pos_ta", "word_type", "sample_verse", "see_also", "simple_paraphrase_ta", "theological_significance", "modern_clarification"]:
                                parsed.pop(k, None)
                            return parsed
                else:
                    payload = {
                        "contents": [{"parts": [{"text": f"{FULL_ENTRY_PROMPT}\n\nTask:\n{user_prompt}"}]}],
                        "generationConfig": {"temperature": 0.1, "responseMimeType": "application/json"}
                    }
                    body = json.dumps(payload).encode("utf-8")
                    req = urllib.request.Request(GEMINI_API_URL, data=body, headers={"Content-Type": "application/json"})
                    with urllib.request.urlopen(req, timeout=30) as resp:
                        data = json.loads(resp.read().decode("utf-8"))
                        parts = data.get("candidates", [{}])[0].get("content", {}).get("parts", [{}])
                        raw_text = parts[0].get("text", "").strip()
                        if "```json" in raw_text:
                            raw_text = raw_text.split("```json")[-1].split("```")[0].strip()
                        elif raw_text.startswith("```"):
                            raw_text = raw_text.split("```")[1].strip()
                        parsed = json.loads(raw_text, strict=False)
                        if isinstance(parsed, dict) and "definition_ta" in parsed:
                            parsed["headword"] = lemma
                            for k in ["pos_ta", "word_type", "sample_verse", "see_also", "simple_paraphrase_ta", "theological_significance", "modern_clarification"]:
                                parsed.pop(k, None)
                            return parsed
            except Exception as e:
                time.sleep(2 * (attempt + 1))
        return None

    def save_entry(self, entry: Dict[str, Any], book_num: int):
        hw = entry["headword"]
        b_name = self.book_names.get(book_num, f"Book {book_num}")
        out_file = os.path.join(OUTPUT_DIR, f"book_{book_num:02d}_{b_name}.json")

        # 1. Thread-safe SQLite upsert
        with db_lock:
            conn = sqlite3.connect(ENRICHED_DB, timeout=30.0)
            conn.execute("PRAGMA journal_mode=WAL")
            conn.execute("PRAGMA busy_timeout=30000")
            c = conn.cursor()
            c.execute("""
                INSERT INTO glossary_entries (
                    headword, gloss_en, original_language, original_word, original_transliteration,
                    original_root, original_meaning, original_lexical_definition, notes,
                    definition_ta, definition_en, first_reference, confidence, entry_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(headword) DO UPDATE SET
                    gloss_en = excluded.gloss_en,
                    original_language = excluded.original_language,
                    original_word = excluded.original_word,
                    original_transliteration = excluded.original_transliteration,
                    original_root = excluded.original_root,
                    original_meaning = excluded.original_meaning,
                    original_lexical_definition = excluded.original_lexical_definition,
                    notes = excluded.notes,
                    definition_ta = excluded.definition_ta,
                    definition_en = excluded.definition_en,
                    first_reference = excluded.first_reference,
                    confidence = excluded.confidence,
                    entry_json = excluded.entry_json
            """, (
                hw,
                entry.get("gloss_en"),
                entry.get("original_language"),
                entry.get("original_word"),
                entry.get("original_transliteration"),
                entry.get("original_root"),
                entry.get("original_meaning"),
                entry.get("original_lexical_definition"),
                entry.get("notes"),
                entry.get("definition_ta"),
                entry.get("definition_en"),
                entry.get("first_reference"),
                float(entry.get("confidence", 1.0)),
                json.dumps(entry, ensure_ascii=False)
            ))

            for sf in entry.get("surface_forms", []):
                c.execute("INSERT OR IGNORE INTO surface_forms (headword, surface_form) VALUES (?, ?)", (hw, sf))

            for ref in entry.get("refs", []):
                c.execute("INSERT OR IGNORE INTO verse_references (headword, reference) VALUES (?, ?)", (hw, ref))

            conn.commit()
            conn.close()

        # 2. Thread-safe JSON file upsert
        with json_lock:
            existing_entries = []
            if os.path.exists(out_file):
                try:
                    with open(out_file, "r", encoding="utf-8") as f:
                        existing_entries = json.load(f)
                except Exception:
                    existing_entries = []

            # Replace or append
            replaced = False
            for idx, existing in enumerate(existing_entries):
                if existing.get("headword") == hw:
                    existing_entries[idx] = entry
                    replaced = True
                    break
            if not replaced:
                existing_entries.append(entry)

            with open(out_file, "w", encoding="utf-8") as f:
                json.dump(existing_entries, f, ensure_ascii=False, indent=2)


def process_queue_item(item: tuple, worker: LexiconWorker, worker_id: int) -> bool:
    if len(item) >= 8:
        queue_id, headword, first_ref, book_num, ch_num, surfaces_json, refs_json, pos = item[:8]
    else:
        queue_id, headword, first_ref, book_num, ch_num, surfaces_json, refs_json = item[:7]
        pos = None

    surfaces = json.loads(surfaces_json)
    refs = json.loads(refs_json)
    first_surface = surfaces[0] if surfaces else headword

    t0 = time.time()
    result = worker.query_model(headword, first_ref, first_surface, pos=pos)
    elapsed = time.time() - t0

    if result:
        result["first_reference"] = first_ref
        result["surface_forms"] = surfaces
        result["refs"] = refs
        if pos and not result.get("pos"):
            result["pos"] = pos

        worker.save_entry(result, book_num)

        # Mark completed in queue
        with db_lock:
            q_conn = sqlite3.connect(QUEUE_DB, timeout=30.0)
            q_conn.execute("PRAGMA journal_mode=WAL")
            q_conn.execute("PRAGMA busy_timeout=30000")
            qc = q_conn.cursor()
            qc.execute("UPDATE lexicon_queue SET status = 'completed', completed_at = CURRENT_TIMESTAMP WHERE id = ?", (queue_id,))
            q_conn.commit()
            q_conn.close()

        orig = f" [{result.get('original_language', '')}: {result.get('original_word', '')}]" if result.get("original_word") else ""
        print(f"  [W{worker_id}] #{queue_id} {headword}{orig} ({first_ref}) -> {result.get('gloss_en', '')} ({elapsed:.1f}s)", flush=True)
        return True
    else:
        # Failure: reset to pending so it is retried later
        with db_lock:
            q_conn = sqlite3.connect(QUEUE_DB, timeout=30.0)
            q_conn.execute("PRAGMA journal_mode=WAL")
            q_conn.execute("PRAGMA busy_timeout=30000")
            qc = q_conn.cursor()
            qc.execute("UPDATE lexicon_queue SET status = 'pending', completed_at = NULL WHERE id = ?", (queue_id,))
            q_conn.commit()
            q_conn.close()

        print(f"  [W{worker_id} FAIL] Could not generate entry for #{queue_id} {headword} (restored to pending)", flush=True)
        return False


def recover_stale_in_progress():
    """Resets any jobs stuck in 'in_progress' for > 5 minutes back to 'pending'."""
    try:
        conn = sqlite3.connect(QUEUE_DB, timeout=30.0)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA busy_timeout=30000")
        c = conn.cursor()
        c.execute("""
            UPDATE lexicon_queue
            SET status = 'pending', worker_id = NULL
            WHERE status = 'in_progress'
              AND (strftime('%s', 'now') - strftime('%s', completed_at)) > 300
        """)
        recovered = c.rowcount
        conn.commit()
        conn.close()
        if recovered > 0:
            print(f"[Fault Recovery] Restored {recovered} stranded 'in_progress' jobs back to 'pending'.", flush=True)
    except Exception as e:
        print(f"[Warning] Fault recovery check failed: {e}", flush=True)


def claim_next_batch(batch_size: int = 10, book_filter: Optional[int] = None) -> List[tuple]:
    """Atomically claims up to batch_size pending items from the queue."""
    conn = sqlite3.connect(QUEUE_DB, timeout=30.0)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=30000")
    c = conn.cursor()
    c.execute("BEGIN IMMEDIATE")

    try:
        query = """
            SELECT id, headword, first_reference, first_book_num, first_chapter_num, surface_forms_json, refs_json, pos
            FROM lexicon_queue
            WHERE status = 'pending'
        """
        params = []
        if book_filter:
            query += " AND first_book_num = ?"
            params.append(book_filter)
        query += " ORDER BY id ASC LIMIT ?"
        params.append(batch_size)
        items = c.execute(query, params).fetchall()
    except sqlite3.OperationalError:
        query = """
            SELECT id, headword, first_reference, first_book_num, first_chapter_num, surface_forms_json, refs_json
            FROM lexicon_queue
            WHERE status = 'pending'
        """
        params = []
        if book_filter:
            query += " AND first_book_num = ?"
            params.append(book_filter)
        query += " ORDER BY id ASC LIMIT ?"
        params.append(batch_size)
        items = [r + (None,) for r in c.execute(query, params).fetchall()]
    if items:
        ids = [item[0] for item in items]
        placeholders = ",".join(["?"] * len(ids))
        c.execute(f"""
            UPDATE lexicon_queue
            SET status = 'in_progress', completed_at = CURRENT_TIMESTAMP
            WHERE id IN ({placeholders})
        """, ids)
    conn.commit()
    conn.close()
    return items


def is_pass1_running() -> bool:
    """Checks whether Pass 1 is actively running."""
    try:
        conn = sqlite3.connect(QUEUE_DB, timeout=30.0)
        c = conn.cursor()
        row = c.execute("SELECT value FROM pipeline_control WHERE key = 'pass1_status'").fetchone()
        conn.close()
        if row and row[0] == 'running':
            return True
    except Exception:
        pass
    return False


def get_queue_stats() -> Dict[str, int]:
    """Gets total, completed, pending, and in_progress counts."""
    stats = {"total": 0, "completed": 0, "pending": 0, "in_progress": 0}
    try:
        conn = sqlite3.connect(QUEUE_DB, timeout=30.0)
        c = conn.cursor()
        rows = c.execute("SELECT status, count(*) FROM lexicon_queue GROUP BY status").fetchall()
        conn.close()
        for st, cnt in rows:
            if st in stats:
                stats[st] = cnt
            stats["total"] += cnt
    except Exception:
        pass
    return stats


def run_parallel_workers(
    num_workers: int = 2,
    batch_size: int = 10,
    engine: str = "ollama",
    model_name: str = DEFAULT_OLLAMA_MODEL,
    limit: Optional[int] = None,
    book_filter: Optional[int] = None,
    continuous: bool = True
):
    print("================================================================================")
    print(f"PASS 2: STREAMING FAULT-TOLERANT LEXICON ENRICHER")
    print(f"Batch Size: {batch_size} words | Workers: {num_workers} | Engine: {engine} ({model_name})")
    print("================================================================================")

    # Initial fault recovery on startup
    recover_stale_in_progress()

    workers = [LexiconWorker(engine=engine, model_name=model_name) for _ in range(num_workers)]
    total_processed = 0
    t_start = time.time()
    batch_num = 0

    while True:
        # Periodic stale recovery
        recover_stale_in_progress()

        # Check limit
        if limit and total_processed >= limit:
            print(f"\n[Limit Reached] Successfully enriched {total_processed} words.")
            break

        current_batch_limit = batch_size
        if limit:
            current_batch_limit = min(batch_size, limit - total_processed)

        # Claim next batch of 10 items
        items = claim_next_batch(batch_size=current_batch_limit, book_filter=book_filter)

        if not items:
            # Check if Pass 1 is running
            pass1_active = is_pass1_running()
            if continuous and pass1_active:
                stats = get_queue_stats()
                print(f"[Pass 2] Queue caught up ({stats['completed']}/{stats['total']} completed). Waiting 5s for Pass 1 to feed next chapter...", flush=True)
                time.sleep(5)
                continue
            else:
                stats = get_queue_stats()
                print(f"\n[Pass 2 Complete] All available queue words enriched ({stats['completed']}/{stats['total']} total).", flush=True)
                break

        batch_num += 1
        print(f"\n--- Batch #{batch_num}: Processing {len(items)} words (Claimed from queue) ---")
        t_batch = time.time()
        batch_success = 0

        with ThreadPoolExecutor(max_workers=min(num_workers, len(items))) as executor:
            futures = {}
            for idx, item in enumerate(items):
                worker_id = idx % num_workers
                worker = workers[worker_id]
                f = executor.submit(process_queue_item, item, worker, worker_id + 1)
                futures[f] = item

            for f in as_completed(futures):
                try:
                    success = f.result()
                    if success:
                        batch_success += 1
                        total_processed += 1
                except Exception as e:
                    print(f"  [Worker Exception] {e}", flush=True)

        elapsed_b = time.time() - t_batch
        stats = get_queue_stats()
        print(f"  -> Batch #{batch_num} done in {elapsed_b:.1f}s | Enriched: {stats['completed']}/{stats['total']} ({stats['pending']} pending remaining)", flush=True)

    elapsed_total = time.time() - t_start
    print(f"\n================================================================================")
    print(f"PASS 2 FINISHED: Enriched {total_processed} words in {elapsed_total:.2f}s ({elapsed_total/max(1, total_processed):.1f}s/word)")
    print(f"================================================================================\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Pass 2: Streaming Fault-Tolerant Lexicon Worker")
    parser.add_argument("--workers", type=int, default=2, help="Number of parallel worker threads (default: 2)")
    parser.add_argument("--batch-size", type=int, default=10, help="Words per batch (default: 10)")
    parser.add_argument("--engine", type=str, default="ollama", choices=["ollama", "gemini"], help="Engine")
    parser.add_argument("--model", type=str, default=DEFAULT_OLLAMA_MODEL, help="Model name (default: gemma4:12b)")
    parser.add_argument("--limit", type=int, default=None, help="Limit total words to process")
    parser.add_argument("--book", type=int, default=None, help="Book filter (e.g. 1)")
    parser.add_argument("--no-continuous", action="store_true", help="Do not wait for Pass 1 if queue is empty")
    args = parser.parse_args()

    run_parallel_workers(
        num_workers=args.workers,
        batch_size=args.batch_size,
        engine=args.engine,
        model_name=args.model,
        limit=args.limit,
        book_filter=args.book,
        continuous=not args.no_continuous
    )
