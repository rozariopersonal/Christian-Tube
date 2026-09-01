const { DatabaseSync } = require('node:sqlite');
const path = require('path');

const db = new DatabaseSync(path.join(__dirname, '..', 'data', 'books.sqlite'));

function testLookup(bookNum, bookName, chap, verse) {
  console.log(`\n============================================================`);
  console.log(`Commentary Lookup for: ${bookName} ${chap}:${verse}`);
  console.log(`============================================================`);

  const links = db.prepare(`
    SELECT l.book_id, l.book_number, l.chapter, l.verse, l.end_verse, l.page_number, l.start_line, l.end_line, l.headline,
           b.title as book_title, b.author
    FROM book_scripture_links l
    JOIN books b ON l.book_id = b.id
    WHERE l.book_number = ? AND l.chapter = ? AND l.verse = ?
  `).all(bookNum, chap, verse);

  console.log(`Found ${links.length} commentary note(s):\n`);

  for (let i = 0; i < links.length; i++) {
    const r = links[i];
    console.log(`[${i + 1}] Book: "${r.book_title}" (Author: ${r.author})`);
    console.log(`    Location: Page ${r.page_number}, Lines ${r.start_line}–${r.end_line}`);
    console.log(`    Headline: ${r.headline}`);

    // Fetch the actual text lines
    const textRows = db.prepare(`
      SELECT line_number, text 
      FROM book_content 
      WHERE book_id = ? AND page_number = ? AND line_number BETWEEN ? AND ?
      ORDER BY line_number ASC
    `).all(r.book_id, r.page_number, r.start_line, r.end_line);

    console.log(`    Excerpt:`);
    for (const tr of textRows) {
      console.log(`      L${String(tr.line_number).padStart(2, '0')}: ${tr.text}`);
    }
    console.log('');
  }
}

testLookup(45, 'Romans', 8, 28);
testLookup(66, 'Revelation', 1, 1);
testLookup(58, 'Hebrews', 12, 1);
