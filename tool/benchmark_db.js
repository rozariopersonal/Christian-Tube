const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

const dbPath = path.join(__dirname, '..', 'data', 'books.sqlite');
const stats = fs.statSync(dbPath);
const sizeMb = (stats.size / (1024 * 1024)).toFixed(2);

console.log('=== Database File Size ===');
console.log(`File: ${dbPath}`);
console.log(`Size: ${sizeMb} MB (${stats.size} bytes)`);

const db = new DatabaseSync(dbPath);

console.log('\n=== Database Indexes ===');
const indexes = db.prepare(`
  SELECT type, name, tbl_name, sql 
  FROM sqlite_master 
  WHERE type = 'index' AND name NOT LIKE 'sqlite_%'
`).all();

for (const idx of indexes) {
  console.log(`Index: ${idx.name} ON ${idx.tbl_name}`);
  console.log(`  SQL: ${idx.sql}`);
}

console.log('\n=== Query Speed Benchmarks (100 iterations each) ===');

// 1. Verse Commentary Lookup (The query run when a user taps a verse in Bible)
const verseStart = performance.now();
for (let i = 0; i < 100; i++) {
  db.prepare(`
    SELECT l.*, b.title, b.author 
    FROM book_scripture_links l
    JOIN books b ON l.book_id = b.id
    WHERE l.book_number = 45 AND l.chapter = 8 AND l.verse = 28
  `).all();
}
const verseAvg = (performance.now() - verseStart) / 100;
console.log(`1. Verse Commentary Lookup (Romans 8:28): ${verseAvg.toFixed(3)} ms`);

// 2. Reader Page Load (The query run when user turns a page in the reader)
const pageStart = performance.now();
for (let i = 0; i < 100; i++) {
  db.prepare(`
    SELECT line_number, text 
    FROM book_content 
    WHERE book_id = 'beauty_for_ashes' AND page_number = 42
    ORDER BY line_number ASC
  `).all();
}
const pageAvg = (performance.now() - pageStart) / 100;
console.log(`2. Reader Page Load (Beauty for Ashes, Page 42): ${pageAvg.toFixed(3)} ms`);

// 3. Reader Full Chapter Load (Reading a whole chapter)
const chapStart = performance.now();
for (let i = 0; i < 100; i++) {
  db.prepare(`
    SELECT page_number, line_number, text 
    FROM book_content 
    WHERE book_id = 'all_that_jesus_taught' AND chapter_index = 10
    ORDER BY page_number ASC, line_number ASC
  `).all();
}
const chapAvg = (performance.now() - chapStart) / 100;
console.log(`3. Reader Full Chapter Load (All That Jesus Taught, Chapter 10): ${chapAvg.toFixed(3)} ms`);

// 4. Catalog Load (Opening the Books Library grid)
const catStart = performance.now();
for (let i = 0; i < 100; i++) {
  db.prepare(`
    SELECT b.*, COUNT(DISTINCT c.chapter_index) as chapter_count 
    FROM books b 
    LEFT JOIN book_chapters c ON b.id = c.book_id 
    GROUP BY b.id
  `).all();
}
const catAvg = (performance.now() - catStart) / 100;
console.log(`4. Catalog List Load (All 38 books with chapter counts): ${catAvg.toFixed(3)} ms`);
