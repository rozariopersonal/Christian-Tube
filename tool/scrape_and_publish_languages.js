#!/usr/bin/env node
/**
 * tool/scrape_and_publish_languages.js
 *
 * Scrapes Zac Poonen books across languages (Tamil, Hindi, Telugu, Kannada, Malayalam, German)
 * from cfcindia.com subdomains and generates:
 *  1. releases/books/<lang>/<bookId>/toc.json
 *  2. releases/books/<lang>/<bookId>/chapters/<n>.json
 *  3. releases/books/<lang>/published/<bookId>.sqlite.gz
 *  4. releases/books/<lang>/books.sqlite.gz
 *  5. releases/books/covers/<bookId>.jpg
 *  6. Updated common catalog: releases/books/catalog.json
 *     and synced to apps/mobile/assets/books/catalog.json
 */

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { DatabaseSync } = require('node:sqlite');

const BASE_DIR = path.join(__dirname, '..');
const RELEASES_DIR = path.join(BASE_DIR, 'releases');
const RELEASES_BOOKS_DIR = path.join(RELEASES_DIR, 'books');
const RELEASES_COVERS_DIR = path.join(RELEASES_BOOKS_DIR, 'covers');
const APP_CATALOG_PATH = path.join(BASE_DIR, 'apps', 'mobile', 'assets', 'books', 'catalog.json');
const APP_COVERS_DIR = path.join(BASE_DIR, 'apps', 'mobile', 'assets', 'books', 'covers');

fs.mkdirSync(RELEASES_COVERS_DIR, { recursive: true });
fs.mkdirSync(APP_COVERS_DIR, { recursive: true });

const TARGET_CHARS_PER_PAGE = 1500;

const LANGUAGES = [
  { code: 'ta', name: 'Tamil', url: 'https://tamil.cfcindia.com/books' },
  { code: 'hi', name: 'Hindi', url: 'https://hindi.cfcindia.com/books' },
  { code: 'te', name: 'Telugu', url: 'https://telugu.cfcindia.com/books' },
  { code: 'kn', name: 'Kannada', url: 'https://kannada.cfcindia.com/books' },
  { code: 'ml', name: 'Malayalam', url: 'https://malayalam.cfcindia.com/books' },
  { code: 'de', name: 'German', url: 'https://deutsch.cfcindia.com/books' },
];

function slugify(text) {
  return text
    .toLowerCase()
    .replace(/[^\w\s-]/g, '')
    .trim()
    .replace(/[\s_-]+/g, '_')
    .replace(/^-+|-+$/g, '');
}

function cleanHtmlText(html) {
  if (!html) return '';
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
    .replace(/&#160;/g, ' ')
    .replace(/<[^>]+>/g, '')
    .replace(/\r\n|\r|\n/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

async function fetchWithTimeout(url, isBinary = false, timeoutMs = 8000) {
  const res = await fetch(url, {
    signal: AbortSignal.timeout(timeoutMs),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ChristianTubeBookPipeline/1.0',
    },
  });
  if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
  if (isBinary) {
    const ab = await res.arrayBuffer();
    return Buffer.from(ab);
  }
  return await res.text();
}

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
  if (currentChunk) chunks.push(currentChunk);
  return chunks.length > 0 ? chunks : [text];
}

async function extractFromKotobee(kotobeeUrl) {
  const baseKotobee = kotobeeUrl.replace(/\/index\.html.*$/, '');
  const opfUrl = `${baseKotobee}/epub/EPUB/package.opf`;
  const opfText = await fetchWithTimeout(opfUrl);

  // Extract title
  const titleMatch = opfText.match(/<dc:title[^>]*>([\s\S]*?)<\/dc:title>/i);
  const kotobeeTitle = titleMatch ? cleanHtmlText(titleMatch[1]) : '';

  // Extract author
  const authorMatch = opfText.match(/<dc:creator[^>]*>([\s\S]*?)<\/dc:creator>/i);
  const kotobeeAuthor = authorMatch ? cleanHtmlText(authorMatch[1]) : 'Zac Poonen';

  // Extract description
  const descMatch = opfText.match(/<dc:description[^>]*>([\s\S]*?)<\/dc:description>/i);
  const kotobeeDesc = descMatch ? cleanHtmlText(descMatch[1]) : '';

  // Manifest items
  const manifest = new Map();
  const m1 = [...opfText.matchAll(/<item\s+[^>]*id=["']([^"']+)["'][^>]*href=["']([^"']+)["']/gi)];
  for (const m of m1) manifest.set(m[1], m[2]);
  const m2 = [...opfText.matchAll(/<item\s+[^>]*href=["']([^"']+)["'][^>]*id=["']([^"']+)["']/gi)];
  for (const m of m2) manifest.set(m[2], m[1]);

  // Spine items in reading order
  const spineIds = [...opfText.matchAll(/<itemref\s+[^>]*idref=["']([^"']+)["']/gi)].map(m => m[1]);
  const spineFiles = spineIds.map(id => manifest.get(id)).filter(Boolean);

  // Find TOC href
  let tocHref = null;
  for (const [id, href] of manifest.entries()) {
    if (href.endsWith('contents.xhtml') || id === 'contents' || id === 'toc') {
      tocHref = href;
      break;
    }
  }

  const milestones = [];
  if (tocHref) {
    try {
      const tocUrl = new URL(tocHref, `${baseKotobee}/epub/EPUB/`).toString();
      const tocHtml = await fetchWithTimeout(tocUrl);
      const liMatches = [...tocHtml.matchAll(/<li\b(?![^>]*\bnotoc\b)[^>]*>\s*<a\s+[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)];
      for (const m of liMatches) {
        const rawHref = m[1].replace(/#.*$/, '');
        const chTitle = cleanHtmlText(m[2]);
        if (!chTitle || chTitle.length < 2) continue;
        if (chTitle.includes('அட்டை') || chTitle.includes('தலைப்பு') || chTitle.includes('காப்புரிமை') || chTitle.includes('அட்டவணை') || chTitle.includes('பொருளடக்கம்') || chTitle.toLowerCase().includes('cover') || chTitle.toLowerCase().includes('title') || chTitle.toLowerCase().includes('copyright') || chTitle.toLowerCase().includes('contents')) {
          continue;
        }
        const absUrl = new URL(rawHref, tocUrl).toString();
        const relToEpub = absUrl.replace(`${baseKotobee}/epub/EPUB/`, '');
        milestones.push({ title: chTitle, file: relToEpub });
      }
    } catch (_) {}
  }

  // Group spine items into chapters based on milestones
  const milestoneIndices = [];
  for (const ms of milestones) {
    const sIdx = spineFiles.findIndex(f => f.toLowerCase() === ms.file.toLowerCase());
    if (sIdx !== -1) {
      milestoneIndices.push({ title: ms.title, spineIndex: sIdx });
    }
  }

  const chapterGroups = [];
  if (milestoneIndices.length > 0) {
    for (let i = 0; i < milestoneIndices.length; i++) {
      const start = milestoneIndices[i].spineIndex;
      const end = (i + 1 < milestoneIndices.length) ? milestoneIndices[i + 1].spineIndex : spineFiles.length;
      const filesForChapter = spineFiles.slice(start, end);
      chapterGroups.push({
        chapterNum: `Chapter ${i + 1}`,
        title: milestoneIndices[i].title,
        files: filesForChapter,
      });
    }
  } else {
    // If no TOC milestones, treat each spine file as a separate chapter (filtering out common frontmatter)
    for (let i = 0; i < spineFiles.length; i++) {
      const f = spineFiles[i];
      if (f.toLowerCase().includes('cover') || f.toLowerCase().includes('title') || f.toLowerCase().includes('copyright')) {
        continue;
      }
      chapterGroups.push({
        chapterNum: `Chapter ${chapterGroups.length + 1}`,
        title: `Chapter ${chapterGroups.length + 1}`,
        files: [f],
      });
    }
  }

  const chapters = [];
  for (const cg of chapterGroups) {
    const elements = [];
    for (const relFile of cg.files) {
      const fileUrl = `${baseKotobee}/epub/EPUB/${relFile}`;
      try {
        const xhtml = await fetchWithTimeout(fileUrl);
        const elemRegex = /<(h1|h2|h3|h4|h5|blockquote|p|li)(?:\s+[^>]*)?>([\s\S]*?)<\/\1>/gi;
        let match;
        while ((match = elemRegex.exec(xhtml)) !== null) {
          const tag = match[1].toLowerCase();
          const text = cleanHtmlText(match[2]);
          if (!text || text.length < 2) continue;
          if (text.includes('cfcindia') || text.includes('austincfc')) continue;
          let type = 'p';
          if (tag === 'h1' || tag === 'h2') type = 'h2';
          else if (tag === 'h3' || tag === 'h4') type = 'h3';
          else if (tag === 'blockquote') type = 'blockquote';
          elements.push({ type, text });
        }
      } catch (_) {}
    }

    if (elements.length > 0) {
      chapters.push({
        chapterNum: cg.chapterNum,
        title: cg.title,
        elements,
      });
    }
  }

  return { title: kotobeeTitle, author: kotobeeAuthor, description: kotobeeDesc, chapters };
}

function parsePageHtmlChapters(htmlContent) {
  const chapters = [];
  const chapterChunks = htmlContent.split(/<div\s+id=["'][^"']+["']\s+class=["'][^"']*chapter[^"']*["']/i);

  for (let i = 1; i < chapterChunks.length; i++) {
    const chunk = chapterChunks[i];
    const titleMatch = chunk.match(/<h4 class=["']books-chapter-title["']>([\s\S]*?)<\/h4>/i) ||
                       chunk.match(/<h[2-6][^>]*>([\s\S]*?)<\/h[2-6]>/i);
    let chapterNum = '';
    let chapterTitle = 'Chapter ' + i;

    if (titleMatch) {
      const numMatch = titleMatch[1].match(/<div class=["']chapter-number["']>([\s\S]*?)<\/div>/i);
      if (numMatch) chapterNum = cleanHtmlText(numMatch[1]);
      const rawTitle = titleMatch[1].replace(/<div class=["']chapter-number["']>[\s\S]*?<\/div>/i, '');
      chapterTitle = cleanHtmlText(rawTitle) || chapterNum || ('Chapter ' + i);
    }

    const elements = [];
    const elemRegex = /<(h2|h3|h4|h5|blockquote|p)(?:\s+[^>]*)?>([\s\S]*?)<\/\1>/gi;
    let match;
    while ((match = elemRegex.exec(chunk)) !== null) {
      if (match[0].includes('books-chapter-title')) continue;
      const tag = match[1].toLowerCase();
      const text = cleanHtmlText(match[2]);
      if (!text || text.length < 2) continue;
      if (text.includes('cfcindia') || text.includes('austincfc')) continue;
      let type = 'p';
      if (tag === 'h2') type = 'h2';
      else if (tag === 'h3' || tag === 'h4' || tag === 'h5') type = 'h3';
      else if (tag === 'blockquote') type = 'blockquote';
      elements.push({ type, text });
    }

    if (elements.length > 0) {
      chapters.push({ chapterNum, title: chapterTitle, elements });
    }
  }

  return chapters;
}

function paginateChapters(bookId, chapters) {
  let currentPage = 1;
  let currentLine = 1;
  let currentCharsOnPage = 0;
  const chapterRecords = [];
  const contentRecords = [];

  for (let cIdx = 0; cIdx < chapters.length; cIdx++) {
    const ch = chapters[cIdx];
    if (currentCharsOnPage > 0 || currentLine > 1) {
      currentPage++;
      currentLine = 1;
      currentCharsOnPage = 0;
    }

    const startPage = currentPage;
    const startLine = currentLine;

    const headerText = (ch.chapterNum ? ch.chapterNum + ' ' : '') + ch.title;
    contentRecords.push({
      bookId,
      pageNumber: currentPage,
      lineNumber: currentLine,
      chapterIndex: cIdx + 1,
      contentType: 'chapter_header',
      text: headerText,
    });
    currentLine++;
    currentCharsOnPage += headerText.length;

    for (const elem of ch.elements) {
      const textChunks = (elem.type === 'p' && elem.text.length > TARGET_CHARS_PER_PAGE)
        ? splitParagraphIntoSentences(elem.text, TARGET_CHARS_PER_PAGE)
        : [elem.text];

      for (const chunk of textChunks) {
        if (currentCharsOnPage > 0 && (currentCharsOnPage + chunk.length > TARGET_CHARS_PER_PAGE)) {
          currentPage++;
          currentLine = 1;
          currentCharsOnPage = 0;
        }

        contentRecords.push({
          bookId,
          pageNumber: currentPage,
          lineNumber: currentLine,
          chapterIndex: cIdx + 1,
          contentType: elem.type,
          text: chunk,
        });
        currentLine++;
        currentCharsOnPage += chunk.length;
      }
    }

    const endPage = currentPage;
    const endLine = Math.max(1, currentLine - 1);

    chapterRecords.push({
      chapterIndex: cIdx + 1,
      title: ch.title,
      startPage,
      startLine,
      endPage,
      endLine,
    });
  }

  return { totalPages: currentPage, totalLines: currentLine - 1, chapterRecords, contentRecords };
}

function writeBookFiles(lang, bookId, bookMeta, pagination) {
  const bookDir = path.join(RELEASES_BOOKS_DIR, lang, bookId);
  const chaptersDir = path.join(bookDir, 'chapters');
  fs.mkdirSync(chaptersDir, { recursive: true });

  // 1. Write toc.json
  const toc = {
    id: bookId,
    title: bookMeta.title,
    author: bookMeta.author,
    subject: bookMeta.subject,
    totalPages: pagination.totalPages,
    totalLines: pagination.totalLines,
    chapters: pagination.chapterRecords,
  };
  fs.writeFileSync(path.join(bookDir, 'toc.json'), JSON.stringify(toc, null, 2), 'utf8');

  // 2. Write chapters/<n>.json
  for (const ch of pagination.chapterRecords) {
    const lines = pagination.contentRecords.filter(r => r.chapterIndex === ch.chapterIndex);
    const chunk = lines.map(l => ({
      line: l.lineNumber,
      page: l.pageNumber,
      text: l.text,
      contentType: l.contentType,
      isHeading: l.contentType === 'chapter_header' || l.contentType === 'h2' || l.contentType === 'h3',
      headingLevel: l.contentType === 'chapter_header' ? 1 : (l.contentType === 'h2' ? 2 : (l.contentType === 'h3' ? 3 : 0)),
    }));
    fs.writeFileSync(path.join(chaptersDir, `${ch.chapterIndex}.json`), JSON.stringify(chunk), 'utf8');
  }

  // 3. Write published/<bookId>.sqlite.gz
  const pubDir = path.join(RELEASES_BOOKS_DIR, lang, 'published');
  fs.mkdirSync(pubDir, { recursive: true });
  const singleSqlite = path.join(pubDir, `${bookId}.sqlite`);
  if (fs.existsSync(singleSqlite)) fs.unlinkSync(singleSqlite);

  const sdb = new DatabaseSync(singleSqlite);
  sdb.exec(`
    CREATE TABLE books (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL, subject TEXT NOT NULL DEFAULT '',
      categories TEXT NOT NULL DEFAULT '[]', description TEXT, cover_file TEXT,
      total_pages INTEGER NOT NULL, total_lines INTEGER NOT NULL, created_at TEXT NOT NULL
    );
    CREATE TABLE book_chapters (
      book_id TEXT NOT NULL, chapter_index INTEGER NOT NULL, chapter_title TEXT NOT NULL,
      start_page INTEGER NOT NULL, start_line INTEGER NOT NULL, end_page INTEGER NOT NULL, end_line INTEGER NOT NULL,
      PRIMARY KEY (book_id, chapter_index)
    );
    CREATE TABLE book_content (
      book_id TEXT NOT NULL, page_number INTEGER NOT NULL, line_number INTEGER NOT NULL,
      chapter_index INTEGER NOT NULL, content_type TEXT NOT NULL DEFAULT 'p', text TEXT NOT NULL,
      PRIMARY KEY (book_id, page_number, line_number)
    );
  `);

  sdb.prepare(`INSERT INTO books VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(
    bookId, bookMeta.title, bookMeta.author, bookMeta.subject,
    JSON.stringify(bookMeta.categories || []), bookMeta.description, bookMeta.coverFile,
    pagination.totalPages, pagination.totalLines, new Date().toISOString()
  );

  sdb.exec('BEGIN TRANSACTION;');
  const insCh = sdb.prepare(`INSERT INTO book_chapters VALUES (?, ?, ?, ?, ?, ?, ?)`);
  for (const c of pagination.chapterRecords) {
    insCh.run(bookId, c.chapterIndex, c.title, c.startPage, c.startLine, c.endPage, c.endLine);
  }
  const insCnt = sdb.prepare(`INSERT INTO book_content VALUES (?, ?, ?, ?, ?, ?)`);
  for (const row of pagination.contentRecords) {
    insCnt.run(bookId, row.pageNumber, row.lineNumber, row.chapterIndex, row.contentType, row.text);
  }
  sdb.exec('COMMIT;');
  sdb.close();

  // Gzip single SQLite
  const rawBytes = fs.readFileSync(singleSqlite);
  const gzBytes = zlib.gzipSync(rawBytes, { level: 9 });
  fs.writeFileSync(`${singleSqlite}.gz`, gzBytes);
  fs.unlinkSync(singleSqlite);

  return (gzBytes.length / 1024).toFixed(1) + ' KB';
}

function buildLanguageConsolidatedSqlite(lang, bookMetasWithPagination) {
  const langDir = path.join(RELEASES_BOOKS_DIR, lang);
  fs.mkdirSync(langDir, { recursive: true });
  const dbFile = path.join(langDir, 'books.sqlite');
  if (fs.existsSync(dbFile)) fs.unlinkSync(dbFile);

  const db = new DatabaseSync(dbFile);
  db.exec(`
    CREATE TABLE books (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL, subject TEXT NOT NULL DEFAULT '',
      categories TEXT NOT NULL DEFAULT '[]', description TEXT, cover_file TEXT,
      total_pages INTEGER NOT NULL, total_lines INTEGER NOT NULL, created_at TEXT NOT NULL
    );
    CREATE TABLE book_chapters (
      book_id TEXT NOT NULL, chapter_index INTEGER NOT NULL, chapter_title TEXT NOT NULL,
      start_page INTEGER NOT NULL, start_line INTEGER NOT NULL, end_page INTEGER NOT NULL, end_line INTEGER NOT NULL,
      PRIMARY KEY (book_id, chapter_index)
    );
    CREATE TABLE book_content (
      book_id TEXT NOT NULL, page_number INTEGER NOT NULL, line_number INTEGER NOT NULL,
      chapter_index INTEGER NOT NULL, content_type TEXT NOT NULL DEFAULT 'p', text TEXT NOT NULL,
      PRIMARY KEY (book_id, page_number, line_number)
    );
  `);

  const insB = db.prepare(`INSERT INTO books VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
  const insCh = db.prepare(`INSERT INTO book_chapters VALUES (?, ?, ?, ?, ?, ?, ?)`);
  const insCnt = db.prepare(`INSERT INTO book_content VALUES (?, ?, ?, ?, ?, ?)`);

  db.exec('BEGIN TRANSACTION;');
  for (const { meta, pagination } of bookMetasWithPagination) {
    insB.run(
      meta.id, meta.title, meta.author, meta.subject,
      JSON.stringify(meta.categories || []), meta.description, meta.coverFile,
      pagination.totalPages, pagination.totalLines, new Date().toISOString()
    );
    for (const c of pagination.chapterRecords) {
      insCh.run(meta.id, c.chapterIndex, c.title, c.startPage, c.startLine, c.endPage, c.endLine);
    }
    for (const r of pagination.contentRecords) {
      insCnt.run(meta.id, r.pageNumber, r.lineNumber, r.chapterIndex, r.contentType, r.text);
    }
  }
  db.exec('COMMIT;');
  db.close();

  const rawBytes = fs.readFileSync(dbFile);
  const gzBytes = zlib.gzipSync(rawBytes, { level: 9 });
  fs.writeFileSync(`${dbFile}.gz`, gzBytes);
  fs.unlinkSync(dbFile);
  console.log(`  ✓ Built ${lang}/books.sqlite.gz (${(gzBytes.length / 1024 / 1024).toFixed(2)} MB)`);
}

async function processLanguage(langConfig) {
  console.log(`\n======================================================`);
  console.log(`Processing [${langConfig.code}] ${langConfig.name}: ${langConfig.url}`);
  console.log(`======================================================`);

  let catalogHtml;
  try {
    catalogHtml = await fetchWithTimeout(langConfig.url);
  } catch (e) {
    console.error(`Failed to fetch catalog for ${langConfig.name}:`, e.message);
    return [];
  }

  const items = catalogHtml.split(/class=["'][^"']*single-book-item[^"']*["']/);
  const rawBooks = [];

  for (let i = 1; i < items.length; i++) {
    const chunk = items[i];
    const aMatch = chunk.match(/<h6 class=["']book-title["']>\s*<a\s+([^>]+)>([\s\S]*?)<\/a>/i);
    if (!aMatch) continue;
    const aAttrs = aMatch[1];
    const innerText = cleanHtmlText(aMatch[2]);
    const hrefM = aAttrs.match(/href=["']([^"']+)["']/i);
    const titleAttrM = aAttrs.match(/title=["']([^"']+)["']/i);
    if (!hrefM) continue;

    let pageUrl = hrefM[1].trim();
    if (!pageUrl.startsWith('http')) {
      pageUrl = `${new URL(langConfig.url).origin}${pageUrl}`;
    }

    const rawTitle = innerText || (titleAttrM ? cleanHtmlText(titleAttrM[1]) : '') || 'Untitled Book';

    const imgMatch = chunk.match(/<figure class=["']book-thumbnail["']>\s*<img\s+[^>]*src=["']([^"']+)["']/i);
    let coverUrl = imgMatch ? imgMatch[1].trim() : '';
    if (coverUrl && !coverUrl.startsWith('http')) {
      coverUrl = `${new URL(langConfig.url).origin}${coverUrl}`;
    }

    const descMatch = chunk.match(/property=["']schema:summary["']>([\s\S]*?)<\/div>/);
    const desc = descMatch ? cleanHtmlText(descMatch[1]) : '';

    const kotobeeMatch = chunk.match(/href=["'](https?:\/\/[^"']*\/epub\/[^"']+\/index\.html)["']/i);
    const kotobeeUrl = kotobeeMatch ? kotobeeMatch[1] : null;

    // Use URL slug for unique stable book ID
    const urlSlug = pageUrl.split('/').filter(Boolean).pop().replace(/-\d+$/, '');
    const id = `${langConfig.code}_${slugify(urlSlug)}`;

    rawBooks.push({
      id,
      title: rawTitle,
      author: 'Zac Poonen',
      description: desc,
      pageUrl,
      coverUrl,
      kotobeeUrl,
      lang: langConfig.code,
    });
  }

  console.log(`Found ${rawBooks.length} book candidates for [${langConfig.code}].`);

  const langResults = [];
  const processedWithPagination = [];

  for (let idx = 0; idx < rawBooks.length; idx++) {
    const b = rawBooks[idx];
    const prefix = `[${idx + 1}/${rawBooks.length}]`;
    console.log(`\n${prefix} Processing: "${b.title}" (${b.id})`);

    // 1. Download Cover
    const coverFilename = `${b.id}.jpg`;
    const coverDest = path.join(RELEASES_COVERS_DIR, coverFilename);
    const appCoverDest = path.join(APP_COVERS_DIR, coverFilename);

    if (b.coverUrl && !fs.existsSync(coverDest)) {
      try {
        const coverBuf = await fetchWithTimeout(b.coverUrl, true, 8000);
        fs.writeFileSync(coverDest, coverBuf);
        fs.writeFileSync(appCoverDest, coverBuf);
        console.log(`  ✓ Saved cover image (${(coverBuf.length / 1024).toFixed(1)} KB)`);
      } catch (e) {
        console.warn(`  ✗ Cover download failed: ${e.message}`);
      }
    }

    // 2. Fetch & Extract Content
    let chapters = [];
    let bookTitle = b.title;
    let bookAuthor = b.author;
    let bookDesc = b.description;

    // A. Check Kotobee first
    let kUrl = b.kotobeeUrl;
    if (!kUrl) {
      try {
        const pageHtml = await fetchWithTimeout(b.pageUrl, false, 8000);
        const km = pageHtml.match(/href=["'](https?:\/\/[^"']*\/epub\/[^"']+\/index\.html)["']/i);
        if (km) kUrl = km[1];
        else {
          // Parse inline HTML chapters from page
          chapters = parsePageHtmlChapters(pageHtml);
        }
      } catch (e) {
        console.warn(`  ✗ Page fetch error: ${e.message}`);
      }
    }

    if (kUrl) {
      console.log(`  → Extracting from Kotobee EPUB reader...`);
      try {
        const kData = await extractFromKotobee(kUrl);
        if (kData.title) bookTitle = kData.title;
        if (kData.author) bookAuthor = kData.author;
        if (kData.description) bookDesc = kData.description;
        chapters = kData.chapters;
      } catch (e) {
        console.warn(`  ✗ Kotobee extraction failed: ${e.message}`);
      }
    }

    if (!chapters || chapters.length === 0) {
      console.warn(`  ⚠ No readable chapters found for "${b.title}". Skipping.`);
      continue;
    }

    console.log(`  ✓ Extracted ${chapters.length} chapters.`);

    // 3. Paginate
    const pagination = paginateChapters(b.id, chapters);
    console.log(`  ✓ Paginated: ${pagination.totalPages} pages, ${pagination.totalLines} lines.`);

    // 4. Write releases/books/<lang>/<bookId>/...
    const meta = {
      id: b.id,
      title: bookTitle,
      author: bookAuthor,
      subject: 'Christian Living',
      categories: ['Christian Living'],
      description: bookDesc,
      coverFile: coverFilename,
      lang: langConfig.code,
    };

    const gzSize = writeBookFiles(langConfig.code, b.id, meta, pagination);
    console.log(`  ✓ Published book package (${gzSize})`);

    const catalogEntry = {
      id: b.id,
      title: bookTitle,
      author: bookAuthor,
      subject: 'Christian Living',
      categories: ['Christian Living'],
      description: bookDesc,
      coverFile: coverFilename,
      totalPages: pagination.totalPages,
      totalLines: pagination.totalLines,
      downloadSizeFormatted: gzSize,
      createdAt: new Date().toISOString(),
      lang: langConfig.code,
    };

    langResults.push(catalogEntry);
    processedWithPagination.push({ meta, pagination });

    await new Promise(r => setTimeout(r, 150));
  }

  // 5. Build consolidated language database if books processed
  if (processedWithPagination.length > 0) {
    buildLanguageConsolidatedSqlite(langConfig.code, processedWithPagination);
  }

  return langResults;
}

async function main() {
  console.log('Starting Multi-Language Zac Poonen Book Scraper...\n');

  // Load existing catalog
  const catalogFile = path.join(RELEASES_BOOKS_DIR, 'catalog.json');
  let existingCatalog = [];
  if (fs.existsSync(catalogFile)) {
    existingCatalog = JSON.parse(fs.readFileSync(catalogFile, 'utf8'));
    // Ensure English books have "lang": "en"
    for (const b of existingCatalog) {
      if (!b.lang) b.lang = 'en';
    }
  }

  const newCatalogMap = new Map();
  for (const b of existingCatalog) {
    newCatalogMap.set(b.id, b);
  }

  let totalScraped = 0;

  for (const langConfig of LANGUAGES) {
    const books = await processLanguage(langConfig);
    console.log(`\nCompleted [${langConfig.code}] ${langConfig.name}: ${books.length} books packaged.`);
    for (const b of books) {
      newCatalogMap.set(b.id, b);
      totalScraped++;
    }
  }

  const finalCatalog = Array.from(newCatalogMap.values());

  // Save common catalog
  fs.writeFileSync(catalogFile, JSON.stringify(finalCatalog, null, 2), 'utf8');
  fs.writeFileSync(APP_CATALOG_PATH, JSON.stringify(finalCatalog, null, 2), 'utf8');

  console.log(`\n======================================================`);
  console.log(`Multi-Language Ingestion Complete!`);
  console.log(`Total books now in unified catalog: ${finalCatalog.length}`);
  console.log(`New language books added: ${totalScraped}`);
  console.log(`Saved to: ${catalogFile}`);
  console.log(`Synced to: ${APP_CATALOG_PATH}`);
  console.log(`======================================================`);
}

main().catch(err => {
  console.error('Fatal error during scraping:', err);
  process.exit(1);
});
