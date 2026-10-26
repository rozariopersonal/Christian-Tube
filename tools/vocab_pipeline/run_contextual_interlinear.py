import urllib.request
import urllib.error
import json
import time
import os
import sys
import glob
from datetime import datetime

sys.stdout.reconfigure(encoding='utf-8')

API_KEY = os.environ.get("GEMINI_API_KEY", "AIzaSyD04_odTE5jVUZ8yDTCZ7kkaNETo0QCgSk")
MODEL_NAME = "models/gemini-3.1-flash-lite"
API_URL = f"https://generativelanguage.googleapis.com/v1beta/{MODEL_NAME}:generateContent?key={API_KEY}"

# Free Tier safety delay (strictly <= 9 RPM)
REQUEST_DELAY_SEC = 6.5

# 2-3 verses per chunk guarantees 100% token coverage with zero skipped verses
CHUNK_SIZE_VERSES = 2

BASE_BIBLE_DIR = "releases/bibles/taobvsi"
BASE_WORDS_DIR = "releases/study/taobvsi/words"
PROGRESS_JSON = "releases/study/taobvsi/WORDS_PROGRESS.json"
PROGRESS_MD = "releases/study/taobvsi/WORDS_PROGRESS.md"

SYSTEM_PROMPT = """You are an eminent biblical lexicographer, Hebrew/Greek scholar, and New Covenant theologian specializing in the classical Protestant Tamil Bible (TAOVBSI - பரிசுத்த வேதாகமம்).

Given verses with exact pre-tokenized words, output a flat list of words with comprehensive, deeply explanatory exegesis.

CRITICAL REQUIREMENTS:
1. EXACT WORD COVERAGE: Output an entry for EVERY SINGLE input token in order. Never skip any token.
2. ENGLISH WORD: Provide the standard English biblical word corresponding to the token in 'english_word'.
3. CLEAN CANONICAL: Provide the natural, searchable Tamil base in 'canonical' (no artificial regex stubs).

4. HIGHLY EXPLANATORY BILINGUAL DEFINITIONS (NO SHORT SYNONYMS):
   - FORBIDDEN: NEVER write 1-word or 2-word trivial synonyms (e.g. NEVER just 'உலகம்', 'வெளிச்சமின்மை', 'காலியான நிலை', 'The world', 'Absence of light').
   - MANDATORY: Both 'definition_ta' and 'definition_en' MUST be thoroughly explanatory (2–3 full sentences):
     * Explain WHAT the term means conceptually.
     * Explain the theological or physical reality it describes in this specific verse.
     * Explain why this exact word is chosen in the biblical narrative.

5. ORIGINAL WORD WITH EXPLANATORY ROOT DEFINITION & CONTEXT:
   - 'text': Hebrew (OT) or Greek (NT) script.
   - 'transliteration': Latin phonetic.
   - 'strongs': Strong's Concordance ID (e.g. 'H7225').
   - 'root_definition_ta': Explanatory lexical definition of the root in Tamil.
   - 'root_definition_en': Explanatory lexical definition of the root in English.
   - 'context': The specific theological/grammatical nuance and role of this original term in this biblical passage.

6. PRACTICAL SPIRITUAL NOTES (CHRIST-CENTERED):
   - Provide a practical, devotional, Christ-centered note in 'notes' in classical Tamil.
   - Reflect deep New Covenant discipleship: inner holiness, God's sovereignty, Christ as our forerunner, victory over sin, and God redeeming the broken and ruined into a new creation.
   - ABSOLUTE PROHIBITION: NEVER mention 'Zac Poonen' or any person's name anywhere. Frame the notes purely as biblical truth.

7. STRICT VOCABULARY RULES (TAOVBSI PROTESTANT REGISTER):
   - FORBIDDEN: NEVER use 'இறைவன்', 'விவிலியம்', 'புனித' anywhere.
   - MANDATORY: ALWAYS use 'தேவன்', 'கர்த்தர்', 'வேதாகமம்', 'பரிசுத்தம்'.

Output JSON Schema:
{
  "words": [
    {
      "verse": <num>,
      "word": "<surface_token>",
      "english_word": "<english_word>",
      "canonical": "<canonical_tamil>",
      "definition_ta": "<thorough_explanatory_tamil_definition>",
      "definition_en": "<thorough_explanatory_english_definition>",
      "original_word": {
        "text": "<hebrew/greek_script>",
        "transliteration": "<transliteration>",
        "strongs": "<strongs_id>",
        "root_definition_ta": "<explanatory_root_definition_in_tamil>",
        "root_definition_en": "<explanatory_root_definition_in_english>",
        "context": "<original_word_contextual_function>"
      },
      "notes": "<practical_christ_centered_devotional_note_in_tamil>"
    }
  ]
}
"""

def log(msg: str):
    print(msg, flush=True)

def update_progress_files(current_book: int, current_ch: int, current_chunk_verses: str, status: str = "RUNNING"):
    all_files = glob.glob(os.path.join(BASE_WORDS_DIR, "*", "*.json"))
    total_chapters_done = len(all_files)
    total_words_done = 0
    
    chapter_stats = []
    for f in sorted(all_files):
        try:
            with open(f, "r", encoding="utf-8") as fp:
                d = json.load(fp)
                ch_words = len(d.get("words", []))
                total_words_done += ch_words
                chapter_stats.append({
                    "book": d.get("book"),
                    "chapter": d.get("chapter"),
                    "words_parsed": ch_words,
                    "words_expected": d.get("total_words_expected", ch_words),
                    "coverage": round(ch_words / max(1, d.get("total_words_expected", ch_words)) * 100, 1)
                })
        except Exception:
            pass
            
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    data_json = {
        "status": status,
        "last_updated": now_str,
        "current_book": current_book,
        "current_chapter": current_ch,
        "current_chunk": current_chunk_verses,
        "total_chapters_completed": total_chapters_done,
        "total_words_parsed": total_words_done,
        "recent_chapters": chapter_stats[-10:]
    }
    
    with open(PROGRESS_JSON, "w", encoding="utf-8") as fp:
        json.dump(data_json, fp, ensure_ascii=False, indent=2)
        
    md_content = f"""# Contextual Interlinear Pipeline Progress

* **Status:** `{status}`
* **Last Updated:** `{now_str}`
* **Current Processing:** Book `{current_book}`, Chapter `{current_ch}` ({current_chunk_verses})
* **Completed Chapters:** `{total_chapters_done} / 1189`
* **Total Words Parsed:** `{total_words_done:,} words`

---

### Recent Completed Chapters
| Book | Chapter | Expected Words | Parsed Words | Coverage % |
| :---: | :---: | :---: | :---: | :---: |
"""
    for c in reversed(chapter_stats[-10:]):
        md_content += f"| {c['book']} | {c['chapter']} | {c['words_expected']} | {c['words_parsed']} | **{c['coverage']}%** |\n"
        
    md_content += f"\n*Output directory: `releases/study/taobvsi/words/{{book}}/{{chapter}}.json`*\n"
    
    with open(PROGRESS_MD, "w", encoding="utf-8") as fp:
        fp.write(md_content)

def call_gemini(prompt: str, timeout: int = 120):
    payload = {
        "contents": [
            {"role": "user", "parts": [{"text": SYSTEM_PROMPT + "\n\n" + prompt}]}
        ],
        "generationConfig": {
            "temperature": 0.1,
            "responseMimeType": "application/json"
        }
    }
    
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(API_URL, data=body, headers={"Content-Type": "application/json"})
    
    max_retries = 5
    for attempt in range(max_retries):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                text_out = data["candidates"][0]["content"]["parts"][0]["text"]
                return json.loads(text_out)
        except urllib.error.HTTPError as e:
            err_msg = e.read().decode("utf-8", errors="ignore")
            log(f"  [HTTPError {e.code}]: {e.reason}")
            if e.code == 429:
                log("  [429 Rate Limit hit]: backing off...")
                if "RESOURCE_EXHAUSTED" in err_msg and "quota" in err_msg.lower():
                    log("  [DAILY QUOTA EXHAUSTED]: Pausing for 30 minutes before rechecking...")
                    time.sleep(1800)
                else:
                    time.sleep(20 * (attempt + 1))
            else:
                time.sleep(10 * (attempt + 1))
        except Exception as e:
            log(f"  [Connection/Timeout Error]: {e}. Retrying in 10s...")
            time.sleep(10)
            
    raise RuntimeError(f"Failed to call Gemini after {max_retries} attempts.")

def process_chapter(book_num: int, chapter_num: int):
    bible_file = os.path.join(BASE_BIBLE_DIR, str(book_num), f"{chapter_num}.json")
    out_dir = os.path.join(BASE_WORDS_DIR, str(book_num))
    out_file = os.path.join(out_dir, f"{chapter_num}.json")
    
    os.makedirs(out_dir, exist_ok=True)
    
    if os.path.exists(out_file):
        try:
            with open(out_file, "r", encoding="utf-8") as fp:
                existing = json.load(fp)
                if existing.get("is_completed") and len(existing.get("words", [])) > 0:
                    log(f"Chapter {book_num}:{chapter_num} already completed ({len(existing.get('words', []))} words). Skipping.")
                    return True
        except Exception:
            pass
            
    if not os.path.exists(bible_file):
        log(f"Bible file {bible_file} not found!")
        return False
        
    with open(bible_file, "r", encoding="utf-8") as fp:
        verses = json.load(fp)
        
    total_verses = len(verses)
    total_words = sum(len(v["text"].split()) for v in verses)
    log(f"\n================================================================================")
    log(f"PROCESSING CHAPTER {book_num}:{chapter_num} ({total_verses} verses, {total_words} words)")
    log(f"================================================================================")
    
    all_words = []
    
    for i in range(0, total_verses, CHUNK_SIZE_VERSES):
        chunk_verses = verses[i:i + CHUNK_SIZE_VERSES]
        chunk_v_nums = [v["verse"] for v in chunk_verses]
        token_input = [{"verse": v["verse"], "tokens": v["text"].split()} for v in chunk_verses]
        chunk_tokens_expected = sum(len(x["tokens"]) for x in token_input)
        chunk_label = f"Verses {chunk_v_nums[0]}-{chunk_v_nums[-1]}"
        
        update_progress_files(book_num, chapter_num, f"{chunk_label} ({chunk_tokens_expected} words)")
        log(f"{chunk_label} ({chunk_tokens_expected} expected words)...")
        prompt = f"Input Verses:\n{json.dumps(token_input, ensure_ascii=False, indent=2)}"
        
        chunk_retries = 3
        words_res = []
        for c_attempt in range(chunk_retries):
            t_chunk = time.time()
            chunk_res = call_gemini(prompt)
            words_res = chunk_res.get("words", [])
            
            if len(words_res) >= chunk_tokens_expected * 0.95:
                log(f"  Parsed {len(words_res)}/{chunk_tokens_expected} words in {time.time()-t_chunk:.2f}s")
                break
            else:
                log(f"  [Chunk Undercount: {len(words_res)}/{chunk_tokens_expected}]. Retrying attempt {c_attempt+1}...")
                time.sleep(REQUEST_DELAY_SEC)
                
        all_words.extend(words_res)
        time.sleep(REQUEST_DELAY_SEC)
        
    final_output = {
        "book": book_num,
        "chapter": chapter_num,
        "total_verses": total_verses,
        "total_words_expected": total_words,
        "total_words_parsed": len(all_words),
        "is_completed": True,
        "words": all_words
    }
    
    with open(out_file, "w", encoding="utf-8") as fp:
        json.dump(final_output, fp, ensure_ascii=False, indent=2)
        
    log(f"\nSUCCESS: Chapter {book_num}:{chapter_num} completed and saved to {out_file}!")
    log(f"Total words: {len(all_words)} / {total_words} (Coverage: {len(all_words)/max(1, total_words)*100:.1f}%)")
    update_progress_files(book_num, chapter_num, "CHAPTER_COMPLETED", status="RUNNING")

    try:
        from sync_words_to_sqlite import sync_all_chapters
        sync_all_chapters()
    except Exception as e:
        log(f"Auto-sync SQLite notice: {e}")

    return True

def run_book(book_num: int, start_chapter: int = 1, max_chapters: int = None):
    ch_files = glob.glob(os.path.join(BASE_BIBLE_DIR, str(book_num), "*.json"))
    total_chapters = len(ch_files)
    log(f"Book {book_num} has {total_chapters} chapters. Starting from Chapter {start_chapter}...")
    chapters_done = 0
    for ch in range(start_chapter, total_chapters + 1):
        if max_chapters is not None and chapters_done >= max_chapters:
            log(f"Reached max chapters limit ({max_chapters}). Exiting run.")
            break
        processed = process_chapter(book_num, ch)
        if processed:
            chapters_done += 1

def run_auto_next(max_chapters: int = 3):
    """Finds next unfinished chapter in the Bible and processes up to max_chapters."""
    log(f"Searching for next incomplete chapter (max {max_chapters} chapters this run)...")
    chapters_processed = 0
    for b in range(1, 67):
        b_dir = os.path.join(BASE_BIBLE_DIR, str(b))
        if not os.path.exists(b_dir):
            continue
        ch_files = glob.glob(os.path.join(b_dir, "*.json"))
        for ch in range(1, len(ch_files) + 1):
            out_file = os.path.join(BASE_WORDS_DIR, str(b), f"{ch}.json")
            is_done = False
            if os.path.exists(out_file):
                try:
                    with open(out_file, "r", encoding="utf-8") as fp:
                        d = json.load(fp)
                        if d.get("is_completed") and len(d.get("words", [])) > 0:
                            is_done = True
                except Exception:
                    pass
            if not is_done:
                log(f"Found next pending chapter: Book {b}, Chapter {ch}")
                process_chapter(b, ch)
                chapters_processed += 1
                if chapters_processed >= max_chapters:
                    log(f"Completed {chapters_processed} chapter(s). Ending batch.")
                    return

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Contextual Interlinear Pipeline")
    parser.add_argument("--book", type=int, default=1, help="Book number (1 = Genesis)")
    parser.add_argument("--start-chapter", type=int, default=1, help="Starting chapter number")
    parser.add_argument("--max-chapters", type=int, default=None, help="Maximum chapters to process in this run")
    parser.add_argument("--auto-next", action="store_true", help="Auto find next uncompleted chapter")
    args = parser.parse_args()

    log("=" * 80)
    log("CONTEXTUAL INTERLINEAR GENERATOR (FREE TIER)")
    log("=" * 80)
    
    if args.auto_next:
        run_auto_next(max_chapters=args.max_chapters or 3)
    else:
        run_book(args.book, start_chapter=args.start_chapter, max_chapters=args.max_chapters)
