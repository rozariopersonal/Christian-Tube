#!/usr/bin/env node
/**
 * tool/extract_scripture_links.js
 *
 * Scans all ingested books in `data/books.sqlite` for Bible verse references
 * and builds the `book_scripture_links` table for the commentary engine:
 *
 * Schema:
 *  - book_scripture_links (book_number, chapter, verse, end_verse, book_id, page_number, start_line, end_line, headline)
 *
 * Usage:
 *  node tool/extract_scripture_links.js
 */

const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

const DB_PATH = path.join(__dirname, '..', 'data', 'books.sqlite');

const BIBLE_BOOKS = {
  // Old Testament
  'GENESIS': 1, 'GEN': 1,
  'EXODUS': 2, 'EXO': 2, 'EXOD': 2,
  'LEVITICUS': 3, 'LEV': 3,
  'NUMBERS': 4, 'NUM': 4,
  'DEUTERONOMY': 5, 'DEUT': 5, 'DEU': 5,
  'JOSHUA': 6, 'JOSH': 6, 'JOS': 6,
  'JUDGES': 7, 'JUDG': 7, 'JDG': 7,
  'RUTH': 8, 'RUT': 8,
  '1 SAMUEL': 9, '1SAM': 9, '1 SAM': 9, '1SA': 9, '1ST SAMUEL': 9,
  '2 SAMUEL': 10, '2SAM': 10, '2 SAM': 10, '2SA': 10, '2ND SAMUEL': 10,
  '1 KINGS': 11, '1KGS': 11, '1 KGS': 11, '1KI': 11, '1ST KINGS': 11,
  '2 KINGS': 12, '2KGS': 12, '2 KGS': 12, '2KI': 12, '2ND KINGS': 12,
  '1 CHRONICLES': 13, '1CHRON': 13, '1 CHRON': 13, '1CH': 13,
  '2 CHRONICLES': 14, '2CHRON': 14, '2 CHRON': 14, '2CH': 14,
  'EZRA': 15, 'EZR': 15,
  'NEHEMIAH': 16, 'NEH': 16,
  'ESTHER': 17, 'EST': 17, 'ESTH': 17,
  'JOB': 18,
  'PSALM': 19, 'PSALMS': 19, 'PSA': 19, 'PS': 19,
  'PROVERBS': 20, 'PROV': 20, 'PRO': 20,
  'ECCLESIASTES': 21, 'ECCLES': 21, 'ECC': 21,
  'SONG OF SOLOMON': 22, 'SONG OF SONGS': 22, 'SNG': 22, 'CANTICLES': 22,
  'ISAIAH': 23, 'ISA': 23,
  'JEREMIAH': 24, 'JER': 24,
  'LAMENTATIONS': 25, 'LAM': 25,
  'EZEKIEL': 26, 'EZEK': 26, 'EZK': 26,
  'DANIEL': 27, 'DAN': 27,
  'HOSEA': 28, 'HOS': 28,
  'JOEL': 29, 'JOL': 29,
  'AMOS': 30, 'AMO': 30,
  'OBADIAH': 31, 'OBAD': 31, 'OBA': 31,
  'JONAH': 32, 'JON': 32,
  'MICAH': 33, 'MIC': 33,
  'NAHUM': 34, 'NAH': 34, 'NAM': 34,
  'HABAKKUK': 35, 'HAB': 35,
  'ZEPHANIAH': 36, 'ZEPH': 36, 'ZEP': 36,
  'HAGGAI': 37, 'HAG': 37,
  'ZECHARIAH': 38, 'ZECH': 38, 'ZEC': 38,
  'MALACHI': 39, 'MAL': 39,

  // New Testament
  'MATTHEW': 40, 'MATT': 40, 'MAT': 40,
  'MARK': 41, 'MRK': 41,
  'LUKE': 42, 'LUK': 42,
  'JOHN': 43, 'JHN': 43,
  'ACTS': 44, 'ACT': 44,
  'ROMANS': 45, 'ROM': 45,
  '1 CORINTHIANS': 46, '1COR': 46, '1 COR': 46, '1CO': 46, '1ST CORINTHIANS': 46,
  '2 CORINTHIANS': 47, '2COR': 47, '2 COR': 47, '2CO': 47, '2ND CORINTHIANS': 47,
  'GALATIANS': 48, 'GAL': 48,
  'EPHESIANS': 49, 'EPH': 49,
  'PHILIPPIANS': 50, 'PHIL': 50, 'PHP': 50,
  'COLOSSIANS': 51, 'COL': 51,
  '1 THESSALONIANS': 52, '1THESS': 52, '1 THESS': 52, '1TH': 52,
  '2 THESSALONIANS': 53, '2THESS': 53, '2 THESS': 53, '2TH': 53,
  '1 TIMOTHY': 54, '1TIM': 54, '1 TIM': 54, '1TI': 54,
  '2 TIMOTHY': 55, '2TIM': 55, '2 TIM': 55, '2TI': 55,
  'TITUS': 56, 'TIT': 56,
  'PHILEMON': 57, 'PHILEM': 57, 'PHM': 57,
  'HEBREWS': 58, 'HEB': 58,
  'JAMES': 59, 'JAS': 59,
  '1 PETER': 60, '1PET': 60, '1 PET': 60, '1PE': 60,
  '2 PETER': 61, '2PET': 61, '2 PET': 61, '2PE': 61,
  '1 JOHN': 62, '1JHN': 62, '1 JN': 62, '1JN': 62,
  '2 JOHN': 63, '2JHN': 63, '2 JN': 63, '2JN': 63,
  '3 JOHN': 64, '3JHN': 64, '3 JN': 64, '3JN': 64,
  'JUDE': 65, 'JUD': 65,
  'REVELATION': 66, 'REV': 66,
};

// Compile regex for all book aliases
const bookNamesPattern = Object.keys(BIBLE_BOOKS)
  .sort((a, b) => b.length - a.length)
  .map(n => n.replace(/\s+/g, '\\s+'))
  .join('|');

const SCRIPTURE_REGEX = new RegExp(
  `\\b(${bookNamesPattern})\\.?\\s*(\\d+)[:.](\\d+)(?:-(\\d+))?\\b`,
  'gi'
);

function main() {
  if (!fs.existsSync(DB_PATH)) {
    console.error(`Database not found at ${DB_PATH}.`);
    process.exit(1);
  }

  const db = new DatabaseSync(DB_PATH);
  console.log(`\nExtracting Scripture links from ${DB_PATH} ...`);

  db.exec(`
    CREATE TABLE IF NOT EXISTS book_scripture_links (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      book_number INTEGER NOT NULL,
      chapter INTEGER NOT NULL,
      verse INTEGER NOT NULL,
      end_verse INTEGER,
      book_id TEXT NOT NULL,
      page_number INTEGER NOT NULL,
      start_line INTEGER NOT NULL,
      end_line INTEGER NOT NULL,
      headline TEXT,
      FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_scripture_links 
    ON book_scripture_links (book_number, chapter, verse);
  `);

  // Clear existing links
  db.exec('DELETE FROM book_scripture_links;');

  const insertLink = db.prepare(`
    INSERT INTO book_scripture_links (book_number, chapter, verse, end_verse, book_id, page_number, start_line, end_line, headline)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const allLines = db.prepare(`
    SELECT c.book_id, c.page_number, c.line_number, c.text, ch.chapter_title
    FROM book_content c
    LEFT JOIN book_chapters ch ON c.book_id = ch.book_id AND c.chapter_index = ch.chapter_index
    ORDER BY c.book_id, c.page_number, c.line_number
  `).all();

  console.log(`Scanning ${allLines.length} lines for Bible references...`);

  let extractedCount = 0;
  const seenVersesOnPage = new Set();

  db.exec('BEGIN TRANSACTION;');

  for (let i = 0; i < allLines.length; i++) {
    const row = allLines[i];
    SCRIPTURE_REGEX.lastIndex = 0;

    let match;
    while ((match = SCRIPTURE_REGEX.exec(row.text)) !== null) {
      const rawBook = match[1].toUpperCase().replace(/\s+/g, ' ').trim();
      const bookNum = BIBLE_BOOKS[rawBook];
      if (!bookNum) continue;

      const chap = parseInt(match[2], 10);
      const verse = parseInt(match[3], 10);
      const endVerse = match[4] ? parseInt(match[4], 10) : verse;

      // Avoid duplicate tags for the exact same verse on the same page
      const dedupKey = `${row.book_id}_${row.page_number}_${bookNum}_${chap}_${verse}`;
      if (seenVersesOnPage.has(dedupKey)) continue;
      seenVersesOnPage.add(dedupKey);

      // Slicing context: capture ~3 lines before to ~3 lines after on this page
      const startLine = Math.max(1, row.line_number - 2);
      const endLine = Math.min(28, row.line_number + 3);

      const headline = row.chapter_title || `${rawBook} ${chap}:${verse}`;

      insertLink.run(
        bookNum,
        chap,
        verse,
        endVerse,
        row.book_id,
        row.page_number,
        startLine,
        endLine,
        headline
      );
      extractedCount++;
    }
  }

  db.exec('COMMIT;');

  console.log(`\n========================================`);
  console.log(`Scripture link extraction completed!`);
  console.log(`Total verse cross-references indexed: ${extractedCount}`);
  console.log(`========================================`);

  // Spot-check top referenced Bible books
  const topBooks = db.prepare(`
    SELECT book_number, COUNT(*) as count 
    FROM book_scripture_links 
    GROUP BY book_number 
    ORDER BY count DESC 
    LIMIT 10
  `).all();

  console.log('\nTop 10 most commented Bible books:');
  const numToName = {};
  for (const [name, num] of Object.entries(BIBLE_BOOKS)) {
    if (!numToName[num] || name.length > numToName[num].length) {
      numToName[num] = name;
    }
  }

  for (const tb of topBooks) {
    console.log(`  - Book #${tb.book_number} (${numToName[tb.book_number]}): ${tb.count} commentary links`);
  }
}

main();
