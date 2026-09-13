import fs from 'fs';
import path from 'path';
import { DatabaseSync } from 'node:sqlite';
import { StudyChapterOutput } from './types.js';

// ---------------------------------------------------------------------------
// Normalization (ported from tools/bible_study/src/normalizer.ts)
// ---------------------------------------------------------------------------

const ZERO_WIDTH_REGEX = /[\u200B-\u200D\uFEFF\u00AD]/g;

export function normalizeUnicode(text: string): string {
  if (!text) return '';
  return text.normalize('NFC').replace(ZERO_WIDTH_REGEX, '').trim();
}

export function normalizeSurfaceForm(text: string): string {
  const clean = normalizeUnicode(text);
  return clean
    .replace(/^[^\p{L}\p{M}\p{N}]+/u, '')
    .replace(/[^\p{L}\p{M}\p{N}]+$/u, '')
    .trim();
}

// ---------------------------------------------------------------------------
// Pass 2 — Study concepts database (mirrors tools/bible_study compiler)
// ---------------------------------------------------------------------------

export class StudyDatabaseCompiler {
  constructor(private baseDir: string, private versionId: string) {}

  public async compile(): Promise<{
    conceptsCount: number;
    lemmasCount: number;
    surfaceFormsCount: number;
    occurrencesCount: number;
    dbPath: string;
  }> {
    const chaptersDir = path.join(this.baseDir, 'chapters');
    if (!fs.existsSync(chaptersDir)) {
      throw new Error(`Chapters directory not found: ${chaptersDir}`);
    }

    const chapterFiles = fs.readdirSync(chaptersDir)
      .filter((f) => /^b\d+_c\d+\.json$/.test(f) && !f.endsWith('.tmp'))
      .sort();
    if (chapterFiles.length === 0) {
      throw new Error(`No chapter JSON files found in ${chaptersDir}`);
    }

    const dbPath = path.join(this.baseDir, `study_${this.versionId}.sqlite`);
    if (fs.existsSync(dbPath)) fs.unlinkSync(dbPath);
    const db = new DatabaseSync(dbPath);

    db.exec('PRAGMA journal_mode = WAL;');
    db.exec('PRAGMA synchronous = NORMAL;');
    db.exec('PRAGMA foreign_keys = ON;');

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

    const insertSummary = db.prepare(
      'INSERT OR REPLACE INTO chapter_summaries (book, chapter, summary) VALUES (?, ?, ?)'
    );
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

    const findLemma = db.prepare('SELECT id FROM lemmas WHERE concept_id = ? AND lemma = ?');
    const insertLemma = db.prepare(`
      INSERT OR IGNORE INTO lemmas (concept_id, lemma, language, original_word, strongs_id, transliteration, lexical_meaning)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `);
    const findSurfaceForm = db.prepare('SELECT id FROM surface_forms WHERE lemma_id = ? AND surface_form = ?');
    const insertSurfaceForm = db.prepare('INSERT OR IGNORE INTO surface_forms (lemma_id, surface_form, normalized_form) VALUES (?, ?, ?)');
    const insertOccurrence = db.prepare('INSERT OR IGNORE INTO verse_occurrences (surface_form_id, book, chapter, verse) VALUES (?, ?, ?, ?)');

    let conceptsCount = 0;
    let lemmasCount = 0;
    let surfaceFormsCount = 0;
    let occurrencesCount = 0;
    const now = new Date().toISOString();

    db.exec('BEGIN TRANSACTION;');
    try {
      for (const file of chapterFiles) {
        const chapterData = JSON.parse(fs.readFileSync(path.join(chaptersDir, file), 'utf8')) as StudyChapterOutput;
        if (chapterData.chapter_summary && chapterData.book != null && chapterData.chapter != null) {
          insertSummary.run(chapterData.book, chapterData.chapter, chapterData.chapter_summary);
        }
        for (const term of chapterData.terms || []) {
          insertConcept.run(
            term.concept_id, term.concept_name, term.english_name || null,
            term.category, term.importance, term.certainty || 'verified',
            term.certainty_notes || null, term.contemporary_language || null,
            term.definition, term.biblical_meaning || null,
            term.historical_context || null, term.cultural_context || null,
            term.citations && term.citations.length > 0 ? JSON.stringify(term.citations) : null,
            term.metadata?.modern_location || null,
            term.metadata?.coordinates?.latitude || null,
            term.metadata?.coordinates?.longitude || null,
            term.metadata?.modern_equivalent || null,
            term.metadata ? JSON.stringify(term.metadata) : null,
            term.notes || null, now
          );
          conceptsCount++;

          insertLemma.run(
            term.concept_id, term.lemma, term.original_language?.language || null,
            term.original_language?.original_word || term.original_language?.lemma || null,
            term.original_language?.strongs || null,
            term.original_language?.transliteration || null,
            term.original_language?.lexical_meaning || null
          );
          const lemmaRow = findLemma.get(term.concept_id, term.lemma) as { id: number } | undefined;
          if (!lemmaRow) continue;
          lemmasCount++;

          for (const rawSf of term.surface_forms || []) {
            const sf = normalizeSurfaceForm(rawSf);
            const normSf = normalizeUnicode(sf).toLowerCase();
            if (!sf) continue;
            insertSurfaceForm.run(lemmaRow.id, sf, normSf);
            const sfRow = findSurfaceForm.get(lemmaRow.id, sf) as { id: number } | undefined;
            if (!sfRow) continue;
            surfaceFormsCount++;
            insertOccurrence.run(sfRow.id, term.reference.book, term.reference.chapter, term.reference.verse);
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

    db.exec(`
      CREATE INDEX IF NOT EXISTS idx_surface_exact ON surface_forms(surface_form);
      CREATE INDEX IF NOT EXISTS idx_surface_norm ON surface_forms(normalized_form);
      CREATE INDEX IF NOT EXISTS idx_lemmas_concept ON lemmas(concept_id);
      CREATE INDEX IF NOT EXISTS idx_lemmas_strongs ON lemmas(strongs_id);
      CREATE INDEX IF NOT EXISTS idx_occurrences_bcv ON verse_occurrences(book, chapter, verse);
      CREATE INDEX IF NOT EXISTS idx_concepts_cat ON concepts(category);
      CREATE INDEX IF NOT EXISTS idx_concepts_eng ON concepts(english_name);
    `);

    try {
      db.exec(`
        CREATE VIRTUAL TABLE IF NOT EXISTS concepts_fts USING fts5(
          id UNINDEXED, canonical_name, english_name, definition, biblical_meaning,
          historical_context, cultural_context
        );
        INSERT INTO concepts_fts (id, canonical_name, english_name, definition, biblical_meaning, historical_context, cultural_context)
        SELECT id, canonical_name, COALESCE(english_name, ''), definition, COALESCE(biblical_meaning, ''), COALESCE(historical_context, ''), COALESCE(cultural_context, '')
        FROM concepts;
      `);
    } catch {}

    db.close();

    return {
      conceptsCount,
      lemmasCount,
      surfaceFormsCount,
      occurrencesCount,
      dbPath,
    };
  }
}

// ---------------------------------------------------------------------------
// Pass 3 — Verse-level SPECK database (bilingual glossary + FTS)
// ---------------------------------------------------------------------------

export class SpekDatabaseCompiler {
  constructor(private baseDir: string, private versionId: string) {}

  private lastId(db: DatabaseSync): number {
    return Number((db.prepare('SELECT last_insert_rowid() AS id').get() as { id?: number | bigint }).id ?? 0);
  }

  public compile(): { dbPath: string; chapters: number; verses: number; glossaryTerms: number } {
    const chaptersDir = path.join(this.baseDir, 'chapters');
    if (!fs.existsSync(chaptersDir)) {
      throw new Error(`No chapter output at ${chaptersDir}. Run processing first.`);
    }

    const files = fs.readdirSync(chaptersDir)
      .filter((f) => /^b\d+_c\d+\.json$/.test(f) && !f.endsWith('.tmp'))
      .sort((a, b) => {
        const ma = a.match(/^b(\d+)_c(\d+)/)!;
        const mb = b.match(/^b(\d+)_c(\d+)/)!;
        return Number(ma[1]) - Number(mb[1]) || Number(ma[2]) - Number(mb[2]);
      });

    const dbPath = path.join(this.baseDir, `spek_${this.versionId}.sqlite`);
    if (fs.existsSync(dbPath)) fs.rmSync(dbPath);
    const db = new DatabaseSync(dbPath);

    db.exec(`
      PRAGMA journal_mode = WAL;
      CREATE TABLE chapters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        version_id TEXT NOT NULL,
        source_version TEXT,
        book INTEGER NOT NULL,
        book_name TEXT,
        chapter INTEGER NOT NULL,
        chapter_summary TEXT,
        historical_context TEXT,
        cultural_context TEXT,
        certainty TEXT,
        sources TEXT,
        UNIQUE(version_id, book, chapter)
      );
      CREATE TABLE verses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chapter_id INTEGER NOT NULL REFERENCES chapters(id),
        v INTEGER NOT NULL,
        speck_json TEXT NOT NULL,
        UNIQUE(chapter_id, v)
      );
      CREATE TABLE glossary_terms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        term TEXT NOT NULL,
        en TEXT,
        ta TEXT,
        strongs TEXT
      );
      CREATE TABLE verse_glossary (
        verse_id INTEGER NOT NULL REFERENCES verses(id),
        term_id INTEGER NOT NULL REFERENCES glossary_terms(id),
        PRIMARY KEY (verse_id, term_id)
      );
      CREATE VIRTUAL TABLE glossary_fts USING fts5(term, en, ta, content='glossary_terms', content_rowid='id');
      CREATE INDEX idx_verses_chapter_id ON verses(chapter_id);
      CREATE INDEX idx_chapters_book_chapter ON chapters(book, chapter);
    `);

    const insertChapter = db.prepare(`
      INSERT INTO chapters (version_id, source_version, book, book_name, chapter, chapter_summary,
                            historical_context, cultural_context, certainty, sources)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    const insertVerse = db.prepare('INSERT INTO verses (chapter_id, v, speck_json) VALUES (?, ?, ?)');
    const insertGlossary = db.prepare('INSERT INTO glossary_terms (term, en, ta, strongs) VALUES (?, ?, ?, ?)');
    const insertVerseGlossary = db.prepare('INSERT INTO verse_glossary (verse_id, term_id) VALUES (?, ?)');
    const insertFts = db.prepare('INSERT INTO glossary_fts (rowid, term, en, ta) VALUES (?, ?, ?, ?)');

    const termCache = new Map<string, number>();
    let chapterCount = 0;
    let verseCount = 0;
    let glossaryCount = 0;

    db.exec('BEGIN');
    for (const f of files) {
      let parsed: any;
      try {
        parsed = JSON.parse(fs.readFileSync(path.join(chaptersDir, f), 'utf8'));
      } catch {
        continue;
      }

      insertChapter.run(
        parsed.version_id || this.versionId,
        parsed.source_version,
        parsed.book, parsed.book_name,
        parsed.chapter,
        parsed.chapter_summary || null,
        parsed.historical_context,
        parsed.cultural_context,
        parsed.certainty,
        JSON.stringify(parsed.sources || [])
      );
      const chapterId = this.lastId(db);
      chapterCount++;

      for (const verse of parsed.verses || []) {
        insertVerse.run(chapterId, verse.v, JSON.stringify(verse.speck || {}));
        const verseId = this.lastId(db);
        verseCount++;

        for (const g of verse.glossary || []) {
          const key = `${String(g.term).toLowerCase()}::${String(g.en || '').toLowerCase()}`;
          let termId = termCache.get(key);
          if (termId === undefined) {
            insertGlossary.run(g.term, g.en, g.ta, g.strongs ?? null);
            termId = this.lastId(db);
            insertFts.run(termId, g.term, g.en || '', g.ta || '');
            termCache.set(key, termId);
            glossaryCount++;
          }
          insertVerseGlossary.run(verseId, termId);
        }
      }
    }
    db.exec('COMMIT');
    db.close();

    return { dbPath, chapters: chapterCount, verses: verseCount, glossaryTerms: glossaryCount };
  }
}