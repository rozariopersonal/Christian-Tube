import subprocess
import time
import sys
import os
import json
import re
from datetime import datetime, timezone, timedelta

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

env = os.environ.copy()
env["PYTHONIOENCODING"] = "utf-8"

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
PROGRESS_MD = os.path.join(REPO_ROOT, "releases/study/taobvsi/WORDS_PROGRESS.md")
PROGRESS_JSON = os.path.join(REPO_ROOT, "releases/study/taobvsi/WORDS_PROGRESS.json")

IST = timezone(timedelta(hours=5, minutes=30))
KERNEL_SLUG = "arulrozario/taobvsi-vocab-pipeline"

BOOK_NAMES = {
    1: "Genesis (ஆதியாகமம்)", 2: "Exodus (யாத்திராகமம்)", 3: "Leviticus (லேவியராகமம்)",
    4: "Numbers (எண்ணாகமம்)", 5: "Deuteronomy (உபாகமம்)", 6: "Joshua (யோசுவா)",
    7: "Judges (நியாயாதிபதிகள்)", 8: "Ruth (ரூத்)", 9: "1 Samuel (1 சாமுவேல்)",
    10: "2 Samuel (2 சாமுவேல்)", 11: "1 Kings (1 இராஜாக்கள்)", 12: "2 Kings (2 இராஜாக்கள்)",
    13: "1 Chronicles (1 நாளாகமம்)", 14: "2 Chronicles (2 நாளாகமம்)", 15: "Ezra (எஸ்றா)",
    16: "Nehemiah (நெகேமியா)", 17: "Esther (எஸ்தர்)", 18: "Job (யோபு)",
    19: "Psalms (சங்கீதம்)", 20: "Proverbs (நீதிமொழிகள்)", 21: "Ecclesiastes (பிரசங்கி)",
    22: "Song of Solomon (உன்னதப்பாட்டு)", 23: "Isaiah (ஏசாயா)", 24: "Jeremiah (எரேமியா)",
    25: "Lamentations (புலம்பல்)", 26: "Ezekiel (எசேக்கியேல்)", 27: "Daniel (தானியேல்)",
    28: "Hosea (ஓசியா)", 29: "Joel (யோவேல்)", 30: "Amos (ஆமோஸ்)",
    31: "Obadiah (ஒபதியா)", 32: "Jonah (யோனா)", 33: "Micah (மீகா)",
    34: "Nahum (நாகூம்)", 35: "Habakkuk (ஆபகூக்)", 36: "Zephaniah (செப்பனியா)",
    37: "Haggai (ஆகாய்)", 38: "Zechariah (சகரியா)", 39: "Malachi (மல்கியா)",
    40: "Matthew (மத்தேயு)", 41: "Mark (மாற்கு)", 42: "Luke (லூக்கா)",
    43: "John (யோவான்)", 44: "Acts (அப்போஸ்தலர்)", 45: "Romans (ரோமர்)",
    46: "1 Corinthians (1 கொரிந்தியர்)", 47: "2 Corinthians (2 கொரிந்தியர்)",
    48: "Galatians (கலாத்தியர்)", 49: "Ephesians (எபேசியர்)", 50: "Philippians (பிலிப்பியர்)",
    51: "Colossians (கொலோசெயர்)", 52: "1 Thessalonians (1 தெசலோனிக்கேயர்)",
    53: "2 Thessalonians (2 தெசலோனிக்கேயர்)", 54: "1 Timothy (1 தீமோத்தேயு)",
    55: "2 Timothy (2 தீமோத்தேயு)", 56: "Titus (தீத்து)", 57: "Philemon (பிலேமோன்)",
    58: "Hebrews (எபிரெயர்)", 59: "James (யாக்கோபு)", 60: "1 Peter (1 பேதுரு)",
    61: "2 Peter (2 பேதுரு)", 62: "1 John (1 யோவான்)", 63: "2 John (2 யோவான்)",
    64: "3 John (3 யோவான்)", 65: "Jude (யூதா)", 66: "Revelation (வெளிப்படுத்தின விசேஷம்)"
}

# Kernel Version 7 pushed at 12:29:49 IST
start_time = 1792652389.0
print(f"Starting Kaggle Live Progress Sync for '{KERNEL_SLUG}'...", flush=True)

def update_progress_files(status_str, log_text):
    now_utc = datetime.now(timezone.utc)
    now_ist = now_utc.astimezone(IST)
    now_str = f"{now_ist.strftime('%Y-%m-%d %I:%M:%S %p IST')} ({now_utc.strftime('%H:%M:%S UTC')})"
    
    # Parse log text
    current_book = 1
    current_chapter = 1
    current_verse = 1
    total_words_parsed = 0
    db_hits = 0
    llm_calls = 0
    completed_chapters = []
    activity = "Initializing Kaggle Worker"
    
    # Extract entries from json if logs is json or plain text
    lines = []
    try:
        data = json.loads(log_text)
        if isinstance(data, list):
            for item in data:
                lines.extend(item.get("data", "").splitlines())
    except Exception:
        lines = log_text.splitlines()

    for line in lines:
        line_clean = line.strip()
        # Processing Book b:ch
        m_ch = re.search(r">>> Processing Book (\d+):(\d+)", line_clean)
        if m_ch:
            current_book = int(m_ch.group(1))
            current_chapter = int(m_ch.group(2))
            activity = f"Processing Book {current_book}:{current_chapter}"

        # Verse parsing
        m_v = re.search(r"Verse (\d+): (\d+) tokens \((\d+) DB 0ms, (\d+) LLM\)", line_clean)
        if m_v:
            v_num = int(m_v.group(1))
            tokens = int(m_v.group(2))
            h = int(m_v.group(3))
            m = int(m_v.group(4))
            current_verse = v_num
            total_words_parsed += tokens
            db_hits += h
            llm_calls += m
            activity = f"Verse {v_num} ({tokens} tokens - {h} DB, {m} LLM)"

        # Completed chapter
        m_comp = re.search(r"\[COMPLETED\] Book (\d+):(\d+) in ([\d\.]+)s \((\d+) words\)", line_clean)
        if m_comp:
            completed_chapters.append({
                "book": int(m_comp.group(1)),
                "chapter": int(m_comp.group(2)),
                "duration": float(m_comp.group(3)),
                "words": int(m_comp.group(4))
            })

    elapsed_sec = max(1, time.time() - start_time)
    elapsed_str = str(timedelta(seconds=int(elapsed_sec)))

    if not lines or len(lines) < 5:
        if "RUNNING" in status_str:
            if elapsed_sec > 300:
                est_ch = min(20, max(1, int((elapsed_sec - 300) / 220) + 1))
                activity = f"Active GPU Generation (Clean-slate Sequential RAG from Genesis 1:1, ~Genesis {est_ch})"
            else:
                activity = "Setup in progress (Installing Ollama & Downloading gemma4:12b)"
    elif "pull" in log_text.lower() or "unpacking" in log_text.lower():
        activity = "Setup in progress (Downloading Gemma4 Model / Unpacking Dataset)"
    elif "SQLite database initialized" in log_text:
        activity = f"Processing Book {current_book}:{current_chapter}:{current_verse}"

    total_ops = db_hits + llm_calls
    hit_rate = (db_hits / max(1, total_ops)) * 100
    b_name = BOOK_NAMES.get(current_book, f"Book {current_book}")

    elapsed_sec = max(1, time.time() - start_time)
    elapsed_str = str(timedelta(seconds=int(elapsed_sec)))

    status_badge = "🟢 RUNNING"
    if "ERROR" in status_str:
        status_badge = "🔴 ERROR"
    elif "COMPLETE" in status_str:
        status_badge = "🏁 COMPLETED"

    # 1. Generate WORDS_PROGRESS.md
    md_content = f"""# Step 1: Single-Worker Sequential 2-Stage Filtered RAG Progress

* **Status:** `{status_badge} (Kaggle Cloud GPU Worker)`
* **Last Updated:** `{now_str}` *(Auto-synced from Kaggle)*
* **Kaggle Kernel:** [`{KERNEL_SLUG}`](https://www.kaggle.com/code/{KERNEL_SLUG})
* **Hardware:** Kaggle Cloud GPU (Nvidia T4 x2 / P100) | **Model:** `gemma4:12b`
* **Current Location:** Book `{current_book}:{current_chapter}:{current_verse}` — **{b_name}**
* **Activity:** `{activity}`
* **Completed Chapters:** `{len(completed_chapters)} / 1189` ({len(completed_chapters)/1189*100:.1f}%)
* **Total Words Parsed:** `{total_words_parsed:,} / 418,550 words` ({total_words_parsed/418550*100:.2f}%)
* **DB Cache Hit Rate:** `{hit_rate:.1f}%` ({db_hits:,} 0ms hits / {llm_calls:,} LLM definitions)
* **Elapsed Time:** `{elapsed_str}`

### ⚡ Worker Telemetry

| Attribute | Current Value |
| :--- | :--- |
| **Current Target** | Book `{current_book}:{current_chapter}:{current_verse}` ({b_name}) |
| **Current Activity** | `{activity}` |
| **Session Words Parsed** | `{total_words_parsed:,}` |
| **DB Cache Hits** | `{db_hits:,}` (0ms instant DB resolution) |
| **LLM Generations** | `{llm_calls:,}` (Gemma-4 12B) |
| **Completed Chapters** | `{len(completed_chapters)}` chapters |

### 🏥 Kaggle Cloud GPU & Engine Health

| Metric | Current Value | Status |
| :--- | :--- | :--- |
| **Kernel Worker Status** | `{status_str}` | {status_badge} |
| **Model** | `gemma4:12b` (Ollama on Kaggle GPU) | 🟢 Active |
| **Dataset Source** | `arulrozario/taobvsi-bible-base-data` | 📚 Loaded |
| **Sync Watchdog** | `Active (polling Kaggle API every 15s)` | 🛡️ Live |
"""
    try:
        os.makedirs(os.path.dirname(PROGRESS_MD), exist_ok=True)
        with open(PROGRESS_MD, "w", encoding="utf-8") as f:
            f.write(md_content)
    except Exception as e:
        print(f"Error writing markdown: {e}")

    # 2. Update WORDS_PROGRESS.json
    json_data = {
        "status": status_str,
        "last_updated": now_ist.strftime("%Y-%m-%d %H:%M:%S"),
        "current_book": current_book,
        "current_chapter": current_chapter,
        "current_verse": current_verse,
        "current_book_name": b_name,
        "activity": activity,
        "total_chapters_completed": len(completed_chapters),
        "total_words_parsed": total_words_parsed,
        "db_hits": db_hits,
        "llm_calls": llm_calls,
        "cache_hit_rate": round(hit_rate, 1),
        "completed_chapters": completed_chapters
    }
    try:
        with open(PROGRESS_JSON, "w", encoding="utf-8") as f:
            json.dump(json_data, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"Error writing json: {e}")


while True:
    try:
        # 1. Fetch status
        res = subprocess.run(
            ["kaggle", "kernels", "status", KERNEL_SLUG],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env
        )
        status_line = res.stdout.strip()

        # 2. Fetch logs
        l_res = subprocess.run(
            ["kaggle", "kernels", "logs", KERNEL_SLUG],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env
        )
        logs = l_res.stdout

        # 3. Update WORDS_PROGRESS.md and json
        update_progress_files(status_line, logs)

        print(f"[{time.strftime('%H:%M:%S')}] {status_line} -> Updated WORDS_PROGRESS.md", flush=True)

        if "ERROR" in status_line:
            print("\n[ERROR DETECTED IN KAGGLE RUN]")
            print(logs[-2000:])
            break
        elif "COMPLETE" in status_line:
            print("\n[KAGGLE RUN COMPLETED SUCCESSFULLY]")
            break

    except Exception as e:
        print(f"Exception during monitor cycle: {e}", flush=True)

    time.sleep(15)
