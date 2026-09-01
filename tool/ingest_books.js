#!/usr/bin/env node
/**
 * tool/ingest_books.js
 *
 * Converts downloaded raw books into structured SQLite database and SQL file
 * with deterministic page and line coordinates:
 *
 * Tables created:
 *  - books: Catalog metadata, page & line counts, covers
 *  - book_chapters: TOC chapters with start/end page & line boundaries
 *  - book_content: Every line with (book_id, page_number, line_number, chapter_index, text)
 *
 * Output:
 *  - data/books.sqlite (SQLite database)
 *  - data/books.sql (Raw SQL statements)
 *
 * Usage:
 *  node tool/ingest_books.js [--limit N]
 */

const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

const RAW_DIR = path.join(__dirname, '..', 'data', 'books_raw');
const CATALOG_PATH = path.join(RAW_DIR, 'catalog.json');
const HTML_DIR = path.join(RAW_DIR, 'html');
const OUT_SQLITE = path.join(__dirname, '..', 'data', 'books.sqlite');
const OUT_SQL = path.join(__dirname, '..', 'data', 'books.sql');

// Configuration for virtual pagination
const LINES_PER_PAGE = 28;
const TARGET_CHARS_PER_LINE = 72;

function cleanHtml(raw) {
  return raw
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .replace(/&rsquo;/g, "'")
    .replace(/&lsquo;/g, "'")
    .replace(/&rdquo;/g, '"')
    .replace(/&ldquo;/g, '"')
    .replace(/&mdash;/g, '—')
    .replace(/&ndash;/g, '–')
    .replace(/<[^>]+>/g, '')
    .trim();
}

/**
 * Splits a paragraph into natural, readable line chunks.
 */
function splitIntoLines(text, maxChars = TARGET_CHARS_PER_LINE) {
  const words = text.split(/\s+/).filter(w => w.length > 0);
  if (words.length === 0) return [];

  const lines = [];
  let currentLine = '';

  for (const word of words) {
    if (!currentLine) {
      currentLine = word;
    } else if ((currentLine.length + 1 + word.length) <= maxChars) {
      currentLine += ' ' + word;
    } else {
      lines.push(currentLine);
      currentLine = word;
    }
  }
  if (currentLine) {
    lines.push(currentLine);
  }
  return lines;
}

/**
 * Parses the book's chapter structure and paragraphs from its HTML file.
 */
function parseBookHtml(htmlContent) {
  const chapters = [];

  // Match each chapter container:
  // <div id="..." class="chapter ..."> ... </div>
  const chapterChunks = htmlContent.split(/<div\s+id=["'][^"']+["']\s+class=["'][^"']*chapter[^"']*["']/);

  for (let i = 1; i < chapterChunks.length; i++) {
    const chunk = chapterChunks[i];

    // Extract title: <h4 class="books-chapter-title">...</h4>
    const titleMatch = chunk.match(/<h4 class=["']books-chapter-title["']>([\s\S]*?)<\/h4>/);
    let chapterTitle = 'Chapter';
    if (titleMatch) {
      chapterTitle = cleanHtml(titleMatch[1]).replace(/\s+/g, ' ');
    }

    // Extract paragraphs and headings within chapter
    const paragraphs = [];
    const pMatches = chunk.matchAll(/<(?:p|h3|h4|h5)(?:\s+[^>]*)?>([\s\S]*?)<\/(?:p|h3|h4|h5)>/g);
    for (const pm of pMatches) {
      const pText = cleanHtml(pm[1]);
      // Skip empty or purely address/order form boilerplate
      if (!pText || pText.startsWith('Chapter ') && pText === chapterTitle) continue;
      if (pText.includes('austincfc.church/books') || pText.includes('order by Email')) continue;
      paragraphs.push(pText);
    }

    if (paragraphs.length > 0) {
      chapters.push({
        title: chapterTitle,
        paragraphs,
      });
    }
  }

  // Fallback: If no chapter divs matched, extract all <p> tags
  if (chapters.length === 0) {
    const allP = [];
    const pMatches = htmlContent.matchAll(/<p(?:\s+[^>]*)?>([\s\S]*?)<\/p>/g);
    for (const pm of pMatches) {
      const pText = cleanHtml(pm[1]);
      if (pText.length > 20) allP.push(pText);
    }
    if (allP.length > 0) {
      chapters.push({
        title: 'Full Book',
        paragraphs: allP,
      });
    }
  }

  return chapters;
}

function escapeSql(str) {
  if (str === null || str === undefined) return 'NULL';
  return "'" + str.replace(/'/g, "''") + "'";
}

async function main() {
  if (!fs.existsSync(CATALOG_PATH)) {
    console.error(`Catalog not found at ${CATALOG_PATH}. Run tool/download_books.js first.`);
    process.exit(1);
  }

  const catalog = JSON.parse(fs.readFileSync(CATALOG_PATH, 'utf8'));
  console.log(`Loaded catalog with ${catalog.length} books.`);

  // Initialize SQLite database
  if (fs.existsSync(OUT_SQLITE)) fs.unlinkSync(OUT_SQLITE);
  const db = new DatabaseSync(OUT_SQLITE);

  db.exec(`
    CREATE TABLE books (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      author TEXT NOT NULL,
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
      PRIMARY KEY (book_id, chapter_index),
      FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
    );

    CREATE TABLE book_content (
      book_id TEXT NOT NULL,
      page_number INTEGER NOT NULL,
      line_number INTEGER NOT NULL,
      chapter_index INTEGER NOT NULL,
      text TEXT NOT NULL,
      PRIMARY KEY (book_id, page_number, line_number),
      FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
    );

    CREATE INDEX idx_book_page ON book_content (book_id, page_number);
  `);

  const insertBook = db.prepare(`
    INSERT INTO books (id, title, author, description, cover_file, total_pages, total_lines, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const insertChapter = db.prepare(`
    INSERT INTO book_chapters (book_id, chapter_index, chapter_title, start_page, start_line, end_page, end_line)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `);

  const insertLine = db.prepare(`
    INSERT INTO book_content (book_id, page_number, line_number, chapter_index, text)
    VALUES (?, ?, ?, ?, ?)
  `);

  const sqlStatements = [
    `-- Generated by tool/ingest_books.js`,
    `-- Total Books: ${catalog.length}`,
    `PRAGMA foreign_keys = ON;`,
    `BEGIN TRANSACTION;`,
  ];

  let totalIngestedBooks = 0;
  let totalIngestedChapters = 0;
  let totalIngestedLines = 0;

  for (const book of catalog) {
    const htmlFile = path.join(HTML_DIR, `${book.id}.html`);
    if (!fs.existsSync(htmlFile)) {
      console.warn(`Skipping "${book.title}" - HTML file not found.`);
      continue;
    }

    const rawHtml = fs.readFileSync(htmlFile, 'utf8');
    const parsedChapters = parseBookHtml(rawHtml);

    if (parsedChapters.length === 0) {
      console.warn(`Warning: No chapters/paragraphs found for "${book.title}".`);
      continue;
    }

    let currentPage = 1;
    let currentLine = 1;
    let bookTotalLines = 0;

    const chapterRecords = [];
    const contentRecords = [];

    for (let cIdx = 0; cIdx < parsedChapters.length; cIdx++) {
      const ch = parsedChapters[cIdx];
      const startPage = currentPage;
      const startLine = currentLine;

      for (const paragraph of ch.paragraphs) {
        const lines = splitIntoLines(paragraph);
        for (const lineText of lines) {
          contentRecords.push({
            bookId: book.id,
            pageNumber: currentPage,
            lineNumber: currentLine,
            chapterIndex: cIdx + 1,
            text: lineText,
          });

          bookTotalLines++;
          currentLine++;
          if (currentLine > LINES_PER_PAGE) {
            currentPage++;
            currentLine = 1;
          }
        }
        // Small paragraph gap represented by line progression
      }

      const endPage = currentLine === 1 ? Math.max(1, currentPage - 1) : currentPage;
      const endLine = currentLine === 1 ? LINES_PER_PAGE : Math.max(1, currentLine - 1);

      chapterRecords.push({
        bookId: book.id,
        chapterIndex: cIdx + 1,
        chapterTitle: ch.title,
        startPage,
        startLine,
        endPage,
        endLine,
      });
    }

    const finalTotalPages = (currentLine === 1 && currentPage > 1) ? currentPage - 1 : currentPage;
    const nowIso = new Date().toISOString();

    // 1. Insert book metadata
    insertBook.run(
      book.id,
      book.title,
      book.author || 'Zac Poonen',
      book.description || '',
      book.localCoverFile || '',
      finalTotalPages,
      bookTotalLines,
      nowIso
    );

    sqlStatements.push(`INSERT INTO books VALUES (${escapeSql(book.id)}, ${escapeSql(book.title)}, ${escapeSql(book.author)}, ${escapeSql(book.description)}, ${escapeSql(book.localCoverFile)}, ${finalTotalPages}, ${bookTotalLines}, ${escapeSql(nowIso)});`);

    // 2. Insert chapters
    for (const ch of chapterRecords) {
      insertChapter.run(
        ch.bookId,
        ch.chapterIndex,
        ch.chapterTitle,
        ch.startPage,
        ch.startLine,
        ch.endPage,
        ch.endLine
      );
      sqlStatements.push(`INSERT INTO book_chapters VALUES (${escapeSql(ch.bookId)}, ${ch.chapterIndex}, ${escapeSql(ch.chapterTitle)}, ${ch.startPage}, ${ch.startLine}, ${ch.endPage}, ${ch.endLine});`);
    }

    // 3. Insert content lines
    db.exec('BEGIN TRANSACTION;');
    for (const row of contentRecords) {
      insertLine.run(row.bookId, row.pageNumber, row.lineNumber, row.chapterIndex, row.text);
      sqlStatements.push(`INSERT INTO book_content VALUES (${escapeSql(row.bookId)}, ${row.pageNumber}, ${row.lineNumber}, ${row.chapterIndex}, ${escapeSql(row.text)});`);
    }
    db.exec('COMMIT;');

    totalIngestedBooks++;
    totalIngestedChapters += chapterRecords.length;
    totalIngestedLines += bookTotalLines;

    console.log(`✓ Ingested: "${book.title}" (${chapterRecords.length} chapters, ${finalTotalPages} pages, ${bookTotalLines} lines)`);
  }

  sqlStatements.push(`COMMIT;`);
  fs.writeFileSync(OUT_SQL, sqlStatements.join('\n'), 'utf8');

  console.log(`\n========================================`);
  console.log(`Books ingestion completed!`);
  console.log(`SQLite database: ${OUT_SQLITE} (${(fs.statSync(OUT_SQLITE).size / (1024 * 1024)).toFixed(2)} MB)`);
  console.log(`SQL statements:  ${OUT_SQL} (${(fs.statSync(OUT_SQL).size / (1024 * 1024)).toFixed(2)} MB)`);
  console.log(`Total Books:     ${totalIngestedBooks}`);
  console.log(`Total Chapters:  ${totalIngestedChapters}`);
  console.log(`Total Lines:     ${totalIngestedLines}`);
  console.log(`========================================`);
}

main().catch(err => {
  console.error('Fatal error during books ingestion:', err);
  process.exit(1);
});
