# AI Bible Study Generator (`tools/spek`)

A unified, local-LLM pipeline that produces three Bible-study assets per
chapter, writing **directly to the canonical release locations**:

| Pass | What it produces | Output |
| --- | --- | --- |
| `feed` | Meditation-worthy verse ranges (sentence-unit verdicts) | `releases/scriptures.json` + `apps/backend/data/scriptures.json` |
| `study` | High-value concepts/terms, classical **TAOVBSI Tamil** definitions | `releases/study/<version>/` + compiled SQLite |
| `spek` | Per-verse **SPECK** (S/P/E/C/K) + bilingual glossary + context | `releases/spek/<version>/` + compiled SQLite |

It supersedes `tools/bible_study` (study concepts) and
`tool/analyze_scripture_feed.py` (feed analysis). Chunking the feed into
`releases/words_feed/` still delegates to `tool/chunk_web_assets.js`.

## Requirements

- Node.js 24+ (uses `node:sqlite`)
- [Ollama](https://ollama.com) running locally with a model (default
  `qwen2.5:7b`; production target `qwen3:14b` — set in `config.yaml`)

## Setup

```sh
npm install
npm run inspect   # verifies Bible sources + output paths
npm run test:dry  # Genesis 1–5, dry-run (no LLM, no writes)
npm run test:unit # pure-logic unit tests
```

## Usage

```sh
npm run run -- --book 1 --chapter 1            # single chapter (all 3 passes)
npm run run -- --book 5                        # whole book
npm run book -- 19                             # Psalms (book number/name)
npm run resume                                  # crash-safe resume
npm run feed -- --all                           # re-emit scriptures.json from cache
npm run compile                                 # build study + spek SQLite databases
npm run chunk                                   # regenerate words_feed/
npm run review                                  # query the compiled SPEK DB
```

Run long batches with `npx tsx src/cli.ts run --all --passes feed,study`.
Progress is tracked per chapter in `status.json` under each pass output dir;
interrupted runs can be resumed.

## Configuration

Everything lives in `config.yaml`:

- `bible_source_dirs` — per-pass source Bible versions (canonical
  `releases/bibles/<version>/` layout)
- `passes.*.source_version` — which version feeds each pass
- `llm.ollama` — model, temperature, retries, timeouts
- `research` — `none | duckduckgo | opencode` grounding for the SPEK pass
- `processing.dry_run` — global dry-run flag

## Publishing discipline

Any data written under `releases/` and committed must be accompanied by a
`revision` bump in `releases/manifest.json` (see AGENTS.md — installs cache
assets by URL and will otherwise serve stale bytes).

## Tests

- `npm run test:unit` — ported feed partitioning, verdict normalization,
  JSON/schema validation
- `npm run test:dry` — full CLI integration smoke test (Genesis 1–5, dry-run)