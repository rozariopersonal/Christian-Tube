import fs from 'fs';
import path from 'path';
import { ZodType } from 'zod';
import { AppConfig, FeedBatchResponse, FeedBatchResponseSchema, FeedPassage, InputChapter, ScriptureRecord } from './types.js';
import { OllamaStudyClient } from './ollama_client.js';
import { passDirs } from './config.js';

// ---------------------------------------------------------------------------
// Sentence-unit partitioning (identical logic to tool/analyze_scripture_feed.py)
// ---------------------------------------------------------------------------

const SENTENCE_ENDINGS = new Set(['.', '?', '!']);

function endsSentence(text: string): boolean {
  let t = text.trimEnd();
  while (t && "\"')]}".includes(t[t.length - 1])) {
    t = t.slice(0, -1).trimEnd();
  }
  return t.length > 0 && SENTENCE_ENDINGS.has(t[t.length - 1]);
}

function clauseEnd(text: string): boolean {
  let t = text.trimEnd();
  while (t && "\"')]}".includes(t[t.length - 1])) {
    t = t.slice(0, -1).trimEnd();
  }
  return t.length > 0 && (t[t.length - 1] === ':' || t[t.length - 1] === ';');
}

/** Partitions a chapter's verses into sentence-complete units (1 full thought each). */
export function makeSentenceUnits(input: InputChapter, maxSpan = 5): Array<{ start: number; end: number }> {
  const verses = input.verses;
  const units: Array<{ start: number; end: number }> = [];
  let i = 0;
  const n = verses.length;
  while (i < n) {
    let j = i;
    while (j < n && !endsSentence(verses[j].text)) j++;
    if (j >= n) {
      j = n - 1;
    } else if (j - i + 1 > maxSpan) {
      let cut = -1;
      const limit = Math.min(j, i + maxSpan - 1);
      for (let k = i + 1; k <= limit; k++) {
        if (clauseEnd(verses[k].text)) cut = k;
      }
      if (cut > i) j = cut;
      else j = i + maxSpan - 1;
    }
    units.push({ start: verses[i].verse, end: verses[j].verse });
    i = j + 1;
  }
  return units;
}

// ---------------------------------------------------------------------------
// Category taxonomy (from analyze_scripture_feed.py)
// ---------------------------------------------------------------------------

export const FEED_CATEGORIES = [
  'words_of_god', 'jesus_words', 'prophecy', 'promise', 'commandment',
  'wisdom', 'doctrine', 'comfort', 'warning', 'prayer', 'praise', 'parable',
  'salvation', 'divine_action', 'consecration',
];
const SPECK_TAGS = ['S', 'P', 'E', 'C', 'K'];
const BG_PRESETS = ['mountain_dawn', 'ocean_calm', 'desert_dusk', 'forest_sun', 'starry_night'];

export function renderUnits(units: Array<{ start: number; end: number; verses: InputChapter['verses'] }>): string {
  return units
    .map((u, i) => {
      const joined = u.verses.map((v) => v.text).join(' ');
      return `U${i + 1}. [verses ${u.start}-${u.end}] ${joined}`;
    })
    .join('\n');
}

export function normalizeFeedVerdicts(
  raw: FeedBatchResponse,
  units: Array<{ start: number; end: number }>
): FeedPassage[] {
  const expected = units.length;
  const verdicts = (raw.verdicts || []).filter((v) => v && typeof v === 'object');
  const gotIds = verdicts.map((v) => v.id);
  const unique = new Set(gotIds);
  if (gotIds.length !== expected || unique.size !== expected) {
    throw new Error(`Coverage: got ${gotIds.length} verdicts (${unique.size} unique), expected ${expected}`);
  }
  for (const id of gotIds) {
    if (typeof id !== 'number' || id < 1 || id > expected) {
      throw new Error(`Coverage: invalid id ${id}`);
    }
  }
  const out: FeedPassage[] = [];
  for (const v of verdicts) {
    const u = units[v.id - 1];
    if (!u) continue;
    if (!v.include) continue;
    let category = String(v.category || '').trim().toLowerCase().replace(/\s+/g, '_');
    if (!FEED_CATEGORIES.includes(category)) continue;
    const theme = String(v.theme || '').trim().slice(0, 80);
    const speck: string[] = [];
    for (const letter of v.speck || []) {
      const s = String(letter).trim().toUpperCase();
      if (SPECK_TAGS.includes(s) && !speck.includes(s)) speck.push(s);
    }
    out.push({ book: 0, bookName: '', chapter: 0, start: u.start, end: u.end, category, theme, speck });
  }
  return out;
}

// ---------------------------------------------------------------------------
// FeedAnalyzer — per-chapter verdict extraction + scriptures.json emit
// ---------------------------------------------------------------------------

export class FeedAnalyzer {
  private config: AppConfig;
  private llm: OllamaStudyClient;
  private cacheDir: string;

  constructor(config: AppConfig, llm: OllamaStudyClient) {
    this.config = config;
    this.llm = llm;
    this.cacheDir = passDirs(config).feed.cacheDir;
    fs.mkdirSync(this.cacheDir, { recursive: true });
  }

  private cachePath(book: number, chapter: number): string {
    return path.join(this.cacheDir, `b${String(book).padStart(2, '0')}_c${String(chapter).padStart(3, '0')}.json`);
  }

  private loadCache(book: number, chapter: number): FeedPassage[] | null {
    const p = this.cachePath(book, chapter);
    if (!fs.existsSync(p)) return null;
    try {
      return JSON.parse(fs.readFileSync(p, 'utf8')) as FeedPassage[];
    } catch {
      return null;
    }
  }

  private writeCache(book: number, chapter: number, passages: FeedPassage[]): void {
    const tmp = `${this.cachePath(book, chapter)}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(passages), 'utf8');
    fs.renameSync(tmp, this.cachePath(book, chapter));
  }

  /**
   * Analyzes one chapter (batch verdicts over its sentence units).
   * Returns 'cached' | 'completed' | 'failed' | 'empty'.
   */
  public async analyzeChapter(
    input: InputChapter,
    bookName: string,
    force = false
  ): Promise<'cached' | 'completed' | 'failed' | 'empty'> {
    if (!force) {
      const cached = this.loadCache(input.book, input.chapter);
      if (cached) return 'cached';
    }

    const flagged = makeSentenceUnits(input);
    const units = flagged.map((u) => ({
      start: u.start,
      end: u.end,
      verses: input.verses.filter((v) => v.verse >= u.start && v.verse <= u.end),
    }));

    if (units.length === 0) {
      this.writeCache(input.book, input.chapter, []);
      return 'empty';
    }

    const batchUnits = this.config.passes.feed.batch_units;
    const passages: FeedPassage[] = [];
    let lastError: Error | null = null;

    for (let ui = 0; ui < units.length; ui += batchUnits) {
      const batch = units.slice(ui, ui + batchUnits);
      const user = [
        `Bible reference: ${bookName} ${input.chapter}`,
        '',
        'Sentence units to judge, one verdict each (you must cover EVERY unit):',
        renderUnits(batch),
        '',
        'Return one JSON verdict per unit as instructed.',
      ].join('\n');

      let batchPasses: FeedPassage[] | null = null;
      for (let attempt = 1; attempt <= this.config.passes.feed.max_retries; attempt++) {
        try {
          const { data } = await this.llm.generate<FeedBatchResponse>(
            this.llm.getSystemPrompt('feed'),
            user,
            FeedBatchResponseSchema as unknown as ZodType<FeedBatchResponse>,
            { numCtx: this.config.passes.feed.num_ctx }
          );
          batchPasses = normalizeFeedVerdicts(data, batch);
          break;
        } catch (err: any) {
          lastError = err;
          console.warn(`[Feed] ${bookName} ${input.chapter} units ${batch[0].start}-${batch[batch.length - 1].end} attempt ${attempt}/${this.config.passes.feed.max_retries} failed: ${err.message}`);
          if (attempt === this.config.passes.feed.max_retries) {
            return 'failed';
          }
        }
      }

      if (batchPasses) {
        for (const p of batchPasses) {
          p.book = input.book;
          p.bookName = bookName;
          p.chapter = input.chapter;
        }
        passages.push(...batchPasses);
      }
    }

    const sorted = passages.sort((a, b) => a.start - b.start || a.end - b.end);
    this.writeCache(input.book, input.chapter, sorted);
    return 'completed';
  }

  // ---------------------------------------------------------------------------
  // Emission
  // ---------------------------------------------------------------------------

  private referenceLabel(book: number, chapter: number, start: number, end: number, name: string): string {
    return `${name} ${chapter}:${start}` + (end !== start ? `-${end}` : '');
  }

  /** Gathers all cached chapter analyses and writes scriptures.json (canonical + backend mirror). */
  public emitScripture(
    bookNames: Record<number, string>,
    dryRun: boolean,
    opts?: { allowPartial?: boolean; expectedChapters?: number }
  ): ScriptureRecord[] {
    const expected = opts?.expectedChapters ?? 1189;
    if (!opts?.allowPartial && this.cachedChapters() < expected) {
      throw new Error(
        `Feed emission blocked: only ${this.cachedChapters()} chapters cached (need ${expected}). ` +
        'Run the full feed pass or `feed --all` first to avoid clobbering the canonical scriptures.json.'
      );
    }
    const files = fs.readdirSync(this.cacheDir)
      .filter((f) => /^b\d+_c\d+\.json$/.test(f) && !f.endsWith('.tmp'))
      .sort();
    const rng = seedRandom(0);
    const records: ScriptureRecord[] = [];

    for (const f of files) {
      const m = f.match(/^b(\d+)_c(\d+)/);
      if (!m) continue;
      const book = Number(m[1]);
      let passages: FeedPassage[];
      try {
        passages = JSON.parse(fs.readFileSync(path.join(this.cacheDir, f), 'utf8'));
      } catch {
        continue;
      }
      const name = bookNames[book] || `Book ${book}`;
      for (const pas of passages) {
        records.push({
          engine: 'scripture',
          bookNumber: book,
          bookName: name,
          chapter: pas.chapter,
          startVerse: pas.start,
          endVerse: pas.end,
          referenceLabel: this.referenceLabel(book, pas.chapter, pas.start, pas.end, name),
          verseMappings: {},
          category: pas.category,
          tags: [pas.category, 'meditation', ...(pas.speck || []).map((s) => `speck:${s}`)],
          speck: pas.speck || [],
          theme: pas.theme,
          backgroundPreset: BG_PRESETS[Math.floor(rng() * BG_PRESETS.length)],
          isFeatured: false,
        });
      }
    }

    records.sort((a, b) => a.bookNumber - b.bookNumber || a.chapter - b.chapter || a.startVerse - b.startVerse);

    if (dryRun) {
      console.log(`[Feed] dry-run: would write ${records.length} records.`);
      return records;
    }

    const dirs = passDirs(this.config);
    fs.mkdirSync(path.dirname(dirs.feed.chapFile), { recursive: true });
    fs.writeFileSync(dirs.feed.chapFile, JSON.stringify(records, null, 2), 'utf8');
    console.log(`[Feed] Wrote ${records.length} records to ${dirs.feed.chapFile}`);
    if (dirs.feed.mirrorFile && dirs.feed.mirrorFile !== dirs.feed.chapFile) {
      fs.mkdirSync(path.dirname(dirs.feed.mirrorFile), { recursive: true });
      fs.writeFileSync(dirs.feed.mirrorFile, JSON.stringify(records, null, 2), 'utf8');
      console.log(`[Feed] Mirrored to ${dirs.feed.mirrorFile}`);
    }
    return records;
  }

  public cachedChapters(): number {
    if (!fs.existsSync(this.cacheDir)) return 0;
    return fs.readdirSync(this.cacheDir).filter((f) => /^b\d+_c\d+\.json$/.test(f) && !f.endsWith('.tmp')).length;
  }
}

// Deterministic PRNG (LCG) — mirrors the python tool's fixed seed behavior.
function seedRandom(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state * 1664525 + 1013904223) >>> 0;
    return state / 4294967296;
  };
}