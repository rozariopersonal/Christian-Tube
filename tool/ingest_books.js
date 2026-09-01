#!/usr/bin/env node
/**
 * tool/ingest_books.js
 *
 * Converts downloaded raw books into structured SQLite database and SQL file
 * while strictly preserving the original layout:
 *  - Chapter numbers and Chapter titles
 *  - Section headings (h2)
 *  - Subheadings (h3, h4, h5)
 *  - Callout quotes (blockquote)
 *  - Continuous, natural paragraphs (p)
 *
 * Tables created:
 *  - books: Catalog metadata, page & line counts, covers
 *  - book_chapters: TOC chapters with start/end page & line boundaries
 *  - book_content: (book_id, page_number, line_number, chapter_index, content_type, text)
 *
 * Output:
 *  - data/books.sqlite (SQLite database)
 *  - data/books.sql (Raw SQL statements)
 *
 * Usage:
 *  node tool/ingest_books.js
 */

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { DatabaseSync } = require('node:sqlite');

const RAW_DIR = path.join(__dirname, '..', 'data', 'books_raw');
const CATALOG_PATH = path.join(RAW_DIR, 'catalog.json');
const HTML_DIR = path.join(RAW_DIR, 'html');
const OUT_SQLITE = path.join(__dirname, '..', 'data', 'books.sqlite');
const OUT_SQL = path.join(__dirname, '..', 'data', 'books.sql');
const OUT_GZ = path.join(__dirname, '..', 'data', 'books.sqlite.gz');
const APP_CATALOG = path.join(__dirname, '..', 'apps', 'mobile', 'assets', 'books', 'catalog.json');

// Target reading page size for digital books (~250-320 words)
const TARGET_CHARS_PER_PAGE = 1500;

function cleanHtmlText(html) {
  return html
    .replace(/<a\b[^>]*>(.*?)<\/a>/gi, '$1')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .replace(/&#39;/g, "'")
    .replace(/&rsquo;/g, "'")
    .replace(/&lsquo;/g, "'")
    .replace(/&rdquo;/g, '"')
    .replace(/&ldquo;/g, '"')
    .replace(/&mdash;/g, '—')
    .replace(/&ndash;/g, '–')
    .replace(/<[^>]+>/g, '')
    .replace(/\r\n|\r|\n/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Splits a very long paragraph (> 1500 chars) at sentence boundaries
 * so it flows across page boundaries without cutting sentences in half.
 */
function splitParagraphIntoSentences(text, maxChars = TARGET_CHARS_PER_PAGE) {
  if (text.length <= maxChars) return [text];

  const sentences = text.match(/[^.!?]+[.!?]+["'”]?\s*/g) || [text];
  const chunks = [];
  let currentChunk = '';

  for (const sentence of sentences) {
    if (!currentChunk) {
      currentChunk = sentence.trim();
    } else if ((currentChunk.length + sentence.length) <= maxChars) {
      currentChunk += ' ' + sentence.trim();
    } else {
      chunks.push(currentChunk);
      currentChunk = sentence.trim();
    }
  }

  if (currentChunk) {
    chunks.push(currentChunk);
  }

  return chunks.length > 0 ? chunks : [text];
}

/**
 * Parses the book's chapter structure and elements preserving original layout.
 */
function parseBookHtml(htmlContent) {
  const chapters = [];
  const chapterChunks = htmlContent.split(/<div\s+id=["'][^"']+["']\s+class=["'][^"']*chapter[^"']*["']/i);

  for (let i = 1; i < chapterChunks.length; i++) {
    const chunk = chapterChunks[i];

    // Extract chapter title & number
    const titleMatch = chunk.match(/<h4 class=["']books-chapter-title["']>([\s\S]*?)<\/h4>/i);
    let chapterNum = '';
    let chapterTitle = 'Chapter ' + i;

    if (titleMatch) {
      const numMatch = titleMatch[1].match(/<div class=["']chapter-number["']>([\s\S]*?)<\/div>/i);
      if (numMatch) {
        chapterNum = cleanHtmlText(numMatch[1]);
      }
      const rawTitle = titleMatch[1].replace(/<div class=["']chapter-number["']>[\s\S]*?<\/div>/i, '');
      chapterTitle = cleanHtmlText(rawTitle);
      if (!chapterTitle && chapterNum) {
        chapterTitle = chapterNum;
      }
    }

    // Extract elements in exact sequential order: h2, h3, h4, h5, blockquote, p
    const elements = [];
    const elemRegex = /<(h2|h3|h4|h5|blockquote|p)(?:\s+[^>]*)?>([\s\S]*?)<\/\1>/gi;
    let match;

    while ((match = elemRegex.exec(chunk)) !== null) {
      const tag = match[1].toLowerCase();
      const text = cleanHtmlText(match[2]);

      if (!text || text.length < 2) continue;
      if (text.includes('austincfc.church/books') || text.includes('order by Email')) continue;
      if (text.startsWith('Chapter ') && text === chapterTitle) continue;

      let type = 'p';
      if (tag === 'h2') type = 'h2';
      else if (tag === 'h3' || tag === 'h4' || tag === 'h5') type = 'h3';
      else if (tag === 'blockquote') type = 'blockquote';

      elements.push({ type, text });
    }

    if (elements.length > 0) {
      chapters.push({
        chapterNum,
        title: chapterTitle,
        elements,
      });
    }
  }

  // Fallback: If no chapter divs matched
  if (chapters.length === 0) {
    const allElements = [];
    const elemRegex = /<(h2|h3|h4|blockquote|p)(?:\s+[^>]*)?>([\s\S]*?)<\/\1>/gi;
    let match;
    while ((match = elemRegex.exec(htmlContent)) !== null) {
      const tag = match[1].toLowerCase();
      const text = cleanHtmlText(match[2]);
      if (text && text.length > 20 && !text.includes('austincfc.church')) {
        let type = 'p';
        if (tag === 'h2') type = 'h2';
        else if (tag === 'h3' || tag === 'h4') type = 'h3';
        else if (tag === 'blockquote') type = 'blockquote';
        allElements.push({ type, text });
      }
    }
    if (allElements.length > 0) {
      chapters.push({
        chapterNum: '',
        title: 'Full Book',
        elements: allElements,
      });
    }
  }

  return chapters;
}

function escapeSql(str) {
  if (str === null || str === undefined) return 'NULL';
  return "'" + str.replace(/'/g, "''") + "'";
}

function resolvePrimarySubject(cats, author, bookId) {
  if (author.toLowerCase().includes('annie') || cats.includes('Woman')) {
    return 'Women & Mothers';
  }
  if (cats.includes('The home') || bookId.includes('marriage') || bookId.includes('family')) {
    return 'The Home & Family';
  }
  if (cats.includes('Foundational Truth') || cats.includes('Seeker') || bookId.includes('foundation') || bookId.includes('truth')) {
    return 'Foundational Truths';
  }
  if (cats.includes('The Church') || cats.includes('Leader') || bookId.includes('church') || bookId.includes('leader')) {
    return 'The Church & Leadership';
  }
  if (cats.includes('Spirit Filled life') || cats.includes('Devotion to Christ') || bookId.includes('spirit') || bookId.includes('praying')) {
    return 'Spirit-Filled Life & Devotion';
  }
  return 'Discipleship & Christian Living';
}

function extractBookMetadata(html, fallbackAuthor, bookId) {
  const authorMatch = html.match(/writen-by[\s\S]*?Written by\s*:\s*([\s\S]*?)<\/span>/i);
  const catMatch = html.match(/categories-list[\s\S]*?Categories\s*:\s*([\s\S]*?)<\/span>/i);

  const author = authorMatch ? cleanHtmlText(authorMatch[1]) : (fallbackAuthor || 'Zac Poonen');
  const cats = [];
  if (catMatch) {
    const aMatches = catMatch[1].matchAll(/<a\b[^>]*>([\s\S]*?)<\/a>/gi);
    for (const a of aMatches) {
      const c = cleanHtmlText(a[1]);
      if (c) cats.push(c);
    }
  }

  const subject = resolvePrimarySubject(cats, author, bookId);
  return { author, categories: cats, subject };
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
      PRIMARY KEY (book_id, chapter_index),
      FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
    );

    CREATE TABLE book_content (
      book_id TEXT NOT NULL,
      page_number INTEGER NOT NULL,
      line_number INTEGER NOT NULL,
      chapter_index INTEGER NOT NULL,
      content_type TEXT NOT NULL DEFAULT 'p',
      text TEXT NOT NULL,
      PRIMARY KEY (book_id, page_number, line_number),
      FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
    );

    CREATE INDEX idx_book_page ON book_content (book_id, page_number);
  `);

  const insertBook = db.prepare(`
    INSERT INTO books (id, title, author, subject, categories, description, cover_file, total_pages, total_lines, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const insertChapter = db.prepare(`
    INSERT INTO book_chapters (book_id, chapter_index, chapter_title, start_page, start_line, end_page, end_line)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `);

  const insertLine = db.prepare(`
    INSERT INTO book_content (book_id, page_number, line_number, chapter_index, content_type, text)
    VALUES (?, ?, ?, ?, ?, ?)
  `);

  const sqlStatements = [
    `-- Generated by tool/ingest_books.js`,
    `-- Total Books: ${catalog.length}`,
    `PRAGMA foreign_keys = ON;`,
    `BEGIN TRANSACTION;`,
  ];

  let totalIngestedBooks = 0;
  let totalIngestedChapters = 0;
  let totalIngestedElements = 0;

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
    let currentCharsOnPage = 0;
    let bookTotalElements = 0;

    const chapterRecords = [];
    const contentRecords = [];

    for (let cIdx = 0; cIdx < parsedChapters.length; cIdx++) {
      const ch = parsedChapters[cIdx];

      // New chapter always begins on a fresh page (except if page 1 is completely empty)
      if (currentCharsOnPage > 0 || currentLine > 1) {
        currentPage++;
        currentLine = 1;
        currentCharsOnPage = 0;
      }

      const startPage = currentPage;
      const startLine = currentLine;

      // 1. Chapter Header entry
      const headerText = (ch.chapterNum ? ch.chapterNum + ' ' : '') + ch.title;
      contentRecords.push({
        bookId: book.id,
        pageNumber: currentPage,
        lineNumber: currentLine,
        chapterIndex: cIdx + 1,
        contentType: 'chapter_header',
        text: headerText,
      });

      bookTotalElements++;
      currentLine++;
      currentCharsOnPage += headerText.length;

      // 2. Elements within chapter
      for (const elem of ch.elements) {
        const textChunks = (elem.type === 'p' && elem.text.length > TARGET_CHARS_PER_PAGE)
          ? splitParagraphIntoSentences(elem.text, TARGET_CHARS_PER_PAGE)
          : [elem.text];

        for (const chunk of textChunks) {
          // If adding this chunk exceeds page capacity, advance to next page
          if (currentCharsOnPage > 0 && (currentCharsOnPage + chunk.length > TARGET_CHARS_PER_PAGE)) {
            currentPage++;
            currentLine = 1;
            currentCharsOnPage = 0;
          }

          contentRecords.push({
            bookId: book.id,
            pageNumber: currentPage,
            lineNumber: currentLine,
            chapterIndex: cIdx + 1,
            contentType: elem.type,
            text: chunk,
          });

          bookTotalElements++;
          currentLine++;
          currentCharsOnPage += chunk.length;
        }
      }

      const endPage = currentPage;
      const endLine = Math.max(1, currentLine - 1);

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

    const finalTotalPages = currentPage;
    const nowIso = new Date().toISOString();

    const meta = extractBookMetadata(rawHtml, book.author, book.id);
    book.author = meta.author;
    book.subject = meta.subject;
    book.categories = meta.categories;
    book.totalPages = finalTotalPages;
    book.totalLines = bookTotalElements;

    // 1. Insert book metadata
    insertBook.run(
      book.id,
      book.title,
      meta.author,
      meta.subject,
      JSON.stringify(meta.categories),
      book.description || '',
      book.localCoverFile || '',
      finalTotalPages,
      bookTotalElements,
      nowIso
    );

    sqlStatements.push(`INSERT INTO books VALUES (${escapeSql(book.id)}, ${escapeSql(book.title)}, ${escapeSql(meta.author)}, ${escapeSql(meta.subject)}, ${escapeSql(JSON.stringify(meta.categories))}, ${escapeSql(book.description)}, ${escapeSql(book.localCoverFile)}, ${finalTotalPages}, ${bookTotalElements}, ${escapeSql(nowIso)});`);

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

    // 3. Insert content elements
    db.exec('BEGIN TRANSACTION;');
    for (const row of contentRecords) {
      insertLine.run(row.bookId, row.pageNumber, row.lineNumber, row.chapterIndex, row.contentType, row.text);
      sqlStatements.push(`INSERT INTO book_content VALUES (${escapeSql(row.bookId)}, ${row.pageNumber}, ${row.lineNumber}, ${row.chapterIndex}, ${escapeSql(row.contentType)}, ${escapeSql(row.text)});`);
    }
    db.exec('COMMIT;');

    totalIngestedBooks++;
    totalIngestedChapters += chapterRecords.length;
    totalIngestedElements += bookTotalElements;

    console.log(`✓ Ingested: "${book.title}" (${chapterRecords.length} chapters, ${finalTotalPages} pages, ${bookTotalElements} elements)`);
  }

  sqlStatements.push(`COMMIT;`);

  // Write SQL file
  fs.writeFileSync(OUT_SQL, sqlStatements.join('\n'), 'utf8');

  function safeWriteFile(filePath, data) {
    for (let attempt = 1; attempt <= 5; attempt++) {
      try {
        fs.writeFileSync(filePath, data, 'utf8');
        return;
      } catch (err) {
        if (attempt === 5) throw err;
        const end = Date.now() + attempt * 100;
        while (Date.now() < end) {}
      }
    }
  }

  // Update catalog JSONs
  safeWriteFile(CATALOG_PATH, JSON.stringify(catalog, null, 2));
  if (fs.existsSync(APP_CATALOG)) {
    safeWriteFile(APP_CATALOG, JSON.stringify(catalog, null, 2));
  }

  // Compress sqlite to .gz
  console.log('\nCompressing books.sqlite to books.sqlite.gz...');
  const dbBuffer = fs.readFileSync(OUT_SQLITE);
  const gzBuffer = zlib.gzipSync(dbBuffer, { level: 9 });
  fs.writeFileSync(OUT_GZ, gzBuffer);

  const sqliteSizeMb = (fs.statSync(OUT_SQLITE).size / (1024 * 1024)).toFixed(2);
  const sqlSizeMb = (fs.statSync(OUT_SQL).size / (1024 * 1024)).toFixed(2);
  const gzSizeMb = (fs.statSync(OUT_GZ).size / (1024 * 1024)).toFixed(2);

  console.log('\n========================================');
  console.log('Books ingestion with original layout completed!');
  console.log(`SQLite database: ${OUT_SQLITE} (${sqliteSizeMb} MB)`);
  console.log(`Gzipped bundle:  ${OUT_GZ} (${gzSizeMb} MB)`);
  console.log(`SQL statements:  ${OUT_SQL} (${sqlSizeMb} MB)`);
  console.log(`Total Books:     ${totalIngestedBooks}`);
  console.log(`Total Chapters:  ${totalIngestedChapters}`);
  console.log(`Total Elements:  ${totalIngestedElements}`);
  console.log('========================================\n');
}

main().catch(err => {
  console.error('Fatal error during books ingestion:', err);
  process.exit(1);
});
