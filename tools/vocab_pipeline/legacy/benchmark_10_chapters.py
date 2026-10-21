#!/usr/bin/env python3
"""
benchmark_10_chapters.py

Runs the complete vocabulary extraction pipeline on 10 famously complex,
vocabulary-dense chapters of the classical Tamil Bible (TAOVBSI),
using the benchmark winner 'gemma4:e4b' via local Ollama.

Selected 10 Complex Chapters:
1. Genesis 1      (Creation & Primeval Cosmology)
2. Genesis 49     (Jacob's Blessings & Archaic Metaphors)
3. Exodus 28      (High Priest Garments & Gemstones)
4. Leviticus 11   (Clean/Unclean Zoology & Anatomy)
5. Leviticus 16   (Day of Atonement & Sacrificial Rites)
6. Job 38         (Whirlwind Speech & Astronomy)
7. Psalm 119:1-50 (Torah Legal/Wisdom Vocabulary)
8. Isaiah 53      (Messianic Suffering Servant Theology)
9. John 1         (Logos Christology & Incarnation)
10. Hebrews 9     (Tabernacle Typology & Eternal Redemption)
"""

import os
import sys
import json
import time
import sqlite3
import urllib.request
from typing import Dict, List, Set, Any

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
if CURRENT_DIR not in sys.path:
    sys.path.insert(0, CURRENT_DIR)

from morphology import extract_tamil_words, clean_tamil_token, normalize_to_lemma_candidate

BIBLE_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", "..", "releases", "bibles", "taobvsi"))
GLOSSARY_DB = os.path.abspath(os.path.join(CURRENT_DIR, "..", "..", "releases", "study", "taobvsi", "taobvsi_glossary.sqlite"))
OLLAMA_MODEL = "gemma4:e4b"
OLLAMA_URL = "http://localhost:11434/api/generate"

COMPLEX_CHAPTERS = [
    {"book_id": 1,  "name": "ஆதியாகமம்", "osis": "GEN", "chapter": 1,  "desc": "Creation & Primeval Cosmology"},
    {"book_id": 1,  "name": "ஆதியாகமம்", "osis": "GEN", "chapter": 49, "desc": "Jacob's Poetic Blessings & Archaic Fauna"},
    {"book_id": 2,  "name": "யாத்திராகமம்", "osis": "EXO", "chapter": 28, "desc": "Priesthood Garments & Gemstones"},
    {"book_id": 3,  "name": "லேவியராகமம்", "osis": "LEV", "chapter": 11, "desc": "Clean/Unclean Zoology & Anatomical Terms"},
    {"book_id": 3,  "name": "லேவியராகமம்", "osis": "LEV", "chapter": 16, "desc": "Day of Atonement & Sacrificial Typology"},
    {"book_id": 18, "name": "யோபு",       "osis": "JOB", "chapter": 38, "desc": "Whirlwind Speech, Nature & Astronomy"},
    {"book_id": 19, "name": "சங்கீதம்",    "osis": "PSA", "chapter": 119, "desc": "Torah / Legal / Wisdom Vocabulary (Part 1)", "max_verses": 50},
    {"book_id": 23, "name": "ஏசாயா",      "osis": "ISA", "chapter": 53, "desc": "Messianic Suffering Servant Theology"},
    {"book_id": 43, "name": "யோவான்",     "osis": "JHN", "chapter": 1,  "desc": "Logos Christology & Incarnation"},
    {"book_id": 58, "name": "எபிரெயர்",    "osis": "HEB", "chapter": 9,  "desc": "Tabernacle Typology & Eternal Redemption"},
]

INVERTED_SYSTEM_PROMPT = """You are a classical Tamil linguistic classifier for the TAOVBSI Bible text.
Your task is to identify pure grammatical function words, pronouns, conjunctions, particles, discourse fillers, and numbers.

TAG AS "common": true ONLY IF the word is:
1. A pronoun (அவன், அவள், அவர்கள், நான், நீங்கள், தன், அது, அவை, இவன், இவர், எவன்).
2. A conjunction or connective (ஆனால், ஆகையால், ஆனாலும், அல்லது, ஏனெனில், ஆதலால்).
3. A grammatical particle, clitic, or speech reporting marker (என்று, என, ஆயிற்று, என்றார், என்றான், போல, படி).
4. A pure number or ordinal (ஒன்று, இரண்டு, முதலாம், இரண்டாம்).

CRITICAL RULE (DEFAULT TO FALSE):
If a word is a noun, a theological term, a biblical person/place, an archaic word, or an action verb
(like சிருஷ்டி, தேவன், ஆகாயவிரிவு, வெளிச்சம், அன்பு, விசுவாசம், நித்தியஜீவன், இரத்தஞ்சிந்துதல், கிருபாசனம்)
— or if you are in any doubt — tag it as "common": false.

Output strictly a JSON array of objects: [{"word": "அவன்", "common": true}, {"word": "ஆகாயவிரிவு", "common": false}]"""

def query_gemma4_inverted(words_batch: List[str]) -> Dict[str, bool]:
    """Queries gemma4:e4b to tag obvious common words."""
    if not words_batch:
        return {}

    prompt = f"{INVERTED_SYSTEM_PROMPT}\n\nWords to classify:\n{json.dumps(words_batch, ensure_ascii=False)}"
    payload = {
        "model": OLLAMA_MODEL,
        "prompt": prompt,
        "stream": False,
        "format": "json",
        "options": {"temperature": 0.1}
    }

    req = urllib.request.Request(
        OLLAMA_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )

    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            raw = data.get("response", "[]")
            parsed = json.loads(raw)
            if isinstance(parsed, dict):
                for k in ["analysis", "results", "words", "data", "classification"]:
                    if k in parsed and isinstance(parsed[k], list):
                        parsed = parsed[k]
                        break
            if isinstance(parsed, list):
                return {item["word"]: bool(item.get("common", False)) for item in parsed if isinstance(item, dict) and "word" in item}
    except Exception as e:
        print(f"    [Ollama Query Warning: {e}] - defaulting to false (KEEP)")

    return {w: False for w in words_batch}

def load_glossary_database(db_path: str) -> Set[str]:
    """Loads all previously defined headwords and surface forms."""
    cataloged = set()
    if os.path.exists(db_path):
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        for row in c.execute("SELECT headword FROM glossary_entries").fetchall():
            if row[0]: cataloged.add(row[0].strip())
        for row in c.execute("SELECT surface_form FROM surface_forms").fetchall():
            if row[0]: cataloged.add(row[0].strip())
        conn.close()
    return cataloged

def run_benchmark():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    print("=" * 75)
    print("10 COMPLEX BIBLE CHAPTERS VOCABULARY BENCHMARK")
    print(f"Model: {OLLAMA_MODEL} | Architecture: Inverted Default-to-Keep")
    print("=" * 75)

    cataloged_words = load_glossary_database(GLOSSARY_DB)
    print(f"Loaded {len(cataloged_words)} words already recognized in 'taobvsi_glossary.sqlite'.\n")

    overall_results = []
    all_missed_words_for_deepseek = []
    seen_in_benchmark = set()

    for idx, target in enumerate(COMPLEX_CHAPTERS, 1):
        b_id = target["book_id"]
        b_name = target["name"]
        c_num = target["chapter"]
        desc = target["desc"]
        max_v = target.get("max_verses")

        ch_file = os.path.join(BIBLE_ROOT, str(b_id), f"{c_num}.json")
        if not os.path.exists(ch_file):
            print(f"[{idx}/10] Chapter file not found: {ch_file}")
            continue

        with open(ch_file, "r", encoding="utf-8") as f:
            verses = json.load(f)

        if max_v:
            verses = verses[:max_v]

        t_start = time.time()

        # Step 1: Tokenize & identify candidate words
        raw_tokens_count = 0
        chapter_candidates: Dict[str, Dict[str, Any]] = {}

        for v in verses:
            v_num = v.get("verse", 1)
            v_text = v.get("text", "")
            tokens = extract_tamil_words(v_text)
            raw_tokens_count += len(tokens)

            for token in tokens:
                cleaned = clean_tamil_token(token)
                if len(cleaned) < 2:
                    continue

                lemma = normalize_to_lemma_candidate(cleaned)
                if lemma not in chapter_candidates:
                    chapter_candidates[lemma] = {
                        "lemma": lemma,
                        "surface_forms": set(),
                        "first_ref": f"{b_name} {c_num}:{v_num}",
                        "sample_verse": v_text,
                        "already_in_db": (lemma in cataloged_words or cleaned in cataloged_words)
                    }
                chapter_candidates[lemma]["surface_forms"].add(cleaned)

        total_unique_lemmas = len(chapter_candidates)
        already_in_db_count = sum(1 for c in chapter_candidates.values() if c["already_in_db"])
        unseen_candidates = [lemma for lemma, c in chapter_candidates.items() if not c["already_in_db"] and lemma not in seen_in_benchmark]

        # Step 2: Batch classify unseen candidates with gemma4:e4b
        print(f"[{idx}/10] {b_name} {c_num} ({desc})")
        print(f"   Verses: {len(verses)} | Total Tokens: {raw_tokens_count} | Unique Lemmas: {total_unique_lemmas}")
        print(f"   Already in DB: {already_in_db_count} | Unseen Candidates to Check: {len(unseen_candidates)}")

        new_definition_worthy = []
        filtered_common_count = 0

        # Process in batches of 25
        batch_size = 25
        for i in range(0, len(unseen_candidates), batch_size):
            batch = unseen_candidates[i:i + batch_size]
            tags = query_gemma4_inverted(batch)

            for word in batch:
                seen_in_benchmark.add(word)
                is_com = tags.get(word, False)
                if is_com:
                    filtered_common_count += 1
                else:
                    new_definition_worthy.append(word)
                    cand_info = chapter_candidates[word]
                    all_missed_words_for_deepseek.append({
                        "word": word,
                        "surface_forms": sorted(list(cand_info["surface_forms"])),
                        "reference": cand_info["first_ref"],
                        "context_verse": cand_info["sample_verse"],
                        "chapter_theme": desc
                    })

        elapsed = round(time.time() - t_start, 2)
        print(f"   -> Found {len(new_definition_worthy)} GENUINELY MISSED WORDS for DeepSeek (Filtered {filtered_common_count} common words) in {elapsed}s.\n")

        overall_results.append({
            "book": b_name,
            "chapter": c_num,
            "description": desc,
            "verses_count": len(verses),
            "total_tokens": raw_tokens_count,
            "unique_lemmas": total_unique_lemmas,
            "already_in_db": already_in_db_count,
            "missed_words_discovered": len(new_definition_worthy),
            "common_filtered": filtered_common_count,
            "processing_time_sec": elapsed
        })

    # Export Report & DeepSeek Payload
    report_file = os.path.join(CURRENT_DIR, "benchmark_10_chapters_report.json")
    with open(report_file, "w", encoding="utf-8") as f:
        json.dump(overall_results, f, ensure_ascii=False, indent=2)

    deepseek_payload_file = os.path.join(CURRENT_DIR, "benchmark_missed_words.json")
    with open(deepseek_payload_file, "w", encoding="utf-8") as f:
        json.dump({
            "target_model": "deepseek-chat",
            "total_missed_words_in_10_chapters": len(all_missed_words_for_deepseek),
            "words": all_missed_words_for_deepseek
        }, f, ensure_ascii=False, indent=2)

    # Print Final Summary Table
    print("=" * 85)
    print("FINAL 10-CHAPTER BENCHMARK SUMMARY")
    print("=" * 85)
    print(f"{'Chapter':<20} | {'Tokens':<7} | {'Unique':<7} | {'In DB':<6} | {'MISSED (NEW)':<13} | {'Filtered':<8}")
    print("-" * 85)
    tot_tok = tot_uni = tot_db = tot_miss = tot_filt = 0
    for r in overall_results:
        ch_label = f"{r['book']} {r['chapter']}"
        print(f"{ch_label:<20} | {r['total_tokens']:<7} | {r['unique_lemmas']:<7} | {r['already_in_db']:<6} | {r['missed_words_discovered']:<13} | {r['common_filtered']:<8}")
        tot_tok += r["total_tokens"]
        tot_uni += r["unique_lemmas"]
        tot_db += r["already_in_db"]
        tot_miss += r["missed_words_discovered"]
        tot_filt += r["common_filtered"]
    print("-" * 85)
    print(f"{'TOTAL':<20} | {tot_tok:<7} | {tot_uni:<7} | {tot_db:<6} | {tot_miss:<13} | {tot_filt:<8}")
    print("=" * 85)
    print(f"Exported detailed benchmark report: '{os.path.basename(report_file)}'")
    print(f"Exported {len(all_missed_words_for_deepseek)} missed words payload: '{os.path.basename(deepseek_payload_file)}'")

if __name__ == "__main__":
    run_benchmark()
