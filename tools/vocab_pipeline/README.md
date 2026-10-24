# Protestant Tamil Bible Vocabulary Builder Pipeline

Sequential normalized vocabulary builder and contextual lexicon engine for the Protestant Classical Tamil Bible (TAOVBSI - பரிசுத்த வேதாகமம்).

---

## 1. Architecture Overview

### Normalized 2-Table Schema (`taobvsi_glossary.sqlite`)
1. **`unique_words`** (~95,000 distinct surface words):
   * `(id, surface_form, pos, canonical, modern_equivalent, english_word, definition_ta, created_at)`
   * Unique constraint: `UNIQUE(surface_form, pos)`
   * Zero redundancy: Each distinct word form in context is defined **only once**.
2. **`verse_tokens`** (418,550 occurrences):
   * `(book, chapter, verse, word_index, raw_token, word_id)`
   * Lean integer foreign key referencing `unique_words(id)`.
   * Preserves exact verse punctuation and flow.

### Outputs
* **SQLite Database**: `releases/study/taobvsi/taobvsi_glossary.sqlite`
* **Consolidated CSV**: `releases/study/taobvsi/taobvsi_verse_words.csv` (joins both tables in sequential order for human auditing)
* **Per-Chapter JSON**: `releases/study/taobvsi/words/{book}/{chapter}.json`
* **Live Dashboard**: `releases/study/taobvsi/WORDS_PROGRESS.md` (refreshed every 5s)

---

## 2. Hardware Acceleration: Intel Arc GPU (Vulkan)

For PCs with an **Intel Arc GPU** (e.g. Intel Core Ultra with Arc Pro Graphics), Ollama's standard Windows launcher falls back to CPU due to a DXGI 2 GB virtual aperture reporting bug.

We bypass this limitation using the native **Vulkan 1.4 backend** (`ggml-vulkan.dll`), granting the model access to the **54.4 GB unified system RAM heap**:
* **CPU Evaluation**: ~1.45 tokens/second
* **Intel Arc Vulkan Evaluation**: **~6.30 tokens/second (4.3x speedup)**

### Starting the Intel Arc Vulkan Server
```powershell
powershell -ExecutionPolicy Bypass -File tools/vocab_pipeline/start_arc_vulkan_server.ps1
```
*(Or double-click `tools/vocab_pipeline/start_arc_vulkan_server.bat`)*.

See detailed documentation in [INTEL_ARC_VULKAN_ACCELERATION.md](file:///d:/Projects/Christian-Tube/tools/vocab_pipeline/INTEL_ARC_VULKAN_ACCELERATION.md).

---

## 3. Running the Vocabulary Processor

The processor auto-detects whether you are running standard Ollama or the high-speed Intel Arc Vulkan server:

### Direct Python Execution
```powershell
python tools/vocab_pipeline/bible_vocab_processor.py --start-book 1 --start-chapter 1
```

### Export Consolidated CSV Only
To re-generate or audit the consolidated CSV from the SQLite database:
```powershell
python tools/vocab_pipeline/bible_vocab_processor.py --export-csv-only
```

### Running with Docker Compose
```bash
docker compose -f tools/vocab_pipeline/docker-compose.yml up -d --build
```
To view live logs:
```bash
docker compose -f tools/vocab_pipeline/docker-compose.yml logs -f
```

---

## 4. Real-Time Tracking
The processor maintains a real-time Markdown dashboard in `releases/study/taobvsi/WORDS_PROGRESS.md` tracking:
* Completed chapters and verses
* Unique surface words defined vs total target (95,634)
* Compounding cache hit rate (0ms instant resolution)
* Accurate remaining ETA based on the Unique Word Model
