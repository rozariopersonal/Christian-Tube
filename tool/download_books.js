#!/usr/bin/env node
/**
 * tool/download_books.js
 *
 * Scrapes the complete Zac Poonen book catalog from cfcindia.com:
 * 1. Downloads all book covers into `data/books_raw/covers/`
 * 2. Downloads all available `.epub` files into `data/books_raw/epubs/`
 * 3. Downloads all chapter HTML pages into `data/books_raw/html/`
 * 4. Produces `data/books_raw/catalog.json`
 */

const fs = require('fs');
const path = require('path');

const CATALOG_URL = 'https://www.cfcindia.com/books';
const DATA_DIR = path.join(__dirname, '..', 'data', 'books_raw');
const COVERS_DIR = path.join(DATA_DIR, 'covers');
const EPUBS_DIR = path.join(DATA_DIR, 'epubs');
const HTML_DIR = path.join(DATA_DIR, 'html');

fs.mkdirSync(COVERS_DIR, { recursive: true });
fs.mkdirSync(EPUBS_DIR, { recursive: true });
fs.mkdirSync(HTML_DIR, { recursive: true });

function slugify(text) {
  return text
    .toLowerCase()
    .replace(/[^\w\s-]/g, '')
    .trim()
    .replace(/[\s_-]+/g, '_')
    .replace(/^-+|-+$/g, '');
}

async function fetchWithRetry(url, retries = 2, isBinary = false, timeoutMs = 6000) {
  for (let i = 1; i <= retries; i++) {
    try {
      const res = await fetch(url, {
        signal: AbortSignal.timeout(timeoutMs),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ChristianTubeBookPipeline/1.0',
        },
      });
      if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
      if (isBinary) {
        const arrayBuf = await res.arrayBuffer();
        return Buffer.from(arrayBuf);
      }
      return await res.text();
    } catch (e) {
      if (i === retries) throw e;
      await new Promise(r => setTimeout(r, 500 * i));
    }
  }
}

async function main() {
  console.log('Fetching book catalog from cfcindia.com/books...');
  let catalogHtml;
  try {
    catalogHtml = await fetchWithRetry(CATALOG_URL);
  } catch (e) {
    console.log('Online catalog fetch failed, checking local cached content...');
    const fallbackPath = 'C:/Users/Arul Rozario/.gemini/antigravity-ide/brain/7c68c2f5-2e54-424d-b350-6c3f08feead0/.system_generated/steps/79/content.md';
    catalogHtml = fs.readFileSync(fallbackPath, 'utf8');
  }

  const items = catalogHtml.split(/class=["'][^"']*single-book-item[^"']*["']/);
  const rawBooks = [];

  for (let i = 1; i < items.length; i++) {
    const chunk = items[i];
    const titleMatch = chunk.match(/<h6 class=["']book-title["']>\s*<a title=["']([^"']+)["'] href=["']([^"']+)["']/);
    if (!titleMatch) continue;

    const title = titleMatch[1].trim();
    let pageUrl = titleMatch[2].trim();
    if (!pageUrl.startsWith('http')) {
      pageUrl = `https://www.cfcindia.com${pageUrl}`;
    }

    const imgMatch = chunk.match(/<figure class=["']book-thumbnail["']>\s*<img src=["']([^"']+)["']/);
    let coverUrl = imgMatch ? imgMatch[1].trim() : '';
    if (coverUrl && !coverUrl.startsWith('http')) {
      coverUrl = `https://www.cfcindia.com${coverUrl}`;
    }

    const descMatch = chunk.match(/property=["']schema:summary["']>([\s\S]*?)<\/div>/);
    const desc = descMatch ? descMatch[1].replace(/<[^>]+>/g, '').trim() : '';

    const epubMatch = chunk.match(/href=["']([^"']*(?:\.epub|\/epub\/[^"']+))["']/);
    let epubUrl = epubMatch ? epubMatch[1].trim() : '';
    if (epubUrl && !epubUrl.startsWith('http')) {
      epubUrl = `https://www.cfcindia.com${epubUrl}`;
    }

    const id = slugify(title);
    rawBooks.push({
      id,
      title,
      author: 'Zac Poonen',
      description: desc,
      pageUrl,
      coverUrl,
      epubUrl,
    });
  }

  console.log(`Found ${rawBooks.length} books in catalog.`);

  const catalog = [];
  let downloadedCovers = 0;
  let downloadedEpubs = 0;
  let downloadedHtml = 0;

  for (let idx = 0; idx < rawBooks.length; idx++) {
    const b = rawBooks[idx];
    const num = `[${idx + 1}/${rawBooks.length}]`;
    console.log(`\n${num} Processing: "${b.title}" (${b.id})`);

    const bookEntry = { ...b };

    // 1. Download Cover
    if (b.coverUrl) {
      const coverExt = path.extname(new URL(b.coverUrl).pathname) || '.jpg';
      const coverFile = `${b.id}${coverExt}`;
      const coverDest = path.join(COVERS_DIR, coverFile);

      if (fs.existsSync(coverDest)) {
        console.log(`  ✓ Cover already exists (${coverFile})`);
        bookEntry.localCoverFile = coverFile;
      } else {
        try {
          process.stdout.write(`  Downloading cover: ${b.coverUrl} ... `);
          const buf = await fetchWithRetry(b.coverUrl, 2, true);
          fs.writeFileSync(coverDest, buf);
          console.log(`Done (${(buf.length / 1024).toFixed(1)} KB)`);
          bookEntry.localCoverFile = coverFile;
          downloadedCovers++;
        } catch (e) {
          console.log(`Failed: ${e.message}`);
        }
      }
    }

    // 2. Download EPUB (if available)
    if (b.epubUrl) {
      const epubFile = `${b.id}.epub`;
      const epubDest = path.join(EPUBS_DIR, epubFile);

      if (fs.existsSync(epubDest)) {
        console.log(`  ✓ EPUB already exists (${epubFile})`);
        bookEntry.localEpubFile = epubFile;
      } else {
        try {
          process.stdout.write(`  Downloading EPUB: ${b.epubUrl} ... `);
          const buf = await fetchWithRetry(b.epubUrl, 2, true);
          fs.writeFileSync(epubDest, buf);
          console.log(`Done (${(buf.length / 1024).toFixed(1)} KB)`);
          bookEntry.localEpubFile = epubFile;
          downloadedEpubs++;
        } catch (e) {
          console.log(`Failed: ${e.message}`);
        }
      }
    }

    // 3. Download Full Chapter HTML
    if (b.pageUrl) {
      const htmlFile = `${b.id}.html`;
      const htmlDest = path.join(HTML_DIR, htmlFile);

      if (fs.existsSync(htmlDest)) {
        console.log(`  ✓ HTML already exists (${htmlFile})`);
        bookEntry.localHtmlFile = htmlFile;
      } else {
        try {
          process.stdout.write(`  Downloading HTML: ${b.pageUrl} ... `);
          const text = await fetchWithRetry(b.pageUrl, 2, false);
          fs.writeFileSync(htmlDest, text, 'utf8');
          console.log(`Done (${(text.length / 1024).toFixed(1)} KB)`);
          bookEntry.localHtmlFile = htmlFile;
          downloadedHtml++;
        } catch (e) {
          console.log(`Failed: ${e.message}`);
        }
      }
    }

    catalog.push(bookEntry);
    // Be gentle to the server
    await new Promise(r => setTimeout(r, 200));
  }

  const catalogDest = path.join(DATA_DIR, 'catalog.json');
  fs.writeFileSync(catalogDest, JSON.stringify(catalog, null, 2), 'utf8');
  console.log(`\n========================================`);
  console.log(`Catalog download completed successfully!`);
  console.log(`Saved catalog manifest: ${catalogDest}`);
  console.log(`Total books: ${catalog.length}`);
  console.log(`Covers downloaded: ${downloadedCovers}`);
  console.log(`EPUBs downloaded: ${downloadedEpubs}`);
  console.log(`HTMLs downloaded: ${downloadedHtml}`);
  console.log(`========================================`);
}

main().catch(err => {
  console.error('Fatal error during book download:', err);
  process.exit(1);
});
