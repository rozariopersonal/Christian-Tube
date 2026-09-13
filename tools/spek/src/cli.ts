#!/usr/bin/env node
import { Command } from 'commander';
import { execSync } from 'node:child_process';
import fs from 'fs';
import path from 'path';
import { DatabaseSync } from 'node:sqlite';
import { BibleReader } from './bible_reader.js';
import { loadConfig, passDirs, PROJECT_ROOT } from './config.js';
import { OllamaStudyClient } from './ollama_client.js';
import { ChapterProcessor } from './processor.js';
import { StudyDatabaseCompiler, SpekDatabaseCompiler } from './compiler.js';
import { StatusTracker } from './status_tracker.js';

const program = new Command();
program
  .name('spek-analyzer')
  .description('AI Bible Study Generator â€” feed + study + SPECK passes via local Ollama')
  .version('1.0.0');

const TEST_CHAPTERS = [
  { book: 1, chapter: 1 },
  { book: 1, chapter: 2 },
  { book: 1, chapter: 3 },
  { book: 1, chapter: 4 },
  { book: 1, chapter: 5 },
];

// 1. Inspect
program
  .command('inspect')
  .description('Verify Bible sources, outputs, and pass status')
  .option('-c, --config <path>', 'Path to custom config.yaml')
  .action((options) => {
    const config = loadConfig(options.config);
    const dirs = passDirs(config);

    console.log('\n========================================');
    console.log(' AI BIBLE STUDY GENERATOR â€” INSPECT');
    console.log('========================================');
    console.log(`Version id:        ${config.version_id}`);
    console.log(`Language:          ${config.language}`);
    console.log(`LLM:               ${config.llm.ollama.model} @ ${config.llm.ollama.base_url}`);
    console.log(`Enabled passes:    ${new ChapterProcessor(config, new BibleReader(config), new OllamaStudyClient(config)).enabledPasses().join(', ')}`);
    console.log(`Research:          ${config.research.provider}`);

    for (const [key, dir] of Object.entries(config.bible_source_dirs)) {
      const ok = dir && fs.existsSync(dir);
      console.log(`Bible source [${key}]: ${ok ? 'OK' : 'MISSING'} -> ${dir}`);
    }

    console.log(`\nOutputs:`);
    console.log(`  feed    -> ${dirs.feed.chapFile}`);
    console.log(`  study   -> ${dirs.study.baseDir}`);
    console.log(`  spek    -> ${dirs.spek.baseDir}`);
    console.log('========================================\n');
  });

// 2. Status
program
  .command('status')
  .description('Display progress across all passes')
  .option('-c, --config <path>', 'Path to custom config.yaml')
  .action((options) => {
    const config = loadConfig(options.config);
    const dirs = passDirs(config);
    const reader = new BibleReader(config);

    const render = (name: string, tracker: StatusTracker | null) => {
      if (!tracker) return;
      const s = tracker.getSummary();
      const pct = ((s.completed_chapters / s.total_chapters) * 100).toFixed(1);
      console.log(`\n ${name.toUpperCase()} (${s.version_id})`);
      console.log('--------------------------------');
      console.log(`  Completed:  ${s.completed_chapters}/${s.total_chapters} (${pct}%)`);
      console.log(`  Failed:     ${s.failed_chapters}`);
      console.log(`  Pending:    ${s.pending_chapters}`);
      console.log(`  Items:      ${s.total_items}`);
      console.log(`  Updated:    ${s.last_updated}`);
    };

    console.log('\n========================================');
    console.log('  AI BIBLE STUDY GENERATOR â€” STATUS');
    console.log('========================================');

    if (config.passes.feed.enabled) {
      const cached = fs.existsSync(dirs.feed.cacheDir)
        ? fs.readdirSync(dirs.feed.cacheDir).filter((f) => /^b\d+_c\d+\.json$/.test(f)).length
        : 0;
      console.log(`\n FEED (per-chapter cache, ${config.passes.feed.source_version})`);
      console.log('--------------------------------');
      console.log(`  Chapters cached: ${cached} / 1189`);
    }

    render('study', config.passes.study.enabled ? new StatusTracker('study', config.version_id, dirs.study.baseDir) : null);
    render('spek', config.passes.spek.enabled ? new StatusTracker('spek', config.version_id, dirs.spek.baseDir) : null);
    console.log('========================================\n');
  });

// 3. Test (Genesis 1â€“5, all enabled passes)
program
  .command('test')
  .description('Pilot run on Genesis 1 to 5')
  .option('-c, --config <path>', 'Path to custom config.yaml')
  .option('--dry-run', 'Validate wiring only (no LLM calls, no writes)')
  .action(async (options) => {
    const config = loadConfig(options.config);
    if (options.dryRun) config.processing.dry_run = true;
    const reader = new BibleReader(config);
    const llm = new OllamaStudyClient(config);
    const processor = new ChapterProcessor(config, reader, llm);

    console.log('\n[Test Mode] Running Genesis 1 to 5 (passes: ' + processor.enabledPasses().join(', ') + ')...');
    if (config.processing.dry_run) console.log('[Test Mode] DRY-RUN â€” no LLM calls, no writes.\n');

    const res = await processor.processBatch(TEST_CHAPTERS);
    console.log(`\n[Test Mode Complete] Completed: ${res.completed}, Skipped: ${res.skipped}, Failed: ${res.failed}`);

    if (!config.processing.dry_run) {
      await compileAll(config, ['study', 'spek']);
    }
  });

// 4. Books list
program
  .command('books')
  .description('List all 66 books with per-pass status')
  .option('-c, --config <path>', 'Path to custom config.yaml')
  .action((options) => {
    const config = loadConfig(options.config);
    const reader = new BibleReader(config);
    const dirs = passDirs(config);
    const studyTracker = config.passes.study.enabled ? new StatusTracker('study', config.version_id, dirs.study.baseDir) : null;
    const spekTracker = config.passes.spek.enabled ? new StatusTracker('spek', config.version_id, dirs.spek.baseDir) : null;
    const feedCache = dirs.feed.cacheDir;

    console.log('\n #  English              Chaps  Study  Spek   Feed');
    console.log(''.padEnd(60, '-'));

    let tCh = 0, tSt = 0, tSp = 0, tFd = 0;
    for (let b = 1; b <= 66; b++) {
      const book = reader.findBook(b)!;
      let st = 0, sp = 0, fd = 0;
      for (let c = 1; c <= book.chapters; c++) {
        if (studyTracker && studyTracker.isChapterCompleted(b, c)) st++;
        if (spekTracker && spekTracker.isChapterCompleted(b, c)) sp++;
        const f = path.join(feedCache, `b${String(b).padStart(2, '0')}_c${String(c).padStart(3, '0')}.json`);
        if (fs.existsSync(f)) fd++;
      }
      const icon = (n: number, total: number) => (n === total ? 'âœ”' : n > 0 ? 'â—' : 'Â·');
      console.log(
        `${String(b).padStart(2)}  `.padEnd(5) +
        book.nameEn.padEnd(20) +
        String(book.chapters).padEnd(7) +
        `${icon(st, book.chapters)}${st}/${book.chapters}`.padEnd(10) +
        `${icon(sp, book.chapters)}${sp}/${book.chapters}`.padEnd(10) +
        `${icon(fd, book.chapters)}${fd}/${book.chapters}`
      );
      tCh += book.chapters; tSt += st; tSp += sp; tFd += fd;
    }
    console.log(''.padEnd(60, '='));
    console.log(`Total: ${tSt}/${tCh} study, ${tSp}/${tCh} spek, ${tFd}/${tCh} feed chapters\n`);
  });

// 5. Book
program
  .command('book <target>')
  .description('Process all chapters of one book by number (1-66) or name')
  .option('--force', 'Force re-process completed chapters')
  .option('--dry-run', 'Dry run (no LLM calls, no writes)')
  .option('-c, --config <path>', 'Path to custom config.yaml')
  .action(async (target, options) => {
    const config = loadConfig(options.config);
    if (options.dryRun) config.processing.dry_run = true;
    const reader = new BibleReader(config);
    const book = reader.findBook(target);
    if (!book) {
      console.error(`\n[Error] Book "${target}" not found.\n`);
      process.exit(1);
    }

    const processor = new ChapterProcessor(config, reader, new OllamaStudyClient(config));
    console.log(`\nProcessing ${book.bookNumber}. ${book.nameEn} / ${book.nameTa} (${book.chapters} chapters)...\n`);
    const chapters = Array.from({ length: book.chapters }, (_, i) => ({ book: book.bookNumber, chapter: i + 1 }));
    const res = await processor.processBatch(chapters, options.force);
    processor.getStudyTracker()?.updateConsolidatedBook(book.bookNumber);
    processor.getSpekTracker()?.updateConsolidatedBook(book.bookNumber);
    console.log(`\nBook done. Completed: ${res.completed}, Skipped: ${res.skipped}, Failed: ${res.failed}`);
  });

// 6. Run
program
  .command('run')
  .description('Process one chapter, one book, or all 1,189 chapters')
  .option('-b, --book <target>', 'Book number (1-66) or name')
  .option('-c, --chapter <number>', 'Chapter number', parseInt)
  .option('--all', 'Process all 1,189 chapters')
  .option('--pass <passes>', 'Which pass(es): all | feed | study | spek (comma-separated)', 'all')
  .option('--force', 'Force re-process even if completed')
  .option('--dry-run', 'Dry run (no LLM calls, no writes)')
  .option('--config <path>', 'Path to custom config.yaml')
  .action(async (options) => {
    const config = loadConfig(options.config);
    if (options.dryRun) config.processing.dry_run = true;
    applyPassFilter(config, options.pass);
    const reader = new BibleReader(config);
    const processor = new ChapterProcessor(config, reader, new OllamaStudyClient(config));

    if (options.book && options.chapter) {
      const book = reader.findBook(options.book);
      const bNum = book ? book.bookNumber : parseInt(options.book, 10);
      await processor.processChapter(bNum, options.chapter, options.force);
    } else if (options.book) {
      const book = reader.findBook(options.book);
      if (!book) { console.error(`Book "${options.book}" not found.`); process.exit(1); }
      const chapters = Array.from({ length: book.chapters }, (_, i) => ({ book: book.bookNumber, chapter: i + 1 }));
      await processor.processBatch(chapters, options.force);
      processor.getStudyTracker()?.updateConsolidatedBook(book.bookNumber);
      processor.getSpekTracker()?.updateConsolidatedBook(book.bookNumber);
    } else if (options.all) {
      console.log('Processing all 66 books chapter-by-chapter (resumable).\n');
      for (let b = 1; b <= 66; b++) {
        const book = reader.findBook(b)!;
        console.log(`[${b}/66] ${book.nameEn} (${book.chapters} chapters)...`);
        const chapters = Array.from({ length: book.chapters }, (_, i) => ({ book: b, chapter: i + 1 }));
        await processor.processBatch(chapters, options.force);
        processor.getStudyTracker()?.updateConsolidatedBook(b);
        processor.getSpekTracker()?.updateConsolidatedBook(b);
      }
    } else {
      console.log('Specify --book <n>, --chapter <n>, or --all. See --help.');
    }
  });

// 7. Resume
program
  .command('resume')
  .description('Resume unfinished/failed chapters across all passes')
  .option('--pass <passes>', 'Which pass(es): all | feed | study | spek', 'all')
  .option('--config <path>', 'Path to custom config.yaml')
  .action(async (options) => {
    const config = loadConfig(options.config);
    applyPassFilter(config, options.pass);
    const reader = new BibleReader(config);
    const processor = new ChapterProcessor(config, reader, new OllamaStudyClient(config));

    const all = reader.getAllChapters();
    const pending = all.filter(({ book, chapter }) => {
      const studyDone = !config.passes.study.enabled || processor.getStudyTracker()!.isChapterCompleted(book, chapter);
      const spekDone = !config.passes.spek.enabled || processor.getSpekTracker()!.isChapterCompleted(book, chapter);
      return !studyDone || !spekDone;
    });

    console.log(`[Resume] ${pending.length} chapters incomplete. Resuming...`);
    const res = await processor.processBatch(pending, false);
    console.log(`\n[Resume] Completed: ${res.completed}, Skipped: ${res.skipped}, Failed: ${res.failed}`);
  });

// 8. Feed
program
  .command('feed')
  .description('Run only the feed pass (meditation scripture feed)')
  .option('-b, --book <target>', 'Book number or name')
  .option('-c, --chapter <number>', 'Chapter number', parseInt)
  .option('--all', 'All chapters')
  .option('--force', 'Re-analyze cached chapters')
  .option('--dry-run', 'Dry run (no LLM calls)')
  .option('--config <path>', 'Path to custom config.yaml')
  .action(async (options) => {
    const config = loadConfig(options.config);
    config.passes.study.enabled = false;
    config.passes.spek.enabled = false;
    const reader = new BibleReader(config);
    const processor = new ChapterProcessor(config, reader, new OllamaStudyClient(config));

    const chapters = await resolveChapters(reader, options);
    const res = await processor.processBatch(chapters, options.force);
    console.log(`\n[Feed] Completed: ${res.completed}, Skipped: ${res.skipped}, Failed: ${res.failed}`);
    if (!options.dryRun) {
      try {
        processor.emitFeed(false, { allowPartial: !!options.all });
      } catch (err: any) {
        console.warn(`\n[Feed] Emission skipped: ${err.message}`);
      }
    }
    console.log('[Feed] Next: run the words_feed chunker via `spek chunk` (or tool/chunk_web_assets.js).');
  });

// 9. Compile
program
  .command('compile')
  .description('Compile study + spek SQLite databases (and re-emit scriptures.json)')
  .option('--only <which>', 'compile only: study | spek | feed')
  .option('--config <path>', 'Path to custom config.yaml')
  .action(async (options) => {
    const config = loadConfig(options.config);
    const dirs = passDirs(config);

    if (options.only === 'study' || !options.only) await compileAll(config, ['study']);
    if (options.only === 'spek' || !options.only) await compileAll(config, ['spek']);
    if (options.only === 'feed' || !options.only) {
      const processor = new ChapterProcessor(config, new BibleReader(config), new OllamaStudyClient(config));
      try {
        processor.emitFeed(false, { allowPartial: true });
      } catch (err: any) {
        console.warn(`[Compile] Feed emission skipped: ${err.message}`);
      }
    }
    void dirs;
  });

// 10. Review
program
  .command('review')
  .description('Query the compiled study database or spek database')
  .option('-t, --term <query>', 'Search term name / surface form (study)')
  .option('-c, --category <cat>', 'Filter by category')
  .option('-i, --importance <level>', 'Filter by importance (study)')
  .option('-r, --reference <bcv>', 'SPEK lookup: book:chapter:verse (e.g. 1:1:1)')
  .option('--config <path>', 'Path to custom config.yaml')
  .action((options) => {
    const config = loadConfig(options.config);
    const dirs = passDirs(config);

    if (options.reference) {
      const [book, chapter, verse] = options.reference.split(':').map((x: string) => parseInt(x, 10));
      console.log(`\n=== SPEK lookup ${book}:${chapter}:${verse} ===\n`);
      const dbPath = path.join(dirs.spek.baseDir, `spek_${config.version_id}.sqlite`);
      if (!fs.existsSync(dbPath)) {
        console.error('Spek DB not compiled yet. Run `compile`.');
        return;
      }
      const db = new DatabaseSync(dbPath);
      const row = db.prepare(`
        SELECT c.book, c.book_name, c.chapter, v.v, v.speck_json
        FROM verses v JOIN chapters c ON c.id = v.chapter_id
        WHERE c.book = ? AND c.chapter = ? AND v.v = ?
      `).get(book, chapter, verse) as any;
      db.close();
      if (!row) { console.log('Not found.'); return; }
      console.log(`${row.book_name} ${row.chapter}:${row.v}\n`);
      const speck = JSON.parse(row.speck_json);
      for (const [k, val] of Object.entries(speck)) {
        if ((val as string)?.trim()) console.log(`  ${k} â€” ${val}`);
      }
      return;
    }

    const dbPath = path.join(dirs.study.baseDir, `study_${config.version_id}.sqlite`);
    if (!fs.existsSync(dbPath)) {
      console.error('Study DB not compiled yet. Run `compile`.');
      return;
    }
    const db = new DatabaseSync(dbPath);
    let query = `
      SELECT c.id, c.canonical_name, c.english_name, c.category, c.importance, c.certainty,
             c.certainty_notes, c.definition, c.biblical_meaning, c.historical_context,
             c.cultural_context, c.citations, c.modern_location, c.latitude, c.longitude,
             c.modern_equivalent, l.lemma, l.original_word, l.language, l.strongs_id, l.transliteration
      FROM concepts c
      LEFT JOIN lemmas l ON l.concept_id = c.id
      WHERE 1=1
    `;
    const params: any[] = [];
    if (options.term) {
      query += ` AND (c.canonical_name LIKE ? OR c.english_name LIKE ? OR l.lemma LIKE ? OR l.original_word LIKE ? OR c.modern_location LIKE ?)`;
      params.push(`%${options.term}%`, `%${options.term}%`, `%${options.term}%`, `%${options.term}%`, `%${options.term}%`);
    }
    if (options.category) { query += ` AND c.category = ?`; params.push(options.category); }
    if (options.importance) { query += ` AND c.importance = ?`; params.push(options.importance); }
    query += ` LIMIT 20`;

    const rows = db.prepare(query).all(...params) as any[];
    db.close();
    console.log(`\nFound ${rows.length} terms:\n`);
    for (const r of rows) {
      console.log(`â€¢ [${r.importance.toUpperCase()}] ${r.canonical_name}${r.english_name ? ` / ${r.english_name}` : ''} (${r.category})`);
      if (r.original_word || r.strongs_id || r.transliteration) {
        console.log(`  Original: ${r.original_word ? `${r.original_word} ` : ''}${r.transliteration ? `(${r.transliteration}) ` : ''}${r.strongs_id ? `[${r.strongs_id}]` : ''}`);
      }
      if (r.certainty !== 'verified') console.log(`  Proof: [${r.certainty.toUpperCase()}]${r.certainty_notes ? ': ' + r.certainty_notes : ''}`);
      console.log(`  Definition: ${r.definition}`);
      if (r.biblical_meaning && r.biblical_meaning !== r.definition) console.log(`  Biblical: ${r.biblical_meaning}`);
      if (r.historical_context) console.log(`  Historical: ${r.historical_context}`);
      if (r.cultural_context) console.log(`  Cultural: ${r.cultural_context}`);
      console.log('');
    }
  });

// 11. Chunk (words_feed tree â€” delegates to tool/chunk_web_assets.js)
program
  .command('chunk')
  .description('Regenerate the words_feed chunk tree via tool/chunk_web_assets.js')
  .action(() => {
    const script = path.join(PROJECT_ROOT, '../../tool/chunk_web_assets.js');
    console.log(`Running ${script}...`);
    execSync(`node "${script}"`, { stdio: 'inherit' });
  });

program.parse(process.argv);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function applyPassFilter(config: any, passArg: string): void {
  const wanted = new Set(passArg.split(',').map((s) => s.trim().toLowerCase()));
  if (wanted.has('all')) return;
  config.passes.feed.enabled = wanted.has('feed');
  config.passes.study.enabled = wanted.has('study');
  config.passes.spek.enabled = wanted.has('spek');
}

async function resolveChapters(reader: BibleReader, options: any): Promise<Array<{ book: number; chapter: number }>> {
  if (options.book) {
    const book = reader.findBook(options.book);
    if (!book) { console.error(`Book "${options.book}" not found.`); process.exit(1); }
    if (options.chapter) return [{ book: book.bookNumber, chapter: options.chapter }];
    return Array.from({ length: book.chapters }, (_, i) => ({ book: book.bookNumber, chapter: i + 1 }));
  }
  if (options.all) return reader.getAllChapters();
  return TEST_CHAPTERS;
}

async function compileAll(config: any, which: string[]) {
  const dirs = passDirs(config);
  if (which.includes('study') && config.passes.study.enabled) {
    const dir = dirs.study.baseDir;
    if (fs.existsSync(path.join(dir, 'chapters'))) {
      const c = new StudyDatabaseCompiler(dir, config.version_id);
      try {
        const res = await c.compile();
        console.log(`\n[Study DB] ${res.dbPath}`);
        console.log(`  Concepts: ${res.conceptsCount}, Lemmas: ${res.lemmasCount}, Surface forms: ${res.surfaceFormsCount}, Occurrences: ${res.occurrencesCount}`);
      } catch (err: any) {
        console.error(`[Study DB] ${err.message}`);
      }
    }
  }
  if (which.includes('spek') && config.passes.spek.enabled) {
    const dir = dirs.spek.baseDir;
    if (fs.existsSync(path.join(dir, 'chapters'))) {
      const c = new SpekDatabaseCompiler(dir, config.version_id);
      try {
        const res = c.compile();
        console.log(`\n[Spek DB] ${res.dbPath}`);
        console.log(`  Chapters: ${res.chapters}, Verses: ${res.verses}, Glossary terms: ${res.glossaryTerms}`);
      } catch (err: any) {
        console.error(`[Spek DB] ${err.message}`);
      }
    }
  }
}