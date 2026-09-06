#!/usr/bin/env node
/**
 * tool/publish_books.js
 *
 * Splits the master books database into individual modular SQLite packages:
 *  - Output directory: data/books_published/
 *  - Each book produces:
 *      <book_id>.sqlite (individual SQLite DB)
 *      <book_id>.sqlite.gz (gzipped distribution package, ~20KB - 150KB)
 *  - Updates catalog.json with download sizes and versioning
 *  - Syncs catalog.json to apps/mobile/assets/books/catalog.json
 *
 * Usage:
 *  node tool/publish_books.js
 */

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { DatabaseSync } = require('node:sqlite');

const MASTER_DB_PATH = path.join(__dirname, '..', 'data', 'books.sqlite');
const PUBLISH_DIR = path.join(__dirname, '..', 'data', 'books_published');
const CATALOG_PATH = path.join(__dirname, '..', 'data', 'books_raw', 'catalog.json');
const APP_CATALOG_PATH = path.join(__dirname, '..', 'apps', 'mobile', 'assets', 'books', 'catalog.json');

async function main() {
  if (!fs.existsSync(MASTER_DB_PATH)) {
    console.error(`Master database not found at ${MASTER_DB_PATH}. Run tool/ingest_books.js first.`);
    process.exit(1);
  }

  if (!fs.existsSync(CATALOG_PATH)) {
    console.error(`Catalog not found at ${CATALOG_PATH}.`);
    process.exit(1);
  }

  // Ensure publish directory exists
  if (!fs.existsSync(PUBLISH_DIR)) {
    fs.mkdirSync(PUBLISH_DIR, { recursive: true });
  }

  const masterDb = new DatabaseSync(MASTER_DB_PATH);
  const catalog = JSON.parse(fs.readFileSync(CATALOG_PATH, 'utf8'));

  console.log(`\nPublishing ${catalog.length} books as individual SQLite packages...`);
  console.log(`Destination: ${PUBLISH_DIR}\n`);

  let totalCompressedBytes = 0;

  for (let i = 0; i < catalog.length; i++) {
    const book = catalog[i];
    const bookId = book.id;

    const outSqlite = path.join(PUBLISH_DIR, `${bookId}.sqlite`);
    const outGz = path.join(PUBLISH_DIR, `${bookId}.sqlite.gz`);

    if (fs.existsSync(outSqlite)) fs.unlinkSync(outSqlite);
    if (fs.existsSync(outGz)) fs.unlinkSync(outGz);

    const singleDb = new DatabaseSync(outSqlite);

    // Create schema
    singleDb.exec(`
      CREATE TABLE books (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        author TEXT NOT NULL,
        subject TEXT NOT NULL DEFAULT '',
        categories TEXT NOT NULL DEFAULT '[]',
        description TEXT,
        cover_file TEXT,
        total_pages INTEGER NOT NULL,
        total_lines INTEGER NOT NULL,
        created_at TEXT NOT NULL
      );

      CREATE TABLE book_chapters (
        book_id TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        chapter_title TEXT NOT NULL,
        start_page INTEGER NOT NULL,
        start_line INTEGER NOT NULL,
        end_page INTEGER NOT NULL,
        end_line INTEGER NOT NULL,
        subtitles TEXT NOT NULL DEFAULT '[]',
        PRIMARY KEY (book_id, chapter_index)
      );

      CREATE TABLE book_content (
        book_id TEXT NOT NULL,
        page_number INTEGER NOT NULL,
        line_number INTEGER NOT NULL,
        chapter_index INTEGER NOT NULL,
        content_type TEXT NOT NULL DEFAULT 'p',
        text TEXT NOT NULL,
        PRIMARY KEY (book_id, page_number, line_number)
      );

      CREATE TABLE book_scripture_links (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_number INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        end_verse INTEGER NOT NULL,
        book_id TEXT NOT NULL,
        page_number INTEGER NOT NULL,
        start_line INTEGER NOT NULL,
        end_line INTEGER NOT NULL,
        headline TEXT
      );

      CREATE INDEX idx_book_page ON book_content (book_id, page_number);
      CREATE INDEX idx_book_links ON book_scripture_links (book_number, chapter, verse);
    `);

    // 1. Copy books row
    const bookRow = masterDb.prepare('SELECT * FROM books WHERE id = ?').get(bookId);
    if (bookRow) {
      singleDb.prepare(`
        INSERT INTO books VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        bookRow.id,
        bookRow.title,
        bookRow.author,
        bookRow.subject || '',
        bookRow.categories || '[]',
        bookRow.description,
        bookRow.cover_file,
        bookRow.total_pages,
        bookRow.total_lines,
        bookRow.created_at
      );
    }

    // 2. Copy chapters
    const chapters = masterDb.prepare('SELECT * FROM book_chapters WHERE book_id = ?').all(bookId);
    const insertChapter = singleDb.prepare(`
      INSERT INTO book_chapters VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `);
    singleDb.exec('BEGIN TRANSACTION;');
    for (const ch of chapters) {
      insertChapter.run(
        ch.book_id,
        ch.chapter_index,
        ch.chapter_title,
        ch.start_page,
        ch.start_line,
        ch.end_page,
        ch.end_line,
        ch.subtitles || '[]'
      );
    }
    singleDb.exec('COMMIT;');

    // 3. Copy content
    const content = masterDb.prepare('SELECT * FROM book_content WHERE book_id = ?').all(bookId);
    const insertContent = singleDb.prepare(`
      INSERT INTO book_content VALUES (?, ?, ?, ?, ?, ?)
    `);
    singleDb.exec('BEGIN TRANSACTION;');
    for (const row of content) {
      insertContent.run(
        row.book_id,
        row.page_number,
        row.line_number,
        row.chapter_index,
        row.content_type || 'p',
        row.text
      );
    }
    singleDb.exec('COMMIT;');

    // 4. Copy scripture links
    const links = masterDb.prepare('SELECT * FROM book_scripture_links WHERE book_id = ?').all(bookId);
    const insertLink = singleDb.prepare(`
      INSERT INTO book_scripture_links (book_number, chapter, verse, end_verse, book_id, page_number, start_line, end_line, headline)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    singleDb.exec('BEGIN TRANSACTION;');
    for (const l of links) {
      insertLink.run(
        l.book_number,
        l.chapter,
        l.verse,
        l.end_verse,
        l.book_id,
        l.page_number,
        l.start_line,
        l.end_line,
        l.headline
      );
    }
    singleDb.exec('COMMIT;');

    // Close SQLite
    singleDb.close();

    // Gzip compress
    const sqliteBytes = fs.readFileSync(outSqlite);
    const gzBytes = zlib.gzipSync(sqliteBytes, { level: 9 });
    fs.writeFileSync(outGz, gzBytes);

    const sizeKb = (gzBytes.length / 1024).toFixed(1);
    totalCompressedBytes += gzBytes.length;

    // Update catalog item
    book.downloadFile = `${bookId}.sqlite.gz`;
    book.downloadSizeBytes = gzBytes.length;
    book.downloadSizeFormatted = `${sizeKb} KB`;

    console.log(`[${i + 1}/${catalog.length}] ✓ Published: ${book.title.padEnd(45)} (${sizeKb.padStart(6)} KB) -> ${bookId}.sqlite.gz`);
  }

  function safeWriteFile(filePath, data) {
    for (let attempt = 1; attempt <= 5; attempt++) {
      try {
        fs.writeFileSync(filePath, data, 'utf8');
        return;
      } catch (err) {
        if (attempt === 5) throw err;
        const end = Date.now() + attempt * 150;
        while (Date.now() < end) {}
      }
    }
  }

  // Update catalogs
  safeWriteFile(CATALOG_PATH, JSON.stringify(catalog, null, 2));
  if (fs.existsSync(APP_CATALOG_PATH)) {
    try {
      const fullCatalog = JSON.parse(fs.readFileSync(APP_CATALOG_PATH, 'utf8'));
      const enMap = new Map(catalog.map(b => [b.id, b]));
      const updated = fullCatalog.map(item => {
        if (enMap.has(item.id)) {
          const fresh = enMap.get(item.id);
          return {
            ...item,
            title: fresh.title,
            author: fresh.author,
            subject: fresh.subject,
            totalPages: fresh.totalPages,
            totalLines: fresh.totalLines,
          };
        }
        return item;
      });
      safeWriteFile(APP_CATALOG_PATH, JSON.stringify(updated, null, 2));
    } catch (e) {
      console.warn('Could not merge into app catalog:', e);
    }
  }

  const totalMb = (totalCompressedBytes / (1024 * 1024)).toFixed(2);
  console.log('\n========================================');
  console.log(`Individual book publishing completed!`);
  console.log(`Total Books Published: ${catalog.length}`);
  console.log(`Combined Size of All 38 Books: ${totalMb} MB`);
  console.log(`Average Book Size: ${(totalCompressedBytes / catalog.length / 1024).toFixed(1)} KB`);
  console.log(`Output Directory: ${PUBLISH_DIR}`);
  console.log('========================================\n');
}

main().catch(err => {
  console.error('Fatal error during book publishing:', err);
  process.exit(1);
});
