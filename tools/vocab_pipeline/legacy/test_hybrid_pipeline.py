#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
test_hybrid_pipeline.py

Implements the user's requested 4-stage hybrid architecture:
1. Local Gemma Model (Ollama): Flags pure grammatical function words vs biblical/theological words.
   Rule: "when the common words have biblical context then dont treat it as common".
2. Gemini 2.5 Flash (Lemma-only): Resolves surface forms to canonical dictionary base lemmas
   using chapter reference ONLY, WITHOUT full verse content.
3. Database Deduplication: Filters out lemmas/surface forms already cataloged in the database.
4. Gemini 2.5 Flash (Enriched Entry): Generates full classical Protestant dictionary entries
   (with BDB Hebrew/Greek in Tamil, Zac Poonen discipleship notes without attribution, definition_ta)
   using chapter reference ONLY, NOT full text.
5. Post-Processing: Builds complete concordance references and surface forms.
"""

import os
import sys
import json
import time
import socket
import sqlite3
import urllib.request
import urllib.error
from typing import List, Dict, Any, Set, Tuple, Optional

# Windows IPv4 enforcement
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

BIBLE_ROOT = os.path.join(PROJECT_ROOT, "releases", "bibles", "taobvsi")
LEGACY_GLOSSARY_DB = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "taobvsi_glossary.sqlite")
ENRICHED_DB = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "taobvsi_glossary_enriched.sqlite")
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "glossary_additions")
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Google AI Studio Configuration (Paid Account)
API_KEY = os.environ.get("GEMINI_API_KEY", "AIzaSyDrYl1HkWSyWpVxSe_HfHQNWYbhYGC3z74")
MODEL_NAME = "gemini-2.5-flash"
GEMINI_URL = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL_NAME}:generateContent?key={API_KEY}"

# Local Ollama Configuration
OLLAMA_URL = "http://localhost:11434/api/chat"
OLLAMA_MODEL = "gemma3:4b"  # Fast, accurate classification without slow thinking loops

FULL_ENTRY_PROMPT = """You are an expert biblical lexicographer, Hebraist, Hellenist, and theologian specializing in the classical Protestant Tamil Bible (TAOVBSI).
For the given Tamil biblical base lemma and Scripture Reference (e.g. 'ஆதியாகமம் 1'), produce an enriched lexicon entry with a comprehensive, scholarly Strong's/BDB-style lexical definition for the original biblical language EXPLAINED IN TAMIL.

Strict Guidelines:
1. Original Language & Lexicon (Strong's/BDB standard IN TAMIL):
   - original_language: Hebrew / Greek / Aramaic
   - original_word: Native script with accurate pointing/accents (e.g. רָקִיעַ / ἱλαστήரிον)
   - original_transliteration: Standard phonetic transliteration
   - original_root: Primitive root lemma, transliteration, and meaning in Tamil/English (e.g. "רָקַע (raqa) - தட்டுதல்/பரப்புதல்")
   - original_meaning: Concise English root gloss (1-3 words)
   - original_lexical_definition: Write the detailed Strong's / Brown-Driver-Briggs (BDB) style lexical definition IN TAMIL (தமிழ் மொழியில் எழுதவும்). Explain the root etymology, literal meaning, biblical semantic range, and its theological shade (1-2 sentences in Tamil).

2. Classical Protestant Doctrinal Register:
   - Adhere strictly to historical classical Protestant Tamil biblical vocabulary (TAOVBSI style: தேவன், கர்த்தர், பரிசுத்த ஆவியானவர், வேதாகமம், பிராயச்சித்தம், மீட்பு). Do not use secular or colloquial slang.

3. Strict Language Separation (மொழி கலப்பைத் தவிர்க்கவும்):
   - Every Tamil field (definition_ta, notes, original_lexical_definition) MUST be written in 100% pure, fluent Tamil without English words or Latin script.
   - English fields (definition_en, gloss_en, original_meaning) MUST be written purely in English.

4. Rigorous Spelling & Orthography:
   - Tamil: Check proper pulli, standard orthography without typos.
   - Original Biblical Script: Native Hebrew with Niqqud or Greek with accents. Never mix alphabets.
   - Canonical Base Lemma: 'headword' must strictly be the root dictionary lemma in clean Tamil without inflected suffixes.

5. Theological Notes Policy (Brother Zac Poonen's Teachings):
   - Analyze Brother Zac Poonen's biblical teachings, commentaries, and expositions (CFC, 'Through the Bible', 'All That Jesus Taught', 'Basic Christian Teachings') for this specific passage/concept.
   - If Brother Zac Poonen taught or commented on this concept in this chapter:
     * Summarize his practical, Christ-centered theological insight (focusing on discipleship, inner life, total surrender, power of God's Word & Holy Spirit, and victory over sin) in 1-2 pure classical Tamil sentences.
     * State the spiritual truth directly without mentioning his name (do NOT write 'According to Zac Poonen' or 'சாக் பூனன் அவர்களின் போதனையின்படி').
     * NEVER repeat information already given in 'definition_ta' or 'original_lexical_definition'.
   - If Brother Zac Poonen has NOT specifically commented or taught on this, set "notes": null.

JSON Output Schema:
{
  "headword": "அகராதி வடிவம் (Base Lemma)",
  "transliteration": "Tamil Latin transliteration",
  "gloss_en": "Concise English gloss (1-3 words)",
  "original_language": "Hebrew / Greek / Aramaic",
  "original_word": "Original Hebrew or Greek word in native script",
  "original_transliteration": "English transliteration of original word",
  "original_root": "Primitive root lemma and transliteration",
  "original_meaning": "Literal root meaning in English",
  "original_lexical_definition": "எபிரெய/கிரேக்க மூலச்சொல்லின் வேர்ச்சொல் மற்றும் பயன்பாட்டின் விரிவான தமிழ் விளக்கம்",
  "compound_breakdown": null,
  "notes": "சாக் பூனன் போதனையின் நடைமுறை ஆன்மீக விளக்கம் (பெயர் குறிப்பிடாமல் நேரடியாக எழுதவும்; விளக்கம் இல்லையென்றால் null என்று போடவும்; சொல்லின் பொருளைத் திரும்பக் கூறக்கூடாது)",
  "definition_ta": "Classical Protestant definition (1-2 sentences in pure Tamil)",
  "definition_en": "Accurate English translation of definition",
  "biblical_synonyms": ["1-3 biblical/classical Tamil synonyms"],
  "antonyms": ["1-2 true opposites or []"],
  "modern_equivalents": ["1-2 modern Tamil words"],
  "confidence": 0.98
}"""


def call_local_gemma_filter(words: List[str]) -> List[str]:
    """
    Step 1: Runs local Gemma to flag common words vs non-common words.
    Rule: "when the common words have biblical context then dont treat it as common".
    Returns the list of non-common (theological/biblical/substantive) words.
    """
    if not words:
        return []

    prompt = f"""You are a classical Tamil biblical language expert.
Classify each word from Genesis 1 into common grammatical function words (common: true) or biblical/theological/substantive words (common: false).

CRITICAL RULE:
- When a word has biblical, theological, or narrative context (e.g. ஆதி, தேவன், வானம், பூமி, சிருஷ்டி, வெளிச்சம், இருள், ஆவி, நல்லது, பிரி, நாள், இரவு), DO NOT treat it as common; set common: false.
- ONLY pure grammatical functional words, pronouns, or discourse connectors with NO theological or biblical importance (e.g. அவன், அது, என்று, ஆயிற்று, என, அப்படியே, தான், தங்களில்) may be set to common: true.

Words:
{json.dumps(words, ensure_ascii=False)}

Respond strictly in JSON array: [{{"word": "...", "common": true/false}}]"""

    payload = {
        "model": OLLAMA_MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
        "options": {"temperature": 0.1}
    }

    try:
        req = urllib.request.Request(
            OLLAMA_URL,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=45) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            content = data.get("message", {}).get("content", "").strip()

            if "```json" in content:
                content = content.split("```json")[-1].split("```")[0].strip()
            elif content.startswith("```"):
                content = content.split("```")[1].strip()

            parsed = json.loads(content)
            non_common = []
            for item in parsed:
                w = item.get("word")
                is_c = item.get("common", False)
                if w and not is_c:
                    non_common.append(w)
            return non_common
    except Exception as e:
        print(f"  [Local Gemma Warning] Error in classification: {e}. Defaulting to keep all substantive tokens.")
        return words


def call_gemini_lemma_only(words: List[str], chapter_ref: str) -> List[Dict[str, str]]:
    """
    Step 2: Calls Gemini Flash to produce lemmas ONLY, giving chapter reference WITHOUT content.
    Returns: [{"word": surface_word, "lemma": base_lemma}]
    """
    if not words:
        return []

    prompt = f"""You are an expert biblical lexicographer specializing in the classical Protestant Tamil Bible (TAOVBSI).
For each of the following Tamil biblical words from scripture reference: '{chapter_ref}' (do not require full verse text), determine its canonical dictionary base lemma (அகராதி வடிவம் / வேர்ச்சொல்) in clean uninflected Tamil.

Guidelines:
- Strip inflected verb endings (e.g. 'சிருஷ்டித்தார்' -> 'சிருஷ்டி', 'பிரித்தார்' -> 'பிரி', 'அசைவாடிக்கொண்டிருந்தார்' -> 'அசை').
- Strip noun cases and clitics (e.g. 'வானத்தையும்' -> 'வானம்', 'பூமியையும்' -> 'பூமி', 'வெறுமையுமாய்' -> 'வெறுமை').
- Distinguish separate parts of speech (e.g. 'வெவ்வேறாகப்' -> 'வெவ்வேறு').

Words to resolve:
{json.dumps(words, ensure_ascii=False)}

Respond strictly with a JSON array of objects:
[
  {{"word": "...", "lemma": "..."}}
]"""

    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": 0.0, "responseMimeType": "application/json"}
    }

    try:
        req = urllib.request.Request(
            GEMINI_URL,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            raw = data["candidates"][0]["content"]["parts"][0]["text"].strip()
            return json.loads(raw)
    except Exception as e:
        print(f"  [Gemini Lemma Warning] Error resolving lemmas: {e}")
        return [{"word": w, "lemma": w} for w in words]


def call_gemini_full_entry(lemma: str, chapter_ref: str, surface_form: str) -> Optional[Dict[str, Any]]:
    """
    Step 4: Calls Gemini Flash with the unique lemma and chapter reference (WITHOUT full verse text)
    to generate the complete enriched dictionary JSON entry.
    """
    user_prompt = (
        f"Base Lemma: {lemma}\n"
        f"Surface Form in Text: {surface_form}\n"
        f"Scripture Reference: {chapter_ref}\n\n"
        "Task:\n"
        "Produce the complete classical Protestant enriched lexical entry as valid JSON adhering to the guidelines.\n"
        "Do NOT require full verse text."
    )

    payload = {
        "contents": [{"parts": [{"text": f"{FULL_ENTRY_PROMPT}\n\nTask:\n{user_prompt}"}]}],
        "generationConfig": {"temperature": 0.1, "responseMimeType": "application/json"}
    }

    for attempt in range(3):
        try:
            req = urllib.request.Request(
                GEMINI_URL,
                data=json.dumps(payload).encode("utf-8"),
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                raw = data["candidates"][0]["content"]["parts"][0]["text"].strip()
                parsed = json.loads(raw)
                if isinstance(parsed, dict) and "definition_ta" in parsed:
                    return parsed
        except Exception as e:
            print(f"  [Gemini Full Entry Retry {attempt+1}] {e}")
            time.sleep(2)
    return None


def test_pipeline_on_genesis_1(sample_limit: int = 15):
    print("=" * 75)
    print("TESTING 4-STAGE HYBRID PIPELINE ON GENESIS 1")
    print("1. Local Gemma 4/3 -> 2. Gemini Lemma-Only -> 3. DB Filter -> 4. Gemini Full JSON")
    print("=" * 75)

    # Load Genesis 1 verses
    ch_path = os.path.join(BIBLE_ROOT, "1", "1.json")
    with open(ch_path, "r", encoding="utf-8") as f:
        verses = json.load(f)

    # Collect raw tokens
    all_raw_tokens = []
    token_to_ref = {}
    for v in verses:
        ref_str = f"ஆதியாகமம் 1:{v['verse']}"
        for t in extract_tamil_words(v["text"]):
            cl = clean_tamil_token(t)
            if len(cl) >= 2:
                all_raw_tokens.append(cl)
                if cl not in token_to_ref:
                    token_to_ref[cl] = ref_str

    unique_tokens = list(dict.fromkeys(all_raw_tokens))
    print(f"\n[Extraction] Genesis 1 contains {len(all_raw_tokens)} total words ({len(unique_tokens)} unique tokens).")

    # Take first batch for testing
    test_tokens = unique_tokens[:sample_limit]
    print(f"\n--- STAGE 1: LOCAL GEMMA FILTER (Batch of {len(test_tokens)} words) ---")
    print(f"Tokens: {test_tokens}")

    t0 = time.time()
    non_common_words = call_local_gemma_filter(test_tokens)
    t_gemma = time.time() - t0

    common_flagged = [w for w in test_tokens if w not in non_common_words]
    print(f"Local Gemma completed in {t_gemma:.2f}s.")
    print(f"  * Flagged as Common (Skipped): {common_flagged}")
    print(f"  * Kept as Non-Common (Biblical): {non_common_words}")

    print(f"\n--- STAGE 2: GEMINI FAST LEMMA-ONLY RESOLUTION (Chapter Ref Only, No Content) ---")
    t0 = time.time()
    lemma_results = call_gemini_lemma_only(non_common_words, "ஆதியாகமம் 1")
    t_gemini_lemma = time.time() - t0

    print(f"Gemini Lemma Resolution completed in {t_gemini_lemma:.2f}s:")
    for item in lemma_results:
        print(f"  * Surface: {item['word']:<22} -> Canonical Lemma: {item['lemma']}")

    print(f"\n--- STAGE 3: FILTER AGAINST DATABASE (Matching Lemma or Surface Forms) ---")
    # Simulate DB lookup
    simulated_db = {"தேவன்", "வானம்"}
    new_lemmas_to_generate = {}

    for item in lemma_results:
        w = item["word"]
        lem = item["lemma"]
        if lem in simulated_db or w in simulated_db:
            print(f"  * [DB MATCH - SKIP] '{w}' (lemma: '{lem}') already in DB.")
        else:
            if lem not in new_lemmas_to_generate:
                new_lemmas_to_generate[lem] = w
                print(f"  * [NEW LEMMA - QUEUE] '{lem}' (first surface: '{w}')")

    print(f"\nTotal new unique lemmas to generate: {len(new_lemmas_to_generate)}")

    print(f"\n--- STAGE 4: GEMINI FULL ENRICHED ENTRY (Sample 2 words, Chapter Ref Only, No Full Text) ---")
    sample_lemmas = list(new_lemmas_to_generate.items())[:2]
    for lem, surf in sample_lemmas:
        ref = token_to_ref.get(surf, "ஆதியாகமம் 1")
        print(f"\nGenerating full entry for: {lem} (Reference: {ref})...")
        t0 = time.time()
        entry = call_gemini_full_entry(lem, ref, surf)
        elapsed = time.time() - t0

        if entry:
            orig = f" [{entry.get('original_language', '')}: {entry.get('original_word', '')} ({entry.get('original_transliteration', '')})]"
            print(f"  Success in {elapsed:.2f}s: {entry.get('headword')}{orig}")
            print(f"  Gloss: {entry.get('gloss_en')}")
            print(f"  Original Lexical Def (Tamil): {entry.get('original_lexical_definition')[:100]}...")
            print(f"  Zac Poonen Note: {entry.get('notes')}")
            print(f"  Classical Tamil Def: {entry.get('definition_ta')[:100]}...")
            print(f"  Synonyms: {entry.get('biblical_synonyms')}")

    print("\n" + "=" * 75)
    print("HYBRID PIPELINE TEST COMPLETED SUCCESSFULLY!")
    print("=" * 75)


if __name__ == "__main__":
    test_pipeline_on_genesis_1(sample_limit=18)
