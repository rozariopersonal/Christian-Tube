#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Production Bible Vocabulary & Strong's Lexicon Generator using Unified Gemini 2.5 Flash:
1. Unified Filter & Lemma Resolution: Fast batch call with chapter reference ONLY (no verse text).
   Filters pure grammatical function words (lemma: null) and extracts canonical base lemmas.
2. In-Memory & SQLite Deduplication: Instant 0ms skip for existing lemmas and surface forms.
3. Full Enriched Entry Generation: Strictly sequential generation with Strong's/BDB in Tamil,
   Brother Zac Poonen discipleship notes without attribution, and pure classical Protestant theology.
4. Automated Post-Processing: Fast concordance builder for sorted references and surface forms.
"""

import os
import sys
import json
import time
import socket
import sqlite3
import argparse
import urllib.request
import urllib.error
import concurrent.futures
from typing import Dict, List, Set, Any, Optional, Tuple

# Force IPv4 to prevent Windows dual-stack IPv6 socket hanging
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

from morphology import extract_tamil_words, clean_tamil_token



# Paths
BIBLE_ROOT = os.path.join(PROJECT_ROOT, "releases", "bibles", "taobvsi")
LEGACY_GLOSSARY_DB = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "taobvsi_glossary.sqlite")
ENRICHED_DB = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "taobvsi_glossary_enriched.sqlite")
BOOK_NAMES_FILE = os.path.join(PROJECT_ROOT, "releases", "book_names.json")
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "glossary_additions")
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Engine and Model Configuration
DEFAULT_ENGINE = os.environ.get("GLOSSARY_ENGINE", "ollama")  # 'ollama' or 'gemini'
DEFAULT_OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "gemma4:12b")
OLLAMA_CHAT_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434/api/chat")

# Google AI Studio Configuration (Fallback / Alternate)
API_KEY = os.environ.get("GEMINI_API_KEY", "AIzaSyDrYl1HkWSyWpVxSe_HfHQNWYbhYGC3z74")
GEMINI_MODEL_NAME = "gemini-2.5-flash"
GEMINI_API_URL = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL_NAME}:generateContent?key={API_KEY}"

FULL_ENTRY_PROMPT = """You are an expert biblical lexicographer, Hebraist, Hellenist, and theologian specializing in the classical Protestant Tamil Bible (TAOVBSI).
For the given Tamil biblical base lemma, surface form, and scripture reference (no full verse text needed), produce an enriched lexicon entry with a comprehensive, scholarly Strong's/BDB-style lexical definition for the original biblical language EXPLAINED IN TAMIL.
In all explanations, definitions, and theological notes, strictly adhere to historical Protestant terminology: the Holy Scriptures / Bible is ALWAYS referred to as 'வேதம்' (Vedam) or 'வேதத்தில்' (in Scripture).

Strict Guidelines:
1. Original Language & Lexicon (Strong's/BDB standard IN TAMIL):
   - original_language: Hebrew / Greek / Aramaic
   - original_word: Native script with accurate pointing/accents (Niqqud for Hebrew/Aramaic; breathing marks and accents for Greek).
   - original_transliteration: Standard academic phonetic transliteration.
   - original_root: The actual primitive root verb or parent lemma in original script, transliteration, and literal root meaning in Tamil. 
     * NEVER write generic placeholders like 'அறியப்படாத வேர்ச்சொல்' or 'வேர்ச்சொல் இல்லை' when an etymological root or parent stem is established in classical lexicons (BDB, Gesenius, Thayer, Strong's).
     * If the word is an irreducible primary noun with no verbal root, write: "முதன்மைப் பெயர்ச்சொல் (Primary noun)".
   - original_meaning: The concise literal English gloss (1-3 words) of the PRIMITIVE ROOT itself.
     * CRITICAL INTEGRITY RULE: original_meaning MUST match original_root! Do NOT copy the meaning of the derived noun into original_meaning.
   - original_lexical_definition: Write the detailed Strong's / Brown-Driver-Briggs (BDB) style lexical definition IN TAMIL (தமிழ் மொழியில் எழுதவும்). Explain the root etymology, literal meaning, biblical semantic range ('வேதத்தில் இதன் பிரயோகம்'), and its exact theological shade in this specific scripture context (1-2 sentences in Tamil).
     * SPECIAL WORD USAGE: Always use 'வேதம்' or 'வேதத்தில்' when referencing the Bible or Scripture (e.g. 'பழைய ஏற்பாட்டு வேதத்தில்', 'வேதப் பயன்பாட்டில்'). NEVER use 'விவிலியம்' or 'பைபிள்'.

2. Headword Semantic Alignment:
   - 'headword' MUST strictly represent the canonical base lemma corresponding to the original biblical language concept.
   - Never attach an original language word to an unrelated or fragmented Tamil word. Bound modifiers or qualifiers must be represented by their complete canonical substantive lemma.

3. Mandatory Classical Protestant Register & Strictly Forbidden Roman Catholic / Ecumenical Terms:
   The lexicon is exclusively targeted at Protestant Christians (classical TAOVBSI Tamil tradition). You MUST strictly adhere to classical Protestant biblical vocabulary and NEVER use Roman Catholic liturgical, catechismal, or ecumenical terms:
   * SCRIPTURE / BIBLE:
     - MANDATORY: Always use 'வேதம்', 'வேதத்தில்', 'வேதத்தின்', 'வேதாகமம்', or 'வேத வாக்கியம்'.
     - FORBIDDEN: NEVER use 'விவிலியம்', 'விவிலியத்தில்', 'மறைநூல்', 'மறைவாக்கு', or the loan word 'பைபிள்'.
   * GOD / THE HOLY TRINITY:
     - MANDATORY: The Covenant God is 'தேவன்' (Elohim) and 'கர்த்தர்' (YHWH/Adonai). The Holy Spirit is 'பரிசுத்த ஆவியானவர்' or 'பரிசுத்த ஆவி'.
     - FORBIDDEN: NEVER use 'கடவுள்' or 'இறைவன்' as a substitute for 'தேவன்'. NEVER use 'தூய ஆவியார்' or 'தூய ஆவி'.
   * HOLINESS & THE SAINTS:
     - MANDATORY: Use 'பரிசுத்தம்', 'பரிசுத்தமான', 'பரிசுத்தப்படுத்துதல்'. Living believers are 'பரிசுத்தவான்கள்' (or 'விசுவாசிகள்').
     - FORBIDDEN: NEVER use 'புனிதம்', 'புனிதமான', 'புனிதப்படுத்துதல்', 'புனிதர்', or 'புனிதர்கள்'.
   * SALVATION, GOSPEL & GRACE:
     - MANDATORY: Salvation is 'இரட்சிப்பு' and the Savior is 'இரட்சகர்'. The Gospel is 'சுவிசேஷம்'. Grace is 'கிருபை'.
     - FORBIDDEN: NEVER use 'மீட்பு' / 'மீட்பர்' as a generic catch-all for salvation. NEVER use 'நற்செய்தி'. NEVER use 'அருள்' for divine grace.
   * ORDINANCES & WORSHIP:
     - MANDATORY: Baptism is 'ஞானஸ்நானம்'. The Lord's Supper is 'கர்த்தருடைய பந்தி' or 'இராப்போஜனம்'. Prayer is 'ஜெபம்'. Peace is 'சமாதானம்'.
     - FORBIDDEN: NEVER use 'திருமுழுக்கு'. NEVER use 'நற்கருணை', 'பூசை', or 'திருப்பலி'. NEVER use 'செபம்' or 'ஜெபமாலை'. NEVER use 'அமைதி' for biblical Shalom.
   * MINISTRY & OFFICES:
     - MANDATORY: Biblical offices are 'ஆசாரியன் / ஆசாரியத்துவம்', 'அப்போஸ்தலர்', 'சீஷர்கள்', 'தீர்க்கதரிசி / தீர்க்கதரிசனம்', 'போதகர் / மூப்பர்கள்'.
     - FORBIDDEN: NEVER use 'குரு / குருக்கள் / பாதிரியார் / பூசாரி', 'திருத்தூதர்', 'சீடர்கள்', 'இறைவாக்கினர் / இறைவாக்கு', 'பங்குத்தந்தை / ஆயர்'.
   * SANCTUARY & COVENANT:
     - MANDATORY: 'ஆசரிப்புக் கூடாரம்' (Tabernacle), 'உடன்படிக்கைப் பெட்டி' (Ark of the Covenant), 'கிருபாசனம்' (Mercy Seat), 'பலிபீடம்' (Altar).
     - FORBIDDEN: NEVER use 'சந்திப்புக் கூடாரம்', 'பேழை' (for the Ark), 'தூயகம்', 'பலிப்பீடம்'.
   * ESCHATOLOGY & CHRISTIAN WALK:
     - MANDATORY: 'பரலோகம் / பரலோக ராஜ்யம்', 'நித்திய ஜீவன்', 'மனந்திரும்புதல்', 'நீதிமானாக்குதல்', 'உயிர்த்தெழுதல்', 'மரியாள் (பணிவிடைக்காரி)'.
     - FORBIDDEN: NEVER use 'விண்ணகம் / விண்ணரசு / இறையாட்சி', 'நிலைவாழ்வு', 'மனம்மாற்றம் / தவம்', 'உத்தரிக்கும் ஸ்தலம்' (Purgatory), 'உயிர்ப்பு', 'தேவமாதா / அன்னை மரியா / பரலோக ராக்கினி'.

4. Strict Language Separation & Zero Language Mixing (மொழி கலப்பைத் தவிர்க்கவும்):
   - Every Tamil field (definition_ta, notes, original_lexical_definition) MUST be written in 100% pure, fluent Tamil. Do NOT insert English words, Latin script, or transliterated English jargon inside Tamil sentences.
   - English fields (definition_en, gloss_en, original_meaning) MUST be written purely in grammatical English.

5. Rigorous Spelling & Orthography Verification (எழுத்துப் பிழை சரிபார்ப்பு):
   - Tamil Spelling: Double-check Tamil spelling for absolute correctness. Verify correct phonemes (ற vs ர, ண vs ந vs ன, ள vs ழ vs ல), proper pulli (மெய்யெழுத்து), and standard Tamil orthography without typos.
   - Original Biblical Script: Verify Hebrew/Aramaic native script with exact Niqqud pointing and dagesh, or Greek with exact accents and breathing marks. Never mix Hebrew and Greek characters, and never use Latin letters inside original_word.
   - Canonical Base Lemma: Ensure 'headword' is strictly the root dictionary lemma (அகராதி வடிவம் / வேர்ச்சொல்) in clean Tamil without inflected case-endings or agglutinated suffixes.

6. Theological Notes Policy (Brother Zac Poonen's Teachings):
   - Analyze Brother Zac Poonen's biblical teachings, commentaries, and expositions (CFC, 'Through the Bible', 'All That Jesus Taught', 'Basic Christian Teachings') for this specific passage/concept.
   - If Brother Zac Poonen has taught or commented on this verse or concept:
     * Summarize his practical, Christ-centered theological insight (focusing on discipleship, inner life, total surrender, power of God's Word & Holy Spirit, and victory over sin) in 1-2 pure classical Tamil sentences.
     * SPECIAL WORD USAGE IN NOTES: Whenever referring to the Bible, Scripture, or Biblical doctrine in notes, always use 'வேதம்' / 'வேதத்தில்' / 'வேத போதனை' or 'தேவனுடைய வார்த்தை' (never 'விவிலியம்' or 'பைபிள்').
     * DO NOT write 'According to Zac Poonen' or 'சாக் பூனன் அவர்களின் போதனையின்படி' or any attribution name. Just state the spiritual truth directly and authoritatively!
     * STRICTLY PROHIBITED in 'notes': Never repeat the definition (definition_ta), never repeat the Hebrew/Greek etymology (original_lexical_definition), and never repeat information already in other fields.
   - If Brother Zac Poonen has NOT specifically commented or taught on this verse/concept:
     * You MUST set "notes": null.
     * Do NOT invent generic theological commentary. If not found in Zac Poonen's teachings, strictly output null.

7. Output STRICTLY a single JSON object matching this schema:
{
  "headword": "Canonical Tamil lemma",
  "transliteration": "Tamil Latin transliteration",
  "gloss_en": "Concise English gloss (1-3 words)",
  "original_language": "Hebrew / Greek / Aramaic",
  "original_word": "Original Hebrew or Greek word in native script",
  "original_transliteration": "English transliteration of original word",
  "original_root": "Primitive root lemma, transliteration, and root gloss in Tamil",
  "original_meaning": "Literal English root meaning matching original_root",
  "original_lexical_definition": "எபிரெய/கிரேக்க மூலச்சொல்லின் வேர்ச்சொல் மற்றும் வேதத்தில் இதன் பயன்பாட்டின் விரிவான தமிழ் விளக்கம் (1-2 வாக்கியங்கள்; 'வேதம்'/'வேதத்தில்', 'தேவன்' என்றே பயன்படுத்தவும்; 'விவிலியம்'/'கடவுள்' கூடாது)",
  "compound_breakdown": null,
  "notes": "சாக் பூனன் போதனையின் நடைமுறை ஆன்மீக விளக்கம் ('தேவன்', 'வேதம்', 'பரிசுத்த ஆவியானவர்' என்றே எழுதவும்; 'கடவுள்', 'தூய ஆவி', 'புனிதம்', 'விவிலியம்' கூடாது; பெயர் குறிப்பிடாமல் நேரடியாக எழுதவும்; விளக்கம் இல்லையென்றால் null)",
  "definition_ta": "தூய பாரம்பரிய வேத விளக்கம் (1-2 வாக்கியங்கள்; 'தேவன்', 'கிருபை', 'பரிசுத்தம்', 'இரட்சிப்பு', 'வேதம்' என்றே எழுதவும்; 'கடவுள்', 'புனிதம்', 'மீட்பு', 'நற்செய்தி', 'விவிலியம்', 'பைபிள்' கூடாது)",
  "definition_en": "Accurate English translation of definition",
  "biblical_synonyms": ["1-3 biblical/classical Tamil synonyms"],
  "antonyms": ["1-2 true opposites or []"],
  "modern_equivalents": ["1-2 modern Tamil words"],
  "confidence": 0.98
}"""


class BibleGlossaryGemini:
    def __init__(self, engine: str = DEFAULT_ENGINE, model_name: Optional[str] = None):
        self.engine = engine.lower()
        if model_name:
            self.model_name = model_name
        else:
            self.model_name = DEFAULT_OLLAMA_MODEL if self.engine == "ollama" else GEMINI_MODEL_NAME

        self.book_names = self._load_book_names()
        self.entries_by_headword: Dict[str, Dict[str, Any]] = {}
        self.surface_to_headword: Dict[str, str] = {}
        self.headword_to_book: Dict[str, int] = {}
        self.known_common_words: Set[str] = set()
        self.sqlite_conn = self._init_sqlite_db()

        # Load previously filtered common particles
        self._load_filtered_common_words()

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
                gloss_en TEXT,
                original_language TEXT,
                original_word TEXT,
                original_transliteration TEXT,
                original_root TEXT,
                original_meaning TEXT,
                original_lexical_definition TEXT,
                notes TEXT,
                definition_ta TEXT,
                definition_en TEXT,
                first_reference TEXT,
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
        c.execute("""
            CREATE TABLE IF NOT EXISTS filtered_common_words (
                word TEXT PRIMARY KEY
            )
        """)
        c.execute("CREATE INDEX IF NOT EXISTS idx_entries_headword ON glossary_entries(headword)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_surface_forms ON surface_forms(surface_form)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_refs_headword ON verse_references(headword)")
        conn.commit()
        return conn

    def _load_filtered_common_words(self):
        """Loads previously filtered common particles from SQLite."""
        try:
            c = self.sqlite_conn.cursor()
            rows = c.execute("SELECT word FROM filtered_common_words").fetchall()
            for r in rows:
                if r and r[0]:
                    self.known_common_words.add(r[0].strip())
            print(f"[Common Words] Loaded {len(self.known_common_words)} previously classified common particles.", flush=True)
        except Exception as e:
            print(f"[Warning] Could not load filtered common words: {e}", flush=True)

    def _record_common_word(self, word: str):
        """Records a common particle in memory and SQLite so it is never re-classified."""
        if not word:
            return
        self.known_common_words.add(word)
        try:
            c = self.sqlite_conn.cursor()
            c.execute("INSERT OR IGNORE INTO filtered_common_words (word) VALUES (?)", (word,))
            self.sqlite_conn.commit()
        except Exception:
            pass

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
                    print(f"[Warning] Could not parse {fname}: {e}")

        print(f"[Enriched DB] Loaded {len(self.entries_by_headword)} canonical entries with active Tamil lexical definitions.", flush=True)

    def reset_book(self, book_num: int):
        """Resets all entries for a specific book in memory, output JSON, and SQLite."""
        b_name = self.book_names.get(book_num, f"Book {book_num}")
        out_file = os.path.join(OUTPUT_DIR, f"book_{book_num:02d}_{b_name}.json")
        with open(out_file, "w", encoding="utf-8") as f:
            json.dump([], f, ensure_ascii=False, indent=2)

        # Remove from memory
        to_del = [hw for hw, b in self.headword_to_book.items() if b == book_num]
        for hw in to_del:
            self.entries_by_headword.pop(hw, None)
            self.headword_to_book.pop(hw, None)

        # Remove from SQLite
        try:
            c = self.sqlite_conn.cursor()
            prefix = f"{b_name} %"
            c.execute("DELETE FROM surface_forms WHERE headword IN (SELECT headword FROM glossary_entries WHERE first_reference LIKE ?)", (prefix,))
            c.execute("DELETE FROM glossary_entries WHERE first_reference LIKE ?", (prefix,))
            c.execute("DELETE FROM verse_references WHERE reference LIKE ?", (prefix,))
            if book_num == 1:
                c.execute("DELETE FROM filtered_common_words")
                self.known_common_words.clear()
            self.sqlite_conn.commit()
            print(f"[Reset] Cleared all existing entries for {b_name} in JSON and SQLite.", flush=True)
        except Exception as e:
            print(f"[Reset Error] {e}", flush=True)

    def _sqlite_upsert_entry(self, item: Dict[str, Any]):
        """Persists an entry into the enriched SQLite database."""
        hw = item.get("headword")
        if not hw:
            return
        c = self.sqlite_conn.cursor()
        c.execute("""
            INSERT INTO glossary_entries (
                headword, gloss_en, original_language, original_word, original_transliteration,
                original_root, original_meaning, original_lexical_definition, notes,
                definition_ta, definition_en, first_reference, confidence, entry_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(headword) DO UPDATE SET
                gloss_en=excluded.gloss_en,
                original_language=excluded.original_language,
                original_word=excluded.original_word,
                original_transliteration=excluded.original_transliteration,
                original_root=excluded.original_root,
                original_meaning=excluded.original_meaning,
                original_lexical_definition=excluded.original_lexical_definition,
                notes=excluded.notes,
                definition_ta=excluded.definition_ta,
                definition_en=excluded.definition_en,
                first_reference=excluded.first_reference,
                confidence=excluded.confidence,
                entry_json=excluded.entry_json
        """, (
            hw,
            item.get("gloss_en"),
            item.get("original_language"),
            item.get("original_word"),
            item.get("original_transliteration"),
            item.get("original_root"),
            item.get("original_meaning"),
            item.get("original_lexical_definition"),
            item.get("notes"),
            item.get("definition_ta"),
            item.get("definition_en"),
            item.get("first_reference"),
            item.get("confidence", 1.0),
            json.dumps(item, ensure_ascii=False)
        ))

        # Insert surface forms
        for sf in item.get("surface_forms", []):
            c.execute("INSERT OR IGNORE INTO surface_forms (headword, surface_form) VALUES (?, ?)", (hw, sf))

        # Insert references
        for ref in item.get("refs", []):
            c.execute("INSERT OR IGNORE INTO verse_references (headword, reference) VALUES (?, ?)", (hw, ref))

        self.sqlite_conn.commit()

    def add_surface_and_ref(self, headword: str, surface_form: str, ref_str: str) -> bool:
        """Adds a surface form and a scripture reference to an existing entry."""
        if headword not in self.entries_by_headword:
            return False

        entry = self.entries_by_headword[headword]
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

    # -------------------------------------------------------------------------
    # UNIFIED STAGE 1: BATCH FILTER + LEMMA EXTRACTION
    # -------------------------------------------------------------------------
    def call_gemini_filter_and_lemma(self, words: List[str], chapter_ref: str, max_retries: int = 3) -> List[Dict[str, Any]]:
        """
        Calls Ollama (gemma4:12b) or Gemini Flash in batch with chapter reference ONLY.
        Performs simultaneous common word filtering and canonical base lemma extraction:
        - Common grammatical words / particles / pronouns -> "lemma": null
        - Substantive biblical / theological / narrative words -> "lemma": "base_lemma"
        """
        if not words:
            return []

        prompt = f"""You are an expert biblical lexicographer specializing in the classical Protestant Tamil Bible (TAOVBSI).
For each of the following Tamil biblical words from scripture reference: '{chapter_ref}':
1. Grammatical & Discourse Particles: Filter out pure grammatical function words, pronouns, auxiliary copulas, discourse conjunctions, and inflectional clitics with no distinct theological or biblical lexical significance by setting 'lemma': null.
2. Substantive Biblical Words: For all substantive biblical, theological, historical, or narrative words (nouns, main verbs, significant adjectives, and distinct theological terms), return the canonical uninflected dictionary base lemma in clean Tamil.
3. Compound Words & Bound Modifiers: If a word is an adjectival modifier or bound component of a composite biblical noun, resolve it to the full canonical compound lemma, or set 'lemma': null if it is purely a dependent grammatical modifier. Never output a fragmented adjective as an independent headword.
Rule: Any word carrying substantive theological, biblical, or contextual meaning in this scripture passage must NOT be filtered out. Distinguish parts of speech and always provide the clean dictionary citation form.

Words to evaluate:
{json.dumps(words, ensure_ascii=False)}

Respond strictly in JSON with a 'results' list:
{{
  "results": [
    {{"word": "word_from_list", "lemma": "base_lemma or null"}}
  ]
}}"""

        for attempt in range(max_retries):
            try:
                if self.engine == "ollama":
                    payload = {
                        "model": self.model_name,
                        "messages": [{"role": "user", "content": prompt}],
                        "stream": False,
                        "format": "json",
                        "think": False,
                        "options": {
                            "temperature": 0.0,
                            "num_ctx": 4096,
                            "num_predict": 1024
                        }
                    }
                    body = json.dumps(payload).encode("utf-8")
                    req = urllib.request.Request(OLLAMA_CHAT_URL, data=body, headers={"Content-Type": "application/json"})
                    with urllib.request.urlopen(req, timeout=90) as resp:
                        res = json.loads(resp.read().decode("utf-8"))
                        raw = res.get("message", {}).get("content", "").strip()
                        if not raw:
                            raw = res.get("message", {}).get("thinking", "").strip()
                        if "```json" in raw:
                            raw = raw.split("```json")[-1].split("```")[0].strip()
                        elif raw.startswith("```"):
                            raw = raw.split("```")[1].strip()
                        parsed = json.loads(raw)
                        if isinstance(parsed, dict) and "results" in parsed:
                            return parsed["results"]
                        elif isinstance(parsed, list):
                            return parsed
                        elif isinstance(parsed, dict) and "word" in parsed:
                            return [parsed]
                else:
                    payload = {
                        "contents": [{"parts": [{"text": prompt}]}],
                        "generationConfig": {"temperature": 0.0, "responseMimeType": "application/json"}
                    }
                    body = json.dumps(payload).encode("utf-8")
                    req = urllib.request.Request(GEMINI_API_URL, data=body, headers={"Content-Type": "application/json"})
                    with urllib.request.urlopen(req, timeout=30) as resp:
                        data = json.loads(resp.read().decode("utf-8"))
                        raw = data["candidates"][0]["content"]["parts"][0]["text"].strip()
                        parsed = json.loads(raw)
                        if isinstance(parsed, dict) and "results" in parsed:
                            return parsed["results"]
                        elif isinstance(parsed, list):
                            return parsed
            except urllib.error.HTTPError as e:
                if e.code == 429:
                    time.sleep(5 * (attempt + 1))
                elif e.code == 402:
                    print(f"      [Gemini 402 Credit Depleted] Switching to local Ollama ({DEFAULT_OLLAMA_MODEL})...", flush=True)
                    self.engine = "ollama"
                    self.model_name = DEFAULT_OLLAMA_MODEL
                    return self.call_gemini_filter_and_lemma(words, chapter_ref, max_retries - attempt)
                else:
                    time.sleep(2)
            except Exception as e:
                time.sleep(2)

        # Fallback: assume all are substantive if call fails
        return [{"word": w, "lemma": w} for w in words]

    # -------------------------------------------------------------------------
    # STAGE 3: FULL ENRICHED ENTRY GENERATION (Sequential)
    # -------------------------------------------------------------------------
    def query_gemini_full_entry(self, lemma: str, reference: str, surface_form: str, max_retries: int = 3) -> Optional[Dict[str, Any]]:
        """Queries Ollama (gemma4:12b) or Google AI Studio API for a single unique lemma."""
        user_prompt = (
            f"Base Lemma: {lemma}\n"
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
                        "options": {
                            "temperature": 0.1,
                            "num_ctx": 4096,
                            "num_predict": 1024
                        }
                    }
                    body = json.dumps(payload).encode("utf-8")
                    req = urllib.request.Request(OLLAMA_CHAT_URL, data=body, headers={"Content-Type": "application/json"})
                    with urllib.request.urlopen(req, timeout=120) as resp:
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
                            parsed["headword"] = lemma  # Enforce base lemma
                            for k in ["pos_ta", "word_type", "sample_verse", "see_also", "simple_paraphrase_ta", "theological_significance", "modern_clarification"]:
                                parsed.pop(k, None)
                            return parsed
                else:
                    payload = {
                        "contents": [
                            {
                                "parts": [
                                    {"text": f"{FULL_ENTRY_PROMPT}\n\nTask:\n{user_prompt}"}
                                ]
                            }
                        ],
                        "generationConfig": {
                            "temperature": 0.1,
                            "responseMimeType": "application/json"
                        }
                    }
                    body = json.dumps(payload).encode("utf-8")
                    req = urllib.request.Request(GEMINI_API_URL, data=body, headers={"Content-Type": "application/json"})
                    with urllib.request.urlopen(req, timeout=30) as resp:
                        data = json.loads(resp.read().decode("utf-8"))
                        candidates = data.get("candidates", [])
                        if not candidates:
                            return None
                        parts = candidates[0].get("content", {}).get("parts", [])
                        if not parts:
                            return None

                        raw_text = parts[0].get("text", "").strip()
                        if len(parts) > 1 and not raw_text.startswith("{"):
                            raw_text = parts[-1].get("text", "").strip()

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
            except urllib.error.HTTPError as e:
                if e.code == 429:
                    wait_time = 5 * (attempt + 1)
                    print(f"      [Rate Limit 429] Waiting {wait_time}s before retry...", flush=True)
                    time.sleep(wait_time)
                elif e.code == 402:
                    print(f"      [Gemini 402 Credit Depleted] Switching to local Ollama ({DEFAULT_OLLAMA_MODEL})...", flush=True)
                    self.engine = "ollama"
                    self.model_name = DEFAULT_OLLAMA_MODEL
                    return self.query_gemini_full_entry(lemma, reference, surface_form, max_retries - attempt)
                elif e.code == 503:
                    time.sleep(3)
                else:
                    print(f"      [HTTP Error {e.code}] {e.reason}", flush=True)
                    return None
            except Exception as e:
                print(f"      [API Error] {e}", flush=True)
                time.sleep(2)

        return None

    def process_chapters(self, book_num: int, target_chapters: Optional[List[int]] = None, limit: Optional[int] = None) -> List[Dict[str, Any]]:
        """Processes chapters sequentially using the unified Gemini 2.5 Flash pipeline."""
        b_name = self.book_names.get(book_num, f"Book {book_num}")
        b_dir = os.path.join(BIBLE_ROOT, str(book_num))
        if not os.path.exists(b_dir):
            print(f"[Warning] Directory for book {book_num} ({b_name}) not found.")
            return []

        out_file = os.path.join(OUTPUT_DIR, f"book_{book_num:02d}_{b_name}.json")
        book_entries = [e for hw, e in self.entries_by_headword.items() if self.headword_to_book.get(hw) == book_num]

        all_ch_files = sorted(
            [f for f in os.listdir(b_dir) if f.endswith(".json")],
            key=lambda x: int(os.path.splitext(x)[0]) if os.path.splitext(x)[0].isdigit() else 999
        )

        if target_chapters:
            ch_files = [f for f in all_ch_files if int(os.path.splitext(f)[0]) in target_chapters]
        else:
            ch_files = all_ch_files

        ch_display = f"Chapters {target_chapters}" if target_chapters else f"All {len(ch_files)} Chapters"
        print("\n" + "=" * 75, flush=True)
        print(f"PROCESSING: Book {book_num} — {b_name} ({ch_display})", flush=True)
        print(f"Engine: {self.engine.upper()} [{self.model_name}] (Filter + Lemma + Enriched Lexicon)", flush=True)
        print(f"Target Output: {out_file}", flush=True)
        print(f"Active Memory: {len(self.entries_by_headword)} distinct lemmas already defined.", flush=True)
        print("=" * 75, flush=True)

        generated_this_run = 0

        for ch_file in ch_files:
            c_num = int(os.path.splitext(ch_file)[0]) if os.path.splitext(ch_file)[0].isdigit() else 1
            ch_path = os.path.join(b_dir, ch_file)
            with open(ch_path, "r", encoding="utf-8") as jf:
                verses = json.load(jf)

            chapter_ref = f"{b_name} {c_num}"
            raw_tokens = []
            token_to_ref = {}

            for v in verses:
                v_num = v.get("verse", 1)
                ref_str = f"{b_name} {c_num}:{v_num}"
                for t in extract_tamil_words(v.get("text", "")):
                    cl = clean_tamil_token(t)
                    if len(cl) >= 2:
                        raw_tokens.append(cl)
                        if cl not in token_to_ref:
                            token_to_ref[cl] = ref_str

            unique_chapter_tokens = list(dict.fromkeys(raw_tokens))
            print(f"\n[{chapter_ref}] Tokens: {len(raw_tokens)} total ({len(unique_chapter_tokens)} unique surface forms).", flush=True)

            # -------------------------------------------------------------
            # PRE-CLASSIFICATION FILTER (Level 1: Exclude already known words)
            # -------------------------------------------------------------
            tokens_to_classify = []
            pre_skipped_common = 0
            pre_linked_existing = 0

            for word in unique_chapter_tokens:
                ref_str = token_to_ref.get(word, f"{chapter_ref}:1")

                # 1. Check if already known common particle
                if word in self.known_common_words:
                    pre_skipped_common += 1
                    continue

                # 2. Check if already known headword
                if word in self.entries_by_headword:
                    self.add_surface_and_ref(word, word, ref_str)
                    pre_linked_existing += 1
                    continue

                # 3. Check if already known surface form mapping to an existing entry
                target_hw = self.surface_to_headword.get(word)
                if target_hw and target_hw in self.entries_by_headword:
                    self.add_surface_and_ref(target_hw, word, ref_str)
                    pre_linked_existing += 1
                    continue

                # Truly unclassified word
                tokens_to_classify.append(word)

            print(f"  [Pre-Filter] {pre_skipped_common} known common particles skipped, {pre_linked_existing} existing lexicon words linked. Truly new to classify: {len(tokens_to_classify)}.", flush=True)

            # -------------------------------------------------------------
            # STAGE 1: Parallel/Batch Classification (Only for truly unseen tokens)
            # -------------------------------------------------------------
            resolved_pairs: List[Dict[str, Any]] = []
            if tokens_to_classify:
                batch_size = 15 if self.engine == "ollama" else 35
                batches = [tokens_to_classify[i:i + batch_size] for i in range(0, len(tokens_to_classify), batch_size)]
                max_workers = 1 if self.engine == "ollama" else min(6, len(batches))
                print(f"  [Stage 1] Classifying {len(tokens_to_classify)} tokens in {len(batches)} batches (workers: {max_workers})...", flush=True)
                t_s1 = time.time()
                completed_batches = 0
                with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
                    futures = [executor.submit(self.call_gemini_filter_and_lemma, b, chapter_ref) for b in batches]
                    for f in concurrent.futures.as_completed(futures):
                        completed_batches += 1
                        try:
                            res = f.result()
                            resolved_pairs.extend(res)
                            print(f"    [Stage 1 Batch {completed_batches}/{len(batches)}] Resolved {len(res)} tokens ({time.time() - t_s1:.1f}s)", flush=True)
                        except Exception as e:
                            print(f"    [Batch Error] {e}", flush=True)

                elapsed_s1 = time.time() - t_s1
                print(f"  [Stage 1 Done] Classification finished in {elapsed_s1:.2f}s.", flush=True)
            else:
                print(f"  [Stage 1 Skipped] All {len(unique_chapter_tokens)} tokens were already classified!", flush=True)

            # -------------------------------------------------------------
            # STAGE 2: Lemma Deduplication & Exclusion (Level 2)
            # -------------------------------------------------------------
            lemmas_to_generate: Dict[str, str] = {} # lemma -> first surface form
            new_common_count = 0
            lemma_db_skips = 0

            for item in resolved_pairs:
                word = item.get("word", "")
                lemma = item.get("lemma")
                ref_str = token_to_ref.get(word, f"{chapter_ref}:1")

                if not lemma:
                    # Flagged by Gemini as common particle (lemma: null)
                    # Memorize so it is NEVER classified again across chapters
                    self._record_common_word(word)
                    new_common_count += 1
                    continue

                # Map surface form to its lemma
                self.surface_to_headword[word] = lemma

                # LEVEL 2 EXCLUSION: Is the canonical lemma already in our dictionary?
                if lemma in self.entries_by_headword:
                    # Lemma already exists! Exclude from Stage 3 full generation!
                    self.add_surface_and_ref(lemma, word, ref_str)
                    lemma_db_skips += 1
                else:
                    # Genuinely new lemma to generate
                    if lemma not in lemmas_to_generate:
                        lemmas_to_generate[lemma] = word

            print(f"  [Stage 2 Done] {new_common_count} new common particles memorized, {lemma_db_skips} lemmas already in DB. Genuinely new unique lemmas to generate: {len(lemmas_to_generate)}.", flush=True)

            # -------------------------------------------------------------
            # STAGE 3: Full Enriched Generation (Strictly Sequential)
            # -------------------------------------------------------------
            for lemma_idx, (lemma, surface_form) in enumerate(lemmas_to_generate.items(), 1):
                if limit and generated_this_run >= limit:
                    print(f"\n[Limit Reached] Stopping after {limit} words.", flush=True)
                    break

                ref_str = token_to_ref.get(surface_form, f"{chapter_ref}:1")
                print(f"  -> [{lemma_idx}/{len(lemmas_to_generate)}] Generating lexicon entry for '{lemma}' ({ref_str})...", flush=True)

                # Double check memory
                if lemma in self.entries_by_headword:
                    self.add_surface_and_ref(lemma, surface_form, ref_str)
                    continue

                t0 = time.time()
                result = self.query_gemini_full_entry(lemma, ref_str, surface_form)
                elapsed = time.time() - t0

                if result:
                    hw = result.get("headword", lemma)
                    if hw in self.entries_by_headword:
                        self.add_surface_and_ref(hw, surface_form, ref_str)
                        continue

                    result["first_reference"] = ref_str
                    result["surface_forms"] = [surface_form] if surface_form != hw else [hw]
                    if "refs" not in result:
                        result["refs"] = [ref_str]

                    self.entries_by_headword[hw] = result
                    self.surface_to_headword[hw] = hw
                    self.surface_to_headword[surface_form] = hw
                    self.headword_to_book[hw] = book_num
                    book_entries.append(result)
                    generated_this_run += 1

                    # Upsert to SQLite
                    self._sqlite_upsert_entry(result)

                    orig = f" [{result.get('original_language', '')}: {result.get('original_word', '')} ({result.get('original_transliteration', '')})]" if result.get("original_word") else ""
                    conf_val = float(result.get("confidence", 1.0))
                    print(f"  [{len(book_entries)}] {hw}{orig} ({ref_str}) -> {result.get('gloss_en', '')} [conf: {conf_val:.2f}] ({elapsed:.2f}s)", flush=True)
                    if result.get("notes"):
                        print(f"      Note:  {result.get('notes')}", flush=True)
                    else:
                        print(f"      Note:  [None]", flush=True)
                    if result.get("definition_ta"):
                        print(f"      Def:   {result.get('definition_ta')[:90]}...", flush=True)

                    # Commit to disk (book JSON) after every single generated word
                    with open(out_file, "w", encoding="utf-8") as out_f:
                        json.dump(book_entries, out_f, ensure_ascii=False, indent=2)

                # Strict sequential pacing: polite pause between calls
                time.sleep(0.5)

            # Save chapter completion checkpoint
            with open(out_file, "w", encoding="utf-8") as out_f:
                json.dump(book_entries, out_f, ensure_ascii=False, indent=2)

        print(f"\n[Run Complete] {b_name}: {len(book_entries)} total entries in JSON and SQLite. (Generated {generated_this_run} this run)\n", flush=True)
        return book_entries




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


def main():
    parser = argparse.ArgumentParser(description="TAOVBSI Bible Vocabulary & Strong's Generator")
    parser.add_argument("--book", type=int, default=1, help="Book number (1 = Genesis)")
    parser.add_argument("--chapters", type=str, default=None, help="Target chapters, e.g. '1' or '1,2,3' or '1-5'")
    parser.add_argument("--engine", type=str, default="ollama", choices=["ollama", "gemini"], help="Inference engine (ollama or gemini)")
    parser.add_argument("--model", type=str, default="gemma4:12b", help="Model name for engine")
    parser.add_argument("--limit", type=int, default=None, help="Maximum number of new root words to generate")
    parser.add_argument("--reset", action="store_true", help="Reset all existing entries for this book")

    args = parser.parse_args()
    target_chapters = parse_chapter_arg(args.chapters)

    generator = BibleGlossaryGemini(engine=args.engine, model_name=args.model)

    if args.reset:
        generator.reset_book(args.book)

    generator.process_chapters(book_num=args.book, target_chapters=target_chapters, limit=args.limit)


if __name__ == "__main__":
    main()
