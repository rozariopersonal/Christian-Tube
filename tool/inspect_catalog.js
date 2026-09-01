const fs = require('fs');
const path = require('path');

const contentPath = 'C:/Users/Arul Rozario/.gemini/antigravity-ide/brain/7c68c2f5-2e54-424d-b350-6c3f08feead0/.system_generated/steps/79/content.md';
const html = fs.readFileSync(contentPath, 'utf8');

// Regex to extract books
// <div class="col-lg-3 col-md-4 col-sm-4 col-xs-6 nopadding single-book-item">
const items = html.split(/class=["'][^"']*single-book-item[^"']*["']/);
console.log('Book chunks found:', items.length - 1);

const books = [];
for (let i = 1; i < items.length; i++) {
  const chunk = items[i];
  
  // Title & link: <h6 class="book-title">\s*<a title="([^"]+)" href="([^"]+)"
  const titleMatch = chunk.match(/<h6 class=["']book-title["']>\s*<a title=["']([^"']+)["'] href=["']([^"']+)["']/);
  const title = titleMatch ? titleMatch[1].trim() : 'Unknown';
  const pageUrl = titleMatch ? titleMatch[2].trim() : '';

  // Cover image: <img src="([^"]+)"
  const imgMatch = chunk.match(/<figure class=["']book-thumbnail["']>\s*<img src=["']([^"']+)["']/);
  const coverUrl = imgMatch ? imgMatch[1].trim() : '';

  // Description: <div class="field-item even" property="schema:summary">([^<]+)</div>
  const descMatch = chunk.match(/property=["']schema:summary["']>([^<]+)<\/div>/);
  const desc = descMatch ? descMatch[1].trim() : '';

  // EPUB link: href="([^"]+\.epub)" or href="([^"]+/epub/[^"]+)"
  const epubMatch = chunk.match(/href=["']([^"']*(?:\.epub|\/epub\/[^"']+))["']/);
  const epubUrl = epubMatch ? epubMatch[1].trim() : '';

  // MOBI link
  const mobiMatch = chunk.match(/href=["']([^"']*\.mobi)["']/);
  const mobiUrl = mobiMatch ? mobiMatch[1].trim() : '';

  books.push({
    title,
    pageUrl,
    coverUrl,
    desc,
    epubUrl,
    mobiUrl
  });
}

console.log(`Parsed ${books.length} books.`);
console.log('Sample book 0:', JSON.stringify(books[0], null, 2));
console.log('Sample Through the Bible:', JSON.stringify(books.find(b => b.title.includes('Through The Bible')), null, 2));

const withEpub = books.filter(b => b.epubUrl);
console.log(`Books with EPUB link directly on catalog page: ${withEpub.length}/${books.length}`);
