/**
 * build_songs_catalog.js
 *
 * Imports Tamil songs from the worshipsongs-db-dev SQLite and English songs
 * from the Hymnal API (SDA Hymnal), normalises them into the Song JSON schema,
 * and writes `releases/songs/catalog.json`.
 *
 * Usage:
 *   node tool/build_songs_catalog.js
 *   node tool/build_songs_catalog.js --skip-tamil     # English only
 *   node tool/build_songs_catalog.js --skip-english    # Tamil only
 *
 * Caches fetched data under data/worshipsongs/ and data/hymnal/ so re-runs
 * are fast and offline-safe.
 */

const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

// ── Paths ───────────────────────────────────────────────────────────────────

const BASE_DIR = path.join(__dirname, '..');
const RELEASES_DIR = path.join(BASE_DIR, 'releases');
const SONGS_DIR = path.join(RELEASES_DIR, 'songs');
const DATA_DIR = path.join(BASE_DIR, 'data');
const TAMIL_DIR = path.join(DATA_DIR, 'worshipsongs');
const HYMNAL_DIR = path.join(DATA_DIR, 'hymnal');
const TAMIL_DB_PATH = path.join(TAMIL_DIR, 'songs.sqlite');
const HYMNAL_ALL_PATH = path.join(HYMNAL_DIR, 'hymns.json');
const HYMNAL_CATEGORIES_PATH = path.join(HYMNAL_DIR, 'categories.json');

const HYMNAL_API = 'https://hymnal.rindra.org/api';
const HYMNAL_EN_CATEGORY_ID = 3; // SDA Hymnal (English)
const HYMNAL_CONCURRENCY = 8;
const HYMNAL_REQUEST_DELAY_MS = 30;

const SQLITE_SOURCE_URL =
  'https://raw.githubusercontent.com/mcruncher/worshipsongs-db-dev/master/songs.sqlite';

// ── CLI flags ───────────────────────────────────────────────────────────────

const args = process.argv.slice(2);
const skipTamil = args.includes('--skip-tamil');
const skipEnglish = args.includes('--skip-english');

// ── Helpers ─────────────────────────────────────────────────────────────────

function ensureDir(dirPath) {
  if (!fs.existsSync(dirPath)) fs.mkdirSync(dirPath, { recursive: true });
}

function writeJson(filePath, data) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf8');
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

async function fetchWithRetry(url, opts = {}, retries = 3) {
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(15000), ...opts });
      if (res.status === 404) return null;
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return res;
    } catch (e) {
      if (attempt === retries) throw e;
      await sleep(500 * attempt);
    }
  }
  return null;
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function bumpRevision() {
  const revLen = 8;
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  let rev = '';
  for (let i = 0; i < revLen; i++) rev += chars[Math.floor(Math.random() * chars.length)];
  const manifestPath = path.join(RELEASES_DIR, 'manifest.json');
  const manifest = readJson(manifestPath);
  manifest.revision = rev;
  manifest.updatedAt = new Date().toISOString();
  manifest.songs = { catalog: rev };
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n', 'utf8');
  console.log(`  ✓ Bumped manifest revision to ${rev}`);
  return rev;
}

// ── Tamil (worshipsongs-db-dev) ─────────────────────────────────────────────

function isTamilChar(ch) {
  const code = ch.codePointAt(0);
  return code >= 0x0b80 && code <= 0x0bff;
}

function isLatinChar(ch) {
  const code = ch.codePointAt(0);
  return (code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a);
}

/// Split a verse's text into parallel Tamil-script and Latin-transliteration
/// lines. The worshipsongs DB pairs every Tamil line with its transliteration
/// on the following line, so both sequences are kept in order.
function splitVerseText(text) {
  const tamilLines = [];
  const latinLines = [];
  const hasTamil = /[\u0B80-\u0BFF]/.test(text);
  if (!hasTamil) return { tamil: '', latin: '' };

  const lines = text
    .split('\n')
    .map(l => l.replace(/^\d+\.\s*/, '').trim())
    .filter(Boolean);

  for (const line of lines) {
    const lineHasTamil = /[\u0B80-\u0BFF]/.test(line);
    if (lineHasTamil) {
      tamilLines.push(line);
    } else {
      latinLines.push(line);
    }
  }
  return { tamil: tamilLines.join('\n'), latin: latinLines.join('\n') };
}

/// Extract a verse's Tamil + Latin text from its XML/CDATA content.
function extractVersePair(content) {
  const hasYWrap = /\{y\}/.test(content);
  const raw = hasYWrap
    ? content.replace(/\{r\}[\s\S]*?\{\/r\}/g, '').replace(/\{y\}|\{\/y\}|\{r\}|\{\/r\}/g, '')
    : content;
  return splitVerseText(raw.replace(/<!\[CDATA\[|\]\]>/g, ''));
}

/// Clean text for reading: trim lines and drop footnote markers like "2X" /
/// "(2)".
function cleanLyricText(text) {
  return text
    .split('\n')
    .map(l => l.replace(/\s*\(?\s*\d+\s*[xX]\)?\s*$/i, '').trim())
    .filter(Boolean)
    .join('\n');
}

function tamilScriptRatio(text) {
  let tamil = 0, latin = 0;
  for (const ch of text) {
    if (isTamilChar(ch)) tamil++;
    else if (isLatinChar(ch)) latin++;
  }
  const denom = tamil + latin;
  return denom === 0 ? 0 : tamil / denom;
}

function parseOpenlpLyrics(songRow) {
  const re = /<verse\b[^>]*\blabel="([^"]*)"[^>]*\btype="([^"]*)"[^>]*>([\s\S]*?)<\/verse>/g;
  const verses = new Map();   // key = "type-label" -> { tamil, latin }
  const typeLabels = [];      // ordered list of {key, type, label}
  let m;
  while ((m = re.exec(songRow.lyrics))) {
    const [, label, type, raw] = m;
    const pair = extractVersePair(raw);
    const key = `${type}-${label}`;
    if (pair.tamil) {
      verses.set(key, pair);
      typeLabels.push({ key, type, label });
    }
  }
  return { verses, typeLabels };
}

/// Extract a clean Tamil-script title from the first Tamil line of the song.
function extractTamilTitle(songRow) {
  const { typeLabels, verses } = parseOpenlpLyrics(songRow);
  let firstTamil = null;
  for (const { key } of typeLabels) {
    const text = verses.get(key).tamil;
    if (!text) continue;
    const firstLine = text.split('\n').map(l => l.trim()).find(Boolean);
    if (firstLine) { firstTamil = firstLine; break; }
  }
  if (!firstTamil) return null;
  return firstTamil
    .replace(/^\d+\s*[.):]?\s*/, '')
    .replace(/^\([0-9xX]+\)\s*/i, '')
    .replace(/\s*\([xX]?\d+\)\s*$/i, '')
    .replace(/\s*[-–]\s*\d+\s*[xX]?\s*$/i, '')
    .trim();
}

/// Extract a transliterated (Latin) title, preferring the source row's Latin
/// title, else the first Latin line of the first verse.
function extractTitleRoman(songRow, parsed) {
  const srcTitle = (songRow.title || '').trim();
  if (srcTitle && /[A-Za-z]/.test(srcTitle)) return srcTitle;
  const { typeLabels, verses } = parsed;
  for (const { key } of typeLabels) {
    const latin = verses.get(key).latin;
    if (!latin) continue;
    const firstLine = latin.split('\n').map(l => l.trim()).find(Boolean);
    if (firstLine) return firstLine;
  }
  return null;
}

function assembleOrderedVerses(songRow) {
  const parsed = parseOpenlpLyrics(songRow);
  const { verses, typeLabels } = parsed;
  const rawOrder = (songRow.verse_order || '').trim();
  const orderTokens = rawOrder ? rawOrder.split(/\s+/).filter(Boolean) : [];

  const tamilResult = [];
  const latinResult = [];
  let lastEmittedKey = null;
  const used = new Set();

  function emit(key) {
    if (key === lastEmittedKey) return;
    const pair = verses.get(key);
    if (!pair) return;
    const t = cleanLyricText(pair.tamil);
    if (!t) return;
    tamilResult.push(t);
    latinResult.push(cleanLyricText(pair.latin));
    lastEmittedKey = key;
    used.add(key);
  }

  if (orderTokens.length > 0) {
    for (const token of orderTokens) emit(token);
    for (const { key } of typeLabels) if (!used.has(key)) emit(key);
  } else {
    for (const { key } of typeLabels) emit(key);
  }
  return { parsed, tamil: tamilResult, latin: latinResult };
}

async function importTamilSongs() {
  ensureDir(TAMIL_DIR);

  // Download SQLite if missing
  if (!fs.existsSync(TAMIL_DB_PATH)) {
    console.log('  Downloading Tamil songs SQLite...');
    const res = await fetchWithRetry(SQLITE_SOURCE_URL);
    if (!res) throw new Error('Failed to download songs.sqlite');
    const buf = Buffer.from(await res.arrayBuffer());
    fs.writeFileSync(TAMIL_DB_PATH, buf);
    console.log(`  ✓ Downloaded ${buf.length} bytes → ${TAMIL_DB_PATH}`);
  } else {
    console.log('  Using cached Tamil songs SQLite.');
  }

  const db = new DatabaseSync(TAMIL_DB_PATH);

  // Build author lookup (song_id → displayName)
  const authorsRaw = db.prepare('SELECT id, display_name FROM authors').all();
  const authorById = new Map(authorsRaw.map(a => [a.id, a.display_name]));

  const songAuthors = db.prepare('SELECT author_id, song_id FROM authors_songs').all();
  const songAuthorsMap = new Map();
  for (const { author_id, song_id } of songAuthors) {
    if (!songAuthorsMap.has(song_id)) songAuthorsMap.set(song_id, []);
    songAuthorsMap.get(song_id).push(author_id);
  }

  // Build songbook lookup (song_id → songbook name)
  const songbooksRaw = db.prepare('SELECT id, name FROM song_books').all();
  const songbookById = new Map(songbooksRaw.map(sb => [sb.id, sb.name]));

  const songSongbooks = db.prepare('SELECT songbook_id, song_id FROM songs_songbooks').all();
  const songSongbooksMap = new Map();
  for (const { songbook_id, song_id } of songSongbooks) {
    if (!songSongbooksMap.has(song_id)) songSongbooksMap.set(song_id, []);
    songSongbooksMap.get(song_id).push(songbook_id);
  }

  // Build topic lookup (song_id → topic names)
  const topicsRaw = db.prepare('SELECT id, name FROM topics').all();
  const topicById = new Map(topicsRaw.map(t => [t.id, t.name]));

  const songTopics = db.prepare('SELECT song_id, topic_id FROM songs_topics').all();
  const songTopicsMap = new Map();
  for (const { song_id, topic_id } of songTopics) {
    if (!songTopicsMap.has(song_id)) songTopicsMap.set(song_id, []);
    songTopicsMap.get(song_id).push(topic_id);
  }

  // Parse all songs
  const rows = db.prepare(
    'SELECT id, title, lyrics, verse_order, comments FROM songs WHERE lyrics IS NOT NULL AND lyrics != \'\''
  ).all();

  const songs = [];
  let skipped = 0;
  let noVerses = 0;

  for (const row of rows) {
    const { parsed, tamil: tamilVerses, latin: latinVerses } = assembleOrderedVerses(row);
    // Skip songs with no Tamil verses at all
    if (tamilVerses.length === 0) { noVerses++; continue; }

    // Drop songs whose assembled lyrics are not predominantly Tamil script
    // (e.g. transliterated/English-only content), honoring the no-Romanised rule.
    const joinedForRatio = tamilVerses.join('\n');
    if (tamilScriptRatio(joinedForRatio) < 0.6) { skipped++; continue; }

    // Determine the songbook (collection) — prefer the first one
    const bookIds = songSongbooksMap.get(row.id) || [];
    const rawBookName = bookIds.length > 0 ? songbookById.get(bookIds[0]) : null;
    // Clean collection name: extract Tamil part from braces if present
    let collection = null;
    if (rawBookName) {
      const braceMatch = rawBookName.match(/\{(.+)\}/);
      collection = braceMatch ? braceMatch[1] : rawBookName;
    }

    // Author(s): take the first non-unknown author
    const aIds = songAuthorsMap.get(row.id) || [];
    let authorName = null;
    for (const aid of aIds) {
      const dn = authorById.get(aid) || '';
      // Skip "Author Unknown" / "ஆசிரியர் தெரியவில்லை"
      if (!dn.includes('Unknown') && !dn.includes('தெரியவில்லை') && dn.trim()) {
        // Clean display_name: take Tamil part from braces if present
        const m = dn.match(/\{(.+)\}/);
        authorName = m ? m[1] : dn.trim();
        break;
      }
    }

    // Category from topics
    const topicIds = songTopicsMap.get(row.id) || [];
    const primaryTopic = topicIds.length > 0 ? topicById.get(topicIds[0]) : null;
    let category = null;
    if (primaryTopic) {
      const m = primaryTopic.match(/\{(.+)\}/);
      category = m ? m[1] : primaryTopic;
    }

    const titleRoman = extractTitleRoman(row, parsed);
    songs.push({
      id: `ta-${row.id}`,
      title: extractTamilTitle(row) || row.title,
      titleRoman,
      author: authorName,
      collection: collection,
      language: 'ta',
      category: category,
      verses: tamilVerses,
      versesRoman: latinVerses,
    });
  }

  console.log(`  ✓ Parsed ${songs.length} Tamil songs (skipped ${noVerses} with no Tamil verses, ${skipped} with low Tamil ratio)`);
  return songs;
}

// ── English (Hymnal API – SDA Hymnal, category 3) ───────────────────────────

async function fetchJsonCached(url, cachePath) {
  if (fs.existsSync(cachePath)) {
    return readJson(cachePath);
  }
  const res = await fetchWithRetry(url);
  if (!res) return null;
  const data = await res.json();
  ensureDir(path.dirname(cachePath));
  fs.writeFileSync(cachePath, JSON.stringify(data, null, 2), 'utf8');
  return data;
}

async function fetchHymnDetail(id, cacheDir) {
  const cachePath = path.join(cacheDir, `${id}.json`);
  if (fs.existsSync(cachePath)) return readJson(cachePath);
  const res = await fetchWithRetry(`${HYMNAL_API}/hymns/${id}.json`);
  if (!res) return null;
  const data = await res.json();
  ensureDir(cacheDir);
  fs.writeFileSync(cachePath, JSON.stringify(data, null, 2), 'utf8');
  return data;
}

async function importEnglishSongs() {
  ensureDir(HYMNAL_DIR);

  // Fetch categories list
  console.log('  Fetching hymn categories...');
  const categories = await fetchJsonCached(
    `${HYMNAL_API}/categories.json`,
    HYMNAL_CATEGORIES_PATH
  );
  if (!categories) throw new Error('Failed to fetch categories.json');

  const enCat = categories.find(c => c.ID === HYMNAL_EN_CATEGORY_ID);
  console.log(`  Using English collection: "${enCat?.Name}" (${enCat?.count} hymns)`);

  // Fetch all hymns (full list)
  console.log('  Fetching hymns index (all 4,485)...');
  const allHymns = await fetchJsonCached(`${HYMNAL_API}/hymns.json`, HYMNAL_ALL_PATH);
  if (!allHymns) throw new Error('Failed to fetch hymns.json');

  const enHymns = allHymns.filter(h => h.Category === HYMNAL_EN_CATEGORY_ID);
  console.log(`  Found ${enHymns.length} English hymns to fetch lyrics for.`);

  // Fetch lyrics with concurrency limit
  const detailCacheDir = path.join(HYMNAL_DIR, 'details');
  ensureDir(detailCacheDir);

  const hymnDetails = [];
  for (let i = 0; i < enHymns.length; i++) {
    const h = enHymns[i];
    try {
      const detail = await fetchHymnDetail(h.ID, detailCacheDir);
      if (detail && Array.isArray(detail.Lyrics)) {
        hymnDetails.push(detail);
      } else {
        hymnDetails.push({ ...h, Lyrics: [] });
      }
    } catch (e) {
      console.error(`  ✗ Failed hymn ${h.ID} "${h.Title}": ${e.message}`);
      hymnDetails.push({ ...h, Lyrics: [] });
    }
    if (i % 50 === 0) process.stdout.write(`\r  Fetched ${i + 1}/${enHymns.length}...`);
    if ((i + 1) % HYMNAL_CONCURRENCY === 0) await sleep(HYMNAL_REQUEST_DELAY_MS);
  }
  process.stdout.write('\n');

  const songs = [];
  for (const detail of hymnDetails) {
    const verses = (detail.Lyrics || [])
      .map(ly => ly.text.replace(/\\n/g, '\n').trim())
      .filter(Boolean);
    if (verses.length === 0) continue;

    songs.push({
      id: `en-sda-${detail.Number ?? detail.ID}`,
      title: detail.Title || '',
      author: detail.Author || null,
      collection: 'SDA Hymnal',
      language: 'en',
      category: null,
      verses,
    });
  }

  console.log(`  ✓ Parsed ${songs.length} English hymns from SDA Hymnal`);
  return songs;
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  console.log('=== Building songs catalog ===\n');

  const allSongs = [];

  if (!skipTamil) {
    console.log('[1/3] Importing Tamil songs from worshipsongs-db-dev...');
    const tamilSongs = await importTamilSongs();
    allSongs.push(...tamilSongs);
  }

  if (!skipEnglish) {
    console.log('\n[2/3] Importing English songs from Hymnal API...');
    const englishSongs = await importEnglishSongs();
    allSongs.push(...englishSongs);
  }

  // Deduplicate by id (safety net)
  const seen = new Set();
  const deduped = [];
  for (const s of allSongs) {
    if (!seen.has(s.id)) {
      seen.add(s.id);
      deduped.push(s);
    }
  }

  console.log(`\n[3/3] Writing ${deduped.length} songs to catalog...`);
  const catalog = { songs: deduped };
  ensureDir(SONGS_DIR);
  writeJson(path.join(SONGS_DIR, 'catalog.json'), catalog);
  console.log(`  ✓ Wrote releases/songs/catalog.json`);

  bumpRevision();

  const tamilCount = deduped.filter(s => s.language === 'ta').length;
  const englishCount = deduped.filter(s => s.language === 'en').length;
  console.log(`\n========================================`);
  console.log(`✓ Songs catalog built successfully!`);
  console.log(`  Tamil: ${tamilCount}  |  English: ${englishCount}  |  Total: ${deduped.length}`);
  console.log(`========================================\n`);
}

main().catch(e => { console.error('Fatal:', e); process.exit(1); });
