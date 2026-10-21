#!/usr/bin/env python3
"""
pipeline.py

Main processing pipeline for TAOVBSI Bible text vocabulary extraction.
- Scans Bible chapter by chapter.
- Maintains in-memory verse tracking and newly-discovered word compiling.
- Uses an Inverted "Default-to-Keep" filter:
    * Tier 1: Deterministic scraped stopwords (instant).
    * Tier 2: Local Ollama inverted classifier (tags only obvious common words).
    * Any unclassified or ambiguous word DEFAULTS TO KEEP (Definition-Worthy).
- Compares with existing taobvsi_glossary.sqlite to flag already-cataloged terms
  and isolate the exact list of MISSED words for DeepSeek.
- Outputs:
    * unique_words_with_references.json
    * missed_words_for_deepseek.json
"""

import os
import sys
import json
import sqlite3
from typing import Dict, List, Set, Any, Optional

# Local imports from tools/vocab_pipeline
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
if CURRENT_DIR not in sys.path:
    sys.path.insert(0, CURRENT_DIR)

from morphology import extract_tamil_words, clean_tamil_token, normalize_to_lemma_candidate
from common_stopwords import COMMON_TAMIL_STOPWORDS, is_stopword
from ollama_filter import tag_common_words_with_ollama

# Default paths
DEFAULT_SAMPLE_PATH = os.path.join(CURRENT_DIR, "taovbsi_sample.json")
DEFAULT_GLOSSARY_DB = os.path.abspath(
    os.path.join(CURRENT_DIR, "..", "..", "releases", "study", "taobvsi", "taobvsi_glossary.sqlite")
)
OUT_UNIQUE_WORDS = os.path.join(CURRENT_DIR, "unique_words_with_references.json")
OUT_DEEPSEEK_PAYLOAD = os.path.join(CURRENT_DIR, "missed_words_for_deepseek.json")


class BibleVocabPipeline:
    def __init__(self, glossary_db_path: Optional[str] = DEFAULT_GLOSSARY_DB):
        # Master sets to ensure we never re-verify the same word twice
        self.seen_lemmas: Set[str] = set()
        self.allowed_words: Set[str] = set()      # Definition-worthy (common: false)
        self.ignored_words: Set[str] = set()      # Stopwords / common filler (common: true)

        # Word -> detailed verse mapping index
        # key: canonical lemma
        self.word_index: Dict[str, Dict[str, Any]] = {}

        # Pre-load existing glossary database if present
        self.existing_glossary: Dict[str, str] = {} # word -> category
        if glossary_db_path and os.path.exists(glossary_db_path):
            self._load_existing_glossary(glossary_db_path)

    def _load_existing_glossary(self, db_path: str):
        """Loads already-defined lemmas and surface forms from SQLite."""
        try:
            conn = sqlite3.connect(db_path)
            c = conn.cursor()
            # 1. Load headwords
            for row in c.execute("SELECT headword, category FROM glossary_entries").fetchall():
                if row[0]:
                    self.existing_glossary[row[0]] = row[1] or "existing_entry"
            # 2. Load surface forms
            for row in c.execute(
                "SELECT sf.surface_form, ge.category FROM surface_forms sf "
                "JOIN glossary_entries ge ON sf.entry_id = ge.id"
            ).fetchall():
                if row[0]:
                    self.existing_glossary[row[0]] = row[1] or "existing_form"
            conn.close()
            print(f"[Database] Loaded {len(self.existing_glossary)} existing cataloged terms from '{os.path.basename(db_path)}'.")
        except Exception as e:
            print(f"[Database Warning] Could not read glossary DB: {e}")

    def is_definition_worthy(self, word: str, newly_discovered_batch: List[str]) -> bool:
        """
        Determines if a word should be kept for definition using the Inverted Filter:
        1. If in deterministic stopwords set -> False
        2. If already in allowed_words -> True
        3. If already in ignored_words -> False
        4. Query local Ollama tagger to check if it's tagged 'common: true'.
           If Ollama is offline or says common: false -> DEFAULT TO TRUE (KEEP).
        """
        if is_stopword(word) or word in COMMON_TAMIL_STOPWORDS:
            self.ignored_words.add(word)
            return False

        if word in self.allowed_words:
            return True
        if word in self.ignored_words:
            return False

        # If word is already in the existing glossary, it's definitely a content word
        if word in self.existing_glossary:
            self.allowed_words.add(word)
            return True

        # Default to True (Fail-safe)
        return True

    def process_chapter(
        self,
        book_id: int,
        book_name: str,
        chapter: int,
        verses: List[Dict[str, Any]],
        use_ollama: bool = False,
        ollama_model: str = "gemma2:2b"
    ) -> List[str]:
        """
        Scans a single chapter, tracks word-to-verse mappings, and returns newly discovered words.
        """
        new_batch_candidates: List[str] = []

        # 1. First pass: extract tokens and discover candidates
        verse_tokens_map = []
        for v in verses:
            v_num = v.get("verse", 1)
            v_text = v.get("text", "")
            tokens = extract_tamil_words(v_text)
            verse_tokens_map.append((v_num, v_text, tokens))

            for token in tokens:
                cleaned = clean_tamil_token(token)
                if len(cleaned) < 2:
                    continue

                # Instant deterministic stopword check
                if is_stopword(cleaned) or cleaned in COMMON_TAMIL_STOPWORDS:
                    self.ignored_words.add(cleaned)
                    continue

                lemma = normalize_to_lemma_candidate(cleaned)
                if lemma not in self.seen_lemmas:
                    self.seen_lemmas.add(lemma)
                    if lemma not in self.allowed_words and lemma not in self.ignored_words:
                        new_batch_candidates.append(lemma)

        # 2. Local Ollama Inverted Classification pass (if enabled)
        if use_ollama and new_batch_candidates:
            print(f"  Sending {len(new_batch_candidates)} candidate words to Ollama ('{ollama_model}') for common-word tagging...")
            ollama_tags = tag_common_words_with_ollama(new_batch_candidates, model=ollama_model)
            if ollama_tags is not None:
                for cand in new_batch_candidates:
                    is_common = ollama_tags.get(cand, False)
                    if is_common:
                        self.ignored_words.add(cand)
                    else:
                        self.allowed_words.add(cand)
            else:
                # Fallback: Ollama unavailable -> Default to KEEP
                print("  [Ollama Notice] Ollama server offline. Defaulting all candidates to KEEP.")
                for cand in new_batch_candidates:
                    self.allowed_words.add(cand)
        else:
            # Deterministic default-to-keep
            for cand in new_batch_candidates:
                self.allowed_words.add(cand)

        # 3. Second pass: record occurrences of allowed words
        new_words_in_chapter: List[str] = []
        for v_num, v_text, tokens in verse_tokens_map:
            citation = f"{book_name} {chapter}:{v_num}"

            for token in tokens:
                cleaned = clean_tamil_token(token)
                if len(cleaned) < 2 or cleaned in self.ignored_words:
                    continue

                lemma = normalize_to_lemma_candidate(cleaned)
                if lemma in self.ignored_words:
                    continue

                # Word is definition-worthy
                if lemma not in self.word_index:
                    is_already_in_db = (lemma in self.existing_glossary or cleaned in self.existing_glossary)
                    existing_cat = self.existing_glossary.get(lemma) or self.existing_glossary.get(cleaned)

                    self.word_index[lemma] = {
                        "lemma": lemma,
                        "surface_forms": set(),
                        "first_reference": citation,
                        "all_references": [],
                        "sample_verse": v_text,
                        "already_in_glossary": bool(is_already_in_db),
                        "existing_category": existing_cat
                    }
                    new_words_in_chapter.append(lemma)

                entry = self.word_index[lemma]
                entry["surface_forms"].add(cleaned)
                entry["all_references"].append({
                    "book": book_id,
                    "book_name": book_name,
                    "chapter": chapter,
                    "verse": v_num
                })

        return new_words_in_chapter

    def export_results(
        self,
        unique_words_path: str = OUT_UNIQUE_WORDS,
        missed_words_path: str = OUT_DEEPSEEK_PAYLOAD
    ):
        """
        Exports the master unique vocabulary database and the specific missed words payload.
        """
        all_unique_entries = []
        missed_entries_for_deepseek = []

        for lemma, data in sorted(self.word_index.items(), key=lambda x: x[0]):
            sorted_forms = sorted(list(data["surface_forms"]))
            entry = {
                "lemma": lemma,
                "surface_forms": sorted_forms,
                "first_reference": data["first_reference"],
                "total_occurrences": len(data["all_references"]),
                "sample_verse": data["sample_verse"],
                "already_in_glossary": data["already_in_glossary"],
                "existing_category": data["existing_category"]
            }
            all_unique_entries.append(entry)

            # If NOT already in the glossary, this is a MISSED word to be defined!
            if not data["already_in_glossary"]:
                missed_entries_for_deepseek.append({
                    "word": lemma,
                    "surface_forms": sorted_forms,
                    "reference": data["first_reference"],
                    "context_verse": data["sample_verse"]
                })

        # 1. Master unique words JSON
        with open(unique_words_path, "w", encoding="utf-8") as f:
            json.dump(all_unique_entries, f, ensure_ascii=False, indent=2)

        # 2. Missed words JSON formatted for DeepSeek batching
        with open(missed_words_path, "w", encoding="utf-8") as f:
            json.dump({
                "target_model": "deepseek-chat",
                "total_missed_words": len(missed_entries_for_deepseek),
                "words_batch": missed_entries_for_deepseek
            }, f, ensure_ascii=False, indent=2)

        print("\n" + "=" * 65)
        print("PIPELINE EXECUTION SUMMARY")
        print("=" * 65)
        print(f"Total Unique Definition-Worthy Lemmas: {len(all_unique_entries)}")
        print(f"  ├─ Already Cataloged in DB:         {len(all_unique_entries) - len(missed_entries_for_deepseek)}")
        print(f"  └─ Genuinely Missed / New Words:     {len(missed_entries_for_deepseek)}")
        print(f"Total Common/Stopwords Filtered:      {len(self.ignored_words)}")
        print(f"Saved Master Vocabulary Index to:     '{os.path.basename(unique_words_path)}'")
        print(f"Saved Missed Words for DeepSeek to:   '{os.path.basename(missed_words_path)}'")
        print("=" * 65)


def load_book_names() -> Dict[int, str]:
    """Loads Tamil book names from apps/backend/data/book_names.json if available."""
    names_path = os.path.abspath(os.path.join(CURRENT_DIR, "..", "..", "apps", "backend", "data", "book_names.json"))
    if os.path.exists(names_path):
        try:
            with open(names_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                # Map book_number -> Tamil name
                res = {}
                for item in data:
                    b_num = item.get("book_number") or item.get("id") or item.get("book")
                    b_name = item.get("name_ta") or item.get("tamil_name") or item.get("name")
                    if b_num and b_name:
                        res[int(b_num)] = b_name
                return res
        except Exception:
            pass
    # Fallback common book names
    return {
        1: "ஆதியாகமம்", 2: "யாத்திராகமம்", 3: "லேவியராகமம்", 4: "எண்ணாகமம்", 5: "உபாகமம்",
        19: "சங்கீதம்", 20: "நீதிமொழிகள்", 40: "மத்தேயு", 41: "மாற்கு", 42: "லூக்கா",
        43: "யோவான்", 44: "அப்போஸ்தலர்", 45: "ரோமர்", 66: "வெளிப்படுத்தின விசேஷம்"
    }

def run_pipeline(
    input_file: Optional[str] = None,
    book_num: Optional[int] = None,
    scan_all: bool = False,
    use_ollama: bool = False,
    ollama_model: str = "gemma2:2b"
):
    print("Starting Tamil Bible Vocabulary Pipeline...")
    pipeline = BibleVocabPipeline()
    book_names = load_book_names()

    bible_root = os.path.abspath(os.path.join(CURRENT_DIR, "..", "..", "releases", "bibles", "taobvsi"))

    if input_file:
        print(f"Mode: Reading custom file '{input_file}'")
        if not os.path.exists(input_file):
            print(f"Error: File '{input_file}' does not exist.")
            return
        with open(input_file, "r", encoding="utf-8") as f:
            data = json.load(f)
        chapters = data.get("chapters", [])
        print(f"Loaded {len(chapters)} chapter(s) for processing.\n")
        for ch in chapters:
            b_id = ch.get("book_id", 1)
            b_name = ch.get("book_name", book_names.get(b_id, f"Book {b_id}"))
            c_num = ch.get("chapter", 1)
            verses = ch.get("verses", [])
            new_words = pipeline.process_chapter(
                book_id=b_id,
                book_name=b_name,
                chapter=c_num,
                verses=verses,
                use_ollama=use_ollama,
                ollama_model=ollama_model
            )
            print(f"[{b_name} {c_num}] Processed {len(verses)} verses. Discovered {len(new_words)} new unique vocabulary words.")

    elif book_num or scan_all:
        books_to_scan = range(1, 67) if scan_all else [book_num]
        print(f"Mode: Scanning Bible repository at '{bible_root}' for {len(books_to_scan)} book(s)...")

        for b in books_to_scan:
            b_dir = os.path.join(bible_root, str(b))
            if not os.path.exists(b_dir):
                print(f"[Warning] Book directory '{b_dir}' not found.")
                continue
            b_name = book_names.get(b, f"Book {b}")
            ch_files = sorted(
                [f for f in os.listdir(b_dir) if f.endswith(".json")],
                key=lambda x: int(os.path.splitext(x)[0]) if os.path.splitext(x)[0].isdigit() else 999
            )
            print(f"\nProcessing {b_name} ({len(ch_files)} chapters)...")
            for ch_file in ch_files:
                c_num = int(os.path.splitext(ch_file)[0]) if os.path.splitext(ch_file)[0].isdigit() else 1
                ch_path = os.path.join(b_dir, ch_file)
                with open(ch_path, "r", encoding="utf-8") as f:
                    verses = json.load(f)
                new_words = pipeline.process_chapter(
                    book_id=b,
                    book_name=b_name,
                    chapter=c_num,
                    verses=verses,
                    use_ollama=use_ollama,
                    ollama_model=ollama_model
                )
                if new_words:
                    print(f"  Ch {c_num}: +{len(new_words)} new words (total seen: {len(pipeline.word_index)})")

    else:
        # Default to mock sample
        run_pipeline(input_file=DEFAULT_SAMPLE_PATH, use_ollama=use_ollama, ollama_model=ollama_model)
        return

    pipeline.export_results()


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="TAOVBSI Classical Tamil Vocabulary Extraction Pipeline")
    parser.add_argument("--sample", action="store_true", help="Run against mock test sample (Genesis 1 & John 3:16)")
    parser.add_argument("--input", default=None, help="Path to custom Bible chapters JSON")
    parser.add_argument("--book", type=int, default=None, help="Process a specific book by number (1-66)")
    parser.add_argument("--all", action="store_true", help="Process the entire Bible (all 66 books)")
    parser.add_argument("--ollama", action="store_true", help="Enable local Ollama linguistic tagging")
    parser.add_argument("--model", default="gemma2:2b", help="Ollama model name (default: gemma2:2b)")
    args = parser.parse_args()

    # Reconfigure stdout for Windows console UTF-8 support
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    input_file = args.input
    if args.sample:
        input_file = DEFAULT_SAMPLE_PATH

    run_pipeline(
        input_file=input_file,
        book_num=args.book,
        scan_all=args.all,
        use_ollama=args.ollama,
        ollama_model=args.model
    )
