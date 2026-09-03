# AI-Assisted Bible Study Knowledge Base Generator

A high-performance, resumable TypeScript pipeline that extracts theological concepts, lemmas, archaic vocabulary, and original-language Strong's roots from Bible chapters using **Google Gemini 2.5 Flash** (`gemini-2.5-flash`), storing durable chapter outputs as JSON before compiling into an offline SQLite study database for the mobile Bible reader.

---

## 1. Prerequisites (Windows 11)

- **Node.js**: v20+ (Tested on Node.js v24)
- **Google Gemini API Key**: Obtain a key from [Google AI Studio](https://aistudio.google.com/).

### Setup
1. In `tools/bible_study/`:
   ```bash
   cp .env.example .env
   ```
2. Open `.env` and paste your Gemini API key:
   ```env
   GEMINI_API_KEY=AIzaSy...
   ```

---

## 2. Gemini Free Tier Optimizations (15 RPM / 1,500 RPD)

The tool is pre-configured specifically to run safely within the **Google Gemini API Free Tier**:
* **15 RPM Limit (Requests Per Minute)**: Paced automatically with a **4,500ms delay** between chapter requests (`pause_between_requests_ms: 4500`). This ensures a sustained rate of **~10–12 RPM**, safely below the 15 RPM ceiling.
* **1,500 RPD Limit (Requests Per Day)**: Since the entire Bible is **1,189 chapters**, the entire Bible can actually be processed within a single day's free quota.
* **Smart 429 Window Recovery**: If a 429 / Rate Limit error is returned by Google, the client automatically backs off for **25 to 30 seconds** with jitter, allowing the 60-second sliding rate window to clear before retrying.

---

## 3. CLI Commands Reference

All commands can be run from `tools/bible_study/` (or via `npm run study -- <command>` from the project root):

### Inspect Source
Inspects the configured Bible database or JSON chapter source, verifies verse detection, and displays current progress:
```bash
npx tsx src/cli.ts inspect
```

To inspect the compiled SQLite database:
```bash
npx tsx src/cli.ts inspect --compiled
```

### Check Progress & Status
Displays current progress metrics (completed, pending, failed, terms generated):
```bash
npx tsx src/cli.ts status
```

### Test Mode (Genesis 1 to 5)
Processes Genesis chapters 1 to 5 and compiles the test output:
```bash
# Live API test:
npx tsx src/cli.ts test

# Dry-run test (local validation without API calls):
npx tsx src/cli.ts test --dry-run
```

### Process Specific Chapters / Books
```bash
# Process a single chapter (e.g. Genesis 1)
npx tsx src/cli.ts run --book 1 --chapter 1

# Process an entire book (e.g. Genesis - all 50 chapters)
npx tsx src/cli.ts run --book 1

# Force re-processing even if previously completed:
npx tsx src/cli.ts run --book 1 --chapter 1 --force
```

### Process the Entire Bible
Processes all 1,189 chapters of the Bible:
```bash
npx tsx src/cli.ts run --all
```

### Resume After Pause or Interruption
If the process is interrupted (Ctrl+C, power loss, rate limit), restart it anytime:
```bash
npx tsx src/cli.ts resume
```
*It reads `output/<version_id>/status.json` and continues immediately from the next pending chapter with zero duplicate API calls.*

### Compile All Chapter JSONs to SQLite
Compiles all completed chapter JSON files in `output/<version_id>/chapters/` into the consolidated SQLite database:
```bash
npx tsx src/cli.ts compile
```
Output: `output/<version_id>/study_<version_id>.sqlite` (with FTS5 search enabled).

### Terminal Review Tool
Inspect and search extracted concepts directly in the terminal:
```bash
npx tsx src/cli.ts review --term "சிருஷ்டி"
npx tsx src/cli.ts review --importance high
npx tsx src/cli.ts review --category archaic_term
```

### Run Unit Tests
```bash
npx tsx --test tests/normalizer.test.ts tests/validation.test.ts
```

---

## 3. High-Resumability Architecture

```
[TAOVBSI Chapter Input] ──► [Gemini 2.5 Flash] ──► [Zod Schema Validation]
                                                        │
                                                        ▼
                                        `output/ta_ovbsi/chapters/b01_c001.json`
                                                        │
                                                        ▼ (Atomic Update)
                                        `output/ta_ovbsi/status.json`
                                                        │
                                                        ▼ (On demand: 'compile')
                                        `output/ta_ovbsi/study_ta_ovbsi.sqlite`
```

1. **Standalone Chapter Files**: Each chapter is saved to `output/<version_id>/chapters/b{book}_c{chapter}.json`.
2. **Atomic Status Checkpoint**: `status.json` tracks each chapter (`completed`, `failed`, `in_progress`, token metrics).
3. **Decoupled Compilation**: Changing SQLite table schemas or indexes never requires re-running the Gemini API; you simply run `npx tsx src/cli.ts compile` on the saved JSON files.
