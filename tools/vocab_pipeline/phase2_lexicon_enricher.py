#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Phase 2 Bible Study Lexicon Enrichment Pipeline
================================================
Generates rich, 360° theological, original-language (Hebrew/Greek/Strong's),
metrological, and practical discipleship entries for all canonical lemmas
in the Bible, populating `study_lexicon` and `study_lexicon_fts`.

Accelerated via Intel Arc Vulkan GPU server (port 8080) or Ollama (port 11434).
"""

import os
import sys
import time
import json
import sqlite3
import argparse
import urllib.request
import urllib.error
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone

sys.stdout.reconfigure(encoding="utf-8")

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", ".."))
SQLITE_PATH = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "taobvsi_glossary.sqlite")

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:8080")
MODEL_NAME = os.environ.get("MODEL_NAME", "gemma4:12b")

TELEMETRY = {
    "total_lemmas": 0,
    "completed_lemmas": 0,
    "start_time": time.time(),
    "backend_type": "unknown",
    "consecutive_errors": 0,
    "lock": threading.Lock()
}

DB_WRITE_LOCK = threading.Lock()

# ==============================================================================
# 1. DATABASE INITIALIZATION & DDL
# ==============================================================================

def init_study_lexicon_db(db_path: str):
    """Initializes the Phase 2 master study_lexicon table and FTS5 search index."""
    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("PRAGMA journal_mode = WAL;")
    cur.execute("PRAGMA synchronous = NORMAL;")

    # Master Study Lexicon Table
    cur.execute("""
    CREATE TABLE IF NOT EXISTS study_lexicon (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        
        -- 1. HEADWORD & CLASSIFICATION
        lemma TEXT NOT NULL UNIQUE,
        pos TEXT NOT NULL DEFAULT 'noun',
        pos_ta TEXT NOT NULL DEFAULT 'சொல்',
        entry_type TEXT NOT NULL DEFAULT 'theological',
        
        -- 2. ORIGINAL BIBLICAL LANGUAGE & CONCORDANCE
        original_lang TEXT,
        original_script TEXT,
        transliteration TEXT,
        strongs_number TEXT,
        original_root_meaning TEXT,
        
        -- 3. LINGUISTIC & BILINGUAL BRIDGE
        gloss_en TEXT NOT NULL DEFAULT '',
        definition_ta TEXT NOT NULL DEFAULT '',
        definition_en TEXT,
        modern_spoken_tamil TEXT NOT NULL DEFAULT '',
        translation_notes TEXT,
        
        -- 4. ONOMASTICS (For Biblical Characters & Places)
        name_meaning TEXT,
        character_archetype TEXT,
        geographical_location TEXT,
        
        -- 5. BIBLICAL METROLOGY (Coins, Weights, Measures & Calendar)
        is_metrology BOOLEAN DEFAULT 0,
        modern_metric_value TEXT,
        ancient_economic_value TEXT,
        
        -- 6. REDEMPTIVE HISTORY & BIBLICAL THEOLOGY
        ot_covenant_context TEXT,
        christological_fulfillment TEXT,
        new_covenant_reality TEXT,
        theological_pillar TEXT,
        
        -- 7. THEOLOGICAL CONTRASTS & TYPOLOGY
        theological_antonyms TEXT,
        is_typological BOOLEAN DEFAULT 0,
        typological_meaning TEXT,
        figurative_usage TEXT,
        
        -- 8. PRACTICAL DISCIPLESHIP & CONSCIENCE EXAMINATION
        discipleship_application TEXT NOT NULL DEFAULT '',
        heart_reflection_questions TEXT NOT NULL DEFAULT '[]',
        common_misconceptions TEXT,
        
        -- 9. SCRIPTURE ANCHORS & THEMATIC CLUSTERING
        anchor_verses TEXT DEFAULT '[]',
        thematic_tags TEXT DEFAULT '[]',
        related_lemmas TEXT DEFAULT '[]',
        
        -- 10. METRICS & AUDIT
        occurrence_count INTEGER DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    """)

    # Fast Lookups
    cur.execute("CREATE INDEX IF NOT EXISTS idx_study_lexicon_lemma ON study_lexicon(lemma);")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_study_lexicon_strongs ON study_lexicon(strongs_number);")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_study_lexicon_type ON study_lexicon(entry_type);")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_study_lexicon_pillar ON study_lexicon(theological_pillar);")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_study_lexicon_lang ON study_lexicon(original_lang);")

    # FTS5 Virtual Search Table
    try:
        cur.execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS study_lexicon_fts USING fts5(
            lemma,
            gloss_en,
            strongs_number,
            modern_spoken_tamil,
            definition_ta,
            definition_en,
            name_meaning,
            theological_pillar,
            thematic_tags,
            content='study_lexicon',
            content_rowid='id'
        );
        """)

        # Triggers for Automatic FTS Sync
        cur.execute("""
        CREATE TRIGGER IF NOT EXISTS trg_study_ai AFTER INSERT ON study_lexicon BEGIN
            INSERT INTO study_lexicon_fts(rowid, lemma, gloss_en, strongs_number, modern_spoken_tamil, definition_ta, definition_en, name_meaning, theological_pillar, thematic_tags)
            VALUES (new.id, new.lemma, new.gloss_en, new.strongs_number, new.modern_spoken_tamil, new.definition_ta, new.definition_en, new.name_meaning, new.theological_pillar, new.thematic_tags);
        END;
        """)

        cur.execute("""
        CREATE TRIGGER IF NOT EXISTS trg_study_ad AFTER DELETE ON study_lexicon BEGIN
            INSERT INTO study_lexicon_fts(study_lexicon_fts, rowid, lemma, gloss_en, strongs_number, modern_spoken_tamil, definition_ta, definition_en, name_meaning, theological_pillar, thematic_tags)
            VALUES ('delete', old.id, old.lemma, old.gloss_en, old.strongs_number, old.modern_spoken_tamil, old.definition_ta, old.definition_en, old.name_meaning, old.theological_pillar, old.thematic_tags);
        END;
        """)

        cur.execute("""
        CREATE TRIGGER IF NOT EXISTS trg_study_au AFTER UPDATE ON study_lexicon BEGIN
            INSERT INTO study_lexicon_fts(study_lexicon_fts, rowid, lemma, gloss_en, strongs_number, modern_spoken_tamil, definition_ta, definition_en, name_meaning, theological_pillar, thematic_tags)
            VALUES ('delete', old.id, old.lemma, old.gloss_en, old.strongs_number, old.modern_spoken_tamil, old.definition_ta, old.definition_en, old.name_meaning, old.theological_pillar, old.thematic_tags);
            INSERT INTO study_lexicon_fts(rowid, lemma, gloss_en, strongs_number, modern_spoken_tamil, definition_ta, definition_en, name_meaning, theological_pillar, thematic_tags)
            VALUES (new.id, new.lemma, new.gloss_en, new.strongs_number, new.modern_spoken_tamil, new.definition_ta, new.definition_en, new.name_meaning, new.theological_pillar, new.thematic_tags);
        END;
        """)
    except Exception as e:
        print(f"[FTS Init Warning]: {e}")

    conn.commit()
    conn.close()
    print(f"Master study_lexicon table ready at {db_path}")

# ==============================================================================
# 2. LLM CONNECTION & PROTOCOL
# ==============================================================================

def probe_backend():
    """Detects llama-server on port 8080 (Intel Arc Vulkan) or Ollama on port 11434."""
    global OLLAMA_HOST
    candidates = ["http://127.0.0.1:8080", "http://localhost:8080", "http://127.0.0.1:11434", "http://localhost:11434"]
    for host in candidates:
        # Check llama-server OpenAI endpoint
        try:
            req = urllib.request.Request(f"{host}/v1/models", headers={"User-Agent": "ChristianTube-Pipeline"})
            with urllib.request.urlopen(req, timeout=3) as resp:
                if resp.status == 200:
                    OLLAMA_HOST = host
                    TELEMETRY["backend_type"] = "llama_server"
                    print(f"Connected to llama-server (Intel Arc Vulkan GPU) at {host}")
                    return True
        except Exception:
            pass

        # Check Ollama version
        try:
            req = urllib.request.Request(f"{host}/api/version", headers={"User-Agent": "ChristianTube-Pipeline"})
            with urllib.request.urlopen(req, timeout=3) as resp:
                if resp.status == 200:
                    OLLAMA_HOST = host
                    TELEMETRY["backend_type"] = "ollama"
                    print(f"Connected to Ollama daemon at {host}")
                    return True
        except Exception:
            pass

    print(f"Warning: No live server detected on 8080 or 11434. Defaulting to {OLLAMA_HOST}")
    return False

def call_llm(system_prompt: str, user_prompt: str, max_tokens: int = 1800, timeout: int = 240) -> dict | None:
    """Invokes the LLM and guarantees clean JSON parsing."""
    b_type = TELEMETRY.get("backend_type", "llama_server")
    if b_type == "llama_server":
        endpoint = f"{OLLAMA_HOST}/v1/chat/completions"
        payload = {
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            "response_format": {"type": "json_object"},
            "temperature": 0.1,
            "max_tokens": max_tokens
        }
    else:
        endpoint = f"{OLLAMA_HOST}/api/chat"
        payload = {
            "model": MODEL_NAME,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            "format": "json",
            "stream": False,
            "think": False,
            "options": {
                "temperature": 0.1,
                "num_predict": max_tokens
            }
        }

    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(endpoint, data=body, headers={"Content-Type": "application/json"})

    for attempt in range(1, 4):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                if b_type == "llama_server":
                    msg = data.get("choices", [{}])[0].get("message", {})
                    content = msg.get("content") or msg.get("reasoning_content") or ""
                else:
                    content = data.get("message", {}).get("content", "")

                content_clean = content.strip()
                if content_clean.startswith("```json"):
                    content_clean = content_clean[7:]
                if content_clean.startswith("```"):
                    content_clean = content_clean[3:]
                if content_clean.endswith("```"):
                    content_clean = content_clean[:-3]

                parsed = json.loads(content_clean.strip())
                TELEMETRY["consecutive_errors"] = 0
                return parsed
        except Exception as e:
            time.sleep(1.5 * attempt)

    return None

# ==============================================================================
# 3. PROMPT TEMPLATES & SYSTEM KNOWLEDGE
# ==============================================================================

SYSTEM_PROMPT = """You are the Senior Theological Lexicographer and Biblical Scholar for the Tamil Old & New Testament Lexicon.
Your goal is to produce an authoritative, exhaustive, 360° biblical study lexicon entry for a given Tamil canonical lemma (வேர்ச்சொல்).
The lexicon bridges classical biblical Greek and Hebrew roots, biblical metrology/onomastics, redemptive theology (covenant progression, Christological fulfillment), and practical discipleship (Zac Poonen / New Covenant inward obedience, victory over sin).

You MUST respond strictly with valid JSON conforming to this exact structure:
{
  "lemma": "Tamil canonical lemma (e.g. தாலந்து)",
  "pos": "noun / verb / adjective / proper_noun / particle",
  "pos_ta": "பெயர்ச்சொல் / வினைச்சொல் / சிறப்புப் பெயர் / இடைச்சொல்",
  "entry_type": "theological / person / place / measure_coin / ritual / general",
  "original_lang": "Hebrew / Greek / Aramaic (or Both)",
  "original_script": "Original Hebrew script (with vowel points) or Greek script",
  "transliteration": "Scholarly English transliteration (e.g., talanton / chesed / pistis)",
  "strongs_number": "Strong's number e.g. G5007 / H2617",
  "original_root_meaning": "Etymological root in Ancient Near East / Greco-Roman world",
  "gloss_en": "Concise English translation / gloss",
  "definition_ta": "Comprehensive Biblical Tamil definition explaining spiritual and contextual meaning",
  "definition_en": "Expository English theological definition",
  "modern_spoken_tamil": "Spoken/modern Tamil equivalent bridging archaic 19th-century Bower/Fabricius terminology",
  "translation_notes": "Why 1800s translators chose this word; comparisons with modern versions or linguistic nuances",
  "name_meaning": "Prophetic/spiritual meaning if person/place, else null",
  "character_archetype": "Spiritual archetype if person, else null",
  "geographical_location": "Modern location or terrain if place, else null",
  "is_metrology": false,
  "modern_metric_value": "Equivalent metric value if weight/measure/coin, else null",
  "ancient_economic_value": "Ancient economic value/labor equivalent if currency/measure, else null",
  "ot_covenant_context": "Usage in Law, Tabernacle, Old Covenant shadows",
  "christological_fulfillment": "How Jesus Christ embodies, fulfills, or transforms this concept",
  "new_covenant_reality": "Inward spiritual reality in the New Covenant (heart vs letter)",
  "theological_pillar": "Theology Proper / Christology / Pneumatology / Soteriology / Ecclesiology / Eschatology",
  "theological_antonyms": [{"word": "எதிர்ச்சொல்", "contrast": "விளக்கம்"}],
  "is_typological": false,
  "typological_meaning": "Type -> Antitype fulfillment if shadow/symbol, else null",
  "figurative_usage": "Metaphorical or symbolic usage across scripture",
  "discipleship_application": "Practical takeaway for personal holiness, faith, and obedience",
  "heart_reflection_questions": [
    "தனிப்பட்ட வாழ்க்கையில் தேவனை நோக்கிய ஊடுருவும் சுயபரிசோதனை கேள்வி 1",
    "ஊடுருவும் சுயபரிசோதனை கேள்வி 2"
  ],
  "common_misconceptions": "Modern distortion, legalistic or liberal misconception to avoid",
  "anchor_verses": ["புத்தகம் அதிகாரம்:வசனம் 1", "புத்தகம் அதிகாரம்:வசனம் 2"],
  "thematic_tags": ["கருத்து 1", "கருத்து 2", "கருத்து 3"],
  "related_lemmas": ["தொடர்புடைய சொல் 1", "தொடர்புடைய சொல் 2"]
}
Only output the raw JSON object. Do not include markdown code fence formatting or commentary outside the JSON."""

def build_user_prompt(lemma: str, info: dict) -> str:
    """Builds the contextual prompt with database facts."""
    return f"""Please generate the complete 360° Bible Study Lexicon entry for the Tamil canonical lemma:
LEMA: "{lemma}"

KNOWN CANONICAL CONTEXT FROM SCRIPTURE DATABASE:
- Total Biblical Occurrences: {info.get('occurrence_count', 1)}
- Testament Presence: {info.get('testament_distribution', 'Both Old & New Testaments')}
- Existing Known English Equivalents: {', '.join(info.get('english_words', [])[:5])}
- Known Parts of Speech: {', '.join(info.get('pos_tags', [])[:3])}
- Canonical First Verse: {info.get('first_ref', 'N/A')}
- Canonical Last Verse: {info.get('last_ref', 'N/A')}
- Sample Verse Sentences:
{chr(10).join('- ' + s for s in info.get('sample_sentences', [])[:4])}

Ensure accurate Hebrew/Greek lemma, Strong's number, deep theological definition, Christological fulfillment, and practical discipleship application. Output strict JSON only."""

# ==============================================================================
# 4. CONTEXT GATHERING & WORKER
# ==============================================================================

def get_lemma_context(conn: sqlite3.Connection, lemma: str) -> dict:
    """Extracts known context for lemma from unique_words and verse_tokens."""
    cur = conn.cursor()
    
    # 1. Occurrence count & unique_words records
    cur.execute("""
    SELECT surface_form, pos, english_word, definition_ta, modern_equivalent
    FROM unique_words
    WHERE canonical = ?
    """, (lemma,))
    uw_rows = cur.fetchall()

    english_words = list(dict.fromkeys(r[2].strip() for r in uw_rows if r[2] and r[2].strip()))
    pos_tags = list(dict.fromkeys(r[1].strip() for r in uw_rows if r[1] and r[1].strip()))

    # 2. Verse distribution & references
    cur.execute("""
    SELECT vt.book, vt.chapter, vt.verse, vt.raw_token
    FROM verse_tokens vt
    JOIN unique_words u ON vt.word_id = u.id
    WHERE u.canonical = ?
    ORDER BY vt.book ASC, vt.chapter ASC, vt.verse ASC
    """, (lemma,))
    vt_rows = cur.fetchall()
    total_occ = len(vt_rows)

    first_ref = f"{vt_rows[0][0]}:{vt_rows[0][1]}:{vt_rows[0][2]}" if vt_rows else None
    last_ref = f"{vt_rows[-1][0]}:{vt_rows[-1][1]}:{vt_rows[-1][2]}" if vt_rows else None

    # Testament presence
    books = set(r[0] for r in vt_rows)
    has_ot = any(b <= 39 for b in books)
    has_nt = any(b >= 40 for b in books)
    if has_ot and has_nt:
        t_dist = "Both Old (Hebrew) and New (Greek) Testaments"
    elif has_ot:
        t_dist = "Old Testament only (Hebrew/Aramaic)"
    elif has_nt:
        t_dist = "New Testament only (Greek)"
    else:
        t_dist = "Biblical Canon"

    # Distinct sample references
    sample_sentences = []
    seen_refs = set()
    for r in vt_rows:
        ref_str = f"Book {r[0]} {r[1]}:{r[2]}"
        if ref_str not in seen_refs:
            seen_refs.add(ref_str)
            sample_sentences.append(f"{ref_str} ({r[3]})")
            if len(sample_sentences) >= 4:
                break

    return {
        "occurrence_count": total_occ,
        "testament_distribution": t_dist,
        "english_words": english_words,
        "pos_tags": pos_tags,
        "first_ref": first_ref,
        "last_ref": last_ref,
        "sample_sentences": sample_sentences,
    }

def save_study_lexicon_entry(db_path: str, lemma: str, occ_count: int, entry: dict) -> bool:
    """Inserts or replaces the enriched 360° lexicon entry in SQLite."""
    with DB_WRITE_LOCK:
        try:
            conn = sqlite3.connect(db_path, timeout=30.0)
            cur = conn.cursor()

            # Helper serializers
            def to_json(val, default="[]"):
                if val is None:
                    return default
                if isinstance(val, (list, dict)):
                    return json.dumps(val, ensure_ascii=False)
                return str(val)

            cur.execute("""
            INSERT OR REPLACE INTO study_lexicon (
                lemma, pos, pos_ta, entry_type,
                original_lang, original_script, transliteration, strongs_number, original_root_meaning,
                gloss_en, definition_ta, definition_en, modern_spoken_tamil, translation_notes,
                name_meaning, character_archetype, geographical_location,
                is_metrology, modern_metric_value, ancient_economic_value,
                ot_covenant_context, christological_fulfillment, new_covenant_reality, theological_pillar,
                theological_antonyms, is_typological, typological_meaning, figurative_usage,
                discipleship_application, heart_reflection_questions, common_misconceptions,
                anchor_verses, thematic_tags, related_lemmas, occurrence_count, updated_at
            ) VALUES (
                ?, ?, ?, ?,
                ?, ?, ?, ?, ?,
                ?, ?, ?, ?, ?,
                ?, ?, ?,
                ?, ?, ?,
                ?, ?, ?, ?,
                ?, ?, ?, ?,
                ?, ?, ?,
                ?, ?, ?, ?, CURRENT_TIMESTAMP
            )
            """, (
                lemma,
                entry.get("pos", "noun"),
                entry.get("pos_ta", "சொல்"),
                entry.get("entry_type", "theological"),
                entry.get("original_lang"),
                entry.get("original_script"),
                entry.get("transliteration"),
                entry.get("strongs_number"),
                entry.get("original_root_meaning"),
                entry.get("gloss_en", ""),
                entry.get("definition_ta", ""),
                entry.get("definition_en"),
                entry.get("modern_spoken_tamil", ""),
                entry.get("translation_notes"),
                entry.get("name_meaning"),
                entry.get("character_archetype"),
                entry.get("geographical_location"),
                1 if entry.get("is_metrology") else 0,
                entry.get("modern_metric_value"),
                entry.get("ancient_economic_value"),
                entry.get("ot_covenant_context"),
                entry.get("christological_fulfillment"),
                entry.get("new_covenant_reality"),
                entry.get("theological_pillar"),
                to_json(entry.get("theological_antonyms")),
                1 if entry.get("is_typological") else 0,
                entry.get("typological_meaning"),
                entry.get("figurative_usage"),
                entry.get("discipleship_application", ""),
                to_json(entry.get("heart_reflection_questions")),
                entry.get("common_misconceptions"),
                to_json(entry.get("anchor_verses")),
                to_json(entry.get("thematic_tags")),
                to_json(entry.get("related_lemmas")),
                occ_count
            ))

            conn.commit()
            conn.close()
            return True
        except Exception as e:
            print(f"[DB Save Error for '{lemma}']: {e}")
            return False

def process_single_lemma(lemma: str, db_path: str) -> bool:
    """Enriches a single canonical lemma via LLM and saves to SQLite."""
    # 1. Fetch DB context
    try:
        conn = sqlite3.connect(db_path, timeout=30.0)
        info = get_lemma_context(conn, lemma)
        conn.close()
    except Exception as e:
        print(f"[Context Error for '{lemma}']: {e}")
        return False

    # 2. Call LLM
    user_prompt = build_user_prompt(lemma, info)
    t0 = time.time()
    result = call_llm(SYSTEM_PROMPT, user_prompt)
    dt = time.time() - t0

    if not result or not isinstance(result, dict) or not result.get("definition_ta"):
        print(f"  [LLM Fail] Lemma '{lemma}' returned invalid result ({dt:.1f}s)")
        return False

    # 3. Save to database
    occ_count = info.get("occurrence_count", 1)
    saved = save_study_lexicon_entry(db_path, lemma, occ_count, result)
    if saved:
        strongs = result.get("strongs_number") or "-"
        lang = result.get("original_lang") or "-"
        pillar = result.get("theological_pillar") or "-"
        print(f"  [Saved] '{lemma}' ({occ_count}x) | Strong's: {strongs} | {lang} | {pillar} | Time: {dt:.1f}s")
    return saved

# ==============================================================================
# 5. MAIN ENRICHMENT COORDINATOR
# ==============================================================================

def run_phase2_pipeline(db_path: str, max_lemmas: int | None = None, workers: int = 3):
    """Coordinates parallel Phase 2 enrichment."""
    print("=" * 80)
    print("PHASE 2 MASTER BIBLE STUDY LEXICON ENRICHMENT PIPELINE")
    print("=" * 80)
    print(f"Database: {db_path}")
    print(f"Workers: {workers}")

    # Step 1: Initialize Database
    init_study_lexicon_db(db_path)

    # Step 2: Probe Backend
    probe_backend()

    # Step 3: Get distinct canonical lemmas sorted by Bible occurrences
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("""
    SELECT u.canonical, count(vt.book) as occ
    FROM unique_words u
    JOIN verse_tokens vt ON vt.word_id = u.id
    WHERE u.canonical IS NOT NULL AND length(trim(u.canonical)) > 0
    GROUP BY u.canonical
    ORDER BY occ DESC
    """)
    all_lemmas = cur.fetchall()

    # Query already completed lemmas
    cur.execute("SELECT lemma FROM study_lexicon")
    completed_set = set(r[0] for r in cur.fetchall())
    conn.close()

    pending_lemmas = [(l, occ) for l, occ in all_lemmas if l not in completed_set]
    total_canonical = len(all_lemmas)
    total_completed = len(completed_set)
    total_pending = len(pending_lemmas)

    if max_lemmas:
        pending_lemmas = pending_lemmas[:max_lemmas]

    print(f"Total Unique Canonical Roots in Bible: {total_canonical:,}")
    print(f"Already Enriched in study_lexicon: {total_completed:,}")
    print(f"Pending to Enrich: {len(pending_lemmas):,} (Queue target: {total_pending:,})")
    print("-" * 80)

    if not pending_lemmas:
        print("All canonical lemmas are already fully enriched in study_lexicon!")
        return

    TELEMETRY["total_lemmas"] = len(pending_lemmas)
    TELEMETRY["completed_lemmas"] = 0
    start_time = time.time()

    # Step 4: Parallel Processing Pool
    print(f"Launching {workers} parallel workers on {OLLAMA_HOST}...")
    with ThreadPoolExecutor(max_workers=workers) as executor:
        future_to_lemma = {
            executor.submit(process_single_lemma, lemma, db_path): lemma
            for lemma, _ in pending_lemmas
        }

        for future in as_completed(future_to_lemma):
            lem = future_to_lemma[future]
            try:
                success = future.result()
                if success:
                    with TELEMETRY["lock"]:
                        TELEMETRY["completed_lemmas"] += 1
                        done = TELEMETRY["completed_lemmas"]
                        tot = TELEMETRY["total_lemmas"]
                        elapsed = time.time() - start_time
                        rate = done / elapsed if elapsed > 0 else 0.0
                        rem_sec = (tot - done) / rate if rate > 0 else 0
                        rem_min = rem_sec / 60
                        if done % 5 == 0 or done == tot:
                            print(f">>> [PROGRESS] {done}/{tot} ({done/tot*100:.1f}%) | Speed: {rate*60:.1f} lemmas/min | Est Rem: {rem_min:.1f}m")
            except Exception as e:
                print(f"[Worker Exception for '{lem}']: {e}")

    print("=" * 80)
    print("PHASE 2 ENRICHMENT RUN COMPLETE!")
    print(f"Enriched {TELEMETRY['completed_lemmas']} lemmas in {(time.time() - start_time)/60:.1f} minutes.")
    print("=" * 80)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Phase 2 360° Bible Study Lexicon Enrichment")
    parser.add_argument("--db", type=str, default=SQLITE_PATH, help="Path to taobvsi_glossary.sqlite")
    parser.add_argument("--limit", type=int, default=None, help="Limit number of lemmas to process in this run")
    parser.add_argument("--workers", type=int, default=3, help="Number of parallel worker threads (default 3)")
    args = parser.parse_args()

    run_phase2_pipeline(db_path=args.db, max_lemmas=args.limit, workers=args.workers)
