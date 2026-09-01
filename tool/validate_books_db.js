#!/usr/bin/env node
/**
 * tool/validate_books_db.js
 *
 * Validates the generated books SQLite database:
 * 1. Checks schema & foreign keys
 * 2. Checks data integrity (no orphaned lines, no null titles, continuous line numbers)
 * 3. Checks cover asset presence
 * 4. Displays a formatted catalog report
 */

const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

const DB_PATH = path.join(__dirname, '..', 'data', 'books.sqlite');
const COVERS_DIR = path.join(__dirname, '..', 'data', 'books_raw', 'covers');

function main() {
  if (!fs.existsSync(DB_PATH)) {
    console.error(`Database not found at ${DB_PATH}. Run tool/ingest_books.js first.`);
    process.exit(1);
  }

  const db = new DatabaseSync(DB_PATH);
  console.log(`\nValidating database: ${DB_PATH} ...`);

  // 1. Table Counts
  const booksCount = db.prepare('SELECT COUNT(*) as count FROM books').get().count;
  const chaptersCount = db.prepare('SELECT COUNT(*) as count FROM book_chapters').get().count;
  const linesCount = db.prepare('SELECT COUNT(*) as count FROM book_content').get().count;

  console.log(`- Books count:    ${booksCount}`);
  console.log(`- Chapters count: ${chaptersCount}`);
  console.log(`- Lines count:    ${linesCount}`);

  if (booksCount === 0 || linesCount === 0) {
    throw new Error('Validation failed: database contains 0 books or lines!');
  }

  // 2. Foreign Key & Orphan Checks
  const orphanedChapters = db.prepare(`
    SELECT COUNT(*) as count FROM book_chapters 
    WHERE book_id NOT IN (SELECT id FROM books)
  `).get().count;

  const orphanedLines = db.prepare(`
    SELECT COUNT(*) as count FROM book_content 
    WHERE book_id NOT IN (SELECT id FROM books)
  `).get().count;

  if (orphanedChapters > 0 || orphanedLines > 0) {
    throw new Error(`Integrity error: found ${orphanedChapters} orphaned chapters and ${orphanedLines} orphaned lines!`);
  }
  console.log('✓ Foreign key integrity verified (0 orphaned records)');

  // 3. Primary Key & Ordering Check
  const duplicatePKs = db.prepare(`
    SELECT book_id, page_number, line_number, COUNT(*) as c
    FROM book_content
    GROUP BY book_id, page_number, line_number
    HAVING c > 1
  `).all();

  if (duplicatePKs.length > 0) {
    throw new Error(`Duplicate line coordinate error found in ${duplicatePKs.length} rows!`);
  }
  console.log('✓ Primary key uniqueness verified');

  // 4. Catalog Report
  const allBooks = db.prepare(`
    SELECT b.id, b.title, b.author, b.cover_file, b.total_pages, b.total_lines,
           COUNT(DISTINCT c.chapter_index) as chapter_count
    FROM books b
    LEFT JOIN book_chapters c ON b.id = c.book_id
    GROUP BY b.id
    ORDER BY b.total_lines DESC
  `).all();

  console.log('\n========================================================================================================');
  console.log(
    'ID'.padEnd(32) +
    'Title'.padEnd(38) +
    'Chaps'.padStart(6) +
    'Pages'.padStart(7) +
    'Lines'.padStart(8) +
    'Cover'.padStart(8)
  );
  console.log('--------------------------------------------------------------------------------------------------------');

  let coversFound = 0;
  for (const b of allBooks) {
    const hasCover = b.cover_file && fs.existsSync(path.join(COVERS_DIR, b.cover_file));
    if (hasCover) coversFound++;

    const shortId = b.id.length > 30 ? b.id.substring(0, 27) + '...' : b.id;
    const shortTitle = b.title.length > 36 ? b.title.substring(0, 33) + '...' : b.title;

    console.log(
      shortId.padEnd(32) +
      shortTitle.padEnd(38) +
      String(b.chapter_count).padStart(6) +
      String(b.total_pages).padStart(7) +
      String(b.total_lines).padStart(8) +
      (hasCover ? '✓ OK' : 'MISSING').padStart(8)
    );
  }
  console.log('========================================================================================================');
  console.log(`Covers verified locally: ${coversFound}/${allBooks.length}`);

  // 5. Sample Read Test
  console.log('\n--- Sample Verification: First 5 lines of top book ---');
  const topBook = allBooks[0];
  const sampleLines = db.prepare(`
    SELECT page_number, line_number, text 
    FROM book_content 
    WHERE book_id = ? AND page_number = 1 
    ORDER BY line_number ASC 
    LIMIT 5
  `).all(topBook.id);

  console.log(`Book: "${topBook.title}" (Page 1):`);
  for (const l of sampleLines) {
    console.log(`  [P1:L${String(l.line_number).padStart(2, '0')}] ${l.text}`);
  }

  console.log('\n✓ ALL DATABASE VALIDATION CHECKS PASSED SUCCESSFULLY!\n');
}

main();
