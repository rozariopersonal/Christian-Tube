#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Synchronizes all generated contextual interlinear word JSON files into:
1. releases/study/taobvsi/taobvsi_glossary.sqlite (SQLite database)
2. releases/dictionaries/dict_ta_glossary.sqlite.gz (Gzipped distribution archive)
3. releases/manifest.json (Revision bumping for instant auto-sync)
"""

import os
import sys
import glob
import json
import gzip
import shutil
import sqlite3
import random
import string
from datetime import datetime

sys.stdout.reconfigure(encoding="utf-8")

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", ".."))

WORDS_DIR = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "words")
SQLITE_PATH = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "taobvsi_glossary.sqlite")
GZ_PATH = os.path.join(PROJECT_ROOT, "releases", "dictionaries", "dict_ta_glossary.sqlite.gz")
MANIFEST_PATH = os.path.join(PROJECT_ROOT, "releases", "manifest.json")


def log(msg: str):
    print(msg, flush=True)


def init_db(conn: sqlite3.Connection):
    cur = conn.cursor()

    cur.execute("""
    CREATE TABLE IF NOT EXISTS glossary_entries (
      id TEXT PRIMARY KEY,
      headword TEXT NOT NULL,
      transliteration TEXT,
      pos TEXT NOT NULL DEFAULT 'noun',
      pos_ta TEXT NOT NULL DEFAULT 'சொல்',
      category TEXT DEFAULT 'theological',
      gloss_en TEXT NOT NULL DEFAULT '',
      english_word TEXT,
      definition_ta TEXT NOT NULL DEFAULT '',
      definition_en TEXT NOT NULL DEFAULT '',
      examples TEXT,
      original_lang TEXT,
      original_lemma TEXT,
      original_translit TEXT,
      strongs TEXT,
      root_definition_ta TEXT,
      root_definition_en TEXT,
      original_context TEXT,
      modern_equivalents TEXT,
      see_also TEXT,
      notes TEXT,
      forms TEXT,
      refs TEXT,
      occurrence_count INTEGER DEFAULT 0
    )
    """)

    # Alter table if existing schema lacks new columns
    cur.execute("PRAGMA table_info(glossary_entries)")
    cols = [r[1] for r in cur.fetchall()]
    new_cols = [
        ("english_word", "TEXT"),
        ("original_translit", "TEXT"),
        ("root_definition_ta", "TEXT"),
        ("root_definition_en", "TEXT"),
        ("original_context", "TEXT"),
    ]
    for col_name, col_type in new_cols:
        if col_name not in cols:
            cur.execute(f"ALTER TABLE glossary_entries ADD COLUMN {col_name} {col_type}")

    cur.execute("""
    CREATE TABLE IF NOT EXISTS surface_forms (
      surface_form TEXT PRIMARY KEY,
      entry_id TEXT NOT NULL REFERENCES glossary_entries(id)
    )
    """)

    cur.execute("""
    CREATE TABLE IF NOT EXISTS verse_words (
      book INTEGER NOT NULL,
      chapter INTEGER NOT NULL,
      verse INTEGER NOT NULL,
      word_index INTEGER NOT NULL,
      surface_form TEXT NOT NULL,
      english_word TEXT,
      canonical TEXT,
      entry_id TEXT,
      definition_ta TEXT,
      definition_en TEXT,
      original_text TEXT,
      original_translit TEXT,
      strongs TEXT,
      root_definition_ta TEXT,
      root_definition_en TEXT,
      original_context TEXT,
      notes TEXT,
      PRIMARY KEY (book, chapter, verse, word_index)
    )
    """)

    cur.execute("CREATE INDEX IF NOT EXISTS idx_verse_words_ref ON verse_words(book, chapter, verse)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_verse_words_surface ON verse_words(surface_form)")

    cur.execute("""
    CREATE TABLE IF NOT EXISTS verse_glossary (
      book INTEGER NOT NULL,
      chapter INTEGER NOT NULL,
      verse INTEGER NOT NULL,
      entry_id TEXT NOT NULL,
      surface_form TEXT NOT NULL,
      PRIMARY KEY (book, chapter, verse, entry_id, surface_form)
    )
    """)

    conn.commit()


def sync_all_chapters():
    os.makedirs(os.path.dirname(SQLITE_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(GZ_PATH), exist_ok=True)

    json_files = sorted(glob.glob(os.path.join(WORDS_DIR, "*", "*.json")))
    if not json_files:
        log("No word JSON files found in " + WORDS_DIR)
        return

    log(f"Syncing {len(json_files)} chapter files to SQLite...")

    conn = sqlite3.connect(SQLITE_PATH)
    init_db(conn)
    cur = conn.cursor()

    total_words_synced = 0
    total_entries_synced = 0

    for fpath in json_files:
        try:
            with open(fpath, "r", encoding="utf-8") as fp:
                data = json.load(fp)
        except Exception as e:
            log(f"Error reading {fpath}: {e}")
            continue

        book_num = data.get("book")
        ch_num = data.get("chapter")
        words = data.get("words", [])

        if not book_num or not ch_num or not words:
            continue

        # Clean existing records for this chapter in verse_words and verse_glossary
        cur.execute("DELETE FROM verse_words WHERE book = ? AND chapter = ?", (book_num, ch_num))
        cur.execute("DELETE FROM verse_glossary WHERE book = ? AND chapter = ?", (book_num, ch_num))

        for idx, w in enumerate(words):
            v_num = w.get("verse", 1)
            surface = (w.get("word") or "").strip()
            canonical = (w.get("canonical") or surface).strip()
            english_word = (w.get("english_word") or "").strip()
            def_ta = (w.get("definition_ta") or "").strip()
            def_en = (w.get("definition_en") or "").strip()
            notes = (w.get("notes") or "").strip()

            orig = w.get("original_word") or {}
            orig_text = (orig.get("text") or "").strip()
            orig_translit = (orig.get("transliteration") or "").strip()
            strongs = (orig.get("strongs") or "").strip()
            root_def_ta = (orig.get("root_definition_ta") or "").strip()
            root_def_en = (orig.get("root_definition_en") or "").strip()
            orig_context = (orig.get("context") or "").strip()
            orig_lang = "Hebrew" if book_num <= 39 else "Greek"

            entry_id = canonical if canonical else surface
            ref_str = f"{book_num}:{ch_num}:{v_num}"

            # 1. Insert verse_words row
            cur.execute("""
            INSERT OR REPLACE INTO verse_words (
              book, chapter, verse, word_index, surface_form, english_word,
              canonical, entry_id, definition_ta, definition_en,
              original_text, original_translit, strongs,
              root_definition_ta, root_definition_en, original_context, notes
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                book_num, ch_num, v_num, idx, surface, english_word,
                canonical, entry_id, def_ta, def_en,
                orig_text, orig_translit, strongs,
                root_def_ta, root_def_en, orig_context, notes
            ))

            # 2. Insert surface_forms mapping
            if surface:
                cur.execute("INSERT OR REPLACE INTO surface_forms (surface_form, entry_id) VALUES (?, ?)", (surface, entry_id))

            # 3. Insert verse_glossary mapping
            if surface and entry_id:
                cur.execute("INSERT OR REPLACE INTO verse_glossary (book, chapter, verse, entry_id, surface_form) VALUES (?, ?, ?, ?, ?)",
                            (book_num, ch_num, v_num, entry_id, surface))

            # 4. Upsert glossary_entries
            cur.execute("SELECT refs, forms, occurrence_count FROM glossary_entries WHERE id = ?", (entry_id,))
            row = cur.fetchone()
            if row:
                existing_refs = json.loads(row[0]) if row[0] else []
                existing_forms = json.loads(row[1]) if row[1] else []
                occ = (row[2] or 0) + 1

                if ref_str not in existing_refs:
                    existing_refs.append(ref_str)
                if surface not in existing_forms:
                    existing_forms.append(surface)

                cur.execute("""
                UPDATE glossary_entries SET
                  english_word = COALESCE(NULLIF(?, ''), english_word),
                  gloss_en = COALESCE(NULLIF(?, ''), gloss_en),
                  definition_ta = COALESCE(NULLIF(?, ''), definition_ta),
                  definition_en = COALESCE(NULLIF(?, ''), definition_en),
                  original_lemma = COALESCE(NULLIF(?, ''), original_lemma),
                  original_translit = COALESCE(NULLIF(?, ''), original_translit),
                  strongs = COALESCE(NULLIF(?, ''), strongs),
                  root_definition_ta = COALESCE(NULLIF(?, ''), root_definition_ta),
                  root_definition_en = COALESCE(NULLIF(?, ''), root_definition_en),
                  original_context = COALESCE(NULLIF(?, ''), original_context),
                  notes = COALESCE(NULLIF(?, ''), notes),
                  forms = ?,
                  refs = ?,
                  occurrence_count = ?
                WHERE id = ?
                """, (
                    english_word, english_word, def_ta, def_en,
                    orig_text, orig_translit, strongs,
                    root_def_ta, root_def_en, orig_context, notes,
                    json.dumps(existing_forms, ensure_ascii=False),
                    json.dumps(existing_refs, ensure_ascii=False),
                    occ,
                    entry_id
                ))
            else:
                total_entries_synced += 1
                cur.execute("""
                INSERT INTO glossary_entries (
                  id, headword, transliteration, pos, pos_ta, category,
                  gloss_en, english_word, definition_ta, definition_en,
                  original_lang, original_lemma, original_translit, strongs,
                  root_definition_ta, root_definition_en, original_context,
                  notes, forms, refs, occurrence_count
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
                """, (
                    entry_id, canonical, orig_translit, 'noun', 'சொல்', 'theological',
                    english_word, english_word, def_ta, def_en,
                    orig_lang, orig_text, orig_translit, strongs,
                    root_def_ta, root_def_en, orig_context,
                    notes, json.dumps([surface], ensure_ascii=False),
                    json.dumps([ref_str], ensure_ascii=False)
                ))

            total_words_synced += 1

    conn.commit()

    # Rebuild FTS table
    try:
        cur.execute("DROP TABLE IF EXISTS glossary_fts")
        cur.execute("""
        CREATE VIRTUAL TABLE glossary_fts USING fts5(
            id, headword, transliteration, gloss_en, definition_ta, definition_en
        )
        """)
        cur.execute("""
        INSERT INTO glossary_fts (id, headword, transliteration, gloss_en, definition_ta, definition_en)
        SELECT id, headword, transliteration, gloss_en, definition_ta, definition_en FROM glossary_entries
        """)
        conn.commit()
        log("glossary_fts search index rebuilt successfully.")
    except Exception as e:
        log(f"FTS note: {e}")

    conn.close()
    log(f"SQLite DB updated: {total_words_synced} words synced ({total_entries_synced} new entries).")

    # Compress to GZ for release distribution
    log(f"Compressing SQLite to {GZ_PATH}...")
    with open(SQLITE_PATH, "rb") as f_in:
        with gzip.open(GZ_PATH, "wb", compresslevel=9) as f_out:
            shutil.copyfileobj(f_in, f_out)
    gz_size = os.path.getsize(GZ_PATH)
    log(f"Compressed archive ready: {gz_size / (1024*1024):.2f} MB")

    # Bump manifest revision
    bump_manifest_revision()


def bump_manifest_revision():
    if not os.path.exists(MANIFEST_PATH):
        return

    try:
        from datetime import timezone
        with open(MANIFEST_PATH, "r", encoding="utf-8") as fp:
            manifest = json.load(fp)

        # Generate unique 8-char random alphanumeric revision
        new_rev = "".join(random.choices(string.ascii_lowercase + string.digits, k=8))
        manifest["revision"] = new_rev
        manifest["updatedAt"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")

        with open(MANIFEST_PATH, "w", encoding="utf-8") as fp:
            json.dump(manifest, fp, indent=2)

        log(f"Bumped releases/manifest.json revision to: {new_rev}")
    except Exception as e:
        log(f"Failed to bump manifest revision: {e}")


if __name__ == "__main__":
    sync_all_chapters()
