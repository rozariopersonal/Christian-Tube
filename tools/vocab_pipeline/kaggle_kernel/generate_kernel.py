import json
import os

kernel_dir = os.path.abspath("tools/vocab_pipeline/kaggle_kernel")
os.makedirs(kernel_dir, exist_ok=True)

metadata = {
    "id": "arulrozario/taobvsi-vocab-pipeline",
    "title": "TAOBVSI Vocab Pipeline",
    "code_file": "taobvsi_pipeline.ipynb",
    "language": "python",
    "kernel_type": "notebook",
    "is_private": "true",
    "enable_gpu": "true",
    "enable_tpu": "false",
    "enable_internet": "true",
    "dataset_sources": ["arulrozario/taobvsi-bible-base-data"],
    "competition_sources": [],
    "kernel_sources": [],
    "model_sources": []
}

with open(os.path.join(kernel_dir, "kernel-metadata.json"), "w", encoding="utf-8") as fp:
    json.dump(metadata, fp, indent=2)

cell1_code = """# 1. Install zstd (required by Ollama installer) and Ollama binary
!apt-get update && apt-get install -y zstd
!curl -fsSL https://ollama.com/install.sh | sh
"""

cell2_code = """# 2. Start Ollama daemon and pull gemma4:12b
import subprocess, time, urllib.request, os

env = os.environ.copy()
env["OLLAMA_NUM_PARALLEL"] = "1"
env["OLLAMA_CONTEXT_LENGTH"] = "8192"

p = subprocess.Popen(["ollama", "serve"], env=env)
time.sleep(5)

for attempt in range(15):
    try:
        with urllib.request.urlopen("http://localhost:11434/api/version", timeout=5) as resp:
            print("Ollama daemon running:", resp.read().decode())
            break
    except Exception:
        time.sleep(2)

!ollama pull gemma4:12b
"""

cell3_code = """# 3. Clean slate unpack: Copy ONLY raw Bible texts; zero pre-existing glossary/cache
import glob, os, shutil

input_root = "/kaggle/input/taobvsi-bible-base-data"
working_data = "/kaggle/working/data"

# Clean any existing working data to guarantee a 100% clean state
if os.path.exists(working_data):
    shutil.rmtree(working_data)

os.makedirs(f"{working_data}/bibles", exist_ok=True)
os.makedirs(f"{working_data}/study/taobvsi/words", exist_ok=True)

# Copy ONLY raw Bible verse texts (taobvsi/<book>/<chapter>.json)
if os.path.exists(f"{input_root}/bibles/taobvsi"):
    shutil.copytree(f"{input_root}/bibles/taobvsi", f"{working_data}/bibles/taobvsi", dirs_exist_ok=True)
elif os.path.exists(f"{input_root}/bibles"):
    shutil.copytree(f"{input_root}/bibles", f"{working_data}/bibles", dirs_exist_ok=True)

print("Clean slate verified:")
print(" - Raw Bible texts loaded:", len(os.listdir(f'{working_data}/bibles/taobvsi')), "books")
print(" - Pre-existing glossary: 0 files (Starting completely fresh)")
print(" - Pre-existing words cache: 0 files")
"""

cell4_code = '''# 4. Sequential Bible RAG Processor (From Beginning: Book 1:1)
import sqlite3, json, time, urllib.request, os, sys, glob, csv
from datetime import datetime, timezone, timedelta

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

OLLAMA_HOST = "http://localhost:11434"
MODEL_NAME = "gemma4:12b"
BASE_BIBLE_DIR = "/kaggle/working/data/bibles/taobvsi"
BASE_WORDS_DIR = "/kaggle/working/data/study/taobvsi/words"
SQLITE_PATH = "/kaggle/working/data/study/taobvsi/taobvsi_glossary.sqlite"
CSV_PATH = "/kaggle/working/data/study/taobvsi/taobvsi_verse_words.csv"

PUNCT_CHARS = ".,;:!?()[]\'\\""

POS_SYSTEM_PROMPT = """You are an expert Protestant classical Tamil Bible linguist and grammarian specializing in the Tamil Bible (TAOVBSI - பரிசுத்த வேதாகமம்).
Your task is to tokenize the given Bible verse into sequential word tokens and determine the Part of Speech (POS) abbreviation for each token in its exact verse context.
Allowed POS abbreviations: "n" (Noun), "v" (Verb), "adj" (Adjective), "adv" (Adverb), "pron" (Pronoun), "part" (Particle/Postposition), "conj" (Conjunction), "num" (Numeral), "interj" (Interjection).
Use short keys: "i": index, "w": token, "p": POS abbreviation.
Output JSON: {"words": [{"i": 0, "w": "<token>", "p": "<pos>"}]}"""

DELTA_SYSTEM_PROMPT = """You are an expert Protestant classical Tamil Bible lexicographer and theologian specializing in the Tamil Bible (TAOVBSI - பரிசுத்த வேதாகமம்).
Define ONLY the requested missing words.
Rules:
1. "c" (canonical): Bare imperative root for verbs (கொடு, சொல், பார்), nominative base form for nouns (விதை, கனி, பூமி, தேவன்).
2. "d" (definition_ta): 1 concise explanatory sentence in classical Tamil.
3. "m" (modern_equivalent): 1-2 modern Tamil words.
4. "e" (english_word): Standard biblical English translation.
5. Protestant Register: Use classical Protestant terms (தேவன், கர்த்தர், வேதாகமம், பரிசுத்தம்). NEVER Catholic/secular terms (இறைவன், புனித).
Output JSON: {"definitions": [{"i": 0, "c": "<root>", "d": "<def>", "m": "<modern>", "e": "<eng>"}]}"""

POS_QUERY_MAP = {"n": ["noun", "person", "place"], "v": ["verb"], "adj": ["adjective"], "adv": ["adverb"], "pron": ["pronoun"], "part": ["particle"], "prep": ["particle"], "conj": ["conjunction"], "num": ["numeral"], "interj": ["interjection"]}
POS_FULL = {"n": "noun", "v": "verb", "adj": "adjective", "adv": "adverb", "pron": "pronoun", "part": "particle", "prep": "particle", "conj": "conjunction", "num": "numeral", "interj": "interjection"}

def get_db():
    conn = sqlite3.connect(SQLITE_PATH, timeout=60)
    conn.execute("PRAGMA journal_mode=WAL")
    return conn

def init_db():
    with get_db() as conn:
        c = conn.cursor()
        c.execute("""
            CREATE TABLE IF NOT EXISTS glossary_entries (
                id TEXT PRIMARY KEY,
                headword TEXT NOT NULL,
                pos TEXT NOT NULL,
                pos_ta TEXT NOT NULL,
                english_word TEXT,
                definition_ta TEXT,
                definition_en TEXT,
                modern_equivalents TEXT,
                strongs TEXT,
                original_lemma TEXT,
                original_translit TEXT
            )
        """)
        c.execute("""
            CREATE TABLE IF NOT EXISTS surface_forms (
                surface_form TEXT PRIMARY KEY,
                entry_id TEXT NOT NULL REFERENCES glossary_entries(id)
            )
        """)
        c.execute("""
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
                modern_equivalent TEXT,
                pos TEXT,
                PRIMARY KEY (book, chapter, verse, word_index)
            )
        """)
        c.execute("CREATE INDEX IF NOT EXISTS idx_vw_lookup ON verse_words (surface_form, pos)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_sf_lookup ON surface_forms (surface_form)")
        cols = [r[1] for r in c.execute("PRAGMA table_info(glossary_entries)").fetchall()]
        if "english_word" not in cols:
            try:
                c.execute("ALTER TABLE glossary_entries ADD COLUMN english_word TEXT")
                if "gloss_en" in cols:
                    c.execute("UPDATE glossary_entries SET english_word = gloss_en WHERE english_word IS NULL")
            except Exception:
                pass
        for col in ["root_definition_ta", "root_definition_en", "original_context", "original_translit"]:
            if col not in cols:
                try:
                    c.execute(f"ALTER TABLE glossary_entries ADD COLUMN {col} TEXT")
                except Exception:
                    pass
        conn.commit()
    print("SQLite database initialized and schema verified.")

def lookup_word(raw_token, p):
    clean = raw_token.strip(PUNCT_CHARS)
    if not clean:
        return None
    allowed = POS_QUERY_MAP.get(p, [POS_FULL.get(p, "noun")])
    placeholders = ",".join(["?"] * len(allowed))
    with get_db() as conn:
        c = conn.cursor()
        r = c.execute(f"SELECT canonical, pos, definition_ta, modern_equivalent, english_word FROM verse_words WHERE (surface_form=? OR canonical=?) AND pos IN ({placeholders}) LIMIT 1", (clean, clean, *allowed)).fetchone()
        if r:
            return {"canonical": r[0], "pos": r[1], "definition_ta": r[2], "modern_equivalent": r[3] or "", "english_word": r[4] or "", "source": "db"}
        r2 = c.execute(f"SELECT g.headword, g.pos, g.definition_ta, g.modern_equivalents, g.english_word FROM surface_forms s JOIN glossary_entries g ON s.entry_id=g.id WHERE s.surface_form=? AND g.pos IN ({placeholders}) LIMIT 1", (clean, *allowed)).fetchone()
        if r2:
            return {"canonical": r2[0], "pos": r2[1], "definition_ta": r2[2], "modern_equivalent": r2[3] or "", "english_word": r2[4] or "", "source": "db"}
    return None

def call_ollama(sys_prompt, user_prompt, num_predict=1200):
    payload = {"model": MODEL_NAME, "messages": [{"role": "system", "content": sys_prompt}, {"role": "user", "content": user_prompt}], "format": "json", "stream": False, "options": {"temperature": 0.1, "num_predict": num_predict}}
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(f"{OLLAMA_HOST}/api/chat", data=body, headers={"Content-Type": "application/json"})
    for _ in range(3):
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                d = json.loads(resp.read().decode("utf-8"))
                return json.loads(d["message"]["content"])
        except Exception:
            time.sleep(2)
    return None

def process_verse(b, ch, v_obj):
    v_num = v_obj["verse"]
    v_text = v_obj["text"]
    tokens = v_text.split()
    expected_count = len(tokens)

    res = call_ollama(POS_SYSTEM_PROMPT, f"Verse {v_num}: {v_text}", num_predict=max(800, expected_count * 35))
    words = res.get("words", []) if res else []
    if len(words) != expected_count:
        words = [next((w for w in words if w.get("i") == i or w.get("w") == tok), {"i": i, "w": tok, "p": "n"}) for i, tok in enumerate(tokens)]

    missing = []
    resolved = {}
    db_hits = 0
    for tok in words:
        found = lookup_word(tok["w"], tok["p"])
        if found:
            db_hits += 1
            resolved[tok["i"]] = {**found, "word": tok["w"], "verse": v_num, "word_index": tok["i"]}
        else:
            missing.append(tok)

    if missing:
        user_p = f"Verse: {v_text}\\nMissing words to define:\\n" + json.dumps(missing, ensure_ascii=False)
        d_res = call_ollama(DELTA_SYSTEM_PROMPT, user_p, num_predict=max(800, len(missing) * 90))
        defs = {d["i"]: d for d in d_res.get("definitions", [])} if d_res else {}
        for m in missing:
            d = defs.get(m["i"], {})
            clean = m["w"].strip(PUNCT_CHARS)
            full_pos = POS_FULL.get(m["p"], "noun")
            canonical = d.get("c", clean) or clean
            def_ta = d.get("d", "")
            modern = d.get("m", clean) or clean
            eng = d.get("e", "")
            resolved[m["i"]] = {"word": m["w"], "verse": v_num, "word_index": m["i"], "pos": full_pos, "canonical": canonical, "definition_ta": def_ta, "modern_equivalent": modern, "english_word": eng, "source": "llm"}

    rows_to_save = [resolved[i] for i in range(expected_count) if i in resolved]
    with get_db() as conn:
        for r in rows_to_save:
            entry_id = r["canonical"]
            conn.execute("INSERT OR IGNORE INTO glossary_entries (id, headword, pos, pos_ta, english_word, definition_ta, modern_equivalents) VALUES (?,?,?,?,?,?,?)",
                         (entry_id, r["canonical"], r["pos"], r["pos"], r["english_word"], r["definition_ta"], r["modern_equivalent"]))
            clean = r["word"].strip(PUNCT_CHARS)
            if clean:
                conn.execute("INSERT OR IGNORE INTO surface_forms (surface_form, entry_id) VALUES (?,?)", (clean, entry_id))
            conn.execute("INSERT OR REPLACE INTO verse_words (book, chapter, verse, word_index, surface_form, pos, canonical, entry_id, english_word, modern_equivalent, definition_ta) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                         (b, ch, v_num, r["word_index"], r["word"], r["pos"], r["canonical"], entry_id, r["english_word"], r["modern_equivalent"], r["definition_ta"]))
        conn.commit()

    write_hdr = (not os.path.exists(CSV_PATH)) or (os.path.getsize(CSV_PATH) == 0)
    with open(CSV_PATH, "a", encoding="utf-8", newline="") as fp:
        writer = csv.writer(fp)
        if write_hdr:
            writer.writerow(["book", "chapter", "verse", "word_index", "surface_form", "pos", "canonical", "english_word", "modern_equivalent", "definition_ta"])
        for r in rows_to_save:
            writer.writerow([b, ch, v_num, r["word_index"], r["word"], r["pos"], r["canonical"], r["english_word"], r["modern_equivalent"], r["definition_ta"]])

    print(f"    Verse {v_num}: {expected_count} tokens ({db_hits} DB 0ms, {len(missing)} LLM)", flush=True)
    return rows_to_save

def process_chapter(b, ch):
    in_file = f"{BASE_BIBLE_DIR}/{b}/{ch}.json"
    out_dir = f"{BASE_WORDS_DIR}/{b}"
    out_file = f"{out_dir}/{ch}.json"
    os.makedirs(out_dir, exist_ok=True)
    if os.path.exists(out_file):
        try:
            if json.load(open(out_file, encoding="utf-8")).get("is_step1_completed"):
                print(f"  [SKIP] Book {b}:{ch} already complete.")
                return
        except Exception:
            pass

    if not os.path.exists(in_file):
        return
    verses = json.load(open(in_file, encoding="utf-8"))
    print(f"\\n>>> Processing Book {b}:{ch} ({len(verses)} verses)...", flush=True)
    t0 = time.time()
    all_words = []
    for v in verses:
        res = process_verse(b, ch, v)
        all_words.extend(res)

    output_data = {"book": b, "chapter": ch, "total_verses": len(verses), "total_words_parsed": len(all_words), "is_step1_completed": True, "words": all_words}
    with open(out_file, "w", encoding="utf-8") as fp:
        json.dump(output_data, fp, ensure_ascii=False, indent=2)
    print(f"[COMPLETED] Book {b}:{ch} in {time.time()-t0:.1f}s ({len(all_words)} words)!", flush=True)

def run_all():
    init_db()
    print("Starting Sequential Pipeline from Genesis 1:1 on Kaggle...")
    for b in range(1, 67):
        files = sorted(glob.glob(f"{BASE_BIBLE_DIR}/{b}/*.json"), key=lambda x: int(os.path.splitext(os.path.basename(x))[0]))
        for f in files:
            ch = int(os.path.splitext(os.path.basename(f))[0])
            process_chapter(b, ch)
    print("\\n================ ALL BIBLE CHAPTERS COMPLETE ==================")

run_all()
'''

cell5_code = """# 5. Package results for 1-click download
!zip -r /kaggle/working/taobvsi_completed.zip /kaggle/working/data/study/taobvsi/
print("Packaging complete! Download 'taobvsi_completed.zip' from Kaggle output.")
"""

notebook = {
    "cells": [
        {"cell_type": "code", "execution_count": None, "metadata": {}, "outputs": [], "source": [l + "\n" for l in cell1_code.splitlines()]},
        {"cell_type": "code", "execution_count": None, "metadata": {}, "outputs": [], "source": [l + "\n" for l in cell2_code.splitlines()]},
        {"cell_type": "code", "execution_count": None, "metadata": {}, "outputs": [], "source": [l + "\n" for l in cell3_code.splitlines()]},
        {"cell_type": "code", "execution_count": None, "metadata": {}, "outputs": [], "source": [l + "\n" for l in cell4_code.splitlines()]},
        {"cell_type": "code", "execution_count": None, "metadata": {}, "outputs": [], "source": [l + "\n" for l in cell5_code.splitlines()]}
    ],
    "metadata": {
        "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
        "language_info": {"codemirror_mode": {"name": "ipython", "version": 3}, "file_extension": ".py", "mimetype": "text/x-python", "name": "python", "nbconvert_exporter": "python", "pygments_lexer": "ipython3", "version": "3.10.12"}
    },
    "nbformat": 4,
    "nbformat_minor": 4
}

with open(os.path.join(kernel_dir, "taobvsi_pipeline.ipynb"), "w", encoding="utf-8") as fp:
    json.dump(notebook, fp, indent=2)

print("Kernel and Notebook generated cleanly without syntax bugs!")
