#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_references.py

Post-processing concordance builder for TAOVBSI glossary entries.
- Reads generated glossary entries from releases/study/taobvsi/glossary_additions/book_*.json.
- Scans every verse in the corresponding Bible book (releases/bibles/taobvsi/{book_num}/).
- Accurately maps every inflected token and grammatical form to its canonical headword.
- Compiles the full, sorted, de-duplicated list of `refs` (e.g. ["ஆதியாகமம் 1:1", "ஆதியாகமம் 1:2", ...]).
- Compiles the complete list of all distinct `surface_forms` (e.g. ["பூமி", "பூமியை", "பூமியானது", ...]).
- Updates both the output JSON file and SQLite database tables (surface_forms, verse_references).
"""

import os
import sys
import json
import sqlite3
from typing import Dict, List, Set, Any, Optional

sys.stdout.reconfigure(encoding="utf-8")

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", ".."))

if CURRENT_DIR not in sys.path:
    sys.path.insert(0, CURRENT_DIR)

from morphology import extract_tamil_words, clean_tamil_token, normalize_to_lemma_candidate

BIBLE_ROOT = os.path.join(PROJECT_ROOT, "releases", "bibles", "taobvsi")
LEGACY_GLOSSARY_DB = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "taobvsi_glossary.sqlite")
ENRICHED_DB = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "taobvsi_glossary_enriched.sqlite")
BOOK_NAMES_FILE = os.path.join(PROJECT_ROOT, "releases", "book_names.json")
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "glossary_additions")


def load_book_names() -> Dict[int, str]:
    if os.path.exists(BOOK_NAMES_FILE):
        try:
            with open(BOOK_NAMES_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                ta_names = data.get("taobvsi", {})
                return {int(k): v for k, v in ta_names.items()}
        except Exception:
            pass
    return {1: "ஆதியாகமம்"}


def load_legacy_mappings() -> Dict[str, str]:
    mapping = {}
    if os.path.exists(LEGACY_GLOSSARY_DB):
        try:
            conn = sqlite3.connect(LEGACY_GLOSSARY_DB)
            c = conn.cursor()
            rows = c.execute(
                "SELECT s.surface_form, g.headword FROM surface_forms s JOIN glossary_entries g ON s.entry_id = g.id"
            ).fetchall()
            for s_form, h_word in rows:
                if s_form and h_word:
                    mapping[s_form.strip()] = h_word.strip()
            conn.close()
        except Exception:
            pass
    return mapping


def parse_ref_key(r_str: str):
    """Natural sort key for scripture references like 'ஆதியாகமம் 1:12' -> (1, 12)."""
    try:
        parts = r_str.split(" ")[-1].split(":")
        return (int(parts[0]), int(parts[1]))
    except Exception:
        return (999, 999)


def build_references_for_book(book_num: int):
    book_names = load_book_names()
    b_name = book_names.get(book_num, f"Book {book_num}")
    b_dir = os.path.join(BIBLE_ROOT, str(book_num))
    if not os.path.exists(b_dir):
        print(f"[Post-Processing] Directory for book {book_num} ({b_name}) not found.")
        return

    out_file = os.path.join(OUTPUT_DIR, f"book_{book_num:02d}_{b_name}.json")
    if not os.path.exists(out_file):
        print(f"[Post-Processing] Glossary JSON {out_file} not found.")
        return

    with open(out_file, "r", encoding="utf-8") as f:
        entries = json.load(f)

    if not entries:
        print(f"[Post-Processing] No entries in {out_file}.")
        return

    entries_by_hw = {e["headword"]: e for e in entries if e.get("headword")}

    # Seed mapping from legacy DB and existing entries
    surface_to_hw = load_legacy_mappings()
    for hw, e in entries_by_hw.items():
        surface_to_hw[hw] = hw
        for sf in e.get("surface_forms", []):
            surface_to_hw[sf] = hw

    print(f"\n[Post-Processing] Scanning {b_name} Bible text to build complete references for {len(entries_by_hw)} headwords...", flush=True)

    all_ch_files = sorted(
        [f for f in os.listdir(b_dir) if f.endswith(".json")],
        key=lambda x: int(os.path.splitext(x)[0]) if os.path.splitext(x)[0].isdigit() else 999
    )

    total_refs_added = 0
    total_surfaces_added = 0

    for ch_file in all_ch_files:
        c_num = int(os.path.splitext(ch_file)[0]) if os.path.splitext(ch_file)[0].isdigit() else 1
        ch_path = os.path.join(b_dir, ch_file)
        with open(ch_path, "r", encoding="utf-8") as jf:
            verses = json.load(jf)

        for v in verses:
            v_num = v.get("verse", 1)
            v_text = v.get("text", "")
            ref_str = f"{b_name} {c_num}:{v_num}"
            tokens = extract_tamil_words(v_text)

            for t in tokens:
                cl = clean_tamil_token(t)
                if len(cl) < 2:
                    continue

                # 1. Exact lookup
                target_hw = surface_to_hw.get(cl)

                # 2. Morphological stem
                if not target_hw:
                    stem = normalize_to_lemma_candidate(cl)
                    target_hw = surface_to_hw.get(stem) or (stem if stem in entries_by_hw else None)

                # If matches a cataloged headword
                if target_hw and target_hw in entries_by_hw:
                    entry = entries_by_hw[target_hw]
                    if "surface_forms" not in entry:
                        entry["surface_forms"] = [target_hw]
                    if cl not in entry["surface_forms"]:
                        entry["surface_forms"].append(cl)
                        surface_to_hw[cl] = target_hw
                        total_surfaces_added += 1

                    if "refs" not in entry:
                        entry["refs"] = [entry.get("first_reference", ref_str)]
                    if ref_str not in entry["refs"]:
                        entry["refs"].append(ref_str)
                        total_refs_added += 1

    # Connect to SQLite for persisting
    conn = sqlite3.connect(ENRICHED_DB)
    c = conn.cursor()

    for e in entries:
        hw = e.get("headword")
        if not hw:
            continue
        # Sort and clean references
        if "refs" in e:
            e["refs"] = sorted(list(set(e["refs"])), key=parse_ref_key)
        # Sort and clean surface forms (headword first, then sorted variants)
        if "surface_forms" in e:
            other_forms = sorted([s for s in set(e["surface_forms"]) if s != hw])
            e["surface_forms"] = [hw] + other_forms

        # Update SQLite
        c.execute("UPDATE glossary_entries SET entry_json = ? WHERE headword = ?", (
            json.dumps(e, ensure_ascii=False), hw
        ))
        for sf in e.get("surface_forms", []):
            c.execute("INSERT OR IGNORE INTO surface_forms (headword, surface_form) VALUES (?, ?)", (hw, sf))
        for ref in e.get("refs", []):
            c.execute("INSERT OR IGNORE INTO verse_references (headword, reference) VALUES (?, ?)", (hw, ref))

    conn.commit()
    conn.close()

    # Save to JSON
    with open(out_file, "w", encoding="utf-8") as out_f:
        json.dump(entries, out_f, ensure_ascii=False, indent=2)

    print(f"[Post-Processing Complete] Successfully compiled {total_surfaces_added} new surface forms and {total_refs_added} new verse references across {b_name}!", flush=True)


if __name__ == "__main__":
    b_num = 1
    if len(sys.argv) > 1:
        try:
            b_num = int(sys.argv[1])
        except Exception:
            pass
    build_references_for_book(b_num)
