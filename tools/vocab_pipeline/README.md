# TAOVBSI Classical Tamil Vocabulary Extraction Pipeline

An automated, fail-safe linguistic pipeline designed to extract **100% of the vocabulary** from the Classical Tamil Bible (TAOVBSI Version), cross-reference it against existing glossary databases, and prepare batch definitions for **DeepSeek-V3**.

---

## 1. Why This Pipeline Was Built

When DeepSeek was previously prompted to read Bible chapters and define words directly, it missed up to **55% of unique vocabulary** due to attention bias, token limits, and selective recall.

This pipeline fixes that by introducing **Deterministic Preprocessing**:
1. **100% Token Coverage:** Python reads every single word in every verse.
2. **Agglutination Normalizer:** Strips case markers (`-ஐ`, `-ஆல்`, `-கு`, `-இல்`, `-உடைய`) and clitics (`-உம்`, `-ஏ`, `-ஓ`), grouping surface variants under their canonical root lemma.
3. **Inverted "Default-to-Keep" Filter:**
   - Drops 764 scraped classical Tamil stopwords (pronouns, conjunctions, particles, auxiliaries).
   - Any borderline word is classified by a local model (Ollama) strictly for `common: true`.
   - **Crucial Rule:** Any word not confirmed as a common filler **defaults to KEEP (definition-worthy)**.
4. **Existing DB Cross-Check:** Automatically connects to `releases/study/taobvsi/taobvsi_glossary.sqlite` to identify words already defined, outputting only the **genuinely missed words** for DeepSeek.

---

## 2. Directory Structure

```
tools/vocab_pipeline/
├── taovbsi_sample.json             # Mock test data (Genesis 1:1-5 & John 3:16)
├── stopwords_scraper.py            # Scrapes high-frequency functional words across the Bible
├── common_stopwords.py             # 764 classical Tamil stopwords (auto-generated)
├── common_words_blacklist.json     # JSON dump of scraped stopwords
├── morphology.py                   # Tamil Unicode cleaner & classical suffix normalizer
├── ollama_filter.py                # Inverted local model tagger (Ollama)
├── pipeline.py                     # Main orchestrator CLI
├── unique_words_with_references.json # Master output with verse tracking
└── missed_words_for_deepseek.json  # Clean payload with verse context for DeepSeek
```

---

## 3. CLI Usage

All commands run from the repository root or inside `tools/vocab_pipeline/`:

### A. Run against the Mock Sample (Genesis 1:1-5 & John 3:16)
```bash
python tools/vocab_pipeline/pipeline.py --sample
```

### B. Run against a Single Book (e.g. Ruth, Book 8)
```bash
python tools/vocab_pipeline/pipeline.py --book 8
```

### C. Run with Local Ollama Linguistic Tagging
```bash
python tools/vocab_pipeline/pipeline.py --sample --ollama --model gemma2:2b
```

### D. Run against the Entire Bible (All 66 Books, 1,189 Chapters)
```bash
python tools/vocab_pipeline/pipeline.py --all
```

### E. Re-scrape Common Stopwords across the Bible
```bash
python tools/vocab_pipeline/stopwords_scraper.py
```
