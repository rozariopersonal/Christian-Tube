const fs = require('fs');

const contentPath = 'C:/Users/Arul Rozario/.gemini/antigravity-ide/brain/7c68c2f5-2e54-424d-b350-6c3f08feead0/.system_generated/steps/79/content.md';
const html = fs.readFileSync(contentPath, 'utf8');

const items = html.split(/class=["'][^"']*single-book-item[^"']*["']/);
const books = [];
for (let i = 1; i < items.length; i++) {
  const chunk = items[i];
  const titleMatch = chunk.match(/<h6 class=["']book-title["']>\s*<a title=["']([^"']+)["'] href=["']([^"']+)["']/);
  const title = titleMatch ? titleMatch[1].trim() : 'Unknown';
  const pageUrl = titleMatch ? titleMatch[2].trim() : '';
  const coverMatch = chunk.match(/<figure class=["']book-thumbnail["']>\s*<img src=["']([^"']+)["']/);
  const coverUrl = coverMatch ? coverMatch[1].trim() : '';
  const epubMatch = chunk.match(/href=["']([^"']*(?:\.epub|\/epub\/[^"']+))["']/);
  const epubUrl = epubMatch ? epubMatch[1].trim() : '';

  books.push({ title, pageUrl, coverUrl, epubUrl });
}

const withoutEpub = books.filter(b => !b.epubUrl);
console.log('Books without direct EPUB in catalog:');
for (const b of withoutEpub) {
  console.log(`- ${b.title} (${b.pageUrl})`);
}
