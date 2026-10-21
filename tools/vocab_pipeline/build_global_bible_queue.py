#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_global_bible_queue.py

PASS 1 of the 2-Pass Architecture (Driven 100% by Gemma):
1. Sequentially scans the Tamil Bible (TAOVBSI) chapter-by-chapter.
2. Identifies unique base lemmas using local Gemma (gemma4:12b) in batches.
3. Automatically tracks:
   - 'first_reference': The very first verse in scripture where the lemma appears.
   - 'surface_forms': All inflected forms of the word in scripture.
   - 'refs': Complete de-duplicated list of every verse reference.
   - 'first_book_num' & 'first_chapter_num': Canonical location of first appearance.
4. Persistent SQLite Token Cache:
   - Caches token -> lemma mappings so identical words across the Bible are never re-evaluated.
5. Writes sequential queue to: releases/study/taobvsi/taobvsi_glossary_queue.sqlite
"""

import os
import sys
import json
import time
import sqlite3
import argparse
import urllib.request
import urllib.error
from typing import Dict, List, Set, Any, Optional, Tuple

sys.stdout.reconfigure(encoding="utf-8")

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", ".."))

if CURRENT_DIR not in sys.path:
    sys.path.insert(0, CURRENT_DIR)

from morphology import extract_tamil_words, clean_tamil_token
from common_stopwords import is_stopword

BIBLE_ROOT = os.path.join(PROJECT_ROOT, "releases", "bibles", "taobvsi")
BOOK_NAMES_FILE = os.path.join(PROJECT_ROOT, "releases", "book_names.json")
ENRICHED_DB = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "taobvsi_glossary_enriched.sqlite")
QUEUE_DB = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "taobvsi_glossary_queue.sqlite")
OLLAMA_CHAT_URL = "http://localhost:11434/api/chat"
DEFAULT_MODEL = "gemma4:12b"


def init_queue_db(db_path: str = QUEUE_DB) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path, timeout=30.0)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=30000")
    c = conn.cursor()
    c.execute("""
        CREATE TABLE IF NOT EXISTS lexicon_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            headword TEXT UNIQUE NOT NULL,
            first_reference TEXT NOT NULL,
            first_book_num INTEGER NOT NULL,
            first_chapter_num INTEGER NOT NULL,
            surface_forms_json TEXT NOT NULL,
            refs_json TEXT NOT NULL,
            status TEXT DEFAULT 'pending', -- 'pending', 'in_progress', 'completed', 'skipped'
            worker_id TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            completed_at TIMESTAMP
        )
    """)
    c.execute("CREATE INDEX IF NOT EXISTS idx_queue_status ON lexicon_queue(status)")
    c.execute("CREATE INDEX IF NOT EXISTS idx_queue_headword ON lexicon_queue(headword)")
    c.execute("CREATE INDEX IF NOT EXISTS idx_queue_book ON lexicon_queue(first_book_num)")

    # Ensure pos column exists
    try:
        c.execute("ALTER TABLE lexicon_queue ADD COLUMN pos TEXT")
    except sqlite3.OperationalError:
        pass

    # Persistent model token cache: saves Gemma classifications
    c.execute("""
        CREATE TABLE IF NOT EXISTS token_cache (
            token TEXT PRIMARY KEY,
            lemma TEXT,
            pos TEXT,
            model TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    c.execute("CREATE INDEX IF NOT EXISTS idx_token_cache_token ON token_cache(token)")

    try:
        c.execute("ALTER TABLE token_cache ADD COLUMN pos TEXT")
    except sqlite3.OperationalError:
        pass

    # Pipeline control table: coordinates Pass 1 & Pass 2 in parallel
    c.execute("""
        CREATE TABLE IF NOT EXISTS pipeline_control (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()
    return conn


def load_token_cache(conn: sqlite3.Connection) -> Dict[str, Tuple[Optional[str], Optional[str]]]:
    c = conn.cursor()
    try:
        rows = c.execute("SELECT token, lemma, pos FROM token_cache").fetchall()
    except sqlite3.OperationalError:
        rows = [(r[0], r[1], None) for r in c.execute("SELECT token, lemma FROM token_cache").fetchall()]
    cache: Dict[str, Tuple[Optional[str], Optional[str]]] = {}
    for tok, lem, pos in rows:
        cache[tok] = (lem.strip() if lem and lem.strip() else None, pos.strip() if pos and pos.strip() else None)
    return cache


def save_token_cache_batch(conn: sqlite3.Connection, results: Dict[str, Tuple[Optional[str], Optional[str]]], model_name: str):
    c = conn.cursor()
    c.execute("BEGIN TRANSACTION")
    for tok, (lem, pos) in results.items():
        c.execute("""
            INSERT INTO token_cache (token, lemma, pos, model)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(token) DO UPDATE SET
                lemma = excluded.lemma,
                pos = excluded.pos,
                model = excluded.model
        """, (tok, lem, pos, model_name))
    conn.commit()


def load_completed_headwords(enriched_db: str = ENRICHED_DB) -> Set[str]:
    completed = set()
    if os.path.exists(enriched_db):
        try:
            conn = sqlite3.connect(enriched_db, timeout=30.0)
            c = conn.cursor()
            rows = c.execute("SELECT headword FROM glossary_entries").fetchall()
            for r in rows:
                if r[0]:
                    completed.add(r[0].strip())
            conn.close()
        except Exception as e:
            print(f"[Warning] Could not load enriched db: {e}")
    return completed


def load_existing_queue_data(conn: sqlite3.Connection) -> Dict[str, Dict[str, Any]]:
    c = conn.cursor()
    rows = c.execute("SELECT headword, first_reference, first_book_num, first_chapter_num, surface_forms_json, refs_json FROM lexicon_queue").fetchall()
    existing: Dict[str, Dict[str, Any]] = {}
    for r in rows:
        existing[r[0]] = {
            "first_ref": r[1],
            "book": r[2],
            "chapter": r[3],
            "surfaces": set(json.loads(r[4])),
            "refs": json.loads(r[5])
        }
    return existing


def load_book_names(filepath: str = BOOK_NAMES_FILE) -> Dict[int, str]:
    if os.path.exists(filepath):
        try:
            with open(filepath, "r", encoding="utf-8") as f:
                data = json.load(f)
                return {int(k): v for k, v in data.get("taobvsi", {}).items()}
        except Exception:
            pass
    return {1: "ஆதியாகமம்"}


def natural_sort_key(ref_str: str):
    try:
        parts = ref_str.split(" ")[-1].split(":")
        return (int(parts[0]), int(parts[1]))
    except Exception:
        return (999, 999)


def parse_chapter_arg(val: Optional[str]) -> Optional[List[int]]:
    if not val:
        return None
    chapters = []
    for part in val.split(","):
        part = part.strip()
        if "-" in part:
            start, end = part.split("-")
            chapters.extend(range(int(start), int(end) + 1))
        elif part.isdigit():
            chapters.append(int(part))
    return sorted(list(set(chapters)))


def call_gemma_batch(
    tokens: List[str],
    model_name: str = DEFAULT_MODEL,
    max_retries: int = 3
) -> Dict[str, Tuple[Optional[str], Optional[str]]]:
    """
    Calls Gemma via Ollama to classify a batch of tokens into canonical base lemma and POS.
    Returns: Dict[token, (lemma, pos)]
    """
    if not tokens:
        return {}

    prompt = f"""You are an expert biblical lexicographer specializing in the classical Protestant Tamil Bible (TAOVBSI).
For each of the following Tamil biblical words from scripture:
1. Grammatical & Discourse Particles: Filter out pure grammatical function words, pronouns, auxiliary copulas, optative clitics (e.g. 'கடவது', 'வேண்டும்'), discourse conjunctions ('ஆதலால்'), and inflectional particles with no distinct theological or lexical significance by setting 'lemma': null and 'pos': null.
2. Part of Speech Separation: Strictly preserve distinct lemmas for different parts of speech:
   - Verbs: Return the uninflected imperative/root verb (e.g., 'இரட்சி', 'சா', 'புசி', 'அறி', 'பரிசுத்தப்படுத்து'). Set 'pos': 'verb'.
   - Abstract / Common Nouns: Return the canonical nominative dictionary noun (e.g., 'இரட்சிப்பு', 'சாவு', 'புசிப்பு', 'அறிவு', 'பரிசுத்தம்'). Set 'pos': 'noun'.
   - Personal / Agent Nouns: Return the distinct agent title (e.g., 'இரட்சகர்', 'பரிசுத்தவான்', 'சிருஷ்டிகர்'). Set 'pos': 'agent_noun'.
   - Adjectives: Return the base adjectival form (e.g., 'பரிசுத்த', 'நல்ல'). Set 'pos': 'adjective'.
   DO NOT merge or collapse a verb into a noun, nor an agent into a verb.
3. Classical Protestant Register: Use strictly classical Protestant Tamil terminology. NEVER return 'கடவுள்' for Godhead (use 'தேவன்' or 'கர்த்தர்'). NEVER return 'புனிதம்' (use 'பரிசுத்தம்'), 'மீட்பு' (use 'இரட்சிப்பு'), 'விவிலியம்' (use 'வேதம்').
Rule: Do not omit substantive words. Return clean uninflected root dictionary citation forms.

Words:
{json.dumps(tokens, ensure_ascii=False)}

Respond strictly in JSON with this structure:
{{
  "results": [
    {{"word": "word_from_list", "lemma": "base_lemma or null", "pos": "verb|noun|agent_noun|adjective|null"}}
  ]
}}"""

    payload = {
        "model": model_name,
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
        "format": "json",
        "think": False,
        "keep_alive": "24h",
        "options": {
            "temperature": 0.0,
            "num_ctx": 4096,
            "num_predict": 1024
        }
    }

    req_data = json.dumps(payload).encode("utf-8")
    for attempt in range(max_retries):
        try:
            req = urllib.request.Request(
                OLLAMA_CHAT_URL,
                data=req_data,
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=300) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                raw_text = data.get("message", {}).get("content", "").strip()
                parsed = json.loads(raw_text)
                results_map = {}
                for item in parsed.get("results", []):
                    w = item.get("word")
                    lem = item.get("lemma")
                    pos = item.get("pos")
                    if w:
                        clean_lem = lem.strip() if lem and isinstance(lem, str) and lem.strip() else None
                        clean_pos = pos.strip().lower() if pos and isinstance(pos, str) and pos.strip() else None
                        results_map[w] = (clean_lem, clean_pos)
                return results_map
        except Exception as e:
            time.sleep(5 * (attempt + 1))
            if attempt == max_retries - 1:
                print(f"[Error] Gemma call failed after {max_retries} attempts: {e}", flush=True)

    # Fallback if model fails completely: return empty dict so tokens are not erroneously cached
    return {}


def build_global_queue(
    max_books: Optional[int] = None,
    book_num: Optional[int] = None,
    target_chapters: Optional[List[int]] = None,
    model_name: str = DEFAULT_MODEL,
    batch_size: int = 20
):
    scope_str = ""
    if book_num:
        scope_str += f"Book {book_num}"
        if target_chapters:
            scope_str += f" (Chapters {target_chapters[0]}-{target_chapters[-1]})"
    elif max_books:
        scope_str += f"First {max_books} Books"
    else:
        scope_str += "Whole Bible (66 Books)"

    print("================================================================================")
    print(f"PASS 1: GEMMA-DRIVEN SCRIPTURE LEMMATIZER & QUEUE BUILDER [{scope_str}]")
    print(f"Model: {model_name} | Batch Size: {batch_size}")
    print("================================================================================")

    t0 = time.time()
    book_names = load_book_names()
    completed_headwords = load_completed_headwords()
    print(f"Loaded {len(completed_headwords)} pre-existing enriched lemmas from SQLite.")

    queue_conn = init_queue_db()
    token_cache = load_token_cache(queue_conn)
    print(f"Loaded {len(token_cache)} cached token classifications from SQLite.")

    # Record Pass 1 status in pipeline_control
    qc_init = queue_conn.cursor()
    qc_init.execute("""
        INSERT INTO pipeline_control (key, value, updated_at)
        VALUES ('pass1_status', 'running', CURRENT_TIMESTAMP)
        ON CONFLICT(key) DO UPDATE SET value = 'running', updated_at = CURRENT_TIMESTAMP
    """)
    queue_conn.commit()

    total_verses = 0
    total_tokens = 0
    unique_tokens = set()

    # Dictionary maintaining canonical queue order (pre-seeded with existing queue items for resumability)
    lemma_data: Dict[str, Dict[str, Any]] = load_existing_queue_data(queue_conn)
    print(f"Loaded {len(lemma_data)} existing unique base lemmas from queue database.")

    start_book = book_num if book_num else 1
    end_book = book_num if book_num else (max_books if max_books else 66)

    pending_unknown_tokens: Set[str] = set()
    token_to_occurrences: Dict[str, List[tuple]] = {}  # token -> list of (ref_str, b_idx, ch_num)

    def process_pending_batch():
        nonlocal pending_unknown_tokens, token_cache
        if not pending_unknown_tokens:
            return
        to_classify = list(pending_unknown_tokens)
        t_batch_start = time.time()
        print(f"  [Gemma] Classifying batch of {len(to_classify)} unseen tokens...", end="", flush=True)

        res = call_gemma_batch(to_classify, model_name=model_name)
        elapsed_b = time.time() - t_batch_start
        print(f" done in {elapsed_b:.1f}s ({elapsed_b/len(to_classify):.2f}s/token)")

        # Update cache in memory and SQLite only for successfully classified tokens
        if res:
            token_cache.update(res)
            save_token_cache_batch(queue_conn, res, model_name)
            for k in res.keys():
                pending_unknown_tokens.discard(k)
        else:
            print(f"  [Skip] Batch inference skipped {len(to_classify)} tokens after retries.", flush=True)
            for k in to_classify:
                pending_unknown_tokens.discard(k)

    # Pass 1: Scan and resolve
    for b_idx in range(start_book, end_book + 1):
        b_dir = os.path.join(BIBLE_ROOT, str(b_idx))
        if not os.path.exists(b_dir):
            continue
        b_name = book_names.get(b_idx, f"Book {b_idx}")

        ch_files = sorted(
            [f for f in os.listdir(b_dir) if f.endswith(".json")],
            key=lambda x: int(os.path.splitext(x)[0]) if os.path.splitext(x)[0].isdigit() else 999
        )

        for ch_f in ch_files:
            ch_num_str = os.path.splitext(ch_f)[0]
            if not ch_num_str.isdigit():
                continue
            ch_num = int(ch_num_str)

            if target_chapters and ch_num not in target_chapters:
                continue

            with open(os.path.join(b_dir, ch_f), "r", encoding="utf-8") as jf:
                verses = json.load(jf)

            print(f"\nScanning {b_name} Chapter {ch_num} ({len(verses)} verses)...")

            # Collect words in this chapter
            chapter_tokens_sequence: List[tuple] = []  # (cl, ref_str)

            for v in verses:
                total_verses += 1
                v_num = v.get("verse", 1)
                ref_str = f"{b_name} {ch_num}:{v_num}"
                tokens = extract_tamil_words(v.get("text", ""))

                for tok in tokens:
                    total_tokens += 1
                    cl = clean_tamil_token(tok)
                    if len(cl) < 2 or is_stopword(cl):
                        continue

                    unique_tokens.add(cl)
                    chapter_tokens_sequence.append((cl, ref_str))

                    if cl not in token_cache:
                        pending_unknown_tokens.add(cl)
                        if len(pending_unknown_tokens) >= batch_size:
                            process_pending_batch()

            # Process remaining tokens for the chapter
            if pending_unknown_tokens:
                process_pending_batch()

            # Now resolve lemmas for this chapter in exact scripture order
            new_lemmas_in_chapter = 0
            newly_discovered_this_chapter = []
            for cl, ref_str in chapter_tokens_sequence:
                entry = token_cache.get(cl)
                if not entry:
                    continue
                lemma, pos = entry if isinstance(entry, tuple) else (entry, None)
                if not lemma or len(lemma) < 2 or is_stopword(lemma):
                    continue

                if lemma not in lemma_data:
                    new_lemmas_in_chapter += 1
                    newly_discovered_this_chapter.append(lemma)
                    lemma_data[lemma] = {
                        "first_ref": ref_str,
                        "book": b_idx,
                        "chapter": ch_num,
                        "pos": pos,
                        "surfaces": {cl},
                        "refs": [ref_str]
                    }
                else:
                    lemma_data[lemma]["surfaces"].add(cl)
                    if not lemma_data[lemma].get("pos") and pos:
                        lemma_data[lemma]["pos"] = pos
                    if ref_str not in lemma_data[lemma]["refs"]:
                        lemma_data[lemma]["refs"].append(ref_str)

            # Stream commit newly discovered lemmas into lexicon_queue immediately for Pass 2 workers
            if newly_discovered_this_chapter:
                qc = queue_conn.cursor()
                qc.execute("BEGIN TRANSACTION")
                for lem in newly_discovered_this_chapter:
                    data = lemma_data[lem]
                    is_completed = lem in completed_headwords
                    status = "completed" if is_completed else "pending"
                    surfaces_sorted = sorted(list(data["surfaces"]))
                    refs_sorted = sorted(list(data["refs"]), key=natural_sort_key)
                    qc.execute("""
                        INSERT INTO lexicon_queue (
                            headword, pos, first_reference, first_book_num, first_chapter_num,
                            surface_forms_json, refs_json, status, completed_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(headword) DO UPDATE SET
                            pos = COALESCE(excluded.pos, lexicon_queue.pos),
                            surface_forms_json = excluded.surface_forms_json,
                            refs_json = excluded.refs_json
                    """, (
                        lem,
                        data.get("pos"),
                        data["first_ref"],
                        data["book"],
                        data["chapter"],
                        json.dumps(surfaces_sorted, ensure_ascii=False),
                        json.dumps(refs_sorted, ensure_ascii=False),
                        status,
                        time.strftime("%Y-%m-%d %H:%M:%S") if is_completed else None
                    ))
                queue_conn.commit()

            # Always update pipeline_control for this chapter
            qc = queue_conn.cursor()
            qc.execute("""
                INSERT INTO pipeline_control (key, value, updated_at)
                VALUES ('last_scanned_chapter', ?, CURRENT_TIMESTAMP)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = CURRENT_TIMESTAMP
            """, (f"{b_name} {ch_num}",))
            qc.execute("""
                INSERT INTO pipeline_control (key, value, updated_at)
                VALUES ('total_lemmas_queued', ?, CURRENT_TIMESTAMP)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = CURRENT_TIMESTAMP
            """, (str(len(lemma_data)),))
            queue_conn.commit()

            print(f"  -> Discovered {new_lemmas_in_chapter} new unique base lemmas in Chapter {ch_num} (Total so far: {len(lemma_data)})")

    scan_time = time.time() - t0
    print(f"\n[Scan Finished in {scan_time:.2f}s]")
    print(f"  • Verses scanned: {total_verses}")
    print(f"  • Total tokens scanned: {total_tokens}")
    print(f"  • Unique surface forms: {len(unique_tokens)}")
    print(f"  • Unique canonical base lemmas identified by Gemma: {len(lemma_data)}")

    # Populate SQLite queue table
    print("\nPopulating 'lexicon_queue' table in SQLite...")
    inserted_count = 0
    completed_count = 0

    c = queue_conn.cursor()
    c.execute("BEGIN TRANSACTION")
    for lemma, data in lemma_data.items():
        is_completed = lemma in completed_headwords
        status = "completed" if is_completed else "pending"
        if is_completed:
            completed_count += 1

        surfaces_sorted = sorted(list(data["surfaces"]))
        refs_sorted = sorted(list(data["refs"]), key=natural_sort_key)

        c.execute("""
            INSERT INTO lexicon_queue (
                headword, first_reference, first_book_num, first_chapter_num,
                surface_forms_json, refs_json, status, completed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(headword) DO UPDATE SET
                surface_forms_json = excluded.surface_forms_json,
                refs_json = excluded.refs_json,
                status = excluded.status,
                completed_at = excluded.completed_at
        """, (
            lemma,
            data["first_ref"],
            data["book"],
            data["chapter"],
            json.dumps(surfaces_sorted, ensure_ascii=False),
            json.dumps(refs_sorted, ensure_ascii=False),
            status,
            time.strftime("%Y-%m-%d %H:%M:%S") if is_completed else None
        ))
        inserted_count += 1

    c.execute("""
        INSERT INTO pipeline_control (key, value, updated_at)
        VALUES ('pass1_status', 'completed', CURRENT_TIMESTAMP)
        ON CONFLICT(key) DO UPDATE SET value = 'completed', updated_at = CURRENT_TIMESTAMP
    """)
    queue_conn.commit()
    queue_conn.close()

    total_time = time.time() - t0
    pending_count = inserted_count - completed_count
    print(f"\n[PASS 1 COMPLETE in {total_time:.2f}s]")
    print(f"  • Total Unique Lemmas in Queue: {inserted_count}")
    print(f"  • Already Enriched (Completed): {completed_count}")
    print(f"  • Ready for Parallel Pass 2 (Pending): {pending_count}")
    print(f"Queue Database: {QUEUE_DB}\n")

    # Print Validation Breakdown
    print("================================================================================")
    if book_num:
        b_name = book_names.get(book_num, f"Book {book_num}")
        print(f"PASS 1 BREAKDOWN: {b_name} (First Appearance by Chapter)")
        print("================================================================================")
        by_ch: Dict[int, List[tuple]] = {}
        for lem, d in lemma_data.items():
            by_ch.setdefault(d["chapter"], []).append((lem, d))

        for c_num in sorted(by_ch.keys()):
            ch_lemmas = by_ch[c_num]
            print(f"\n--- CHAPTER {c_num}: {len(ch_lemmas)} Newly Discovered Unique Lemmas ---")
            for idx, (lem, d) in enumerate(ch_lemmas, 1):
                surfs = sorted(list(d["surfaces"]))
                surfs_preview = ", ".join(surfs[:3]) + (f" (+{len(surfs)-3} more)" if len(surfs) > 3 else "")
                print(f"  {idx:2d}. {lem:<16} [{d['first_ref']}] ({len(d['refs'])} refs) -> [{surfs_preview}]")
    else:
        print("PASS 1 WHOLE-BIBLE BREAKDOWN (Newly Discovered Unique Lemmas per Book)")
        print("================================================================================")
        by_bk: Dict[int, List[tuple]] = {}
        for lem, d in lemma_data.items():
            by_bk.setdefault(d["book"], []).append((lem, d))

        for b_idx in sorted(by_bk.keys()):
            bk_lemmas = by_bk[b_idx]
            b_name = book_names.get(b_idx, f"Book {b_idx}")
            sample = ", ".join([lem for lem, _ in bk_lemmas[:4]])
            print(f"  Book {b_idx:2d}. {b_name:<20} : {len(bk_lemmas):4d} new lemmas (e.g. {sample}...)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Pass 1: Build Scripture Queue via Gemma")
    parser.add_argument("--max-books", type=int, default=None, help="Limit to first N books")
    parser.add_argument("--book", type=int, default=None, help="Specific book number (1 = Genesis)")
    parser.add_argument("--chapters", type=str, default=None, help="Specific chapters, e.g. '1-5' or '1,2,3'")
    parser.add_argument("--model", type=str, default=DEFAULT_MODEL, help="Ollama model name (default: gemma4:12b)")
    parser.add_argument("--batch-size", type=int, default=20, help="Batch size for Gemma inference (default: 20)")
    parser.add_argument("--clean", action="store_true", help="Drop and rebuild queue table from scratch")
    parser.add_argument("--reset-cache", action="store_true", help="Clear token cache table from scratch")
    args = parser.parse_args()

    if (args.clean or args.reset_cache) and os.path.exists(QUEUE_DB):
        conn = sqlite3.connect(QUEUE_DB)
        if args.clean:
            conn.execute("DROP TABLE IF EXISTS lexicon_queue")
            print("[Clean] Dropped previous lexicon_queue table.", flush=True)
        if args.reset_cache:
            conn.execute("DROP TABLE IF EXISTS token_cache")
            print("[Reset Cache] Dropped previous token_cache table.", flush=True)
        conn.commit()
        conn.close()

    target_chs = parse_chapter_arg(args.chapters)
    build_global_queue(
        max_books=args.max_books,
        book_num=args.book,
        target_chapters=target_chs,
        model_name=args.model,
        batch_size=args.batch_size
    )
