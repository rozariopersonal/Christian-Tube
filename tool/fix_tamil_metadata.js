/**
 * tool/fix_tamil_metadata.js
 *
 * Fixes Tamil book metadata by recomputing totalLines, totalPages, and chapter
 * records from the existing chapter JSON files (which have correct content).
 * Also rebuilds the per-book SQLite.gz packages and consolidated ta/books.sqlite.gz.
 * Updates toc.json and catalog.json + app asset catalog.
 */

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { DatabaseSync } = require('node:sqlite');

const BASE_DIR = path.join(__dirname, '..');
const RELEASES_BOOKS_DIR = path.join(BASE_DIR, 'releases', 'books');
const APP_CATALOG_PATH = path.join(BASE_DIR, 'apps', 'mobile', 'assets', 'books', 'catalog.json');
const CATALOG_PATH = path.join(RELEASES_BOOKS_DIR, 'catalog.json');

const LANG = 'ta';
const LANG_DIR = path.join(RELEASES_BOOKS_DIR, LANG);

function buildSingleBookSqlite(bookId, meta, chapterRecords, contentRecords, outDir) {
  fs.mkdirSync(outDir, { recursive: true });
  const singleSqlite = path.join(outDir, `${bookId}.sqlite`);
  if (fs.existsSync(singleSqlite)) fs.unlinkSync(singleSqlite);

  const sdb = new DatabaseSync(singleSqlite);
  sdb.exec(`
    CREATE TABLE books (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL, subject TEXT NOT NULL DEFAULT '',
      categories TEXT NOT NULL DEFAULT '[]', description TEXT, cover_file TEXT,
      total_pages INTEGER NOT NULL, total_lines INTEGER NOT NULL, created_at TEXT NOT NULL
    );
    CREATE TABLE book_chapters (
      book_id TEXT NOT NULL, chapter_index INTEGER NOT NULL, chapter_title TEXT NOT NULL,
      start_page INTEGER NOT NULL, start_line INTEGER NOT NULL, end_page INTEGER NOT NULL, end_line INTEGER NOT NULL,
      PRIMARY KEY (book_id, chapter_index)
    );
    CREATE TABLE book_content (
      book_id TEXT NOT NULL, page_number INTEGER NOT NULL, line_number INTEGER NOT NULL,
      chapter_index INTEGER NOT NULL, content_type TEXT NOT NULL DEFAULT 'p', text TEXT NOT NULL,
      PRIMARY KEY (book_id, page_number, line_number)
    );
  `);

  sdb.prepare(`INSERT INTO books VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(
    bookId, meta.title, meta.author, meta.subject,
    JSON.stringify(meta.categories || []), meta.description || '', meta.coverFile || '',
    meta.totalPages, meta.totalLines, new Date().toISOString()
  );

  sdb.exec('BEGIN TRANSACTION;');
  const insCh = sdb.prepare(`INSERT INTO book_chapters VALUES (?, ?, ?, ?, ?, ?, ?)`);
  for (const c of chapterRecords) {
    insCh.run(bookId, c.chapterIndex, c.title, c.startPage, c.startLine, c.endPage, c.endLine);
  }
  const insCnt = sdb.prepare(`INSERT INTO book_content VALUES (?, ?, ?, ?, ?, ?)`);
  for (const row of contentRecords) {
    insCnt.run(bookId, row.pageNumber, row.lineNumber, row.chapterIndex, row.contentType, row.text);
  }
  sdb.exec('COMMIT;');
  sdb.close();

  const rawBytes = fs.readFileSync(singleSqlite);
  const gzBytes = zlib.gzipSync(rawBytes, { level: 9 });
  fs.writeFileSync(`${singleSqlite}.gz`, gzBytes);
  fs.unlinkSync(singleSqlite);
  return gzBytes;
}

function buildConsolidatedSqlite(allBooks) {
  const dbFile = path.join(LANG_DIR, 'books.sqlite');
  if (fs.existsSync(dbFile)) fs.unlinkSync(dbFile);

  const db = new DatabaseSync(dbFile);
  db.exec(`
    CREATE TABLE books (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL, subject TEXT NOT NULL DEFAULT '',
      categories TEXT NOT NULL DEFAULT '[]', description TEXT, cover_file TEXT,
      total_pages INTEGER NOT NULL, total_lines INTEGER NOT NULL, created_at TEXT NOT NULL
    );
    CREATE TABLE book_chapters (
      book_id TEXT NOT NULL, chapter_index INTEGER NOT NULL, chapter_title TEXT NOT NULL,
      start_page INTEGER NOT NULL, start_line INTEGER NOT NULL, end_page INTEGER NOT NULL, end_line INTEGER NOT NULL,
      PRIMARY KEY (book_id, chapter_index)
    );
    CREATE TABLE book_content (
      book_id TEXT NOT NULL, page_number INTEGER NOT NULL, line_number INTEGER NOT NULL,
      chapter_index INTEGER NOT NULL, content_type TEXT NOT NULL DEFAULT 'p', text TEXT NOT NULL,
      PRIMARY KEY (book_id, page_number, line_number)
    );
  `);

  const insB = db.prepare(`INSERT INTO books VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
  const insCh = db.prepare(`INSERT INTO book_chapters VALUES (?, ?, ?, ?, ?, ?, ?)`);
  const insCnt = db.prepare(`INSERT INTO book_content VALUES (?, ?, ?, ?, ?, ?)`);

  db.exec('BEGIN TRANSACTION;');
  for (const { meta, chapterRecords, contentRecords } of allBooks) {
    insB.run(
      meta.id, meta.title, meta.author, meta.subject,
      JSON.stringify(meta.categories || []), meta.description || '', meta.coverFile || '',
      meta.totalPages, meta.totalLines, new Date().toISOString()
    );
    for (const c of chapterRecords) {
      insCh.run(meta.id, c.chapterIndex, c.title, c.startPage, c.startLine, c.endPage, c.endLine);
    }
    for (const r of contentRecords) {
      insCnt.run(meta.id, r.pageNumber, r.lineNumber, r.chapterIndex, r.contentType, r.text);
    }
  }
  db.exec('COMMIT;');
  db.close();

  const rawBytes = fs.readFileSync(dbFile);
  const gzBytes = zlib.gzipSync(rawBytes, { level: 9 });
  fs.writeFileSync(`${dbFile}.gz`, gzBytes);
  fs.unlinkSync(dbFile);
  console.log(`\u2713 Built ta/books.sqlite.gz (${(gzBytes.length / 1024 / 1024).toFixed(2)} MB)`);
}

async function main() {
  console.log('=== Tamil Book Metadata Fix ===\n');

  const catalog = JSON.parse(fs.readFileSync(CATALOG_PATH, 'utf8'));
  const taMeta = {};
  for (const b of catalog) {
    if (b.lang === LANG) taMeta[b.id] = b;
  }

  const bookDirs = fs.readdirSync(LANG_DIR)
    .filter(d => d !== 'published' && fs.statSync(path.join(LANG_DIR, d)).isDirectory());

  console.log(`Found ${bookDirs.length} Tamil book directories.\n`);

  const allBooksData = [];
  const updatedCatalogEntries = [];

  for (const bookId of bookDirs) {
    const bookDir = path.join(LANG_DIR, bookId);
    const chaptersDir = path.join(bookDir, 'chapters');

    if (!fs.existsSync(chaptersDir)) {
      console.warn(`  ! No chapters/ dir for ${bookId}, skipping.`);
      continue;
    }

    const chapterFiles = fs.readdirSync(chaptersDir)
      .filter(f => f.endsWith('.json'))
      .sort((a, b) => parseInt(a) - parseInt(b));

    if (chapterFiles.length === 0) {
      console.warn(`  ! No chapter files for ${bookId}, skipping.`);
      continue;
    }

    console.log(`Processing ${bookId} (${chapterFiles.length} chapters)...`);

    // Read all content records
    const allContentRecords = [];
    for (const f of chapterFiles) {
      const lines = JSON.parse(fs.readFileSync(path.join(chaptersDir, f), 'utf8'));
      const chIdx = parseInt(f);
      for (const l of lines) {
        allContentRecords.push({
          bookId,
          pageNumber: l.page,
          lineNumber: l.line,
          chapterIndex: chIdx,
          contentType: l.contentType || 'p',
          text: l.text,
        });
      }
    }

    // Recompute chapter records
    const chapterIndices = [...new Set(allContentRecords.map(r => r.chapterIndex))].sort((a, b) => a - b);
    const chapterRecords = [];

    for (const cIdx of chapterIndices) {
      const rows = allContentRecords.filter(r => r.chapterIndex === cIdx);
      if (rows.length === 0) continue;

      const allPages = rows.map(r => r.pageNumber);
      const startPage = Math.min(...allPages);
      const endPage = Math.max(...allPages);
      const startRows = rows.filter(r => r.pageNumber === startPage);
      const endRows = rows.filter(r => r.pageNumber === endPage);
      const startLine = Math.min(...startRows.map(r => r.lineNumber));
      const endLine = Math.max(...endRows.map(r => r.lineNumber));

      // Strip "அதிகாரம் N " prefix from chapter header to get clean title
      const header = rows.find(r => r.contentType === 'chapter_header');
      let title = header ? header.text : `Chapter ${cIdx}`;
      title = title.replace(/^அதிகாரம்\s+\d+\s*/u, '').trim() || title;

      chapterRecords.push({ chapterIndex: cIdx, title, startPage, startLine, endPage, endLine });
    }

    const totalPages = Math.max(...allContentRecords.map(r => r.pageNumber));
    const totalLines = allContentRecords.length;

    const existingMeta = taMeta[bookId] || {};
    const meta = {
      id: bookId,
      title: existingMeta.title || bookId,
      author: existingMeta.author || 'Zac Poonen',
      subject: existingMeta.subject || 'Christian Living',
      categories: existingMeta.categories || ['Christian Living'],
      description: existingMeta.description || '',
      coverFile: existingMeta.coverFile || `${bookId}.jpg`,
      lang: LANG,
      totalPages,
      totalLines,
    };

    // Rewrite toc.json
    const toc = {
      id: bookId,
      title: meta.title,
      author: meta.author,
      subject: meta.subject,
      totalPages,
      totalLines,
      chapters: chapterRecords,
    };
    fs.writeFileSync(path.join(bookDir, 'toc.json'), JSON.stringify(toc, null, 2), 'utf8');
    console.log(`  + toc.json: ${totalPages} pages, ${totalLines} lines, ${chapterRecords.length} chapters`);

    // Rebuild per-book SQLite.gz
    const pubDir = path.join(LANG_DIR, 'published');
    const gzBytes = buildSingleBookSqlite(bookId, meta, chapterRecords, allContentRecords, pubDir);
    console.log(`  + published/${bookId}.sqlite.gz (${(gzBytes.length / 1024).toFixed(1)} KB)`);

    const gzSize = `${(gzBytes.length / 1024).toFixed(1)} KB`;
    updatedCatalogEntries.push({
      id: bookId,
      title: meta.title,
      author: meta.author,
      subject: meta.subject,
      categories: meta.categories,
      description: meta.description,
      coverFile: meta.coverFile,
      totalPages,
      totalLines,
      downloadSizeFormatted: gzSize,
      createdAt: existingMeta.createdAt || new Date().toISOString(),
      lang: LANG,
    });

    allBooksData.push({ meta, chapterRecords, contentRecords: allContentRecords });
    console.log('');
  }

  // Rebuild consolidated sqlite
  buildConsolidatedSqlite(allBooksData);

  // Update catalogs
  const updatedIds = new Set(updatedCatalogEntries.map(b => b.id));
  const otherEntries = catalog.filter(b => !updatedIds.has(b.id));
  const finalCatalog = [...otherEntries, ...updatedCatalogEntries];

  fs.writeFileSync(CATALOG_PATH, JSON.stringify(finalCatalog, null, 2), 'utf8');
  fs.writeFileSync(APP_CATALOG_PATH, JSON.stringify(finalCatalog, null, 2), 'utf8');

  console.log(`\n=== Done ===`);
  console.log(`Fixed ${updatedCatalogEntries.length} Tamil books.`);
  console.log('');
  console.log('ID'.padEnd(55) + 'Pages'.padEnd(8) + 'Lines');
  console.log('-'.repeat(75));
  for (const b of updatedCatalogEntries) {
    console.log(b.id.padEnd(55) + String(b.totalPages).padEnd(8) + b.totalLines);
  }
}

main().catch(err => {
  console.error('Fatal:', err);
  process.exit(1);
});
