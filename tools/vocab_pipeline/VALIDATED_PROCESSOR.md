# Validated normalized vocabulary processor

`validated_vocab_processor.py` is the normalized, DB-first processor brought forward
from the current local pipeline. The existing processor and cloud/API processors remain separate.
This change does not start a worker, migrate hosted assets, or modify release data.

## Run

From the repository root, with Bible chapter JSON files available in `releases/`:

```powershell
python tools/vocab_pipeline/validated_vocab_processor.py --start-book 1 --start-chapter 1 --end-book 1 --end-chapter 2
```

For a separate trial dataset, set `BIBLE_DIR`, `WORDS_DIR`, `GLOSSARY_SQLITE`,
`CSV_PATH`, `PROGRESS_MD`, and `HEALTH_JSON` to trial paths before running.
The defaults point to the existing `releases/study/taobvsi` dataset. Do not run
multiple writers against those paths. The processor supports Ollama and a local
llama-server at port 8080 using the same model as the current pipeline.

## Response and completion contract

- New words require a recognized POS, canonical root, Tamil definition, modern
  Tamil equivalent, and English translation. Empty or incorrectly typed fields
  are unresolved; they never become placeholder noun entries.
- Cached ambiguous words receive candidate IDs, lemmas, POS, and definitions for
  context. Their responses contain only an occurrence index and selected ID.
  A null/unknown ID remains unresolved, rather than choosing the first candidate.
- Both backends receive a JSON schema. Local validation still checks occurrence
  IDs, duplicate responses, and membership of candidate IDs.
- Each batch has at most three attempts. Valid results survive subsequent
  attempts; only unresolved occurrences are requested again. Repeated words
  remain separate occurrences because their contextual POS can differ.
- Definition requests start with at least 500 output tokens. Unresolved retries
  use smaller groups and larger per-word allowances, capped at 2,000 tokens per
  request, to accommodate Tamil tokenization within the 4K server context.
- Successful definitions are committed even if another word in that verse fails.
  A failed verse is left pending, the run exits with status 1, and completed
  earlier verses remain in an atomic partial checkpoint. Rerunning reuses them.
- A completed chapter must match every source token, in order, with all required
  fields. Old completion markers with blank definitions are invalidated. Only
  complete, source-matched verses can be resumed from old JSON.
- The dashboard counts chapters validated during the current run, including
  validated skips. It no longer infers completion by counting JSON filenames.
- Existing incomplete dictionary entries are repaired in place, preserving IDs
  and verse references. Complete cached definitions are not overwritten.
- CSV is derived from the database once on orderly shutdown (including an
  unresolved chapter), instead of appended during retries. This avoids duplicate
  audit rows and repeated CSV file writes. After abrupt termination, regenerate:

```powershell
python tools/vocab_pipeline/validated_vocab_processor.py --export-csv-only
```

Validation checks structure and coverage. It does not establish linguistic
correctness: expert review of lemma, sense, translation, and Protestant register
is still required. The current `(surface_form, pos)` uniqueness constraint cannot
represent multiple senses with the same POS; candidate rejection safely leaves
such a case pending. Sense-aware storage and model/hardware changes are deferred.

## Verification

```powershell
python -m unittest discover -s tools/vocab_pipeline/tests -v
```

The tests use temporary SQLite databases, miniature source chapters, and mocked
inference responses. They do not contact a model or read/write release assets.
This Python-only suite is the validation boundary for the local processor;
Flutter builds and app navigation tests are outside its scope.

The expected speed gains come from reduced ambiguity output, targeted retries,
and fewer redundant file writes. No end-to-end inference speedup is claimed;
benchmark validated words per minute on a separate reviewed dataset before
switching a running worker to this processor.
