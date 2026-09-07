#!/usr/bin/env node
/**
 * tool/sync_cfc_articles.js
 *
 * Scraper for CFC India Word for the Week (WFTW) articles.
 * English build (default / --all) produces:
 *  - releases/articles/wftw_feed.sqlite.gz (for the mobile feed)
 *  - releases/articles/wftw_manifest.json (for background sync hot-swapping)
 *  - releases/articles/wftw/*.json (individual live-synced articles)
 *  - releases/articles/wftw_index.json (web-safe article index)
 *
 * Multi-language build (--langs=...) produces, for every configured language:
 *  - releases/articles/{code}/{YYYY_MM_DD}.json (translated article content)
 *  - releases/articles/{code}/index.json (per-language web-safe index)
 *  - releases/articles/articles_index.json (combined index with `lang` field)
 *  - releases/articles/languages.json (manifest with per-language counts)
 *
 * Usage:
 *   node tool/sync_cfc_articles.js                    # English: current month + indexes
 *   node tool/sync_cfc_articles.js --all              # English: full backfill 2001→now
 *   node tool/sync_cfc_articles.js --langs=seed        # incremental: seed languages, recent months
 *   node tool/sync_cfc_articles.js --langs=all         # incremental: all languages, recent months
 *   node tool/sync_cfc_articles.js --langs=de,ta       # incremental: comma-separated subset
 *   node tool/sync_cfc_articles.js --langs=seed --full # deep backfill for seed languages
 */

const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { DatabaseSync } = require('node:sqlite');
const zlib = require('zlib');

const LANGUAGE_MANIFEST_PATH = path.join(__dirname, 'cfc_languages.json');
const LANGUAGE_MANIFEST = JSON.parse(fs.readFileSync(LANGUAGE_MANIFEST_PATH, 'utf8')).languages;

const DATA_DIR = path.join(__dirname, '..', 'data');
const STATE_DB_PATH = path.join(DATA_DIR, 'cfc_articles_state.sqlite');
const RELEASES_ARTICLES_DIR = path.join(__dirname, '..', 'releases', 'articles');
const WFTW_JSON_DIR = path.join(RELEASES_ARTICLES_DIR, 'wftw');
const FEED_DB_PATH = path.join(RELEASES_ARTICLES_DIR, 'wftw_feed.sqlite');
const FEED_DB_GZ_PATH = path.join(RELEASES_ARTICLES_DIR, 'wftw_feed.sqlite.gz');
const MANIFEST_PATH = path.join(RELEASES_ARTICLES_DIR, 'wftw_manifest.json');
// Web-safe article index (used by the app's article browser on all platforms;
// the feed DB itself is mobile-only SQLite).
const INDEX_PATH = path.join(RELEASES_ARTICLES_DIR, 'wftw_index.json');

const COMBINED_INDEX_PATH = path.join(RELEASES_ARTICLES_DIR, 'articles_index.json');
const LANGUAGES_MANIFEST_OUT_PATH = path.join(RELEASES_ARTICLES_DIR, 'languages.json');

// How many consecutive empty month-grids (going back in time) end a language's
// deep crawl. The WFTW archive is published weekly from each language's start,
// so genuinely-empty tail months mean translations had not begun yet.
const STALE_MONTH_STOP = 8;

// Ensure directories exist
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
if (!fs.existsSync(WFTW_JSON_DIR)) fs.mkdirSync(WFTW_JSON_DIR, { recursive: true });

// Initialize state ledger (English crawl only)
const stateDb = new DatabaseSync(STATE_DB_PATH);
stateDb.exec(`
  CREATE TABLE IF NOT EXISTS crawled_articles (
    id TEXT PRIMARY KEY,
    url TEXT,
    content_hash TEXT,
    crawled_at INTEGER
  );
`);

// Initialize output Feed DB. CI checkouts are fresh (the uncompressed DB is
// not committed), so continue from the committed archive: decompress the .gz
// into the working DB first, then append/upsert this run's articles. Without
// this each CI run rebuilt the feed from only the current month, losing history.
if (!fs.existsSync(FEED_DB_PATH) && fs.existsSync(FEED_DB_GZ_PATH)) {
    console.log("Continuing from committed feed archive (wftw_feed.sqlite.gz)...");
    const compressed = fs.readFileSync(FEED_DB_GZ_PATH);
    const decompressed = zlib.gunzipSync(compressed);
    fs.writeFileSync(FEED_DB_PATH, decompressed);
}
const feedDb = new DatabaseSync(FEED_DB_PATH);
feedDb.exec(`
  CREATE TABLE IF NOT EXISTS wftw_verses (
    article_id TEXT PRIMARY KEY,
    date_ms INTEGER,
    year INTEGER,
    book_number INTEGER,
    chapter INTEGER,
    start_verse INTEGER,
    end_verse INTEGER,
    article_title TEXT,
    fallback_excerpt TEXT
  );
`);

// HTTP Helper
const TRANSPORT = { 'https:': https, 'http:': http };
function fetch(url, retries = 3) {
  return new Promise((resolve, reject) => {
    const mod = TRANSPORT[url.startsWith('https:') ? 'https:' : 'http:'] || http;
    mod.get(url, { headers: { 'User-Agent': 'ChristianTubeCrawler/1.0' } }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        let loc = res.headers.location;
        if (!loc.startsWith('http')) loc = new URL(loc, url).href;
        return resolve(fetch(loc, retries));
      }
      if (res.statusCode !== 200) {
        if (retries > 0) return setTimeout(() => resolve(fetch(url, retries - 1)), 1000);
        return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
      }
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => resolve(d));
    }).on('error', (err) => {
      if (retries > 0) return setTimeout(() => resolve(fetch(url, retries - 1)), 1500);
      reject(err);
    });
  });
}

function cleanHtml(html) {
  // strip strong, em, b, i, span etc but convert <br> to newline
  let cleaned = html.replace(/<br\s*\/?>/gi, '\n');
  cleaned = cleaned.replace(/<[^>]+>/g, '');
  cleaned = cleaned.replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&#39;/g, "'").replace(/&quot;/g, '"');
  return cleaned.trim();
}

const BIBLE_BOOKS = {
  'genesis': 1, 'exodus': 2, 'leviticus': 3, 'numbers': 4, 'deuteronomy': 5,
  'joshua': 6, 'judges': 7, 'ruth': 8, '1 samuel': 9, '2 samuel': 10,
  '1 kings': 11, '2 kings': 12, '1 chronicles': 13, '2 chronicles': 14,
  'ezra': 15, 'nehemiah': 16, 'esther': 17, 'job': 18, 'psalm': 19, 'psalms': 19,
  'proverbs': 20, 'ecclesiastes': 21, 'song of solomon': 22, 'isaiah': 23,
  'jeremiah': 24, 'lamentations': 25, 'ezekiel': 26, 'daniel': 27, 'hosea': 28,
  'joel': 29, 'amos': 30, 'obadiah': 31, 'jonah': 32, 'micah': 33, 'nahum': 34,
  'habakkuk': 35, 'zephaniah': 36, 'haggai': 37, 'zechariah': 38, 'malachi': 39,
  'matthew': 40, 'mark': 41, 'luke': 42, 'john': 43, 'acts': 44, 'romans': 45,
  '1 corinthians': 46, '2 corinthians': 47, 'galatians': 48, 'ephesians': 49,
  'philippians': 50, 'colossians': 51, '1 thessalonians': 52, '2 thessalonians': 53,
  '1 timothy': 54, '2 timothy': 55, 'titus': 56, 'philemon': 57, 'hebrews': 58,
  'james': 59, '1 peter': 60, '2 peter': 61, '1 john': 62, '2 john': 63,
  '3 john': 64, 'jude': 65, 'revelation': 66
};

function extractScripture(text) {
  const match = text.match(/(Genesis|Exodus|Leviticus|Numbers|Deuteronomy|Joshua|Judges|Ruth|1\s*Samuel|2\s*Samuel|1\s*Kings|2\s*Kings|1\s*Chronicles|2\s*Chronicles|Ezra|Nehemiah|Esther|Job|Psalms?|Proverbs|Ecclesiastes|Song of Solomon|Isaiah|Jeremiah|Lamentations|Ezekiel|Daniel|Hosea|Joel|Amos|Obadiah|Jonah|Micah|Nahum|Habakkuk|Zephaniah|Haggai|Zechariah|Malachi|Matthew|Mark|Luke|John|Acts|Romans|1\s*Corinthians|2\s*Corinthians|Galatians|Ephesians|Philippians|Colossians|1\s*Thessalonians|2\s*Thessalonians|1\s*Timothy|2\s*Timothy|Titus|Philemon|Hebrews|James|1\s*Peter|2\s*Peter|1\s*John|2\s*John|3\s*John|Jude|Revelation)\s*(\d+):(\d+)(?:-(\d+))?/i);
  if (!match) return null;
  
  const bookName = match[1].toLowerCase().replace(/\s+/g, ' ');
  const bookNumber = BIBLE_BOOKS[bookName];
  if (!bookNumber) return null;

  return {
    book_number: bookNumber,
    chapter: parseInt(match[2], 10),
    start_verse: parseInt(match[3], 10),
    end_verse: match[4] ? parseInt(match[4], 10) : parseInt(match[3], 10)
  };
}

const MONTHS = {
  'Jan': '01', 'Feb': '02', 'Mar': '03', 'Apr': '04', 'May': '05', 'Jun': '06',
  'Jul': '07', 'Aug': '08', 'Sep': '09', 'Oct': '10', 'Nov': '11', 'Dec': '12'
};

/**
 * Extracts the article body HTML from a WFTW article page.
 * Order of preference:
 *  1. `.article-body` container (English pages),
 *  2. the `.field-name-body` Drupal region up to the excerpt-end marker
 *     (language pages; keeps sidebar/footer `<p>` text out),
 *  3. bare `<p>` tags (fallback).
 */
function extractBodyHtml(html) {
  const articleBody = html.match(/<div[^>]*class="article-body"[^>]*>([\s\S]*?)<\/div>\s*<\/div>\s*<\/div>\s*<\/div>/i);
  if (articleBody) return articleBody[1];

  const bodyStart = html.indexOf('field-name-body');
  if (bodyStart >= 0) {
    const endMarker = html.indexOf('ENDS class="article-home-excerpts"', bodyStart);
    const regionEnd = endMarker >= 0 ? endMarker : Math.min(html.length, bodyStart + 60000);
    const region = html.slice(bodyStart, regionEnd);
    const pTags = region.match(/<p[^>]*>[\s\S]*?<\/p>/gi) || [];
    return pTags.join('');
  }

  const pMatches = html.match(/<p>[\s\S]*?<\/p>/gi);
  if (pMatches) return pMatches.filter(p => !p.includes('cfcindia.com/wftw')).join('');

  return '';
}

/** Builds the article `lines` array from body HTML + title (mirrors English build). */
function buildLines(contentHtml, title) {
  const lines = [];
  lines.push({ line: 1, text: title, isHeading: true, headingLevel: 1 });

  let lineCount = 2;
  const pTags = contentHtml.match(/<p[^>]*>([\s\S]*?)<\/p>/gi) || [];

  let combinedTextForExtraction = title + " ";

  for (const p of pTags) {
    let text = cleanHtml(p);
    if (!text) continue;
    lines.push({ line: lineCount++, text: text, isHeading: false });
    if (lineCount <= 4) {
        combinedTextForExtraction += text + " ";
    }
  }
  return { lines, combinedTextForExtraction };
}

async function processArticle(url, title, dateObj) {
  const articleId = `${dateObj.year}_${dateObj.monthStr}_${dateObj.day.padStart(2, '0')}`;
  
  // Check state db
  const existing = stateDb.prepare('SELECT content_hash FROM crawled_articles WHERE id = ?').get(articleId);
  
  const html = await fetch(url);
  const hash = crypto.createHash('md5').update(html).digest('hex');
  
  if (existing && existing.content_hash === hash) {
    console.log(`Skipping unchanged article: ${articleId}`);
    return;
  }
  
  console.log(`Processing article: ${articleId} - ${title}`);
  
  // Parse HTML
  const contentHtml = extractBodyHtml(html);

  const { lines, combinedTextForExtraction } = buildLines(contentHtml, title);

  // Extract Scripture
  const scripture = extractScripture(combinedTextForExtraction);
  let fallback = null;
  if (!scripture) {
      if (lines.length > 1) {
          fallback = lines[1].text.substring(0, 150) + (lines[1].text.length > 150 ? '...' : '');
      }
  }

  // Generate JSON
  const articleJson = {
    id: articleId,
    title: title,
    date: `${dateObj.year}-${dateObj.monthStr}-${dateObj.day.padStart(2, '0')}`,
    author: "Zac Poonen",
    lines: lines
  };
  
  fs.writeFileSync(path.join(WFTW_JSON_DIR, `${articleId}.json`), JSON.stringify(articleJson, null, 2));

  // Update Feed DB
  const dateMs = new Date(`${dateObj.year}-${dateObj.monthStr}-${dateObj.day.padStart(2, '0')}T00:00:00Z`).getTime();
  
  feedDb.prepare(`
    INSERT INTO wftw_verses (article_id, date_ms, year, book_number, chapter, start_verse, end_verse, article_title, fallback_excerpt)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(article_id) DO UPDATE SET 
      date_ms=excluded.date_ms, year=excluded.year, book_number=excluded.book_number, chapter=excluded.chapter,
      start_verse=excluded.start_verse, end_verse=excluded.end_verse, article_title=excluded.article_title, fallback_excerpt=excluded.fallback_excerpt
  `).run(
    articleId, dateMs, dateObj.year, 
    scripture ? scripture.book_number : null,
    scripture ? scripture.chapter : null,
    scripture ? scripture.start_verse : null,
    scripture ? scripture.end_verse : null,
    title, fallback
  );

  // Update state db
  stateDb.prepare(`
    INSERT INTO crawled_articles (id, url, content_hash, crawled_at)
    VALUES (?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET content_hash=excluded.content_hash, crawled_at=excluded.crawled_at, url=excluded.url
  `).run(articleId, url, hash, Date.now());
}

async function scrapeMonth(year, monthNum) {
  console.log(`Scraping index for ${year}-${monthNum}...`);
  const url = `https://cfcindia.com/wftw?y=${year}&m=${monthNum}`;
  const html = await fetch(url);
  
  // Extract articles from the grid.
  // <div class="col-lg-6 col-md-6 col-sm-6 col-xs-12 wftw-home-excerpts ">
  const excerptsRegex = /<div class="col-lg-6 col-md-6\s*col-sm-6 col-xs-12 wftw-home-excerpts ">([\s\S]*?)<\/div><!--ENDS class="article-home-excerpts" -->/gi;
  let match;
  while ((match = excerptsRegex.exec(html)) !== null) {
      const block = match[1];
      
      const dayMatch = block.match(/<div class="wftw-day">\s*(\d+)\s*<\/div>/i);
      const monthMatch = block.match(/<div class="wftw-month">\s*([A-Za-z]+)\s*<\/div>/i);
      const yearMatch = block.match(/<div class="wftw-year">\s*(\d+)\s*<\/div>/i);
      const titleMatch = block.match(/<a href="(https:\/\/cfcindia.com\/wftw\/[^"]+)">([\s\S]*?)<\/a>/i);
      
      if (dayMatch && monthMatch && yearMatch && titleMatch) {
          const dateObj = {
              day: dayMatch[1].trim(),
              month: monthMatch[1].trim(),
              monthStr: MONTHS[monthMatch[1].trim()] || monthNum.toString().padStart(2, '0'),
              year: parseInt(yearMatch[1].trim(), 10)
          };
          const articleUrl = titleMatch[1];
          const title = cleanHtml(titleMatch[2]);

          try {
              await processArticle(articleUrl, title, dateObj);
          } catch (e) {
              // One bad page (404, transient error) must not abort the whole
              // backfill; the content-hash ledger lets a later rerun retry it.
              console.error(`SKIP (continue): ${title} -- ${e.message}`);
          }
      }
  }
}

/**
 * Crawls one language month-grid. Returns the number of article blocks found
 * so the caller can stop the deep crawl when months go stale.
 */
async function scrapeLangMonth(lang, langEntry, year, monthNum, seenUrls) {
  const url = `${langEntry.base}/wftw?y=${year}&m=${monthNum}`;
  const html = await fetch(url);

  const dir = path.join(RELEASES_ARTICLES_DIR, lang);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

  const monthStr = monthNum.toString().padStart(2, '0');
  const excerptsRegex = /<div class="col-lg-6 col-md-6\s*col-sm-6 col-xs-12 wftw-home-excerpts ">([\s\S]*?)<\/div><!--ENDS class="article-home-excerpts" -->/gi;
  let block;
  let found = 0;
  while ((block = excerptsRegex.exec(html)) !== null) {
      const dayMatch = block[1].match(/<div class="wftw-day">\s*(\d+)\s*<\/div>/i);
      const titleMatch = block[1].match(/<a href="(https?:\/\/[^"]+\/wftw\/[^"]+)">([\s\S]*?)<\/a>/i);
      if (!dayMatch || !titleMatch) continue;

      const dayNum = parseInt(dayMatch[1].trim(), 10);
      if (Number.isNaN(dayNum)) continue;

      const articleUrl = titleMatch[1];
      // Sparse language months pad their grid with the most recent article(s),
      // which then bubble up in every later month page. A URL already captured
      // for this language this run belongs to an earlier month — skip it.
      if (seenUrls.has(articleUrl)) {
          console.log(`[${lang}] seen (pad skip): ${articleUrl}`);
          continue;
      }
      seenUrls.add(articleUrl);

      const dateObj = {
          day: dayNum,
          month: '',
          monthStr,
          year: year
      };
      const title = cleanHtml(titleMatch[2]);
      found++;

      const articleId = `${dateObj.year}_${dateObj.monthStr}_${dayNum.toString().padStart(2, '0')}`;
      const outPath = path.join(dir, `${articleId}.json`);
      if (fs.existsSync(outPath)) {
          console.log(`[${lang}] exists: ${articleId}`);
          continue;
      }
      try {
          await processLangArticle(lang, dir, articleUrl, title, dateObj);
      } catch (e) {
          // A bad page must not abort the language crawl; the missing file is
          // retried on the next run.
          console.error(`[${lang}] SKIP (continue): ${title} -- ${e.message}`);
      }
  }
  return found;
}

async function processLangArticle(lang, dir, url, title, dateObj) {
  const articleId = `${dateObj.year}_${dateObj.monthStr}_${dateObj.day.toString().padStart(2, '0')}`;
  console.log(`[${lang}] Processing article: ${articleId} - ${title}`);

  const html = await fetch(url);
  const contentHtml = extractBodyHtml(html);
  const { lines } = buildLines(contentHtml, title);

  const articleJson = {
    id: articleId,
    title: title,
    date: `${dateObj.year}-${dateObj.monthStr}-${dateObj.day.toString().padStart(2, '0')}`,
    author: "Zac Poonen",
    lines: lines
  };
  fs.writeFileSync(path.join(dir, `${articleId}.json`), JSON.stringify(articleJson, null, 2));
}

/** Deep backfill for one language: current month down to its floor year. */
async function crawlLangDeep(langEntry) {
  const lang = langEntry.code;
  console.log(`\n=== Deep crawl ${langEntry.label} (${lang}) ===`);
  const seenUrls = new Set();

  // Bound the crawl to committed history so daily full runs don't re-scan
  // months we already contain. Fresh checkouts keep scanning to the floor.
  const dir = path.join(RELEASES_ARTICLES_DIR, lang);
  let earliestYear = null;
  if (fs.existsSync(dir)) {
    for (const f of fs.readdirSync(dir)) {
      const y = parseInt(f.slice(0, 4), 10);
      if (Number.isInteger(y)) earliestYear = earliestYear === null ? y : Math.min(earliestYear, y);
    }
  }
  const lowerBound = earliestYear !== null && earliestYear <= langEntry.floorYear
      ? earliestYear - 1
      : langEntry.floorYear;

  const now = new Date();
  let consecutiveEmpty = 0;
  let total = 0;
  let year = now.getFullYear();
  let month = now.getMonth() + 1;
  let firstStop = true;
  while (year >= lowerBound) {
    let found = 0;
    try {
      found = await scrapeLangMonth(lang, langEntry, year, month, seenUrls);
    } catch (e) {
      if (firstStop) console.error(`[${lang}] Month ${year}-${month} failed: ${e.message}`);
    }
    firstStop = false;
    total += found;
    if (found === 0 && year < now.getFullYear()) {
      consecutiveEmpty++;
      if (consecutiveEmpty >= STALE_MONTH_STOP) {
        console.log(`[${lang}] Stopping backfill at ${year}-${month} (${consecutiveEmpty} empty months).`);
        break;
      }
    } else if (found > 0) {
      consecutiveEmpty = 0;
    }

    month--;
    if (month === 0) { month = 12; year--; }
  }
  console.log(`[${lang}] crawl complete: ${total} new articles.`);
}

/** Incremental crawl for one language: the most recent months only. */
async function crawlLangIncremental(langEntry) {
  const lang = langEntry.code;
  console.log(`\n=== Incremental ${langEntry.label} (${lang}) ===`);
  const seenUrls = new Set();
  const now = new Date();
  const seen = new Set();
  const candidates = [];
  // Current month, then the previous month (mirrors the English daily crawl).
  for (let i = 0; i < 2; i++) {
    let y = now.getFullYear();
    let m = now.getMonth() + 1 - i;
    if (m <= 0) { m += 12; y--; }
    const key = `${y}-${m}`;
    if (seen.has(key)) continue;
    seen.add(key);
    candidates.push([y, m]);
  }
  for (const [y, m] of candidates) {
    try {
      await scrapeLangMonth(lang, langEntry, y, m, seenUrls);
    } catch (e) {
      console.error(`[${lang}] Month ${y}-${m} failed: ${e.message}`);
    }
  }
}

/** Regenerates per-language indexes from their committed content folders. */
function buildLangIndex(dir) {
  const entries = [];
  if (!fs.existsSync(dir)) return entries;
  for (const f of fs.readdirSync(dir)) {
    if (f === 'index.json' || !f.endsWith('.json')) continue;
    try {
      const json = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
      const y = json.date ? parseInt(json.date.slice(0, 4), 10) : null;
      entries.push({
        id: json.id,
        title: json.title,
        date: json.date,
        year: Number.isInteger(y) ? y : null,
        bookNumber: null,
        chapter: null,
        startVerse: null,
        endVerse: null
      });
    } catch (_) {
      // skip unreadable/incomplete files (likely from an interrupted run)
    }
  }
  entries.sort((a, b) => b.date.localeCompare(a.date));
  return entries;
}

/** Returns English index entries (from the committed web-safe index file). */
function englishEntries() {
  try {
    const raw = JSON.parse(fs.readFileSync(INDEX_PATH, 'utf8'));
    if (Array.isArray(raw)) return raw;
  } catch (_) {}
  try {
    const rows = feedDb.prepare(
      'SELECT article_id, article_title, date_ms, year, book_number, chapter, start_verse, end_verse FROM wftw_verses'
    ).all();
    return rows.map((r) => {
      const d = new Date(r.date_ms);
      const mm = String(d.getUTCMonth() + 1).padStart(2, '0');
      const dd = String(d.getUTCDate()).padStart(2, '0');
      return {
        id: r.article_id,
        title: r.article_title,
        date: `${d.getUTCFullYear()}-${mm}-${dd}`,
        year: r.year ?? null,
        bookNumber: r.book_number ?? null,
        chapter: r.chapter ?? null,
        startVerse: r.start_verse ?? null,
        endVerse: r.end_verse ?? null
      };
    });
  } catch (_) {}
  return [];
}

/** Writes per-language indexes, the combined index, and the language manifest. */
function finishLanguages() {
  console.log("Generating per-language indexes, combined index & languages manifest...");

  const combined = [];
  const langCounts = [];

  // English first (hosted under articles/wftw/, index from wftw_index.json).
  const en = englishEntries().map((e) => ({ ...e, lang: 'en' }));
  combined.push(...en);
  langCounts.push({ code: 'en', count: en.length });

  for (const entry of LANGUAGE_MANIFEST) {
    const code = entry.code;
    if (code === 'en') continue;
    const dir = path.join(RELEASES_ARTICLES_DIR, code);
    const index = buildLangIndex(dir);
    // Only materialize an index once a language actually has articles.
    if (index.length > 0) {
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, 'index.json'), JSON.stringify(index));
      console.log(`Wrote articles/${code}/index.json (${index.length} entries)`);
      combined.push(...index.map((e) => ({ ...e, lang: code })));
    }
    langCounts.push({ code, count: index.length });
  }

  combined.sort((a, b) => (b.date.localeCompare(a.date) || a.lang.localeCompare(b.lang)));
  fs.writeFileSync(COMBINED_INDEX_PATH, JSON.stringify(combined));
  console.log(`Wrote ${COMBINED_INDEX_PATH} (${combined.length} entries)`);

  // Language manifest for the app's language picker. Names come from the
  // tool manifest; order: most articles first.
  const nameOf = new Map(LANGUAGE_MANIFEST.map((l) => [l.code, l.label]));
  const manifest = langCounts
    .sort((a, b) => b.count - a.count)
    .map((c) => ({ code: c.code, name: nameOf.get(c.code) || c.code, count: c.count }));
  fs.writeFileSync(LANGUAGES_MANIFEST_OUT_PATH, JSON.stringify(manifest));
  console.log(`Wrote ${LANGUAGES_MANIFEST_OUT_PATH}`);
}

async function finish() {
    console.log("Generating Index, Gzip & Manifest...");

    // Build the platform-neutral article index from the feed DB.
    const rows = feedDb.prepare(
        'SELECT article_id, article_title, date_ms, year, book_number, chapter, start_verse, end_verse FROM wftw_verses'
    ).all();
    const index = rows.map((r) => {
        const d = new Date(r.date_ms);
        const mm = String(d.getUTCMonth() + 1).padStart(2, '0');
        const dd = String(d.getUTCDate()).padStart(2, '0');
        return {
            id: r.article_id,
            title: r.article_title,
            date: `${d.getUTCFullYear()}-${mm}-${dd}`,
            year: r.year ?? null,
            bookNumber: r.book_number ?? null,
            chapter: r.chapter ?? null,
            startVerse: r.start_verse ?? null,
            endVerse: r.end_verse ?? null
        };
    }).sort((a, b) => b.date.localeCompare(a.date));
    fs.writeFileSync(INDEX_PATH, JSON.stringify(index));
    console.log(`Wrote ${INDEX_PATH} (${index.length} entries)`);

    feedDb.close();

    // Gzip the sqlite file
    const dbBuffer = fs.readFileSync(FEED_DB_PATH);
    const gzipped = zlib.gzipSync(dbBuffer);
    fs.writeFileSync(FEED_DB_GZ_PATH, gzipped);
    
    // Generate Manifest
    const hash = crypto.createHash('sha256').update(gzipped).digest('hex');
    const manifest = {
        last_updated: Math.floor(Date.now() / 1000),
        hash: hash
    };
    fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2));
    console.log(`Wrote ${MANIFEST_PATH}`);
}

/** English crawl mode (legacy behaviour). */
async function runEnglish(full) {
    const now = new Date();
    const currentYear = now.getFullYear();
    const currentMonth = now.getMonth() + 1; // 1-12

    if (full) {
        for (let y = currentYear; y >= 2001; y--) {
            for (let m = 12; m >= 1; m--) {
                if (y === currentYear && m > currentMonth) continue;
                await scrapeMonth(y, m);
            }
        }
    } else {
        await scrapeMonth(currentYear, currentMonth);
        if (now.getDate() < 7) {
            let pM = currentMonth - 1;
            let pY = currentYear;
            if (pM === 0) { pM = 12; pY--; }
            await scrapeMonth(pY, pM);
        }
    }

    await finish();
}

/** Resolves --langs=... to a list of language entries (English excluded here). */
function resolveLangsArg(value) {
  if (value === 'seed' || value === 'all') {
    return LANGUAGE_MANIFEST.filter((l) => l.code !== 'en' && !l.disabled && (value === 'all' || l.seed));
  }
  const codes = value.split(',').map((c) => c.trim()).filter(Boolean);
  const out = [];
  for (const code of codes) {
    if (code === 'en') { console.warn('English is managed by the default/--all mode; skipping.'); continue; }
    const entry = LANGUAGE_MANIFEST.find((l) => l.code === code);
    if (!entry) { console.warn(`Unknown language code '${code}' — skipping.`); continue; }
    if (entry.disabled) { console.warn(`[${code}] disabled — skipping.`); continue; }
    out.push(entry);
  }
  return out;
}

async function main() {
    const args = process.argv.slice(2);
    const isAll = args.includes('--all');
    const full = args.includes('--full');
    const langsArgIdx = args.findIndex((a) => a.startsWith('--langs='));

    if (langsArgIdx >= 0) {
        const langs = resolveLangsArg(args[langsArgIdx].slice('--langs='.length));
        if (langs.length === 0) {
            console.error('No languages selected for --langs. Use seed, all, en-free codes, e.g. de,ta.');
            process.exit(1);
        }
        for (const entry of langs) {
            if (full) {
                await crawlLangDeep(entry);
            } else {
                await crawlLangIncremental(entry);
            }
        }
        finishLanguages();
        return;
    }

    await runEnglish(isAll);
}

main().catch(err => {
    console.error(err);
    process.exit(1);
});