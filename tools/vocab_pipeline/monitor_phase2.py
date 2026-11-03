#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Phase 2 Live Lexicon Monitor
============================
Displays live metrics and recently enriched lemmas from `study_lexicon`.
"""

import os
import sys
import time
import sqlite3
import json

sys.stdout.reconfigure(encoding="utf-8")

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", ".."))
SQLITE_PATH = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "taobvsi_glossary.sqlite")
PROGRESS_MD = os.path.join(CURRENT_DIR, "PROGRESS.md")

def get_stats():
    if not os.path.exists(SQLITE_PATH):
        return None

    conn = sqlite3.connect(SQLITE_PATH)
    cur = conn.cursor()

    cur.execute("SELECT count(distinct canonical) FROM unique_words WHERE canonical IS NOT NULL AND length(trim(canonical)) > 0")
    total_canonical = cur.fetchone()[0]

    cur.execute("SELECT count(*) FROM study_lexicon")
    enriched_count = cur.fetchone()[0]

    cur.execute("""
    SELECT lemma, occurrence_count, strongs_number, original_lang, original_script, gloss_en, theological_pillar, definition_ta, updated_at
    FROM study_lexicon
    ORDER BY id DESC
    LIMIT 20
    """)
    recent = cur.fetchall()
    conn.close()

    pct = (enriched_count / total_canonical * 100) if total_canonical > 0 else 0.0

    return {
        "total_canonical": total_canonical,
        "enriched_count": enriched_count,
        "percent": pct,
        "recent": recent
    }

def update_markdown_dashboard(stats):
    """Updates tools/vocab_pipeline/PROGRESS.md with clean formatting."""
    bar_width = 30
    filled = int(bar_width * stats["percent"] / 100)
    bar = "█" * filled + "░" * (bar_width - filled)

    md = [
        "# Phase 2: Master 360° Bible Study Lexicon — Live Status",
        "",
        f"> **Last Refreshed:** {time.strftime('%Y-%m-%d %H:%M:%S')} | **Backend:** Intel Arc Vulkan GPU (Port 8080, 3 Slots)",
        "",
        "## Overall Progress",
        f"```text",
        f"[{bar}] {stats['enriched_count']:,} / {stats['total_canonical']:,} lemmas ({stats['percent']:.2f}%)",
        f"```",
        "",
        "| Metric | Value |",
        "| :--- | :--- |",
        f"| **Enriched Lemmas in `study_lexicon`** | **{stats['enriched_count']:,}** |",
        f"| **Total Canonical Bible Roots** | **{stats['total_canonical']:,}** |",
        f"| **Remaining to Process** | **{stats['total_canonical'] - stats['enriched_count']:,}** |",
        f"| **Completion** | **{stats['percent']:.2f}%** |",
        "",
        "---",
        "",
        "## Recently Enriched 360° Study Lexicon Entries",
        "",
        "| # | Lemma (வேர்ச்சொல்) | Occurrences | Strong's | Original Script | English Gloss | Theological Pillar |",
        "| :-: | :--- | :-: | :--- | :--- | :--- | :--- |"
    ]

    for idx, r in enumerate(stats["recent"], start=1):
        lemma = r[0]
        occ = f"{r[1]:,}"
        strongs = r[2] or "-"
        orig = f"{r[4]} ({r[3]})" if r[4] else (r[3] or "-")
        gloss = r[5] or "-"
        pillar = r[6] or "-"
        md.append(f"| {idx} | **{lemma}** | {occ} | `{strongs}` | {orig} | {gloss} | {pillar} |")

    md.append("")
    md.append("---")
    md.append("*To monitor live in terminal, run: `python tools/vocab_pipeline/monitor_phase2.py --watch`*")

    with open(PROGRESS_MD, "w", encoding="utf-8") as f:
        f.write("\n".join(md))

def print_terminal(stats):
    bar_width = 30
    filled = int(bar_width * stats["percent"] / 100)
    bar = "█" * filled + "░" * (bar_width - filled)

    print("=" * 80)
    print("PHASE 2 MASTER BIBLE STUDY LEXICON — LIVE MONITOR")
    print("=" * 80)
    print(f"[{bar}] {stats['enriched_count']:,} / {stats['total_canonical']:,} ({stats['percent']:.2f}%)")
    print(f"Database: {SQLITE_PATH}")
    print(f"Live Markdown Dashboard: {PROGRESS_MD}")
    print("-" * 80)
    print(f"{'#':<3} {'Lemma':<16} {'Bible Occ':<10} {'Strong':<12} {'Gloss (English)':<28} {'Pillar'}")
    print("-" * 80)

    for idx, r in enumerate(stats["recent"][:12], start=1):
        lemma = r[0]
        occ = f"{r[1]:,}x"
        strongs = r[2] or "-"
        gloss = (r[5] or "-")[:26]
        pillar = (r[6] or "-")[:20]
        print(f"{idx:<3} {lemma:<16} {occ:<10} {strongs:<12} {gloss:<28} {pillar}")

    print("=" * 80)

if __name__ == "__main__":
    watch_mode = "--watch" in sys.argv
    while True:
        stats = get_stats()
        if stats:
            update_markdown_dashboard(stats)
            print_terminal(stats)
        if not watch_mode:
            break
        time.sleep(4)
