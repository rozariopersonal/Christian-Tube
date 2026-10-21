#!/usr/bin/env python3
"""
run_bible_glossary_12b.py

Production Bible Vocabulary & Glossary Generator using local gemma4:12b.
- Directly matches tokens against known lemmas and surface forms in Python (0ms).
- When matched, instantly appends the surface form and verse reference to the existing lemma entry and skips LLM.
- If not matched, resolves lemma candidates via morphology / model.
- Only genuinely new, uncataloged root lemmas are queried to gemma4:12b.
- Stores every word in JSON (book-by-book) and SQLite (taobvsi_glossary_enriched.sqlite) indexed by canonical lemma.
- Fully resumable and real-time incremental saving.
"""

import os
import sys
import json
import time
import sqlite3
import argparse
import urllib.request
from typing import Dict, List, Set, Any, Optional

sys.stdout.reconfigure(encoding="utf-8")

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", ".."))

if CURRENT_DIR not in sys.path:
    sys.path.insert(0, CURRENT_DIR)

from morphology import extract_tamil_words, clean_tamil_token, normalize_to_lemma_candidate
from common_stopwords import COMMON_TAMIL_STOPWORDS, is_stopword

# Paths
BIBLE_ROOT = os.path.join(PROJECT_ROOT, "releases", "bibles", "taobvsi")
LEGACY_GLOSSARY_DB = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "taobvsi_glossary.sqlite")
ENRICHED_DB = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "taobvsi_glossary_enriched.sqlite")
BOOK_NAMES_FILE = os.path.join(PROJECT_ROOT, "releases", "book_names.json")
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "glossary_additions")
os.makedirs(OUTPUT_DIR, exist_ok=True)

MODEL_NAME = "gemma4:12b"
OLLAMA_URL = "http://localhost:11434/api/chat"

SYSTEM_PROMPT = """You are an expert biblical lexicographer, Hebraist, Hellenist, and theologian specializing in the classical Protestant Tamil Bible (TAOVBSI).
For the given Tamil biblical word, scripture reference, and verse context, produce an enriched lexicon entry with a comprehensive, scholarly Strong's/BDB-style lexical definition for the original biblical language EXPLAINED IN TAMIL.

Strict Guidelines:
1. Original Language & Lexicon (Strong's/BDB standard IN TAMIL):
   - original_language: Hebrew / Greek / Aramaic
   - original_word: Native script with accurate pointing/accents
   - original_transliteration: Standard phonetic transliteration
   - original_root: Primitive root lemma, transliteration, and meaning ONLY in Tamil or English (e.g. "רֹאשׁ (rosh) - தலை/ஆரம்பம்")
   - original_meaning: Concise English root gloss (1-3 words)
   - original_lexical_definition: Write the detailed Strong's / Brown-Driver-Briggs (BDB) style lexical definition IN TAMIL (தமிழ் மொழியில் எழுதவும்). Explain the root etymology, literal meaning, biblical semantic range, and its exact theological shade in this specific scripture context (1-2 sentences in Tamil).
2. Compound Breakdown: If the Tamil term is a compound word (e.g., வெட்டாந்தரை = வெட்டம் + தரை, ஆகாயவிரிவு = ஆகாயம் + விரிவு), break it down into its constituent roots and explain the literal combination. If it is a simple single root, set compound_breakdown to null.
3. Simple Paraphrase: Provide a quick 5-8 word plain modern Tamil meaning (simple_paraphrase_ta) suitable for an immediate pop-up reading aid.
4. Formal Definition: Provide a clear, formal doctrinal definition in classical Protestant Tamil (TAOVBSI register: தேவன், கர்த்தர், பரிசுத்த ஆவியானவர், வேதாகமம்). Avoid secular or non-Christian idioms. Also provide an accurate English translation.
5. Synonyms & Antonyms: Provide biblical/classical Tamil synonyms. For antonyms, provide only true conceptual/theological opposites; return an empty list [] for concrete nouns, persons, places, and materials without natural opposites.
6. Modern Clarification: Clarify any archaic Tamil misconceptions, false friends, or ancient units/customs (or null if self-evident).
7. Confidence & Web Search Fallback: Include "confidence" (float between 0.0 and 1.0). If you are confident (>= 0.85), set "search_query": null. If your confidence is low (< 0.85) regarding the exact Hebrew/Greek root or historical meaning, provide a concise search query (e.g. "Genesis 1:6 Hebrew firmament Strongs") so external context can be retrieved.

Output STRICTLY a single JSON object matching this schema:
{
  "headword": "Canonical Tamil lemma",
  "transliteration": "Tamil Latin transliteration",
  "pos_ta": "பெயர்ச்சொல் / வினைச்சொல் / உரிச்சொல் / இடைச்சொல்",
  "word_type": "archaic_literary / theological_doctrine / historical_custom / flora_fauna_mineral / measurement_unit / common_action / other",
  "gloss_en": "Concise English gloss (1-3 words)",
  "original_language": "Hebrew / Greek / Aramaic",
  "original_word": "Original Hebrew or Greek word in native script",
  "original_transliteration": "English transliteration of original word",
  "original_root": "Primitive root lemma and transliteration (e.g. רֹאשׁ / rosh - தலை/ஆரம்பம்)",
  "original_meaning": "Literal root meaning of the Hebrew/Greek word in English",
  "original_lexical_definition": "எபிரெய/கிரேக்க மூலச்சொல்லின் வேர்ச்சொல் மற்றும் வேதாகம பயன்பாட்டின் விரிவான தமிழ் விளக்கம் (Strong's/BDB விளக்கம் தமிழில்)",
  "compound_breakdown": {
    "roots": ["பகுதி1", "பகுதி2"],
    "literal_meaning": "விளக்கம்"
  } or null,
  "simple_paraphrase_ta": "5-8 word plain modern Tamil meaning",
  "definition_ta": "Classical Protestant definition (1-2 sentences)",
  "definition_en": "Accurate English translation of definition",
  "biblical_synonyms": ["1-3 biblical/classical Tamil synonyms"],
  "antonyms": ["1-2 true opposites or []"],
  "modern_equivalents": ["1-2 modern Tamil words"],
  "see_also": ["1-3 related theological themes/terms"],
  "theological_significance": "1-2 sentences on doctrinal, covenantal, or typological significance",
  "modern_clarification": "Note clarifying archaic meaning or unit conversion, or null",
  "confidence": 0.95,
  "search_query": null
}"""


def fetch_web_snippets(query: str, max_results: int = 2) -> str:
    """Fetches external web/lexicon snippets when model confidence is low."""
    try:
        from duckduckgo_search import DDGS
        results = DDGS().text(f"Bible {query}", max_results=max_results)
        snippets = [r.get("body", "").strip() for r in results if r.get("body")]
        if snippets:
            return "\n".join(f"- {s}" for s in snippets)
    except Exception:
        pass

    try:
        import urllib.parse
        import re
        encoded = urllib.parse.quote(query)
        url = f"https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch={encoded}&format=json"
        req = urllib.request.Request(url, headers={"User-Agent": "BibleGlossaryBot/1.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            items = data.get("query", {}).get("search", [])
            snippets = [re.sub(r'<[^>]+>', '', it["snippet"]) for it in items[:max_results] if it.get("snippet")]
            if snippets:
                return "\n".join(f"- {s}" for s in snippets)
    except Exception:
        pass
    return ""


class BibleGlossaryGenerator12B:
    def __init__(self, include_legacy_db: bool = False):
        self.book_names = self._load_book_names()
        self.entries_by_headword: Dict[str, Dict[str, Any]] = {}
        self.surface_to_headword: Dict[str, str] = {}
        self.headword_to_book: Dict[str, int] = {}
        self.sqlite_conn = self._init_sqlite_db()

        # Seed surface form mappings from legacy SQLite database (26,609 pairs)
        self._load_legacy_surface_mappings()

        # Load existing enriched additions (JSON + SQLite)
        self._load_existing_enriched_entries()

    def _load_book_names(self) -> Dict[int, str]:
        if os.path.exists(BOOK_NAMES_FILE):
            try:
                with open(BOOK_NAMES_FILE, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    ta_names = data.get("taobvsi", {})
                    return {int(k): v for k, v in ta_names.items()}
            except Exception as e:
                print(f"[Warning] Could not parse book_names.json: {e}")
        return {
            1: "ஆதியாகமம்", 2: "யாத்திராகமம்", 3: "லேவியராகமம்", 4: "எண்ணாகமம்", 5: "உபாகமம்",
            19: "சங்கீதம்", 20: "நீதிமொழிகள்", 40: "மத்தேயு", 41: "மாற்கு", 42: "லூக்கா",
            43: "யோவான்", 44: "அப்போஸ்தலர்", 45: "ரோமர்", 58: "எபிரெயர்", 66: "வெளிப்படுத்தின விசேஷம்"
        }

    def _init_sqlite_db(self) -> sqlite3.Connection:
        """Initializes the enriched SQLite glossary database."""
        conn = sqlite3.connect(ENRICHED_DB, check_same_thread=False)
        c = conn.cursor()
        c.execute("""
            CREATE TABLE IF NOT EXISTS glossary_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                headword TEXT UNIQUE,
                pos_ta TEXT,
                word_type TEXT,
                gloss_en TEXT,
                original_language TEXT,
                original_word TEXT,
                original_transliteration TEXT,
                original_root TEXT,
                original_meaning TEXT,
                original_lexical_definition TEXT,
                simple_paraphrase_ta TEXT,
                definition_ta TEXT,
                definition_en TEXT,
                theological_significance TEXT,
                modern_clarification TEXT,
                first_reference TEXT,
                sample_verse TEXT,
                confidence REAL,
                entry_json TEXT
            )
        """)
        c.execute("""
            CREATE TABLE IF NOT EXISTS surface_forms (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                headword TEXT,
                surface_form TEXT UNIQUE
            )
        """)
        c.execute("""
            CREATE TABLE IF NOT EXISTS verse_references (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                headword TEXT,
                reference TEXT,
                UNIQUE(headword, reference)
            )
        """)
        c.execute("CREATE INDEX IF NOT EXISTS idx_entries_headword ON glossary_entries(headword)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_surface_forms ON surface_forms(surface_form)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_refs_headword ON verse_references(headword)")
        conn.commit()
        return conn

    def _load_legacy_surface_mappings(self):
        """Pre-seeds the surface form -> headword resolver with known Bible morphology mappings."""
        if not os.path.exists(LEGACY_GLOSSARY_DB):
            return
        try:
            conn = sqlite3.connect(LEGACY_GLOSSARY_DB)
            c = conn.cursor()
            rows = c.execute("SELECT s.surface_form, g.headword FROM surface_forms s JOIN glossary_entries g ON s.entry_id = g.id").fetchall()
            for s_form, h_word in rows:
                if s_form and h_word:
                    s_clean = s_form.strip()
                    h_clean = h_word.strip()
                    self.surface_to_headword[s_clean] = h_clean
            conn.close()
            print(f"[Resolver] Loaded {len(self.surface_to_headword)} pre-compiled surface->lemma mappings.", flush=True)
        except Exception as e:
            print(f"[Warning] Could not load legacy surface mappings: {e}", flush=True)

    def _load_existing_enriched_entries(self):
        """Loads all generated enriched entries from output JSON files and syncs to SQLite."""
        if not os.path.exists(OUTPUT_DIR):
            return
        total_loaded = 0
        for fname in os.listdir(OUTPUT_DIR):
            if fname.endswith(".json") and fname.startswith("book_"):
                b_num = 1
                try:
                    b_num = int(fname.split("_")[1])
                except Exception:
                    pass

                fpath = os.path.join(OUTPUT_DIR, fname)
                try:
                    with open(fpath, "r", encoding="utf-8") as f:
                        entries = json.load(f)
                        for item in entries:
                            hw = item.get("headword")
                            if hw:
                                self.entries_by_headword[hw] = item
                                self.surface_to_headword[hw] = hw
                                self.headword_to_book[hw] = b_num
                                for sf in item.get("surface_forms", []):
                                    self.surface_to_headword[sf] = hw
                                self._sqlite_upsert_entry(item)
                                total_loaded += 1
                except Exception as e:
                    print(f"[Warning] Error reading '{fname}': {e}", flush=True)

        print(f"[Enriched DB] Loaded {total_loaded} canonical entries with active Tamil lexical definitions.", flush=True)

    def _sqlite_upsert_entry(self, item: Dict[str, Any]):
        """Upserts a single enriched entry into SQLite."""
        hw = item.get("headword")
        if not hw:
            return
        try:
            c = self.sqlite_conn.cursor()
            entry_json_str = json.dumps(item, ensure_ascii=False)
            c.execute("""
                INSERT INTO glossary_entries (
                    headword, pos_ta, word_type, gloss_en, original_language,
                    original_word, original_transliteration, original_root, original_meaning,
                    original_lexical_definition, simple_paraphrase_ta, definition_ta, definition_en,
                    theological_significance, modern_clarification, first_reference, sample_verse,
                    confidence, entry_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(headword) DO UPDATE SET
                    pos_ta=excluded.pos_ta,
                    gloss_en=excluded.gloss_en,
                    original_word=excluded.original_word,
                    original_transliteration=excluded.original_transliteration,
                    original_root=excluded.original_root,
                    original_meaning=excluded.original_meaning,
                    original_lexical_definition=excluded.original_lexical_definition,
                    simple_paraphrase_ta=excluded.simple_paraphrase_ta,
                    definition_ta=excluded.definition_ta,
                    definition_en=excluded.definition_en,
                    theological_significance=excluded.theological_significance,
                    modern_clarification=excluded.modern_clarification,
                    entry_json=excluded.entry_json
            """, (
                hw, item.get("pos_ta"), item.get("word_type"), item.get("gloss_en"),
                item.get("original_language"), item.get("original_word"), item.get("original_transliteration"),
                item.get("original_root"), item.get("original_meaning"), item.get("original_lexical_definition"),
                item.get("simple_paraphrase_ta"), item.get("definition_ta"), item.get("definition_en"),
                item.get("theological_significance"), item.get("modern_clarification"),
                item.get("first_reference"), item.get("sample_verse"), item.get("confidence", 1.0),
                entry_json_str
            ))

            for sf in item.get("surface_forms", []):
                c.execute("INSERT OR IGNORE INTO surface_forms (headword, surface_form) VALUES (?, ?)", (hw, sf))

            for ref in item.get("refs", []):
                c.execute("INSERT OR IGNORE INTO verse_references (headword, reference) VALUES (?, ?)", (hw, ref))

            self.sqlite_conn.commit()
        except Exception as e:
            print(f"[SQLite Error] {e}", flush=True)

    def add_surface_and_ref(self, headword: str, surface_form: str, ref_str: str) -> bool:
        """Appends a surface form and Bible verse reference to an existing headword in 0ms."""
        entry = self.entries_by_headword.get(headword)
        if not entry:
            return False

        changed = False
        if "surface_forms" not in entry:
            entry["surface_forms"] = [headword]
        if surface_form not in entry["surface_forms"]:
            entry["surface_forms"].append(surface_form)
            self.surface_to_headword[surface_form] = headword
            try:
                c = self.sqlite_conn.cursor()
                c.execute("INSERT OR IGNORE INTO surface_forms (headword, surface_form) VALUES (?, ?)", (headword, surface_form))
                self.sqlite_conn.commit()
            except Exception:
                pass
            changed = True

        if "refs" not in entry:
            entry["refs"] = [entry["first_reference"]] if "first_reference" in entry else []
        if ref_str not in entry["refs"]:
            entry["refs"].append(ref_str)
            try:
                c = self.sqlite_conn.cursor()
                c.execute("INSERT OR IGNORE INTO verse_references (headword, reference) VALUES (?, ?)", (headword, ref_str))
                self.sqlite_conn.commit()
            except Exception:
                pass
            changed = True

        return changed

    def query_gemma_12b(self, word: str, reference: str, context_verse: str) -> Optional[Dict[str, Any]]:
        """Queries local gemma4:12b via Ollama API with optional web search grounding when confidence is low."""
        user_content = json.dumps({
            "word": word,
            "reference": reference,
            "context_verse": context_verse
        }, ensure_ascii=False)

        messages = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_content}
        ]

        def call_ollama(msgs: List[Dict[str, str]], timeout: int = 300) -> Optional[Dict[str, Any]]:
            payload = {
                "model": MODEL_NAME,
                "messages": msgs,
                "stream": False,
                "format": "json",
                "options": {
                    "temperature": 0.1
                }
            }
            req = urllib.request.Request(
                OLLAMA_URL,
                data=json.dumps(payload).encode("utf-8"),
                headers={"Content-Type": "application/json"}
            )
            try:
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    data = json.loads(resp.read().decode("utf-8"))
                    content_str = data.get("message", {}).get("content", "")
                    return json.loads(content_str)
            except Exception as e:
                print(f"      [Ollama Error] {e}", flush=True)
                return None

        # Pass 1: Local generation
        parsed = call_ollama(messages, timeout=300)
        if not parsed or not isinstance(parsed, dict) or "definition_ta" not in parsed:
            # Retry once
            parsed = call_ollama(messages, timeout=300)
            if not parsed or not isinstance(parsed, dict) or "definition_ta" not in parsed:
                return None

        # Check confidence & optional web search fallback
        conf = float(parsed.get("confidence", 1.0))
        sq = parsed.get("search_query")
        if conf < 0.85 or (sq and sq.strip()):
            query_str = sq.strip() if (sq and sq.strip()) else f"{reference} {word} BibleHub Hebrew"
            print(f"      [Confidence: {conf:.2f} < 0.85] Searching web for grounding: '{query_str}'...", flush=True)
            snippets = fetch_web_snippets(query_str, max_results=2)
            if snippets:
                refinement_prompt = f"Web search returned the following biblical reference data:\n{snippets}\n\nPlease verify/correct the original Hebrew/Greek word, transliteration, roots, and definition. Output the finalized JSON with confidence: 0.95 and search_query: null."
                refine_messages = list(messages)
                refine_messages.append({"role": "assistant", "content": json.dumps(parsed, ensure_ascii=False)})
                refine_messages.append({"role": "user", "content": refinement_prompt})
                refined = call_ollama(refine_messages, timeout=300)
                if refined and isinstance(refined, dict) and "definition_ta" in refined:
                    return refined

        return parsed

    def process_book(self, book_num: int, limit: Optional[int] = None) -> List[Dict[str, Any]]:
        b_name = self.book_names.get(book_num, f"Book {book_num}")
        b_dir = os.path.join(BIBLE_ROOT, str(book_num))
        if not os.path.exists(b_dir):
            print(f"[Warning] Directory for book {book_num} ({b_name}) not found.")
            return []

        out_file = os.path.join(OUTPUT_DIR, f"book_{book_num:02d}_{b_name}.json")
        book_entries = [e for hw, e in self.entries_by_headword.items() if self.headword_to_book.get(hw) == book_num]

        ch_files = sorted(
            [f for f in os.listdir(b_dir) if f.endswith(".json")],
            key=lambda x: int(os.path.splitext(x)[0]) if os.path.splitext(x)[0].isdigit() else 999
        )

        print("\n" + "=" * 75, flush=True)
        print(f"PROCESSING: Book {book_num} — {b_name} ({len(ch_files)} chapters)", flush=True)
        print(f"Target Output: {out_file}", flush=True)
        print(f"Active Memory: {len(self.entries_by_headword)} distinct lemmas already defined.", flush=True)
        print("=" * 75, flush=True)

        generated_this_run = 0

        for ch_file in ch_files:
            c_num = int(os.path.splitext(ch_file)[0]) if os.path.splitext(ch_file)[0].isdigit() else 1
            ch_path = os.path.join(b_dir, ch_file)
            with open(ch_path, "r", encoding="utf-8") as jf:
                verses = json.load(jf)

            chapter_skips = 0
            chapter_candidates = []

            for v in verses:
                v_num = v.get("verse", 1)
                v_text = v.get("text", "")
                ref_str = f"{b_name} {c_num}:{v_num}"
                tokens = extract_tamil_words(v_text)

                for t in tokens:
                    cl = clean_tamil_token(t)
                    if len(cl) < 2 or is_stopword(cl) or cl in COMMON_TAMIL_STOPWORDS:
                        continue

                    # -------------------------------------------------------------
                    # STEP 1: Direct Fast Python Match (0 ms)
                    # -------------------------------------------------------------
                    target_hw = self.surface_to_headword.get(cl)

                    # -------------------------------------------------------------
                    # STEP 2: Morphological Stemming in Python (0 ms)
                    # -------------------------------------------------------------
                    if not target_hw:
                        stem = normalize_to_lemma_candidate(cl)
                        if is_stopword(stem) or stem in COMMON_TAMIL_STOPWORDS:
                            continue
                        target_hw = self.surface_to_headword.get(stem) or (stem if stem in self.entries_by_headword else None)

                    # If matched to an already-generated enriched lemma:
                    if target_hw and target_hw in self.entries_by_headword:
                        self.add_surface_and_ref(target_hw, cl, ref_str)
                        chapter_skips += 1
                        continue

                    # -------------------------------------------------------------
                    # STEP 3: Genuinely New Word Needing Generation
                    # -------------------------------------------------------------
                    query_word = target_hw or normalize_to_lemma_candidate(cl)
                    if is_stopword(query_word) or query_word in COMMON_TAMIL_STOPWORDS:
                        continue

                    # Check if already queued in this chapter
                    if not any(c["word"] == query_word for c in chapter_candidates):
                        chapter_candidates.append({
                            "word": query_word,
                            "surface_form": cl,
                            "reference": ref_str,
                            "context_verse": v_text
                        })

            print(f"[{b_name} {c_num}] Processed tokens: {chapter_skips} instant skips, {len(chapter_candidates)} new root lemmas to generate.", flush=True)

            for item in chapter_candidates:
                if limit and generated_this_run >= limit:
                    print(f"[Limit Reached] Stopping after {limit} words.", flush=True)
                    break

                word = item["word"]
                ref = item["reference"]
                ctx = item["context_verse"]
                sf = item["surface_form"]

                # Double check if generated earlier in the same chapter
                if word in self.entries_by_headword:
                    self.add_surface_and_ref(word, sf, ref)
                    continue

                t0 = time.time()
                result = self.query_gemma_12b(word, ref, ctx)
                elapsed = time.time() - t0

                if result:
                    hw = result.get("headword", word)
                    if hw in self.entries_by_headword:
                        self.add_surface_and_ref(hw, sf, ref)
                        continue

                    result["first_reference"] = ref
                    result["sample_verse"] = ctx
                    result["surface_forms"] = [sf] if sf != hw else [hw]
                    if "refs" not in result:
                        result["refs"] = [ref]

                    self.entries_by_headword[hw] = result
                    self.surface_to_headword[hw] = hw
                    self.surface_to_headword[sf] = hw
                    self.headword_to_book[hw] = book_num
                    book_entries.append(result)
                    generated_this_run += 1

                    # Upsert to SQLite
                    self._sqlite_upsert_entry(result)

                    orig = f" [{result.get('original_language', '')}: {result.get('original_word', '')} ({result.get('original_transliteration', '')})]" if result.get("original_word") else ""
                    conf_val = float(result.get("confidence", 1.0))
                    print(f"  [{len(book_entries)}] {hw}{orig} ({ref}) -> {result.get('gloss_en', '')} [conf: {conf_val:.2f}] ({elapsed:.1f}s)", flush=True)
                    if result.get("simple_paraphrase_ta"):
                        print(f"      Quick: {result.get('simple_paraphrase_ta')}", flush=True)
                    print(f"      Def:   {result.get('definition_ta', '')[:75]}...", flush=True)

                    # Incremental save to JSON
                    with open(out_file, "w", encoding="utf-8") as out_f:
                        json.dump(book_entries, out_f, ensure_ascii=False, indent=2)

                if limit and generated_this_run >= limit:
                    break

            # Save after chapter
            with open(out_file, "w", encoding="utf-8") as out_f:
                json.dump(book_entries, out_f, ensure_ascii=False, indent=2)

            if limit and generated_this_run >= limit:
                break

        print(f"\n[Finished Book {book_num}] Saved {len(book_entries)} total canonical definitions to '{os.path.basename(out_file)}'.", flush=True)
        return book_entries


def main():
    parser = argparse.ArgumentParser(description="Generate classical TAOVBSI Bible glossary using local gemma4:12b with instant lemma matching")
    parser.add_argument("--book", type=int, default=1, help="Book number to process (1-66, default: 1 Genesis)")
    parser.add_argument("--start", type=int, default=None, help="Start book number for range")
    parser.add_argument("--end", type=int, default=None, help="End book number for range")
    parser.add_argument("--all", action="store_true", help="Process all 66 books")
    parser.add_argument("--limit", type=int, default=None, help="Limit number of words to define (for testing)")
    args = parser.parse_args()

    generator = BibleGlossaryGenerator12B()

    if args.all:
        book_range = range(1, 67)
    elif args.start and args.end:
        book_range = range(args.start, args.end + 1)
    else:
        book_range = [args.book]

    for b in book_range:
        generator.process_book(b, limit=args.limit)


if __name__ == "__main__":
    main()
