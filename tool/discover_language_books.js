const fs = require('fs');

const LANG_DOMAINS = [
  { code: 'ta', name: 'Tamil', url: 'https://tamil.cfcindia.com/books' },
  { code: 'hi', name: 'Hindi', url: 'https://hindi.cfcindia.com/books' },
  { code: 'te', name: 'Telugu', url: 'https://telugu.cfcindia.com/books' },
  { code: 'ml', name: 'Malayalam', url: 'https://malayalam.cfcindia.com/books' },
  { code: 'kn', name: 'Kannada', url: 'https://kannada.cfcindia.com/books' },
  { code: 'mr', name: 'Marathi', url: 'https://marathi.cfcindia.com/books' },
  { code: 'es', name: 'Spanish', url: 'https://espanol.cfcindia.com/books' },
  { code: 'fr', name: 'French', url: 'https://francais.cfcindia.com/books' },
  { code: 'de', name: 'German', url: 'https://deutsch.cfcindia.com/books' },
  { code: 'ru', name: 'Russian', url: 'https://russian.cfcindia.com/books' },
  { code: 'pt', name: 'Portuguese', url: 'https://portugues.cfcindia.com/books' },
  { code: 'pl', name: 'Polish', url: 'https://polski.cfcindia.com/books' },
  { code: 'ro', name: 'Romanian', url: 'https://romanian.cfcindia.com/books' },
  { code: 'sr', name: 'Serbian', url: 'https://serbian.cfcindia.com/books' },
  { code: 'si', name: 'Sinhala', url: 'https://sinhala.cfcindia.com/books' },
];

async function checkLang(lang) {
  try {
    const res = await fetch(lang.url, {
      signal: AbortSignal.timeout(10000),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ChristianTubeBookPipeline/1.0',
      },
    });
    if (!res.ok) {
      console.log(`[${lang.code}] ${lang.name}: HTTP ${res.status}`);
      return { ...lang, count: 0, books: [] };
    }
    const html = await res.text();
    const items = html.split(/class=["'][^"']*single-book-item[^"']*["']/);
    const books = [];
    for (let i = 1; i < items.length; i++) {
      const chunk = items[i];
      const titleMatch = chunk.match(/<h6 class=["']book-title["']>\s*<a title=["']([^"']+)["'] href=["']([^"']+)["']/);
      if (titleMatch) {
        const title = titleMatch[1].trim();
        let pageUrl = titleMatch[2].trim();
        if (!pageUrl.startsWith('http')) {
          const origin = new URL(lang.url).origin;
          pageUrl = `${origin}${pageUrl}`;
        }
        const imgMatch = chunk.match(/<figure class=["']book-thumbnail["']>\s*<img src=["']([^"']+)["']/);
        let coverUrl = imgMatch ? imgMatch[1].trim() : '';
        if (coverUrl && !coverUrl.startsWith('http')) {
          const origin = new URL(lang.url).origin;
          coverUrl = `${origin}${coverUrl}`;
        }
        books.push({ title, pageUrl, coverUrl });
      }
    }
    console.log(`[${lang.code}] ${lang.name}: Found ${books.length} books`);
    return { ...lang, count: books.length, books };
  } catch (e) {
    console.log(`[${lang.code}] ${lang.name}: Error: ${e.message}`);
    return { ...lang, count: 0, books: [] };
  }
}

async function main() {
  console.log('Probing language book catalogs on cfcindia.com...\n');
  const results = [];
  for (const l of LANG_DOMAINS) {
    results.push(await checkLang(l));
    await new Promise(r => setTimeout(r, 200));
  }
  console.log('\n--- Summary ---');
  let total = 0;
  for (const r of results) {
    console.log(`${r.name} (${r.code}): ${r.count} books`);
    total += r.count;
  }
  console.log(`\nTotal other-language books found: ${total}`);

  fs.writeFileSync('tool/discovered_languages.json', JSON.stringify(results, null, 2));
}

main();
