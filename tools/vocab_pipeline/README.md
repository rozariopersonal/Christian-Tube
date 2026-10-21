# Step 1 Contextual Bible RAG Vocabulary Pipeline

Containerized sequential 1-pass sense scanner for the Protestant Classical Tamil Bible (TAOVBSI).

---

## 1. Overview & Strategy

Step 1 processes every verse token sequentially in exact order with 100% complete coverage:
* **Unique Sense Resolution via RAG**: Looks up known senses in `releases/study/taobvsi/taobvsi_glossary.sqlite`. If an existing entry matches the contextual sense of the word, it reuses its entry id, canonical root, and definition. If new or distinct, it generates a new sense entry.
* **Compact, Shippable Fields**:
  - `word`: Exact surface token in verse flow.
  - `canonical`: Base/root Tamil headword.
  - `definition_ta`: Concise 1-sentence Tamil definition.
  - `modern_equivalent`: Everyday spoken/written modern Tamil equivalent.
  - `english_word`: Biblical English equivalent.
* **Decoupled Architecture**:
  - **Step 1 (Now)**: Rapid full-Bible scan with short definitions and modern equivalents (ready for immediate release).
  - **Step 2 (Future)**: Hebrew & Greek Strong's concordance alignment (`strongs`, `original_lemma`).
  - **Step 3 (Future)**: Christ-centered New Covenant devotional expositions.

---

## 2. Running with Docker Compose

Ensure Ollama is running on the host with `gemma4:12b`:
```powershell
$env:OLLAMA_MODELS="D:\models"; ollama serve
```

### Start the Service in Background
```bash
docker compose -f tools/vocab_pipeline/docker-compose.yml up -d --build
```

### View Live Logs
```bash
docker compose -f tools/vocab_pipeline/docker-compose.yml logs -f
```

### Stop the Service
```bash
docker compose -f tools/vocab_pipeline/docker-compose.yml down
```

---

## 3. Real-Time Tracking
Progress is recorded to `releases/study/taobvsi/WORDS_PROGRESS.md` with current book, chapter, verse chunk, and total parsed word count.
