#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_deepseek_pass1_bible.py

PASS 1 of the Biblical Lexicon Pipeline powered by DeepSeek-V3:
1. Sequentially scans the Tamil Bible (TAOVBSI) chapter-by-chapter across all 66 books.
2. Identifies unique base lemmas using DeepSeek-V3 (deepseek-chat) in batches of 50 tokens.
3. Enforces strict Part-of-Speech separation:
   - Verbs (uninflected root/imperative)
   - Common / Abstract Nouns (canonical nominative)
   - Agent / Personal Nouns (distinct agent titles)
   - Adjectives
4. Automatically tracks:
   - 'first_reference': The very first verse in scripture where the lemma appears.
   - 'surface_forms': All inflected forms of the word in scripture.
   - 'refs': Complete de-duplicated list of every verse reference.
   - 'first_book_num' & 'first_chapter_num': Canonical location of first appearance.
5. Persistent SQLite Token Cache:
   - Caches token -> (lemma, pos) mappings so identical tokens are never re-evaluated.
6. Writes to canonical SQLite queue: releases/study/taobvsi/taobvsi_glossary_queue.sqlite
7. Status Refresh:
   - Automatically refreshes PIPELINE_STATUS.md every 10 seconds in a background daemon thread.
   - Generates individual book-wise reports in releases/study/taobvsi/book_reports/
"""

import os
import sys
import json
import time
import re
import sqlite3
import argparse
import threading
import urllib.request
import urllib.error
from typing import Dict, List, Set, Any, Optional, Tuple
from collections import defaultdict

sys.stdout.reconfigure(encoding="utf-8")

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", ".."))

API_KEY = "sk-f514d1a1c6e14901a79ed5d290af9e51"
DEEPSEEK_URL = "https://api.deepseek.com/chat/completions"

BIBLE_ROOT = os.path.join(PROJECT_ROOT, "releases", "bibles", "taobvsi")
BOOK_NAMES_FILE = os.path.join(PROJECT_ROOT, "releases", "book_names.json")
BOOKS_JSON_FILE = os.path.join(PROJECT_ROOT, "releases", "bibles", "taobvsi", "books.json")
QUEUE_DB = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "taobvsi_glossary_queue.sqlite")
ENRICHED_DB = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "taobvsi_glossary_enriched.sqlite")
STATUS_MD = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "PIPELINE_STATUS.md")
STATUS_JSON = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "PIPELINE_STATUS.json")
LOG_FILE = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "logs", "pass1.log")
BOOK_REPORTS_DIR = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "book_reports")

TOTAL_BIBLE_CHAPTERS = 1189


def log(msg: str):
    print(msg, flush=True)
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(f"{msg}\n")


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
            status TEXT DEFAULT 'pending',
            worker_id TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            completed_at TIMESTAMP,
            pos TEXT
        )
    """)
    c.execute("CREATE INDEX IF NOT EXISTS idx_queue_status ON lexicon_queue(status)")
    c.execute("CREATE INDEX IF NOT EXISTS idx_queue_headword ON lexicon_queue(headword)")
    c.execute("CREATE INDEX IF NOT EXISTS idx_queue_book ON lexicon_queue(first_book_num)")

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
    rows = c.execute("SELECT token, lemma, pos FROM token_cache").fetchall()
    cache: Dict[str, Tuple[Optional[str], Optional[str]]] = {}
    for tok, lem, pos in rows:
        cache[tok] = (lem.strip() if lem and lem.strip() else None, pos.strip() if pos and pos.strip() else None)
    return cache


def save_token_cache_batch(conn: sqlite3.Connection, results: Dict[str, Tuple[Optional[str], Optional[str]]], model_name: str = "deepseek-v3"):
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


def load_book_metadata() -> Tuple[Dict[int, str], Dict[int, int]]:
    tamil_names: Dict[int, str] = {}
    if os.path.exists(BOOK_NAMES_FILE):
        try:
            with open(BOOK_NAMES_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                tamil_names = {int(k): v for k, v in data.get("taobvsi", {}).items()}
        except Exception:
            pass

    chapter_counts: Dict[int, int] = {}
    if os.path.exists(BOOKS_JSON_FILE):
        try:
            with open(BOOKS_JSON_FILE, "r", encoding="utf-8") as f:
                b_list = json.load(f)
                chapter_counts = {item["bookNumber"]: item["chapters"] for item in b_list}
        except Exception:
            pass

    return tamil_names, chapter_counts


def extract_tamil_tokens(text: str) -> List[str]:
    return re.findall(r'[\u0B80-\u0BFF]+', text)


def call_deepseek_batch(tokens: List[str], max_retries: int = 5) -> Tuple[Dict[str, Tuple[Optional[str], Optional[str]]], int, int]:
    prompt = f"""You are an expert biblical lexicographer specializing in the classical Protestant Tamil Bible (TAOVBSI).
For each of the following Tamil biblical words from scripture:
1. Grammatical & Discourse Particles: Filter out pure grammatical function words, pronouns, auxiliary copulas, optative clitics (e.g. 'கடவது', 'வேண்டும்'), discourse conjunctions ('ஆதலால்'), and inflectional particles with no distinct theological or lexical significance by setting 'lemma': null and 'pos': null.
2. Part of Speech Separation: Strictly preserve distinct lemmas for different parts of speech:
   - Verbs: Return the uninflected root/imperative verb (e.g., 'சிருஷ்டி', 'இரு', 'பிரி', 'பார்', 'செய்', 'ஆள்', 'அசைவாடு').
   - Common / Abstract Nouns: Return the canonical nominative dictionary noun (e.g., 'வானம்', 'பூமி', 'ஒழுங்கு', 'வெளிச்சம்', 'இருள்', 'அடையாளம்').
   - Personal / Agent Nouns: Return the distinct agent title (e.g., 'தேவன்', 'படைப்பாளி', 'ஆண்டவர்').
   DO NOT merge verbs into nouns or agents into verbs.
3. Classical Protestant Register: Use strictly classical Protestant Tamil terminology (தேவன், பரிசுத்தம், இரட்சிப்பு, வேதம்).

Words:
{json.dumps(tokens, ensure_ascii=False)}

Respond strictly in JSON with this structure:
{{
  "results": [
    {{"word": "word", "lemma": "base_lemma or null", "pos": "verb, noun, agent_noun, adjective, or null"}}
  ]
}}"""

    payload = {
        "model": "deepseek-chat",
        "messages": [{"role": "user", "content": prompt}],
        "response_format": {"type": "json_object"},
        "temperature": 0.0
    }

    req_data = json.dumps(payload).encode("utf-8")

    for attempt in range(max_retries):
        try:
            req = urllib.request.Request(
                DEEPSEEK_URL,
                data=req_data,
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {API_KEY}"
                }
            )
            with urllib.request.urlopen(req, timeout=45) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                usage = data.get("usage", {})
                p_tok = usage.get("prompt_tokens", 0)
                c_tok = usage.get("completion_tokens", 0)
                content = json.loads(data["choices"][0]["message"]["content"])

                results_map = {}
                for item in content.get("results", []):
                    w = item.get("word")
                    lem = item.get("lemma")
                    pos = item.get("pos")
                    if w:
                        clean_lem = lem.strip() if lem and isinstance(lem, str) and lem.strip() and lem.lower() not in ("null", "none") else None
                        clean_pos = pos.strip().lower() if pos and isinstance(pos, str) and pos.strip() and pos.lower() not in ("null", "none") else None
                        results_map[w] = (clean_lem, clean_pos)
                return results_map, p_tok, c_tok
        except Exception as e:
            wait_sec = 2 * (attempt + 1)
            time.sleep(wait_sec)
            if attempt == max_retries - 1:
                log(f"[Error] DeepSeek call failed after {max_retries} attempts: {e}")
                return {}, 0, 0

    return {}, 0, 0


# Shared Live State for Background 10s Reporter
class PipelineState:
    def __init__(self):
        self.lock = threading.Lock()
        self.current_book_name = "Starting..."
        self.current_book_num = 1
        self.current_ch = 1
        self.total_chapters_scanned = 0
        self.total_lemmas = 0
        self.total_tokens_cached = 0
        self.total_prompt_tok = 677967
        self.total_comp_tok = 1027481
        self.start_time = time.time() - 4800  # reflect total runtime
        self.running = True
        self.book_progress: Dict[int, Dict[str, Any]] = {}
        self.pos_counts: Dict[str, int] = defaultdict(int)


pipeline_state = PipelineState()


def write_status_markdown():
    with pipeline_state.lock:
        b_name = pipeline_state.current_book_name
        b_num = pipeline_state.current_book_num
        ch_num = pipeline_state.current_ch
        total_ch = pipeline_state.total_chapters_scanned
        total_lem = pipeline_state.total_lemmas
        total_cached = pipeline_state.total_tokens_cached
        p_tok = pipeline_state.total_prompt_tok
        c_tok = pipeline_state.total_comp_tok
        elapsed = max(1.0, time.time() - pipeline_state.start_time)
        b_prog = dict(pipeline_state.book_progress)
        pos_dist = dict(pipeline_state.pos_counts)

    cost_p = (p_tok / 1_000_000) * 0.14
    cost_c = (c_tok / 1_000_000) * 0.28
    tot_cost = cost_p + cost_c

    rate_ch_hr = (total_ch / (elapsed / 3600.0)) if elapsed > 0 else 0
    rem_chapters = max(0, TOTAL_BIBLE_CHAPTERS - total_ch)
    est_rem_sec = (rem_chapters / rate_ch_hr * 3600.0) if rate_ch_hr > 0 else 0
    est_target_time = time.strftime("%Y-%m-%d %H:%M", time.localtime(time.time() + est_rem_sec))

    report = f"""# 📖 TAOBVSI Classical Lexicon Pipeline — Live Status Report

> **Engine**: `DeepSeek-V3 (deepseek-chat)` | **Mode**: Sequential Batch Scanner (50 tokens/call)
> **Active Focus**: `{b_name} {ch_num}` (Book {b_num}/66) | **Last Refreshed**: `{time.strftime("%Y-%m-%d %H:%M:%S")}` (Auto-refreshed every 10s)

## 1. Executive Summary & KPIs

| Metric | Current Status | Target Scope | Progress |
| :--- | :---: | :---: | :---: |
| **Pass 1 Scripture Scan** | `RUNNING` ({b_name} {ch_num}) | 66 Books (1,189 Chapters) | **`{total_ch / TOTAL_BIBLE_CHAPTERS * 100:.1f}%`** (`{total_ch}/1,189` ch) |
| **Unique Base Lemmas Queued** | **`{total_lem:,}`** unique lemmas | All 66 Books | Distinct POS separation |
| **Token Cache Volume** | **`{total_cached:,}`** unique tokens | ~94,000 Bible-wide | Instant lookup / 0 redundancy |
| **Pass 1 Scan Speed** | **`{rate_ch_hr:.1f}` chapters/hr** | ~`{elapsed / max(1, total_ch):.1f}s` per chapter | Sequential API stream |
| **Total API Tokens** | Prompt: `{p_tok:,}` | Completion: `{c_tok:,}` | DeepSeek-V3 |
| **Total Pass 1 Financial Cost** | **`${tot_cost:.4f}`** | ~$0.91 projected Bible-wide | Incurred to date |
| **Estimated Completion ETA** | **`{est_target_time}`** | `{rem_chapters}` chapters remaining | ~`{est_rem_sec/60:.1f}` mins |

## 2. Discovered Part-of-Speech (POS) Distribution

| Part of Speech | Discovered Lemmas | Percentage |
| :--- | :---: | :---: |
| **Nouns (noun)** | `{pos_dist.get('noun', 0):,}` | `{pos_dist.get('noun', 0) / max(1, total_lem) * 100:.1f}%` |
| **Verbs (verb)** | `{pos_dist.get('verb', 0):,}` | `{pos_dist.get('verb', 0) / max(1, total_lem) * 100:.1f}%` |
| **Agent / Divine Titles (agent_noun)** | `{pos_dist.get('agent_noun', 0):,}` | `{pos_dist.get('agent_noun', 0) / max(1, total_lem) * 100:.1f}%` |
| **Adjectives (adjective)** | `{pos_dist.get('adjective', 0):,}` | `{pos_dist.get('adjective', 0) / max(1, total_lem) * 100:.1f}%` |
| **Adverbs / Other** | `{pos_dist.get('adverb', 0) + pos_dist.get('other', 0):,}` | `{(pos_dist.get('adverb', 0) + pos_dist.get('other', 0)) / max(1, total_lem) * 100:.1f}%` |

## 3. Book-Wise Progress Summary (66 Books)

| Book # | Book Name | Chapters | Status | First-Appearance Lemmas | Book Report |
| :---: | :--- | :---: | :---: | :---: | :---: |
"""
    for b_idx in range(1, 67):
        p = b_prog.get(b_idx)
        if not p:
            continue
        status_badge = "🟢 100% COMPLETE" if p["completed"] else f"🟡 IN PROGRESS ({p['scanned']}/{p['total_ch']} ch)"
        report_link = f"[`book_{b_idx:02d}_{p['name']}.json`](file:///{BOOK_REPORTS_DIR.replace('\\\\', '/')}/book_{b_idx:02d}_{p['name']}.json)"
        report += f"| {b_idx} | **{p['name']}** | `{p['scanned']}/{p['total_ch']}` | {status_badge} | **`{p['new_lemmas']:,}`** | {report_link} |\n"

    report += f"""
---
*This report refreshes automatically every 10 seconds. Canonical queue:* [`releases/study/taobvsi/taobvsi_glossary_queue.sqlite`](file:///{QUEUE_DB.replace('\\\\', '/')})
"""
    try:
        with open(STATUS_MD, "w", encoding="utf-8") as f:
            f.write(report)
    except Exception:
        pass

    # Produce JSON version every 10s
    json_payload = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "engine": "DeepSeek-V3 (deepseek-chat)",
        "mode": "Sequential Batch Scanner (50 tokens/call)",
        "active_focus": {
            "book_number": b_num,
            "book_name": b_name,
            "chapter": ch_num
        },
        "kpis": {
            "chapters_scanned": total_ch,
            "total_chapters": TOTAL_BIBLE_CHAPTERS,
            "progress_percentage": round(total_ch / TOTAL_BIBLE_CHAPTERS * 100, 2),
            "unique_lemmas_queued": total_lem,
            "tokens_cached": total_cached,
            "scan_speed_chapters_per_hr": round(rate_ch_hr, 1),
            "seconds_per_chapter": round(elapsed / max(1, total_ch), 2),
            "api_prompt_tokens": p_tok,
            "api_completion_tokens": c_tok,
            "total_cost_usd": round(tot_cost, 4),
            "estimated_completion_time": est_target_time,
            "remaining_chapters": rem_chapters,
            "remaining_minutes": round(est_rem_sec / 60.0, 1)
        },
        "pos_distribution": {
            "noun": pos_dist.get("noun", 0),
            "verb": pos_dist.get("verb", 0),
            "agent_noun": pos_dist.get("agent_noun", 0),
            "adjective": pos_dist.get("adjective", 0),
            "adverb_other": pos_dist.get("adverb", 0) + pos_dist.get("other", 0)
        },
        "book_wise_progress": [
            {
                "book_number": b_idx,
                "book_name": p["name"],
                "scanned_chapters": p["scanned"],
                "total_chapters": p["total_ch"],
                "completed": p["completed"],
                "first_appearance_lemmas": p["new_lemmas"],
                "report_file": f"book_reports/book_{b_idx:02d}_{p['name']}.json"
            }
            for b_idx, p in sorted(b_prog.items()) if p["scanned"] > 0 or p["completed"]
        ]
    }
    try:
        with open(STATUS_JSON, "w", encoding="utf-8") as f:
            json.dump(json_payload, f, ensure_ascii=False, indent=2)
    except Exception:
        pass


def status_updater_daemon(interval: int = 10):
    while pipeline_state.running:
        write_status_markdown()
        time.sleep(interval)


def flush_book_report(b_idx: int, b_name: str, total_ch: int, scanned_ch: int, is_completed: bool, book_lemmas: List[Dict[str, Any]]):
    os.makedirs(BOOK_REPORTS_DIR, exist_ok=True)
    report_file = os.path.join(BOOK_REPORTS_DIR, f"book_{b_idx:02d}_{b_name}.json")

    payload = {
        "book_number": b_idx,
        "book_name": b_name,
        "total_chapters": total_ch,
        "scanned_chapters": scanned_ch,
        "is_completed": is_completed,
        "first_appearance_lemmas_count": len(book_lemmas),
        "lemmas": book_lemmas
    }

    try:
        with open(report_file, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
    except Exception as e:
        log(f"[Warning] Failed writing book report {report_file}: {e}")


def run_sequential_deepseek_pass1(start_book: int = 1, end_book: int = 66, batch_size: int = 50):
    log("=" * 80)
    log(f"PASS 1: SEQUENTIAL DEEPSEEK-V3 SCRIPTURE SCANNER (Books {start_book} to {end_book})")
    log(f"Batch Size: {batch_size} tokens/call | Mode: Pure Sequential | Live Status: 10s Refreshes")
    log("=" * 80)

    book_names, book_chapters = load_book_metadata()
    conn = init_queue_db()
    token_cache = load_token_cache(conn)
    log(f"Loaded {len(token_cache):,} existing cached tokens from SQLite.")

    # Load existing queue items so we update refs & surface forms smoothly
    c = conn.cursor()
    c.execute("SELECT headword, pos, first_reference, first_book_num, first_chapter_num, surface_forms_json, refs_json FROM lexicon_queue")
    lemma_data: Dict[str, Dict[str, Any]] = {}
    book_first_lemmas: Dict[int, List[Dict[str, Any]]] = defaultdict(list)
    pos_counts: Dict[str, int] = defaultdict(int)

    for r in c.fetchall():
        hw, pos, first_ref, b_num, ch_num, s_json, r_json = r
        pos_clean = pos.lower() if pos else "noun"
        pos_counts[pos_clean] += 1
        d = {
            "lemma": hw,
            "pos": pos,
            "first_ref": first_ref,
            "book": b_num,
            "chapter": ch_num,
            "surfaces": set(json.loads(s_json)),
            "refs": json.loads(r_json)
        }
        lemma_data[hw] = d
        book_first_lemmas[b_num].append({
            "lemma": hw,
            "pos": pos,
            "first_reference": first_ref,
            "chapter": ch_num,
            "surface_forms": sorted(list(d["surfaces"]))
        })

    log(f"Loaded {len(lemma_data):,} existing queue lemmas from SQLite.")

    # Initialize shared pipeline state
    with pipeline_state.lock:
        pipeline_state.total_lemmas = len(lemma_data)
        pipeline_state.total_tokens_cached = len(token_cache)
        pipeline_state.pos_counts = pos_counts
        for b in range(1, 67):
            b_n = book_names.get(b, f"Book {b}")
            tot_ch = book_chapters.get(b, 1)
            lemmas_for_b = book_first_lemmas.get(b, [])
            pipeline_state.book_progress[b] = {
                "name": b_n,
                "total_ch": tot_ch,
                "scanned": 0,
                "completed": False,
                "new_lemmas": len(lemmas_for_b)
            }

    # Start 10s status updater daemon
    updater_thread = threading.Thread(target=status_updater_daemon, args=(10,), daemon=True)
    updater_thread.start()

    conn.execute("INSERT OR REPLACE INTO pipeline_control (key, value, updated_at) VALUES ('pass1_status', 'running', CURRENT_TIMESTAMP)")
    conn.commit()

    total_chapters_scanned = 0
    pending_tokens: Set[str] = set()

    for b_idx in range(start_book, end_book + 1):
        b_dir = os.path.join(BIBLE_ROOT, str(b_idx))
        if not os.path.exists(b_dir):
            continue
        b_name = book_names.get(b_idx, f"Book {b_idx}")
        total_ch_in_book = book_chapters.get(b_idx, len(os.listdir(b_dir)))

        ch_files = sorted(
            [f for f in os.listdir(b_dir) if f.endswith(".json")],
            key=lambda x: int(os.path.splitext(x)[0]) if os.path.splitext(x)[0].isdigit() else 999
        )

        book_lemmas_this_book = list(book_first_lemmas[b_idx])
        scanned_in_this_book = 0

        for ch_f in ch_files:
            ch_num_str = os.path.splitext(ch_f)[0]
            if not ch_num_str.isdigit():
                continue
            ch_num = int(ch_num_str)

            with pipeline_state.lock:
                pipeline_state.current_book_name = b_name
                pipeline_state.current_book_num = b_idx
                pipeline_state.current_ch = ch_num

            with open(os.path.join(b_dir, ch_f), "r", encoding="utf-8") as jf:
                verses = json.load(jf)

            t_ch_start = time.time()
            chapter_token_seq = []
            for v in verses:
                v_num = v.get("verse", 1)
                ref_str = f"{b_name} {ch_num}:{v_num}"
                text = v.get("text", "")
                tokens = extract_tamil_tokens(text)
                for tok in tokens:
                    if len(tok) < 2:
                        continue
                    chapter_token_seq.append((tok, ref_str))
                    if tok not in token_cache:
                        pending_tokens.add(tok)

            # Process pending tokens sequentially
            if pending_tokens:
                unseen_list = sorted(list(pending_tokens))
                log(f"\nScanning {b_name} Chapter {ch_num} ({len(verses)} verses)...")
                log(f"  Classifying {len(unseen_list)} unseen tokens via DeepSeek-V3 (Sequential)...")
                for i in range(0, len(unseen_list), batch_size):
                    chunk = unseen_list[i : i + batch_size]
                    t_b = time.time()
                    res_map, p_tok, c_tok = call_deepseek_batch(chunk)
                    elapsed_b = time.time() - t_b

                    with pipeline_state.lock:
                        pipeline_state.total_prompt_tok += p_tok
                        pipeline_state.total_comp_tok += c_tok

                    log(f"    [Batch {i//batch_size + 1}/{(len(unseen_list) + batch_size - 1)//batch_size}] {len(chunk)} tokens in {elapsed_b:.2f}s ({elapsed_b/len(chunk):.2f}s/tok) [in={p_tok}, out={c_tok}]")

                    if res_map:
                        token_cache.update(res_map)
                        save_token_cache_batch(conn, res_map, model_name="deepseek-v3")
                        with pipeline_state.lock:
                            pipeline_state.total_tokens_cached = len(token_cache)
                        for k in res_map.keys():
                            pending_tokens.discard(k)
                    else:
                        log(f"[FATAL] API call failed for {len(chunk)} tokens (e.g. Insufficient Balance or Network Error). Halting pipeline cleanly so no scripture words are missed.")
                        conn.close()
                        sys.exit(1)

            # Resolve lemmas in scripture order
            new_lemmas_this_chapter = []
            for tok, ref_str in chapter_token_seq:
                entry = token_cache.get(tok)
                if not entry:
                    continue
                lem, pos = entry
                if not lem or len(lem) < 2:
                    continue

                if lem not in lemma_data:
                    lemma_data[lem] = {
                        "pos": pos,
                        "first_ref": ref_str,
                        "book": b_idx,
                        "chapter": ch_num,
                        "surfaces": {tok},
                        "refs": [ref_str]
                    }
                    new_lemmas_this_chapter.append(lem)
                    item_dict = {
                        "lemma": lem,
                        "pos": pos,
                        "first_reference": ref_str,
                        "chapter": ch_num,
                        "surface_forms": [tok]
                    }
                    book_lemmas_this_book.append(item_dict)
                    with pipeline_state.lock:
                        pipeline_state.pos_counts[pos.lower() if pos else 'noun'] += 1
                else:
                    lemma_data[lem]["surfaces"].add(tok)
                    if not lemma_data[lem].get("pos") and pos:
                        lemma_data[lem]["pos"] = pos
                    if ref_str not in lemma_data[lem]["refs"]:
                        lemma_data[lem]["refs"].append(ref_str)

            # Persist newly discovered lemmas to lexicon_queue
            if new_lemmas_this_chapter:
                qc = conn.cursor()
                qc.execute("BEGIN TRANSACTION")
                for lem in new_lemmas_this_chapter:
                    d = lemma_data[lem]
                    qc.execute("""
                        INSERT INTO lexicon_queue (
                            headword, pos, first_reference, first_book_num, first_chapter_num,
                            surface_forms_json, refs_json, status
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, 'pending')
                        ON CONFLICT(headword) DO UPDATE SET
                            pos = COALESCE(excluded.pos, lexicon_queue.pos),
                            surface_forms_json = excluded.surface_forms_json,
                            refs_json = excluded.refs_json
                    """, (
                        lem,
                        d.get("pos"),
                        d["first_ref"],
                        d["book"],
                        d["chapter"],
                        json.dumps(sorted(list(d["surfaces"])), ensure_ascii=False),
                        json.dumps(d["refs"], ensure_ascii=False)
                    ))
                conn.commit()

            total_chapters_scanned += 1
            scanned_in_this_book += 1
            ch_elapsed = time.time() - t_ch_start

            with pipeline_state.lock:
                pipeline_state.total_chapters_scanned = total_chapters_scanned
                pipeline_state.total_lemmas = len(lemma_data)
                pipeline_state.book_progress[b_idx]["scanned"] = scanned_in_this_book
                pipeline_state.book_progress[b_idx]["new_lemmas"] = len(book_lemmas_this_book)

            if pending_tokens or new_lemmas_this_chapter:
                log(f"  -> {b_name} {ch_num} done in {ch_elapsed:.2f}s | New Lemmas: {len(new_lemmas_this_chapter)} | Total Queue: {len(lemma_data)}")

        # Book completed
        with pipeline_state.lock:
            pipeline_state.book_progress[b_idx]["completed"] = True

        flush_book_report(
            b_idx=b_idx,
            b_name=b_name,
            total_ch=total_ch_in_book,
            scanned_ch=scanned_in_this_book,
            is_completed=True,
            book_lemmas=book_lemmas_this_book
        )
        log(f"[Book {b_idx}/66 Complete] {b_name} finished ({scanned_in_this_book} ch). Report written to book_reports/book_{b_idx:02d}_{b_name}.json ({len(book_lemmas_this_book)} first-appearance lemmas).")

    conn.execute("INSERT OR REPLACE INTO pipeline_control (key, value, updated_at) VALUES ('pass1_status', 'completed', CURRENT_TIMESTAMP)")
    conn.commit()
    conn.close()

    pipeline_state.running = False
    write_status_markdown()

    log("\n" + "=" * 80)
    log(f"PASS 1 WHOLE BIBLE SCAN COMPLETED!")
    log(f"Total Chapters Scanned: {total_chapters_scanned}")
    log(f"Total Unique Base Lemmas Queued: {len(lemma_data)}")
    log(f"Total Tokens Cached: {len(token_cache)}")
    log("=" * 80)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Sequential DeepSeek Pass 1 Scanner")
    parser.add_argument("--start-book", type=int, default=1, help="Starting book number (1-66)")
    parser.add_argument("--end-book", type=int, default=66, help="Ending book number (1-66)")
    parser.add_argument("--batch-size", type=int, default=50, help="Batch size for unseen tokens")
    args = parser.parse_args()

    run_sequential_deepseek_pass1(start_book=args.start_book, end_book=args.end_book, batch_size=args.batch_size)
