import fs from 'fs';
import path from 'path';
import { DatabaseSync } from 'node:sqlite';
import { normalizeSurfaceForm, normalizeUnicode } from './normalizer.js';
import { AppConfig, ChapterOutput } from './types.js';

export class StudyDatabaseCompiler {
  private config: AppConfig;
  private versionDir: string;
  private chaptersDir: string;
  private dbPath: string;

  constructor(config: AppConfig) {
    this.config = config;
    this.versionDir = path.join(config.output_dir, config.version_id);
    this.chaptersDir = path.join(this.versionDir, 'chapters');
    this.dbPath = path.join(this.versionDir, `study_${config.version_id}.sqlite`);
  }

  /**
   * Compiles all chapter JSON files into the consolidated SQLite study database.
   */
  public async compile(): Promise<{
    conceptsCount: number;
    lemmasCount: number;
    surfaceFormsCount: number;
    occurrencesCount: number;
    dbPath: string;
  }> {
    if (!fs.existsSync(this.chaptersDir)) {
      throw new Error(`Chapters directory not found: ${this.chaptersDir}`);
    }

    const chapterFiles = fs
      .readdirSync(this.chaptersDir)
      .filter((f) => f.endsWith('.json') && !f.endsWith('.tmp'))
      .sort();

    if (chapterFiles.length === 0) {
      throw new Error(`No chapter JSON files found in ${this.chaptersDir}`);
    }

    console.log(`[Compiler] Found ${chapterFiles.length} chapter files to compile into ${this.dbPath}...`);

    // Remove existing compiled database if present to rebuild clean
    if (fs.existsSync(this.dbPath)) {
      fs.unlinkSync(this.dbPath);
    }

    const db = new DatabaseSync(this.dbPath);

    // Optimize SQLite settings
    db.exec('PRAGMA journal_mode = WAL;');
    db.exec('PRAGMA synchronous = NORMAL;');
    db.exec('PRAGMA foreign_keys = ON;');

    // 1. Create Tables
    db.exec(`
      CREATE TABLE IF NOT EXISTS chapter_summaries (
        book INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        summary TEXT NOT NULL,
        PRIMARY KEY (book, chapter)
      );

      CREATE TABLE IF NOT EXISTS strongs_entries (
        strongs_id TEXT PRIMARY KEY,
        language TEXT,
        original_word TEXT,
        transliteration TEXT,
        pronunciation TEXT,
        part_of_speech TEXT,
        definition TEXT
      );

      CREATE TABLE IF NOT EXISTS concepts (
        id TEXT PRIMARY KEY,
        canonical_name TEXT NOT NULL,
        english_name TEXT,
        category TEXT NOT NULL,
        importance TEXT NOT NULL,
        certainty TEXT DEFAULT 'verified',
        certainty_notes TEXT,
        contemporary_language TEXT,
        definition TEXT NOT NULL,
        biblical_meaning TEXT,
        historical_context TEXT,
        cultural_context TEXT,
        citations TEXT,
        modern_location TEXT,
        latitude REAL,
        longitude REAL,
        modern_equivalent TEXT,
        metadata TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS lemmas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        concept_id TEXT NOT NULL REFERENCES concepts(id),
        lemma TEXT NOT NULL,
        language TEXT,
        original_word TEXT,
        strongs_id TEXT,
        transliteration TEXT,
        lexical_meaning TEXT,
        UNIQUE(concept_id, lemma)
      );

      CREATE TABLE IF NOT EXISTS surface_forms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lemma_id INTEGER NOT NULL REFERENCES lemmas(id),
        surface_form TEXT NOT NULL,
        normalized_form TEXT NOT NULL,
        UNIQUE(lemma_id, surface_form)
      );

      CREATE TABLE IF NOT EXISTS verse_occurrences (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        surface_form_id INTEGER NOT NULL REFERENCES surface_forms(id),
        book INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        UNIQUE(surface_form_id, book, chapter, verse)
      );
    `);

    // 2. Pre-populate Strong's Lexicon if available
    this.importStrongsLexicon(db);

    // 3. Prepared Statements
    const insertSummary = db.prepare(`
      INSERT OR REPLACE INTO chapter_summaries (book, chapter, summary)
      VALUES (?, ?, ?)
    `);

    const insertConcept = db.prepare(`
      INSERT INTO concepts (id, canonical_name, english_name, category, importance, certainty, certainty_notes, contemporary_language, definition, biblical_meaning, historical_context, cultural_context, citations, modern_location, latitude, longitude, modern_equivalent, metadata, notes, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        english_name = COALESCE(excluded.english_name, concepts.english_name),
        certainty = COALESCE(excluded.certainty, concepts.certainty),
        certainty_notes = COALESCE(excluded.certainty_notes, concepts.certainty_notes),
        historical_context = COALESCE(excluded.historical_context, concepts.historical_context),
        cultural_context = COALESCE(excluded.cultural_context, concepts.cultural_context),
        citations = COALESCE(excluded.citations, concepts.citations),
        modern_location = COALESCE(excluded.modern_location, concepts.modern_location),
        latitude = COALESCE(excluded.latitude, concepts.latitude),
        longitude = COALESCE(excluded.longitude, concepts.longitude),
        modern_equivalent = COALESCE(excluded.modern_equivalent, concepts.modern_equivalent),
        metadata = COALESCE(excluded.metadata, concepts.metadata),
        biblical_meaning = COALESCE(concepts.biblical_meaning, excluded.biblical_meaning),
        notes = COALESCE(concepts.notes, excluded.notes)
    `);

    const findLemma = db.prepare(`
      SELECT id FROM lemmas WHERE concept_id = ? AND lemma = ?
    `);

    const insertLemma = db.prepare(`
      INSERT OR IGNORE INTO lemmas (concept_id, lemma, language, original_word, strongs_id, transliteration, lexical_meaning)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `);

    const findSurfaceForm = db.prepare(`
      SELECT id FROM surface_forms WHERE lemma_id = ? AND surface_form = ?
    `);

    const insertSurfaceForm = db.prepare(`
      INSERT OR IGNORE INTO surface_forms (lemma_id, surface_form, normalized_form)
      VALUES (?, ?, ?)
    `);

    const insertOccurrence = db.prepare(`
      INSERT OR IGNORE INTO verse_occurrences (surface_form_id, book, chapter, verse)
      VALUES (?, ?, ?, ?)
    `);

    let conceptsCount = 0;
    let lemmasCount = 0;
    let surfaceFormsCount = 0;
    let occurrencesCount = 0;

    const now = new Date().toISOString();

    db.exec('BEGIN TRANSACTION;');

    try {
      for (const file of chapterFiles) {
        const filePath = path.join(this.chaptersDir, file);
        const content = fs.readFileSync(filePath, 'utf8');
        const chapterData: ChapterOutput = JSON.parse(content);

        // Insert chapter summary
        if (chapterData.chapter_summary) {
          insertSummary.run(chapterData.book, chapterData.chapter, chapterData.chapter_summary);
        }

        for (const term of chapterData.terms) {
          // A. Upsert Concept
          insertConcept.run(
            term.concept_id,
            term.concept_name,
            term.english_name || null,
            term.category,
            term.importance,
            term.certainty || 'verified',
            term.certainty_notes || null,
            term.contemporary_language || null,
            term.definition,
            term.biblical_meaning || null,
            term.historical_context || null,
            term.cultural_context || null,
            term.citations && term.citations.length > 0 ? JSON.stringify(term.citations) : null,
            term.metadata?.modern_location || null,
            term.metadata?.coordinates?.latitude || null,
            term.metadata?.coordinates?.longitude || null,
            term.metadata?.modern_equivalent || null,
            term.metadata ? JSON.stringify(term.metadata) : null,
            term.notes || null,
            now
          );
          conceptsCount++;

          // B. Upsert Lemma
          insertLemma.run(
            term.concept_id,
            term.lemma,
            term.original_language?.language || null,
            term.original_language?.original_word || term.original_language?.lemma || null,
            term.original_language?.strongs || null,
            term.original_language?.transliteration || null,
            term.original_language?.lexical_meaning || null
          );

          const lemmaRow = findLemma.get(term.concept_id, term.lemma) as { id: number } | undefined;
          if (!lemmaRow) continue;
          const lemmaId = lemmaRow.id;

          // C. Upsert Surface Forms & Verse Occurrences
          for (const rawSf of term.surface_forms) {
            const sf = normalizeSurfaceForm(rawSf);
            const normSf = normalizeUnicode(sf).toLowerCase();
            if (!sf) continue;

            insertSurfaceForm.run(lemmaId, sf, normSf);

            const sfRow = findSurfaceForm.get(lemmaId, sf) as { id: number } | undefined;
            if (!sfRow) continue;
            const sfId = sfRow.id;

            insertOccurrence.run(
              sfId,
              term.reference.book,
              term.reference.chapter,
              term.reference.verse
            );
            occurrencesCount++;
          }
        }
      }

      db.exec('COMMIT;');
    } catch (err) {
      db.exec('ROLLBACK;');
      db.close();
      throw err;
    }

    // 4. Create Indexes
    db.exec(`
      CREATE INDEX IF NOT EXISTS idx_surface_exact ON surface_forms(surface_form);
      CREATE INDEX IF NOT EXISTS idx_surface_norm ON surface_forms(normalized_form);
      CREATE INDEX IF NOT EXISTS idx_lemmas_concept ON lemmas(concept_id);
      CREATE INDEX IF NOT EXISTS idx_lemmas_strongs ON lemmas(strongs_id);
      CREATE INDEX IF NOT EXISTS idx_occurrences_bcv ON verse_occurrences(book, chapter, verse);
      CREATE INDEX IF NOT EXISTS idx_concepts_cat ON concepts(category);
      CREATE INDEX IF NOT EXISTS idx_concepts_eng ON concepts(english_name);
    `);

    // 5. Create Full-Text Search (FTS5) Table
    try {
      db.exec(`
        CREATE VIRTUAL TABLE IF NOT EXISTS concepts_fts USING fts5(
          id UNINDEXED,
          canonical_name,
          english_name,
          definition,
          biblical_meaning,
          historical_context,
          cultural_context
        );

        INSERT INTO concepts_fts (id, canonical_name, english_name, definition, biblical_meaning, historical_context, cultural_context)
        SELECT id, canonical_name, COALESCE(english_name, ''), definition, COALESCE(biblical_meaning, ''), COALESCE(historical_context, ''), COALESCE(cultural_context, '')
        FROM concepts;
      `);
    } catch (ftsErr) {
      console.warn('[Compiler] FTS5 setup note:', ftsErr);
    }

    const counts = {
      concepts: (db.prepare('SELECT count(*) as c FROM concepts').get() as any).c,
      lemmas: (db.prepare('SELECT count(*) as c FROM lemmas').get() as any).c,
      surface_forms: (db.prepare('SELECT count(*) as c FROM surface_forms').get() as any).c,
      occurrences: (db.prepare('SELECT count(*) as c FROM verse_occurrences').get() as any).c,
    };

    db.close();

    return {
      conceptsCount: counts.concepts,
      lemmasCount: counts.lemmas,
      surfaceFormsCount: counts.surface_forms,
      occurrencesCount: counts.occurrences,
      dbPath: this.dbPath,
    };
  }

  private importStrongsLexicon(db: DatabaseSync): void {
    if (!this.config.strongs_source || !fs.existsSync(this.config.strongs_source)) {
      return;
    }

    try {
      const srcDb = new DatabaseSync(this.config.strongs_source);
      const rows = srcDb
        .prepare('SELECT headword, part_of_speech, phonetic, definition FROM dictionary_entries')
        .all() as Array<{
        headword: string;
        part_of_speech: string;
        phonetic: string;
        definition: string;
      }>;
      srcDb.close();

      if (!rows || rows.length === 0) return;

      const insertStrongs = db.prepare(`
        INSERT OR IGNORE INTO strongs_entries (strongs_id, original_word, part_of_speech, pronunciation, definition)
        VALUES (?, ?, ?, ?, ?)
      `);

      for (const row of rows) {
        // Extract Strong's ID like H1254 from 'H1254 (Bara)' or 'H1254'
        const match = row.headword.match(/^([HG]\d+)/i);
        const strongsId = match ? match[1].toUpperCase() : row.headword;
        insertStrongs.run(
          strongsId,
          row.headword,
          row.part_of_speech || null,
          row.phonetic || null,
          row.definition || ''
        );
      }
      console.log(`[Compiler] Pre-loaded ${rows.length} Strong's lexicon entries from ${this.config.strongs_source}`);
    } catch (err) {
      console.warn(`[Compiler] Note: Could not import Strong's lexicon from ${this.config.strongs_source}:`, err);
    }
  }
}
