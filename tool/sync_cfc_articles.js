#!/usr/bin/env node
/**
 * tool/sync_cfc_articles.js
 *
 * Scraper for CFC India Word for the Week (WFTW) articles.
 * Builds:
 *  - releases/articles/wftw_feed.sqlite.gz (for the mobile feed)
 *  - releases/articles/wftw_manifest.json (for background sync hot-swapping)
 *  - releases/articles/wftw/*.json (individual live-synced articles)
 */

const https = require('https');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { DatabaseSync } = require('node:sqlite');
const zlib = require('zlib');

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

// Ensure directories exist
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
if (!fs.existsSync(WFTW_JSON_DIR)) fs.mkdirSync(WFTW_JSON_DIR, { recursive: true });

// Initialize state ledger
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
function fetch(url, retries = 3) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'ChristianTubeCrawler/1.0' } }, (res) => {
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
  let contentHtml = '';
  const contentMatch = html.match(/<div[^>]*class="article-body"[^>]*>([\s\S]*?)<\/div>\s*<\/div>\s*<\/div>\s*<\/div>/i);
  if (contentMatch) {
    contentHtml = contentMatch[1];
  } else {
    // fallback, try to find content between specific tags
    const pMatches = html.match(/<p>[\s\S]*?<\/p>/gi);
    if (pMatches) {
        // filter out footer texts
        contentHtml = pMatches.filter(p => !p.includes('cfcindia.com/wftw')).join('');
    }
  }

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

async function main() {
    const args = process.argv.slice(2);
    const isAll = args.includes('--all');
    
    const now = new Date();
    const currentYear = now.getFullYear();
    const currentMonth = now.getMonth() + 1; // 1-12
    
    if (isAll) {
        for (let y = currentYear; y >= 2001; y--) {
            for (let m = 12; m >= 1; m--) {
                // optimization: if we hit future months, skip
                if (y === currentYear && m > currentMonth) continue;
                await scrapeMonth(y, m);
            }
        }
    } else {
        // Just scrape the current month
        await scrapeMonth(currentYear, currentMonth);
        
        // Also scrape previous month just in case we are on the 1st of the month
        if (now.getDate() < 7) {
            let pM = currentMonth - 1;
            let pY = currentYear;
            if (pM === 0) { pM = 12; pY--; }
            await scrapeMonth(pY, pM);
        }
    }
    
    await finish();
}

main().catch(err => {
    console.error(err);
    process.exit(1);
});
