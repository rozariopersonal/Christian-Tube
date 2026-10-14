/**
 * Unified Bible Importer for Christian-Tube
 * 
 * Supports:
 * - API.Bible (American Bible Society)
 * - YouVersion Platform API (Life.Church)
 * 
 * Outputs canonical releases/bibles/{version}/ structure with counts.json,
 * books.json, per-chapter files, and monolithic bible_{version}.json.
 */

const fs = require('fs');
const path = require('path');
const https = require('https');

const CANON = require('./canon.json');

const RELEASES_DIR = path.resolve(__dirname, '../../releases');
const BIBLES_DIR = path.join(RELEASES_DIR, 'bibles');
const MANIFEST_FILE = path.join(RELEASES_DIR, 'manifest.json');

const API_BIBLE_KEY = process.env.API_BIBLE_KEY || '7-rV1sxCwAuLPp4A2jAmQ';
const YOUVERSION_APP_KEY = process.env.YOUVERSION_APP_KEY || 'uXc7kDxs9Ay9ClVThpIsSIGHiw2clfTWgSOPgAl1B0V6Z6jM';

const TARGET_VERSIONS = {
  // English Modern
  nasb: {
    name: 'New American Standard Bible (1995)',
    folder: 'nasb',
    provider: 'apibible',
    bibleId: 'b8ee27bcd1cae43a-01',
    fallbackProvider: 'youversion',
    fallbackId: 100
  },
  msg: {
    name: 'The Message',
    folder: 'msg',
    provider: 'apibible',
    bibleId: '6f11a7de016f942e-01'
  },
  nlt: {
    name: 'New Living Translation',
    folder: 'nlt',
    provider: 'apibible',
    bibleId: 'd6e14a625393b4da-01'
  },
  niv: {
    name: 'New International Version (2011)',
    folder: 'niv',
    provider: 'youversion',
    bibleId: 111
  },
  amp: {
    name: 'Amplified Bible',
    folder: 'amp',
    provider: 'youversion',
    bibleId: 1588
  },

  // Indian Contemporary & IRV Translations
  hin_hcv: {
    name: 'Hindi Contemporary Version',
    folder: 'hin_hcv',
    provider: 'apibible',
    bibleId: '2133003bb8b5e62b-01'
  },
  tam_tcv: {
    name: 'Tamil Contemporary Version',
    folder: 'tam_tcv',
    provider: 'apibible',
    bibleId: '032ec262506b719f-01'
  },
  tel_tcv: {
    name: 'Telugu Contemporary Version',
    folder: 'tel_tcv',
    provider: 'apibible',
    bibleId: '81d6933d39d343f8-03'
  },
  mal_mcv: {
    name: 'Malayalam Contemporary Version',
    folder: 'mal_mcv',
    provider: 'apibible',
    bibleId: 'de295e9ba65f6d0f-01'
  },
  kan_kcv: {
    name: 'Kannada Contemporary Version',
    folder: 'kan_kcv',
    provider: 'apibible',
    bibleId: '08389f036844c2de-01'
  },
  ben_bcv: {
    name: 'Bengali Contemporary Version',
    folder: 'ben_bcv',
    provider: 'apibible',
    bibleId: 'efd8a351a07d4264-01'
  },
  mar_mcv: {
    name: 'Marathi Contemporary Version',
    folder: 'mar_mcv',
    provider: 'apibible',
    bibleId: '1c825c8591183bb0-01'
  },
  pan_pcv: {
    name: 'Punjabi Contemporary Version',
    folder: 'pan_pcv',
    provider: 'apibible',
    bibleId: '38de522697cd8943-01'
  },
  urd_ucv: {
    name: 'Urdu Contemporary Version',
    folder: 'urd_ucv',
    provider: 'apibible',
    bibleId: 'eecbca904435fce9-01'
  },
  guj_irv: {
    name: 'Gujarati IRV',
    folder: 'guj_irv',
    provider: 'apibible',
    bibleId: 'a3644a98420c2703-01'
  },
  asm_irv: {
    name: 'Assamese IRV',
    folder: 'asm_irv',
    provider: 'apibible',
    bibleId: 'd199679f805f5b29-01'
  }
};

class RateLimitError extends Error {
  constructor(message, retryAfterSec) {
    super(message);
    this.name = 'RateLimitError';
    this.retryAfterSec = retryAfterSec;
  }
}

function httpsGet(hostname, requestPath, headers) {
  return new Promise((resolve, reject) => {
    const options = { hostname, path: requestPath, headers };
    https.get(options, res => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        if (res.statusCode === 429) {
          const retryHeader = res.headers['retry-after'];
          let retrySec = parseInt(retryHeader, 10);
          if (isNaN(retrySec) || retrySec <= 0) {
            retrySec = hostname.includes('youversion') ? 300 : 60;
          }
          return reject(new RateLimitError(`Rate limited (429) by ${hostname}. Retry after ${retrySec}s.`, retrySec));
        }
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            resolve({ statusCode: res.statusCode, headers: res.headers, data: JSON.parse(body) });
          } catch (e) {
            reject(new Error(`JSON parse error from ${hostname}${requestPath}: ${body.substring(0, 200)}`));
          }
        } else {
          reject(new Error(`HTTP ${res.statusCode} from ${hostname}${requestPath}: ${body.substring(0, 300)}`));
        }
      });
    }).on('error', reject);
  });
}

async function fetchWithRetry(fn, maxRetries = 5, delayMs = 1000) {
  let attempt = 0;
  while (true) {
    try {
      return await fn();
    } catch (err) {
      attempt++;
      if (err instanceof RateLimitError) {
        console.warn(`\n    ⏳ [RATE LIMIT] Pausing for ${err.retryAfterSec}s as required by server...`);
        for (let s = err.retryAfterSec; s > 0; s -= 10) {
          process.stdout.write(`       Cooling down... ${s}s remaining\r`);
          await new Promise(r => setTimeout(r, Math.min(10000, s * 1000)));
        }
        console.log(`\n    ▶️ Resuming after rate-limit cooldown.`);
        continue;
      }
      if (attempt >= maxRetries) throw err;
      const wait = delayMs * Math.pow(2, attempt - 1);
      console.warn(`    ⚠️ Retry ${attempt}/${maxRetries} after error: ${err.message}. Waiting ${wait}ms...`);
      await new Promise(r => setTimeout(r, wait));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// YouVersion Fetcher & Parser
// ─────────────────────────────────────────────────────────────────────────────
async function fetchYouVersionChapter(bibleId, bookUsfm, chapter) {
  const reqPath = `/v1/bibles/${bibleId}/passages/${bookUsfm}.${chapter}?format=html`;
  const res = await httpsGet('api.youversion.com', reqPath, {
    'X-YVP-App-Key': YOUVERSION_APP_KEY
  });

  const html = res.data && res.data.content ? res.data.content : '';
  const verses = [];
  const regex = /<span class="yv-v" v="(\d+)"><\/span>(?:<span class="yv-vlbl">\d+<\/span>)?([\s\S]*?)(?=(?:<span class="yv-v" v="\d+"><\/span>|$))/g;
  let m;
  while ((m = regex.exec(html)) !== null) {
    const vNum = parseInt(m[1], 10);
    const text = m[2].replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();
    if (vNum > 0 && text.length > 0) {
      verses.push({ verse: vNum, text });
    }
  }

  // Ensure ordered by verse
  verses.sort((a, b) => a.verse - b.verse);
  return verses;
}

// ─────────────────────────────────────────────────────────────────────────────
// API.Bible Fetcher & Parser (with support for MSG verse spans)
// ─────────────────────────────────────────────────────────────────────────────
async function fetchApiBibleChapter(bibleId, bookUsfm, chapter) {
  const reqPath = `/v1/bibles/${bibleId}/chapters/${bookUsfm}.${chapter}?content-type=json&include-notes=false&include-titles=false&include-chapter-numbers=false&include-verse-numbers=true&include-verse-spans=true`;
  const res = await httpsGet('api.scripture.api.bible', reqPath, {
    'api-key': API_BIBLE_KEY
  });

  const content = (res.data && res.data.data && res.data.data.content) ? res.data.data.content : [];
  const rawVerses = {};
  let currentKey = null;

  function walk(node) {
    if (!node) return;
    if (node.name === 'verse' && node.attrs && (node.attrs.number || node.attrs.sid)) {
      currentKey = (node.attrs.number || node.attrs.sid).trim();
      if (!rawVerses[currentKey]) rawVerses[currentKey] = '';
      return;
    }
    if (node.type === 'text' && node.text && currentKey) {
      rawVerses[currentKey] += node.text;
    }
    if (Array.isArray(node.items)) {
      for (const child of node.items) walk(child);
    }
  }

  for (const n of content) walk(n);

  const finalVersesMap = new Map();

  for (const [key, textRaw] of Object.entries(rawVerses)) {
    const text = textRaw.replace(/\s+/g, ' ').trim();
    if (!text) continue;

    // Check if key is a span like "1-4" or "JUD 1:1-2"
    const spanMatch = key.match(/(\d+)\s*[-–]\s*(\d+)/);
    if (spanMatch) {
      const start = parseInt(spanMatch[1], 10);
      const end = parseInt(spanMatch[2], 10);
      for (let v = start; v <= end; v++) {
        finalVersesMap.set(v, text);
      }
    } else {
      const singleMatch = key.match(/(\d+)$/);
      if (singleMatch) {
        const v = parseInt(singleMatch[1], 10);
        finalVersesMap.set(v, text);
      }
    }
  }

  const verses = Array.from(finalVersesMap.entries())
    .map(([verse, text]) => ({ verse, text }))
    .sort((a, b) => a.verse - b.verse);

  return verses;
}

// ─────────────────────────────────────────────────────────────────────────────
// Chapter Processing
// ─────────────────────────────────────────────────────────────────────────────
async function getChapterVerses(config, bookUsfm, chapter) {
  let verses = [];
  try {
    if (config.provider === 'youversion') {
      verses = await fetchWithRetry(() => fetchYouVersionChapter(config.bibleId, bookUsfm, chapter));
    } else {
      verses = await fetchWithRetry(() => fetchApiBibleChapter(config.bibleId, bookUsfm, chapter));
    }
  } catch (err) {
    if (config.fallbackProvider === 'apibible' && config.fallbackId) {
      console.warn(`    ⚠️ Primary provider failed. Falling back to API.Bible (${config.fallbackId})...`);
      verses = await fetchWithRetry(() => fetchApiBibleChapter(config.fallbackId, bookUsfm, chapter));
    } else {
      throw err;
    }
  }
  return verses;
}

// ─────────────────────────────────────────────────────────────────────────────
// Version Importer
// ─────────────────────────────────────────────────────────────────────────────
async function importVersion(versionKey, config, options = {}) {
  const versionDir = path.join(BIBLES_DIR, config.folder);
  fs.mkdirSync(versionDir, { recursive: true });

  console.log(`\n======================================================`);
  console.log(`🚀 Starting Import: ${config.name} (${versionKey.toUpperCase()})`);
  console.log(`   Destination: releases/bibles/${config.folder}`);
  console.log(`   Provider: ${config.provider} (ID: ${config.bibleId})`);
  console.log(`======================================================`);

  const countsMatrix = [];
  const monolithBooks = [];
  let totalVersesCount = 0;
  let totalChaptersCount = 0;

  for (const book of CANON) {
    const bookDir = path.join(versionDir, String(book.number));
    fs.mkdirSync(bookDir, { recursive: true });

    const bookCounts = [];
    const bookChaptersText = [];

    // Optional limit for testing
    const maxChapters = options.limitChapters ? Math.min(book.chapters, options.limitChapters) : book.chapters;

    process.stdout.write(`📖 [${book.number}/66] ${book.name} (${book.chapters} chs): `);

    for (let ch = 1; ch <= maxChapters; ch++) {
      const chFile = path.join(bookDir, `${ch}.json`);
      let verses = null;

      // Resume support: check if file already exists with valid data
      if (fs.existsSync(chFile)) {
        try {
          const existing = JSON.parse(fs.readFileSync(chFile, 'utf8'));
          if (Array.isArray(existing) && existing.length > 0) {
            verses = existing;
          }
        } catch (_) {}
      }

      if (!verses) {
        verses = await getChapterVerses(config, book.usfm, ch);
        fs.writeFileSync(chFile, JSON.stringify(verses));
        // Respectful throttle to strictly adhere to API rate limits (1200ms for YouVersion, 600ms for API.Bible)
        const throttleMs = config.provider === 'youversion' ? 1200 : 600;
        await new Promise(r => setTimeout(r, throttleMs));
        process.stdout.write(`.`);
      } else {
        process.stdout.write(`c`); // cached
      }

      bookCounts.push(verses.length);
      bookChaptersText.push(verses.map(v => v.text));
      totalVersesCount += verses.length;
      totalChaptersCount++;
    }

    process.stdout.write(` OK\n`);
    countsMatrix.push(bookCounts);
    monolithBooks.push({
      b: book.number,
      n: book.name,
      ch: bookChaptersText
    });
  }

  // Write counts.json
  const countsFile = path.join(versionDir, 'counts.json');
  fs.writeFileSync(countsFile, JSON.stringify(countsMatrix));
  console.log(`✅ Saved ${countsFile}`);

  // Write books.json
  const booksCatalog = CANON.map(b => ({
    bookNumber: b.number,
    name: b.name,
    chapters: b.chapters
  }));
  const booksFile = path.join(versionDir, 'books.json');
  fs.writeFileSync(booksFile, JSON.stringify(booksCatalog));
  console.log(`✅ Saved ${booksFile}`);

  // Write monolithic archive: bible_{folder}.json
  const monolithFile = path.join(BIBLES_DIR, `bible_${config.folder}.json`);
  fs.writeFileSync(monolithFile, JSON.stringify({ books: monolithBooks }));
  console.log(`✅ Saved ${monolithFile}`);

  console.log(`\n🎉 Successfully imported ${config.name}! Total: ${totalChaptersCount} chapters, ${totalVersesCount} verses.\n`);
}

function bumpRevision() {
  const rev = String(Date.now());
  const now = new Date().toISOString();
  fs.writeFileSync(MANIFEST_FILE, JSON.stringify({
    revision: rev,
    updatedAt: now
  }, null, 2));
  console.log(`📌 Bumped releases/manifest.json revision to ${rev} (${now})`);
}

async function main() {
  const args = process.argv.slice(2);
  let toRun = [];

  if (args.includes('--all')) {
    toRun = Object.keys(TARGET_VERSIONS);
  } else {
    for (const arg of args) {
      if (arg.startsWith('--version=')) {
        const v = arg.split('=')[1].toLowerCase();
        if (TARGET_VERSIONS[v]) toRun.push(v);
      }
    }
  }

  if (toRun.length === 0) {
    toRun = ['nasb', 'msg', 'nlt'];
  }

  console.log(`Selected versions to import (${toRun.length}): ${toRun.join(', ')}`);

  const succeeded = [];
  const failed = [];

  for (const v of toRun) {
    try {
      await importVersion(v, TARGET_VERSIONS[v]);
      succeeded.push(v);
    } catch (err) {
      console.error(`\n❌ Failed to import version '${v}': ${err.message}. Skipping and continuing with the remaining versions...`);
      failed.push({ version: v, error: err.message });
    }
  }

  if (succeeded.length > 0) {
    bumpRevision();
    console.log(`\n🎉 Successfully imported and released: ${succeeded.join(', ')}`);
  }

  if (failed.length > 0) {
    console.warn(`\n⚠️ The following versions failed and were ignored:`);
    for (const f of failed) {
      console.warn(`   - ${f.version}: ${f.error}`);
    }
  }

  console.log(`\n🏁 Importer run finished.`);
}

if (require.main === module) {
  main().catch(err => {
    console.error(`❌ Fatal import error:`, err);
    process.exit(1);
  });
}

module.exports = { importVersion, TARGET_VERSIONS };
