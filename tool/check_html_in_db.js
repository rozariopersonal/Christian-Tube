const { DatabaseSync } = require('node:sqlite');
const path = require('path');

const db = new DatabaseSync(path.join(__dirname, '..', 'data', 'books.sqlite'));

const sampleHtml = db.prepare(`SELECT text FROM book_content WHERE text LIKE '%<%' OR text LIKE '%>%' LIMIT 10`).all();
console.log('Lines containing < or > in book_content:', sampleHtml.length);
for (const s of sampleHtml) {
  console.log(' ', s.text);
}

const sampleStyle = db.prepare(`SELECT text FROM book_content WHERE text LIKE '%style=%' OR text LIKE '%class=%' LIMIT 10`).all();
console.log('Lines containing style= or class=:', sampleStyle.length);

const sampleRandom = db.prepare(`SELECT text FROM book_content WHERE book_id = 'beauty_for_ashes' AND page_number = 5 LIMIT 10`).all();
console.log('\nSample 10 lines from Beauty for Ashes (Page 5):');
for (const s of sampleRandom) {
  console.log(' ', JSON.stringify(s.text));
}
