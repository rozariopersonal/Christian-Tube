import fs from 'fs';
import path from 'path';
import { DatabaseSync } from 'node:sqlite';
import { BibleReader } from './bible_reader.js';
import { StatusTracker } from './status_tracker.js';
import { AppConfig } from './types.js';

export class Inspector {
  private config: AppConfig;
  private reader: BibleReader;
  private statusTracker: StatusTracker;

  constructor(config: AppConfig, reader: BibleReader, statusTracker: StatusTracker) {
    this.config = config;
    this.reader = reader;
    this.statusTracker = statusTracker;
  }

  public async inspectSource(): Promise<void> {
    console.log('\n========================================');
    console.log('   BIBLE STUDY KB: SOURCE INSPECTION    ');
    console.log('========================================');
    console.log(`Version ID:       ${this.config.version_id}`);
    console.log(`Target Language:  ${this.config.language}`);
    console.log(`Gemini Model:     ${this.config.gemini.model}`);

    if (this.config.bible_source_dir) {
      console.log(`Source Type:      JSON Directory (${this.config.bible_source_dir})`);
    } else if (this.config.bible_database) {
      console.log(`Source Type:      SQLite Database (${this.config.bible_database})`);
    } else {
      console.log(`Source Type:      Standard Virtual Catalog (No source file)`);
    }

    const books = this.reader.getBooks();
    const totalChapters = books.reduce((acc, b) => acc + b.chapters, 0);

    console.log(`Books Detected:   ${books.length}`);
    console.log(`Total Chapters:   ${totalChapters}`);

    // Sample Genesis 1
    const sample = await this.reader.getChapter(1, 1);
    if (sample) {
      console.log(`\nSample Verification: Book 1 (${sample.book_name}) Chapter 1`);
      console.log(`Verses Found:     ${sample.verses.length}`);
      console.log(`Verse 1:          ${sample.verses[0]?.text || ''}`);
      if (sample.verses.length > 1) {
        console.log(`Verse 2:          ${sample.verses[1]?.text || ''}`);
      }
    } else {
      console.warn('\nWarning: Could not read sample chapter Genesis 1.');
    }

    // Status summary
    const summary = this.statusTracker.getSummary();
    console.log('\n--- Processing Status ---');
    console.log(`Completed:        ${summary.completed_chapters}/${summary.total_chapters}`);
    console.log(`Failed:           ${summary.failed_chapters}`);
    console.log(`Pending:          ${summary.pending_chapters}`);
    console.log(`Terms Generated:  ${summary.total_terms}`);
    console.log('========================================\n');
  }

  public inspectCompiledDb(): void {
    const dbPath = path.join(this.config.output_dir, this.config.version_id, `study_${this.config.version_id}.sqlite`);
    if (!fs.existsSync(dbPath)) {
      console.log(`[Inspector] Compiled SQLite database does not exist yet at: ${dbPath}`);
      return;
    }

    console.log(`\nInspecting Compiled SQLite: ${dbPath}`);
    const db = new DatabaseSync(dbPath);

    const tables = db.prepare(`SELECT name FROM sqlite_master WHERE type='table' ORDER BY name`).all() as any[];
    console.log('Tables:', tables.map((t) => t.name).join(', '));

    const counts = {
      concepts: (db.prepare('SELECT count(*) as c FROM concepts').get() as any).c,
      lemmas: (db.prepare('SELECT count(*) as c FROM lemmas').get() as any).c,
      surface_forms: (db.prepare('SELECT count(*) as c FROM surface_forms').get() as any).c,
      occurrences: (db.prepare('SELECT count(*) as c FROM verse_occurrences').get() as any).c,
    };

    console.log(`Total Concepts:      ${counts.concepts}`);
    console.log(`Total Lemmas:        ${counts.lemmas}`);
    console.log(`Total Surface Forms: ${counts.surface_forms}`);
    console.log(`Total Occurrences:   ${counts.occurrences}`);

    console.log('\nSample Concept:');
    const sampleConcept = db.prepare('SELECT * FROM concepts LIMIT 1').get() as any;
    console.log(sampleConcept);

    db.close();
  }
}
