#!/usr/bin/env node
import { Command } from 'commander';
import { BibleReader } from './bible_reader.js';
import { getGeminiApiKey, loadConfig } from './config.js';
import { GeminiStudyClient } from './gemini_client.js';
import { Inspector } from './inspector.js';
import { ChapterProcessor } from './processor.js';
import { StatusTracker } from './status_tracker.js';
import { StudyDatabaseCompiler } from './compiler.js';
import { DatabaseSync } from 'node:sqlite';
import path from 'path';

const program = new Command();

program
  .name('bible-study-kb')
  .description('AI-Assisted Bible Study Knowledge Base Generator')
  .version('1.0.0');

// 1. Inspect Command
program
  .command('inspect')
  .description('Inspect the Bible source database/files and current status')
  .option('-c, --config <path>', 'Path to custom config.yaml')
  .option('--compiled', 'Inspect the compiled SQLite database')
  .action(async (options) => {
    const config = loadConfig(options.config);
    const reader = new BibleReader(config);
    const tracker = new StatusTracker(config);
    const inspector = new Inspector(config, reader, tracker);

    if (options.compiled) {
      inspector.inspectCompiledDb();
    } else {
      await inspector.inspectSource();
    }
  });

// 2. Status Command
program
  .command('status')
  .description('Display processing progress and token metrics')
  .option('-c, --config <path>', 'Path to custom config.yaml')
  .action((options) => {
    const config = loadConfig(options.config);
    const tracker = new StatusTracker(config);
    const summary = tracker.getSummary();

    const percent = ((summary.completed_chapters / summary.total_chapters) * 100).toFixed(1);

    console.log('\n========================================');
    console.log(` BIBLE STUDY KB PROGRESS: ${config.version_id}`);
    console.log('========================================');
    console.log(`Total Chapters:     ${summary.total_chapters}`);
    console.log(`Completed:          ${summary.completed_chapters} (${percent}%)`);
    console.log(`Failed:             ${summary.failed_chapters}`);
    console.log(`Pending:            ${summary.pending_chapters}`);
    console.log(`Total Terms Extracted: ${summary.total_terms}`);
    console.log(`Last Updated:       ${summary.last_updated}`);
    console.log('========================================\n');
  });

// 3. Test Command (Processes Genesis 1 to 5)
program
  .command('test')
  .description('Test run on Genesis 1 to 5')
  .option('-c, --config <path>', 'Path to custom config.yaml')
  .option('--dry-run', 'Run without calling Gemini API')
  .action(async (options) => {
    const config = loadConfig(options.config);
    if (options.dryRun) {
      config.processing.dry_run = true;
    }

    const reader = new BibleReader(config);
    const tracker = new StatusTracker(config);

    let geminiClient: GeminiStudyClient | null = null;
    if (!config.processing.dry_run) {
      const apiKey = getGeminiApiKey();
      geminiClient = new GeminiStudyClient(config, apiKey);
    }

    const processor = new ChapterProcessor(config, reader, tracker, geminiClient);

    console.log('\n[Test Mode] Running Genesis 1 to 5...\n');
    const testChapters = [
      { book: 1, chapter: 1 },
      { book: 1, chapter: 2 },
      { book: 1, chapter: 3 },
      { book: 1, chapter: 4 },
      { book: 1, chapter: 5 },
    ];

    const res = await processor.processBatch(testChapters);
    console.log(`\n[Test Mode Complete] Completed: ${res.completed}, Skipped: ${res.skipped}, Failed: ${res.failed}`);

    // Auto compile test output to sqlite
    console.log('\n[Test Mode] Compiling test chapters to SQLite...');
    const compiler = new StudyDatabaseCompiler(config);
    const compiled = await compiler.compile();
    console.log(`[Test Mode] Compiled to: ${compiled.dbPath}`);
    console.log(`Concepts: ${compiled.conceptsCount}, Lemmas: ${compiled.lemmasCount}, Surface Forms: ${compiled.surfaceFormsCount}`);
  });

// 4. Books Command (Lists all 66 books with status)
program
  .command('books')
  .description('Display status of all 66 Bible books')
  .option('-c, --config <path>', 'Path to custom config.yaml')
  .action((options) => {
    const config = loadConfig(options.config);
    const reader = new BibleReader(config);
    const tracker = new StatusTracker(config);
    const manifest = tracker.getManifest();

    console.log('\n================================================================================');
    console.log(`                     BIBLE BOOKS STUDY STATUS (${config.version_id})`);
    console.log('================================================================================');
    console.log(
      ' #  '.padEnd(5) +
      'English Name'.padEnd(20) +
      'Tamil Name'.padEnd(26) +
      'Chapters'.padEnd(10) +
      'Done'.padEnd(8) +
      'Progress'.padEnd(10) +
      'Terms'
    );
    console.log(''.padEnd(80, '-'));

    let totalAllChapters = 0;
    let totalAllCompleted = 0;
    let totalAllTerms = 0;

    for (let b = 1; b <= 66; b++) {
      const book = reader.findBook(b);
      if (!book) continue;

      let completedCount = 0;
      let termsCount = 0;

      for (let ch = 1; ch <= book.chapters; ch++) {
        const rec = tracker.getChapterRecord(b, ch);
        if (rec && rec.status === 'completed') {
          completedCount++;
          termsCount += rec.terms_count || 0;
        }
      }

      totalAllChapters += book.chapters;
      totalAllCompleted += completedCount;
      totalAllTerms += termsCount;

      const pct = ((completedCount / book.chapters) * 100).toFixed(0) + '%';
      const statusIcon = completedCount === book.chapters ? '✔' : completedCount > 0 ? '◐' : '○';

      console.log(
        `${String(b).padStart(2)}  `.padEnd(5) +
        book.nameEn.padEnd(20) +
        book.nameTa.padEnd(26) +
        String(book.chapters).padEnd(10) +
        String(completedCount).padEnd(8) +
        `${statusIcon} ${pct}`.padEnd(10) +
        String(termsCount)
      );
    }

    const overallPct = ((totalAllCompleted / totalAllChapters) * 100).toFixed(1);
    console.log(''.padEnd(80, '='));
    console.log(`Total: 66 Books | ${totalAllCompleted}/${totalAllChapters} Chapters Completed (${overallPct}%) | ${totalAllTerms} Total Terms Extracted\n`);
  });

// 5. Book Command (Process a specific book by name or number)
program
  .command('book <target>')
  .description('Process all chapters of a single book by number (1-66) or name (e.g. genesis, ஆதியாகமம்)')
  .option('--force', 'Force re-process chapters even if already completed')
  .option('--dry-run', 'Dry run without calling Gemini API')
  .option('-c, --config <path>', 'Path to custom config.yaml')
  .action(async (target, options) => {
    const config = loadConfig(options.config);
    if (options.dryRun) {
      config.processing.dry_run = true;
    }

    const reader = new BibleReader(config);
    const tracker = new StatusTracker(config);

    const targetBook = reader.findBook(target);
    if (!targetBook) {
      console.error(`\n[Error] Book "${target}" not found.`);
      console.error('Please specify a number (1-66) or name (e.g. genesis, exodus, ஆதியாகமம்).\n');
      process.exit(1);
    }

    let geminiClient: GeminiStudyClient | null = null;
    if (!config.processing.dry_run) {
      const apiKey = getGeminiApiKey();
      geminiClient = new GeminiStudyClient(config, apiKey);
    }

    const processor = new ChapterProcessor(config, reader, tracker, geminiClient);

    console.log('\n================================================================');
    console.log(` PROCESSING BOOK: ${targetBook.bookNumber}. ${targetBook.nameEn} / ${targetBook.nameTa}`);
    console.log(` Chapters: 1 to ${targetBook.chapters}`);
    console.log(` Output Folder: output/${config.version_id}/books/${targetBook.slug}/`);
    console.log(` Consolidated File: output/${config.version_id}/books/${targetBook.slug}.json`);
    console.log('================================================================\n');

    const chapters: Array<{ book: number; chapter: number }> = [];
    for (let c = 1; c <= targetBook.chapters; c++) {
      chapters.push({ book: targetBook.bookNumber, chapter: c });
    }

    const res = await processor.processBatch(chapters, options.force);

    // Update consolidated book JSON file
    tracker.updateConsolidatedBook(targetBook.bookNumber);
    const consolidatedPath = tracker.getConsolidatedBookFilePath(targetBook.bookNumber);

    console.log('\n================================================================');
    console.log(` BOOK COMPLETE: ${targetBook.nameEn} (${targetBook.nameTa})`);
    console.log(` Completed: ${res.completed}, Skipped: ${res.skipped}, Failed: ${res.failed}`);
    console.log(` Consolidated Book File: ${consolidatedPath}`);
    console.log('================================================================\n');
  });

// 6. Run Command
program
  .command('run')
  .description('Process one chapter, one book, or the entire Bible')
  .option('-b, --book <target>', 'Book number (1 to 66) or name (e.g. genesis, ஆதியாகமம்)')
  .option('-c, --chapter <number>', 'Chapter number', parseInt)
  .option('--all', 'Process all 1,189 chapters of the Bible')
  .option('--force', 'Force re-process even if already completed')
  .option('--dry-run', 'Dry run without calling Gemini')
  .option('--config <path>', 'Path to custom config.yaml')
  .action(async (options) => {
    const config = loadConfig(options.config);
    if (options.dryRun) {
      config.processing.dry_run = true;
    }

    const reader = new BibleReader(config);
    const tracker = new StatusTracker(config);

    let geminiClient: GeminiStudyClient | null = null;
    if (!config.processing.dry_run) {
      const apiKey = getGeminiApiKey();
      geminiClient = new GeminiStudyClient(config, apiKey);
    }

    const processor = new ChapterProcessor(config, reader, tracker, geminiClient);

    if (options.book && options.chapter) {
      // Single Chapter
      const bookObj = reader.findBook(options.book);
      const bNum = bookObj ? bookObj.bookNumber : parseInt(options.book, 10);
      await processor.processChapter(bNum, options.chapter, options.force);
    } else if (options.book) {
      // Single Book
      const targetBook = reader.findBook(options.book);
      if (!targetBook) {
        console.error(`Book "${options.book}" not found.`);
        process.exit(1);
      }
      const chapters: Array<{ book: number; chapter: number }> = [];
      for (let c = 1; c <= targetBook.chapters; c++) {
        chapters.push({ book: targetBook.bookNumber, chapter: c });
      }
      console.log(`Processing Book ${targetBook.bookNumber}: ${targetBook.nameEn} / ${targetBook.nameTa} (${targetBook.chapters} chapters)...`);
      await processor.processBatch(chapters, options.force);
      tracker.updateConsolidatedBook(targetBook.bookNumber);
    } else if (options.all) {
      // All 66 Books - Processed Book by Book
      console.log(`Processing all 66 books of the Bible book-by-book...\n`);
      for (let b = 1; b <= 66; b++) {
        if (processor.isDailyQuotaExhausted()) {
          console.log('\n[Run All] Stopped processing remaining books because daily API quota was reached.');
          console.log('[Run All] All completed books and chapters are safely saved in output/ta_ovbsi/books/.');
          console.log('[Run All] Run again anytime or tomorrow when the daily quota resets!\n');
          break;
        }

        const targetBook = reader.findBook(b);
        if (!targetBook) continue;
        console.log(`\n================================================================`);
        console.log(` [${b}/66] STARTING BOOK: ${targetBook.nameEn} / ${targetBook.nameTa} (${targetBook.chapters} chapters)`);
        console.log(`================================================================`);
        const chapters: Array<{ book: number; chapter: number }> = [];
        for (let c = 1; c <= targetBook.chapters; c++) {
          chapters.push({ book: targetBook.bookNumber, chapter: c });
        }
        await processor.processBatch(chapters, options.force);
        tracker.updateConsolidatedBook(targetBook.bookNumber);
        console.log(` [${b}/66] COMPLETED BOOK: ${targetBook.nameEn} -> ${tracker.getConsolidatedBookFilePath(targetBook.bookNumber)}`);
      }
    } else {
      console.log('Please specify --book <n>, --chapter <n>, or --all.');
      console.log('Run with --help for options.');
    }
  });

// 7. Resume Command
program
  .command('resume')
  .description('Resume unprocessed or failed chapters across the Bible')
  .option('--config <path>', 'Path to custom config.yaml')
  .action(async (options) => {
    const config = loadConfig(options.config);
    const reader = new BibleReader(config);
    const tracker = new StatusTracker(config);

    const apiKey = getGeminiApiKey();
    const geminiClient = new GeminiStudyClient(config, apiKey);
    const processor = new ChapterProcessor(config, reader, tracker, geminiClient);

    const all = reader.getAllChapters();
    const pending = all.filter(({ book, chapter }) => !tracker.isChapterCompleted(book, chapter));

    console.log(`[Resume] Found ${pending.length} chapters remaining out of ${all.length}. Resuming...`);
    await processor.processBatch(pending, false);
  });

// 6. Compile Command
program
  .command('compile')
  .description('Compile all stored chapter JSON files into the consolidated SQLite database')
  .option('--config <path>', 'Path to custom config.yaml')
  .action(async (options) => {
    const config = loadConfig(options.config);
    const compiler = new StudyDatabaseCompiler(config);
    try {
      const res = await compiler.compile();
      console.log('\n========================================');
      console.log('    SQLITE STUDY DATABASE COMPILED      ');
      console.log('========================================');
      console.log(`Database:      ${res.dbPath}`);
      console.log(`Concepts:      ${res.conceptsCount}`);
      console.log(`Lemmas:        ${res.lemmasCount}`);
      console.log(`Surface Forms: ${res.surfaceFormsCount}`);
      console.log(`Occurrences:   ${res.occurrencesCount}`);
      console.log('========================================\n');
    } catch (err: any) {
      console.error(`[Compile Error] ${err.message}`);
      process.exit(1);
    }
  });

// 7. Review Command
program
  .command('review')
  .description('Review extracted terms from the compiled database')
  .option('-t, --term <query>', 'Search term name or surface form')
  .option('-c, --category <cat>', 'Filter by category')
  .option('-i, --importance <level>', 'Filter by importance (high, medium, low)')
  .option('--config <path>', 'Path to custom config.yaml')
  .action((options) => {
    const config = loadConfig(options.config);
    const dbPath = path.join(config.output_dir, config.version_id, `study_${config.version_id}.sqlite`);

    if (!path.isAbsolute(dbPath)) {
      // make sure path is ready
    }

    try {
      const db = new DatabaseSync(dbPath);
      let query = `
        SELECT c.id, c.canonical_name, c.english_name, c.category, c.importance, c.certainty, c.certainty_notes, c.definition, c.biblical_meaning, c.historical_context, c.cultural_context, c.citations, c.modern_location, c.latitude, c.longitude, c.modern_equivalent, c.metadata, l.lemma, l.original_word, l.language, l.strongs_id, l.transliteration
        FROM concepts c
        LEFT JOIN lemmas l ON l.concept_id = c.id
        WHERE 1=1
      `;
      const params: any[] = [];

      if (options.term) {
        query += ` AND (c.canonical_name LIKE ? OR c.english_name LIKE ? OR l.lemma LIKE ? OR l.original_word LIKE ? OR c.modern_location LIKE ?)`;
        params.push(`%${options.term}%`, `%${options.term}%`, `%${options.term}%`, `%${options.term}%`, `%${options.term}%`);
      }
      if (options.category) {
        query += ` AND c.category = ?`;
        params.push(options.category);
      }
      if (options.importance) {
        query += ` AND c.importance = ?`;
        params.push(options.importance);
      }

      query += ` LIMIT 20`;

      const rows = db.prepare(query).all(...params) as any[];
      db.close();

      console.log(`\nFound ${rows.length} terms matching criteria:\n`);
      for (const r of rows) {
        const eng = r.english_name ? ` / ${r.english_name}` : '';
        console.log(`• [${r.importance.toUpperCase()}] ${r.canonical_name}${eng} (${r.category})`);
        if (r.original_word || r.strongs_id || r.transliteration) {
          console.log(`  Original: ${r.original_word ? `${r.original_word} ` : ''}${r.transliteration ? `(${r.transliteration}) ` : ''}${r.strongs_id ? `[${r.strongs_id}]` : ''}`);
        }
        if (r.lemma) console.log(`  Lemma: ${r.lemma}`);
        if (r.certainty && r.certainty !== 'verified') {
          const notes = r.certainty_notes ? `: ${r.certainty_notes}` : '';
          console.log(`  Scholarly Proof Status: [${r.certainty.toUpperCase()}]${notes}`);
        }
        if (r.modern_location) {
          const gps = r.latitude && r.longitude ? ` [GPS: ${r.latitude}, ${r.longitude}]` : '';
          console.log(`  Location: ${r.modern_location}${gps}`);
        }
        if (r.modern_equivalent) {
          console.log(`  Measure / Unit: ${r.modern_equivalent}`);
        }
        console.log(`  Definition: ${r.definition}`);
        if (r.biblical_meaning && r.biblical_meaning !== r.definition) {
          console.log(`  Biblical Meaning: ${r.biblical_meaning}`);
        }
        if (r.historical_context) {
          console.log(`  Historical Context: ${r.historical_context}`);
        }
        if (r.cultural_context) {
          console.log(`  Cultural Context: ${r.cultural_context}`);
        }
        if (r.citations) {
          try {
            const citeList = JSON.parse(r.citations);
            if (Array.isArray(citeList) && citeList.length > 0) {
              console.log(`  References & Citations:`);
              for (const c of citeList) {
                console.log(`    - ${c}`);
              }
            }
          } catch {}
        }
        console.log('');
      }
    } catch (err: any) {
      console.error(`[Review Error] Make sure you have run 'compile' first. (${err.message})`);
    }
  });

program.parse(process.argv);
