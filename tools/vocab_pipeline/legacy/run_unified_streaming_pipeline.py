#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_unified_streaming_pipeline.py

Master Streaming Orchestrator:
Runs Pass 1 (Chapter-by-Chapter Scripture Discovery) and
Pass 2 (Streaming 10-Word Enrichment) simultaneously in parallel!

Architecture:
1. Pass 1 (Producer):
   - Scans Scripture chapter by chapter.
   - For unseen words: calls Gemma in batches of 40 to classify base lemmas.
   - Immediately commits each chapter's newly discovered unique base lemmas
     into 'lexicon_queue' in SQLite with status = 'pending'.
2. Pass 2 (Consumer - Fault-Tolerant):
   - Atomically claims 10 words at a time from 'lexicon_queue'.
   - Runs parallel workers to enrich Strong's Hebrew/Greek roots and Zac Poonen notes.
   - Directly writes to 'taobvsi_glossary_enriched.sqlite' and 'book_XX_YY.json'.
   - If Pass 2 catches up with Pass 1, waits gracefully for next chapter.
   - Automatically recovers any interrupted or stale jobs on startup.
3. Both passes run simultaneously on Gemma without conflicts.
"""

import os
import sys
import time
import argparse
import threading
import sqlite3
from typing import Optional

sys.stdout.reconfigure(encoding="utf-8")

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", ".."))

if CURRENT_DIR not in sys.path:
    sys.path.insert(0, CURRENT_DIR)

from build_global_bible_queue import build_global_queue, parse_chapter_arg, QUEUE_DB, DEFAULT_MODEL
from run_parallel_lexicon_workers import run_parallel_workers, get_queue_stats, DEFAULT_OLLAMA_MODEL


def run_pipeline(
    book_num: Optional[int] = None,
    chapters_str: Optional[str] = None,
    max_books: Optional[int] = None,
    model_name: str = DEFAULT_OLLAMA_MODEL,
    engine: str = "ollama",
    workers: int = 2,
    batch_size: int = 10,
    clean_queue: bool = False
):
    print("================================================================================")
    print("UNIFIED STREAMING PIPELINE: PASS 1 & PASS 2 IN PARALLEL")
    print(f"Model: {model_name} | Engine: {engine} | Pass 2 Batch Size: {batch_size} | Workers: {workers}")
    print("================================================================================")

    if clean_queue and os.path.exists(QUEUE_DB):
        conn = sqlite3.connect(QUEUE_DB, timeout=30.0)
        conn.execute("DROP TABLE IF EXISTS lexicon_queue")
        conn.commit()
        conn.close()
        print("[Clean] Reset lexicon_queue table.", flush=True)

    target_chs = parse_chapter_arg(chapters_str)

    pass1_thread = threading.Thread(
        target=build_global_queue,
        kwargs={
            "max_books": max_books,
            "book_num": book_num,
            "target_chapters": target_chs,
            "model_name": model_name,
            "batch_size": 40
        },
        name="Pass1-Producer",
        daemon=True
    )

    pass2_thread = threading.Thread(
        target=run_parallel_workers,
        kwargs={
            "num_workers": workers,
            "batch_size": batch_size,
            "engine": engine,
            "model_name": model_name,
            "book_filter": book_num,
            "continuous": True
        },
        name="Pass2-Consumer",
        daemon=True
    )

    t0 = time.time()
    print("\n[Launch] Starting Pass 1 (Chapter-by-Chapter) & Pass 2 (10-Words-at-a-time)...\n", flush=True)
    pass1_thread.start()
    time.sleep(2)  # Give Pass 1 time to initialize tables
    pass2_thread.start()

    try:
        while pass1_thread.is_alive() or pass2_thread.is_alive():
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[Interrupt] Pipeline stopped by user. All completed entries have been safely committed.", flush=True)
        sys.exit(0)

    pass1_thread.join()
    pass2_thread.join()

    total_time = time.time() - t0
    stats = get_queue_stats()
    print(f"\n================================================================================")
    print(f"UNIFIED PIPELINE COMPLETED in {total_time:.1f}s")
    print(f"Total Enriched Lemmas: {stats['completed']}/{stats['total']}")
    print(f"================================================================================\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Unified Streaming Scripture Lexicon Pipeline")
    parser.add_argument("--book", type=int, default=None, help="Book number (e.g. 1 for Genesis)")
    parser.add_argument("--chapters", type=str, default=None, help="Chapters range (e.g. '1-5' or '6-10')")
    parser.add_argument("--max-books", type=int, default=None, help="Limit to first N books")
    parser.add_argument("--engine", type=str, default="ollama", choices=["ollama", "gemini"], help="Engine")
    parser.add_argument("--model", type=str, default=DEFAULT_OLLAMA_MODEL, help="Model name (default: gemma4:12b)")
    parser.add_argument("--workers", type=int, default=2, help="Number of Pass 2 parallel workers (default: 2)")
    parser.add_argument("--batch-size", type=int, default=10, help="Pass 2 batch size (default: 10)")
    parser.add_argument("--clean", action="store_true", help="Clean queue table from scratch")
    args = parser.parse_args()

    run_pipeline(
        book_num=args.book,
        chapters_str=args.chapters,
        max_books=args.max_books,
        model_name=args.model,
        engine=args.engine,
        workers=args.workers,
        batch_size=args.batch_size,
        clean_queue=args.clean
    )
