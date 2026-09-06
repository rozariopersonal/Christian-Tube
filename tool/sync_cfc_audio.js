#!/usr/bin/env node
/**
 * tool/sync_cfc_audio.js
 *
 * Fault-tolerant crawler and catalog generator for all CFC India audio resources.
 * Streams audio directly from cfcindia.org; builds and updates Git/CDN manifests:
 *   - releases/audio/catalog.json
 *   - releases/audio/series/<series_id>.json
 *
 * Uses SQLite state ledger (data/cfc_audio_state.sqlite) for change tracking,
 * idempotency, and fast daily delta runs.
 *
 * Usage:
 *   node tool/sync_cfc_audio.js [--force]
 */

const https = require('https');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { DatabaseSync } = require('node:sqlite');

const DATA_DIR = path.join(__dirname, '..', 'data');
const DB_PATH = path.join(DATA_DIR, 'cfc_audio_state.sqlite');
const RELEASES_AUDIO_DIR = path.join(__dirname, '..', 'releases', 'audio');
const RELEASES_SERIES_DIR = path.join(RELEASES_AUDIO_DIR, 'series');
const CATALOG_PATH = path.join(RELEASES_AUDIO_DIR, 'catalog.json');

const ASSETS_AUDIO_DIR = path.join(__dirname, '..', 'apps', 'mobile', 'assets', 'audio');
const ASSETS_SERIES_DIR = path.join(ASSETS_AUDIO_DIR, 'series');
const ASSETS_CATALOG_PATH = path.join(ASSETS_AUDIO_DIR, 'catalog.json');

// Ensure directories exist
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
if (!fs.existsSync(RELEASES_SERIES_DIR)) fs.mkdirSync(RELEASES_SERIES_DIR, { recursive: true });
if (!fs.existsSync(ASSETS_SERIES_DIR)) fs.mkdirSync(ASSETS_SERIES_DIR, { recursive: true });

// Initialize SQLite State Store
const db = new DatabaseSync(DB_PATH);
db.exec(`
  CREATE TABLE IF NOT EXISTS crawled_pages (
    url TEXT PRIMARY KEY,
    content_hash TEXT,
    crawled_at INTEGER
  );

  CREATE TABLE IF NOT EXISTS audio_tracks (
    id TEXT PRIMARY KEY,
    audio_url TEXT NOT NULL,
    title TEXT NOT NULL,
    series_id TEXT NOT NULL,
    series_title TEXT NOT NULL,
    speaker TEXT NOT NULL,
    duration_seconds INTEGER DEFAULT 0,
    scripture_book TEXT,
    scripture_chapter INTEGER,
    scripture_verse INTEGER,
    language TEXT DEFAULT 'English',
    page_url TEXT,
    first_seen_at INTEGER
  );

  CREATE TABLE IF NOT EXISTS audio_series (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    category TEXT NOT NULL,
    speaker TEXT NOT NULL,
    cover_url TEXT,
    language TEXT DEFAULT 'English',
    description TEXT,
    track_count INTEGER DEFAULT 0,
    last_updated_at INTEGER
  );
`);

// ── HTTP Fetchers ─────────────────────────────────────────────────────────────

function fetch(url, retries = 3) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'ChristianTubeCrawler/1.0' } }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        let loc = res.headers.location;
        if (!loc.startsWith('http')) loc = new URL(loc, url).href;
        return resolve(fetch(loc, retries));
      }
      if (res.statusCode !== 200) {
        if (retries > 0) {
          return setTimeout(() => resolve(fetch(url, retries - 1)), 1000);
        }
        return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
      }
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => resolve(d));
    }).on('error', (err) => {
      if (retries > 0) {
        return setTimeout(() => resolve(fetch(url, retries - 1)), 1500);
      }
      reject(err);
    });
  });
}

async function fetchJson(url) {
  const text = await fetch(url);
  return JSON.parse(text);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function cleanText(text) {
  if (!text) return '';
  if (Array.isArray(text)) text = text.join(' ');
  if (typeof text !== 'string') text = String(text);
  return text
    .replace(/&#039;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&#8217;/g, "'")
    .replace(/&#8216;/g, "'")
    .replace(/\s+/g, ' ')
    .trim();
}

function slugify(text) {
  return text
    .toString()
    .toLowerCase()
    .trim()
    .replace(/[^\w\s-]/g, '')
    .replace(/[\s_-]+/g, '_')
    .replace(/^-+|-+$/g, '');
}

const BIBLE_BOOKS = {
  'genesis': 'GEN', 'exodus': 'EXO', 'leviticus': 'LEV', 'numbers': 'NUM', 'deuteronomy': 'DEU',
  'joshua': 'JOS', 'judges': 'JDG', 'ruth': 'RUT', '1 samuel': '1SA', '2 samuel': '2SA',
  '1 kings': '1KI', '2 kings': '2KI', '1 chronicles': '1CH', '2 chronicles': '2CH',
  'ezra': 'EZR', 'nehemiah': 'NEH', 'esther': 'EST', 'job': 'JOB', 'psalm': 'PSA', 'psalms': 'PSA',
  'proverbs': 'PRO', 'ecclesiastes': 'ECC', 'song of solomon': 'SNG', 'isaiah': 'ISA',
  'jeremiah': 'JER', 'lamentations': 'LAM', 'ezekiel': 'EZK', 'daniel': 'DAN', 'hosea': 'HOS',
  'joel': 'JOL', 'amos': 'AMO', 'obadiah': 'OBA', 'jonah': 'JON', 'micah': 'MIC', 'nahum': 'NAM',
  'habakkuk': 'HAB', 'zephaniah': 'ZEP', 'haggai': 'HAG', 'zechariah': 'ZEC', 'malachi': 'MAL',
  'matthew': 'MAT', 'mark': 'MRK', 'luke': 'LUK', 'john': 'JHN', 'acts': 'ACT', 'romans': 'ROM',
  '1 corinthians': '1CO', '2 corinthians': '2CO', 'galatians': 'GAL', 'ephesians': 'EPH',
  'philippians': 'PHP', 'colossians': 'COL', '1 thessalonians': '1TH', '2 thessalonians': '2TH',
  '1 timothy': '1TI', '2 timothy': '2TI', 'titus': 'TIT', 'philemon': 'PHM', 'hebrews': 'HEB',
  'james': 'JAS', '1 peter': '1PE', '2 peter': '2PE', '1 john': '1JN', '2 john': '2JN',
  '3 john': '3JN', 'jude': 'JUD', 'revelation': 'REV'
};

function parseScripture(title) {
  const match = title.match(/(Genesis|Exodus|Leviticus|Numbers|Deuteronomy|Joshua|Judges|Ruth|1\s*Samuel|2\s*Samuel|1\s*Kings|2\s*Kings|1\s*Chronicles|2\s*Chronicles|Ezra|Nehemiah|Esther|Job|Psalms?|Proverbs|Ecclesiastes|Song of Solomon|Isaiah|Jeremiah|Lamentations|Ezekiel|Daniel|Hosea|Joel|Amos|Obadiah|Jonah|Micah|Nahum|Habakkuk|Zephaniah|Haggai|Zechariah|Malachi|Matthew|Mark|Luke|John|Acts|Romans|1\s*Corinthians|2\s*Corinthians|Galatians|Ephesians|Philippians|Colossians|1\s*Thessalonians|2\s*Thessalonians|1\s*Timothy|2\s*Timothy|Titus|Philemon|Hebrews|James|1\s*Peter|2\s*Peter|1\s*John|2\s*John|3\s*John|Jude|Revelation)\s*[-:]?\s*(\d+)?(?::(\d+))?/i);
  if (!match) return { book: null, chapter: null, verse: null };
  const bKey = match[1].toLowerCase().replace(/\s+/g, ' ');
  return {
    book: BIBLE_BOOKS[bKey] || null,
    chapter: match[2] ? parseInt(match[2], 10) : null,
    verse: match[3] ? parseInt(match[3], 10) : null,
  };
}

// ── Crawler Phase 1: Core Systematic Study Series ─────────────────────────────

async function crawlStudySeries() {
  console.log('\n--- Phase 1: Ingesting Core Systematic Study Series ---');

  const coreSeries = [
    {
      id: 'through_the_bible',
      title: 'Through The Bible',
      url: 'https://www.cfcindia.com/bible',
      category: 'Bible Survey',
      speaker: 'Zac Poonen',
      coverUrl: 'https://www.cfcindia.org/resources/en/images/through-the-bible.jpg',
      description: '70-Hour Bible Survey covering the distinctive spiritual message of each book from Genesis to Revelation.'
    },
    {
      id: 'basic_christian_teachings',
      title: 'Basic Christian Teachings',
      url: 'https://www.cfcindia.com/basic-christian-teachings',
      category: 'Foundations',
      speaker: 'Zac Poonen',
      coverUrl: 'https://www.cfcindia.org/resources/en/images/basic-christian-teachings.jpg',
      description: '72 foundational teachings on essential Christian truths, discipleship, and victory over sin.'
    },
    {
      id: 'all_that_jesus_taught',
      title: 'All That Jesus Taught',
      url: 'https://www.cfcindia.com/all-that-jesus-taught',
      category: 'Discipleship',
      speaker: 'Zac Poonen',
      coverUrl: 'https://www.cfcindia.org/resources/en/images/all-that-jesus-taught.jpg',
      description: '80 systematic studies on every command and teaching Jesus gave to His disciples.'
    },
    {
      id: 'the_glory_of_the_new_covenant',
      title: 'The Glory of the New Covenant',
      url: 'https://www.cfcindia.com/the-glory-of-the-new-covenant',
      category: 'Christian Living',
      speaker: 'Zac Poonen',
      coverUrl: 'https://www.cfcindia.org/resources/en/images/glory-of-new-covenant-cd.jpg',
      description: '14 life-changing messages exploring the power and liberty of living under the New Covenant.'
    },
    {
      id: 'sermon_on_the_mount',
      title: 'Sermon on the Mount',
      url: 'https://www.cfcindia.com/sermon-on-the-mount',
      category: 'Discipleship',
      speaker: 'Zac Poonen',
      coverUrl: 'https://www.cfcindia.org/images/bank/sermon-on-the-mount-study-card.png',
      description: '18 comprehensive verse-by-verse expositions on Matthew chapters 5, 6, and 7.'
    },
    {
      id: 'fundamental_biblical_truths',
      title: 'Fundamental Biblical Truths',
      url: 'https://www.cfcindia.com/fundamental-biblical-truths',
      category: 'Foundations',
      speaker: 'Zac Poonen',
      coverUrl: 'https://www.cfcindia.org/images/bank/FTB-cd-box-lighthouse.jpg',
      description: '28 essential truths on God’s purpose for man, spiritual warfare, faith, and the Church.'
    },
    {
      id: 'words_of_life',
      title: 'Words of Life',
      url: 'https://www.cfcindia.com/words-of-life',
      category: 'Foundations',
      speaker: 'Zac Poonen',
      coverUrl: 'https://www.cfcindia.org/images/bank/words-of-life-english.jpg',
      description: '60 short, impactful messages on spiritual growth, character, and victorious living.'
    }
  ];

  const insertTrack = db.prepare(`
    INSERT INTO audio_tracks (id, audio_url, title, series_id, series_title, speaker, duration_seconds, scripture_book, scripture_chapter, scripture_verse, language, page_url, first_seen_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      audio_url = excluded.audio_url,
      title = excluded.title,
      series_id = excluded.series_id,
      series_title = excluded.series_title,
      speaker = excluded.speaker,
      scripture_book = excluded.scripture_book,
      scripture_chapter = excluded.scripture_chapter,
      scripture_verse = excluded.scripture_verse
  `);

  const insertSeries = db.prepare(`
    INSERT INTO audio_series (id, title, category, speaker, cover_url, language, description, track_count, last_updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      title = excluded.title,
      category = excluded.category,
      speaker = excluded.speaker,
      cover_url = excluded.cover_url,
      description = excluded.description,
      track_count = excluded.track_count,
      last_updated_at = excluded.last_updated_at
  `);

  for (const s of coreSeries) {
    console.log(`Crawling ${s.title}...`);
    try {
      const html = await fetch(s.url);
      const regex = /<p>\s*<a[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>\s*<\/p>[\s\S]*?<a[^>]+href="([^"]+\.mp3)"/gi;
      let m;
      let count = 0;
      while ((m = regex.exec(html)) !== null) {
        count++;
        const pageUrl = m[1].trim();
        const rawTitle = cleanText(m[2]);
        const mp3Url = m[3].trim();
        const sc = parseScripture(rawTitle);
        const urlHash = crypto.createHash('md5').update(mp3Url).digest('hex').substring(0, 8);
        const trackId = `${s.id}_${String(count).padStart(2, '0')}_${urlHash}`;

        insertTrack.run(
          trackId,
          mp3Url,
          rawTitle,
          s.id,
          s.title,
          s.speaker,
          0,
          sc.book,
          sc.chapter,
          sc.verse,
          'English',
          pageUrl,
          Date.now()
        );
      }

      insertSeries.run(
        s.id,
        s.title,
        s.category,
        s.speaker,
        s.coverUrl,
        'English',
        s.description,
        count,
        Date.now()
      );
      console.log(`  -> Saved ${count} tracks for ${s.title}`);
    } catch (err) {
      console.error(`  Failed to crawl ${s.title}: ${err.message}`);
    }
  }

  // Crawl Verse-by-verse studies across books
  console.log('Crawling Verse-By-Verse series...');
  const vbvBooks = [
    'Genesis', 'Ezra', 'Nehemiah', 'Proverbs', 'Daniel', 'Haggai', 'Zechariah', 'Malachi',
    'Matthew', 'Mark', 'Luke', 'John', 'Acts', 'Romans', '1-Corinthians', '2-Corinthians',
    'Galatians', 'Ephesians', 'Philippians', 'Colossians', '1-Thessalonians', '2-Thessalonians',
    '1-Timothy', '2-Timothy', 'Titus', 'Philemon', 'Hebrews', 'James', '1-Peter', '2-Peter',
    '1-John', '2-John', '3-John', 'Jude', 'Revelation'
  ];

  let totalVbvTracks = 0;
  for (const b of vbvBooks) {
    const bSlug = `verse_by_verse_${slugify(b)}`;
    const bTitle = `Verse By Verse: ${b.replace(/-/g, ' ')}`;
    const bUrl = `https://www.cfcindia.com/verse-by-verse/${b}`;
    try {
      const html = await fetch(bUrl);
      const regex = /<p>\s*<a[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>\s*<\/p>[\s\S]*?<a[^>]+href="([^"]+\.mp3)"/gi;
      let m;
      let bCount = 0;
      while ((m = regex.exec(html)) !== null) {
        bCount++;
        totalVbvTracks++;
        const pageUrl = m[1].trim();
        const rawTitle = cleanText(m[2]);
        const mp3Url = m[3].trim();
        const sc = parseScripture(rawTitle);
        const urlHash = crypto.createHash('md5').update(mp3Url).digest('hex').substring(0, 8);
        const trackId = `${bSlug}_${String(bCount).padStart(2, '0')}_${urlHash}`;

        insertTrack.run(
          trackId,
          mp3Url,
          rawTitle,
          bSlug,
          bTitle,
          'Zac Poonen',
          0,
          sc.book,
          sc.chapter,
          sc.verse,
          'English',
          pageUrl,
          Date.now()
        );
      }

      if (bCount > 0) {
        insertSeries.run(
          bSlug,
          bTitle,
          'Verse By Verse',
          'Zac Poonen',
          'https://www.cfcindia.org/resources/en/images/verse-by-verse.jpg',
          'English',
          `Detailed verse-by-verse audio exposition through the book of ${b.replace(/-/g, ' ')}.`,
          bCount,
          Date.now()
        );
      }
    } catch (_) {
      // Book page might be empty or 404, continue
    }
  }
  console.log(`  -> Saved ${totalVbvTracks} Verse-By-Verse tracks`);
}

// ── Crawler Phase 2: All Series & Sermons API ─────────────────────────────────

async function crawlSermonsApi() {
  console.log('\n--- Phase 2: Ingesting Sermons & Topical Series from CFC API ---');
  
  console.log('Fetching all series metadata...');
  const allSeriesList = await fetchJson('https://www.cfcindia.com/api/all_series.json');
  console.log(`Found ${allSeriesList.length} total series from API`);

  const seriesMetaMap = {};
  for (const s of allSeriesList) {
    const rawTitle = cleanText(s.t || s.tt || '');
    if (!rawTitle) continue;
    const id = slugify(rawTitle);
    seriesMetaMap[rawTitle] = {
      id,
      title: rawTitle,
      link: s.link || ''
    };
  }

  const insertTrack = db.prepare(`
    INSERT INTO audio_tracks (id, audio_url, title, series_id, series_title, speaker, duration_seconds, scripture_book, scripture_chapter, scripture_verse, language, page_url, first_seen_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      audio_url = excluded.audio_url,
      title = excluded.title,
      series_id = excluded.series_id,
      series_title = excluded.series_title,
      speaker = excluded.speaker,
      language = excluded.language
  `);

  let page = 1;
  let totalApiTracks = 0;
  while (true) {
    console.log(`Fetching sermons page ${page}...`);
    try {
      const sermons = await fetchJson(`https://www.cfcindia.com/api/all_sermons.json?page=${page}`);
      if (!Array.isArray(sermons) || sermons.length === 0) break;

      for (const sermon of sermons) {
        const rawAudio = sermon.au;
        const auList = Array.isArray(rawAudio) ? rawAudio : (rawAudio ? [rawAudio] : []);
        const validMp3s = auList.map(x => (x || '').trim()).filter(x => x.toLowerCase().endsWith('.mp3'));
        if (validMp3s.length === 0) continue;

        const title = cleanText(sermon.t || sermon.tt || 'Untitled Sermon');
        const speaker = cleanText(sermon.a || 'Zac Poonen') || 'Zac Poonen';
        const rawSeries = cleanText(sermon.s || '');
        const language = cleanText(sermon.l || 'English') || 'English';
        const pageUrl = sermon.link ? `https://www.cfcindia.com${sermon.link}` : '';
        const sc = parseScripture(title);

        let seriesId = '';
        let seriesTitle = '';

        if (rawSeries) {
          seriesId = slugify(rawSeries);
          seriesTitle = rawSeries;
        } else {
          // Categorize standalone sermons by language / general
          if (language === 'English') {
            seriesId = 'general_sermons_english';
            seriesTitle = 'General Sermons & Messages';
          } else {
            const langSlug = slugify(language);
            seriesId = `general_sermons_${langSlug}`;
            seriesTitle = `${language} Messages`;
          }
        }

        const mp3Url = validMp3s[0];
        const urlHash = crypto.createHash('md5').update(mp3Url).digest('hex').substring(0, 8);
        const titleSlug = slugify(title).substring(0, 30);
        const trackId = `${seriesId}_${titleSlug}_${urlHash}`;

        insertTrack.run(
          trackId,
          mp3Url,
          title,
          seriesId,
          seriesTitle,
          speaker,
          0,
          sc.book,
          sc.chapter,
          sc.verse,
          language,
          pageUrl,
          Date.now()
        );
        totalApiTracks++;
      }

      page++;
    } catch (err) {
      console.error(`Error on page ${page}: ${err.message}`);
      break;
    }
  }

  console.log(`Ingested ${totalApiTracks} sermons with direct MP3 URLs from API`);
}

// ── Crawler Phase 3: Catalog & Manifest Generation ───────────────────────────

function categorizeSeries(title, language) {
  if (language && language !== 'English') return 'Multilingual';
  const t = title.toLowerCase();
  if (t.includes('jesus taught') || t.includes('sermon on the mount') || t.includes('disciple')) return 'Discipleship';
  if (t.includes('verse by verse')) return 'Verse By Verse';
  if (t.includes('through the bible') || t.includes('bible survey')) return 'Bible Survey';
  if (t.includes('bible') || t.includes('genesis') || t.includes('matthew') || t.includes('romans') || t.includes('corinthians')) {
    return 'Bible Survey';
  }
  if (t.includes('devotion') || t.includes('daily')) return 'Daily Devotions';
  if (t.includes('family') || t.includes('marriage') || t.includes('married') || t.includes('home') || t.includes('children')) return 'Family & Home';
  if (t.includes('conference') || t.includes('meeting') || t.includes('camp')) return 'Conferences';
  if (t.includes('basic') || t.includes('foundation') || t.includes('truth') || t.includes('words of life')) return 'Foundations';
  if (t.includes('church') || t.includes('leadership') || t.includes('body')) return 'The Church';
  if (t.includes('cross') || t.includes('abundant life') || t.includes('faith') || t.includes('walk') || t.includes('covenant') || t.includes('spirit')) return 'Christian Living';
  return 'General Sermons';
}

function generateSeriesCover(category, title) {
  const c = category.toLowerCase();
  const t = title.toLowerCase();
  if (t.includes('through the bible')) return 'https://www.cfcindia.org/resources/en/images/through-the-bible.jpg';
  if (t.includes('all that jesus taught')) return 'https://www.cfcindia.org/resources/en/images/all-that-jesus-taught.jpg';
  if (t.includes('basic christian teachings')) return 'https://www.cfcindia.org/resources/en/images/basic-christian-teachings.jpg';
  if (t.includes('glory of the new covenant')) return 'https://www.cfcindia.org/resources/en/images/glory-of-new-covenant-cd.jpg';
  if (t.includes('sermon on the mount')) return 'https://www.cfcindia.org/images/bank/sermon-on-the-mount-study-card.png';
  if (t.includes('fundamental biblical truths')) return 'https://www.cfcindia.org/images/bank/FTB-cd-box-lighthouse.jpg';
  if (t.includes('words of life')) return 'https://www.cfcindia.org/images/bank/words-of-life-english.jpg';
  if (c === 'verse by verse') return 'https://www.cfcindia.org/resources/en/images/verse-by-verse.jpg';
  if (c === 'foundations') return 'https://www.cfcindia.org/resources/en/images/basic-christian-teachings.jpg';
  if (c === 'daily devotions') return 'https://www.cfcindia.org/images/bank/daily_devotion.jpg';
  if (c === 'family & home') return 'https://www.cfcindia.org/images/bank/godly-family-life-cd.jpg';
  if (c === 'conferences') return 'https://www.cfcindia.org/images/bank/cfc-conference-banner.jpg';
  if (c === 'the church') return 'https://www.cfcindia.org/resources/en/icon/cfc-logo-maroon.png';
  if (c === 'discipleship') return 'https://www.cfcindia.org/resources/en/images/all-that-jesus-taught.jpg';
  if (c === 'christian living') return 'https://www.cfcindia.org/resources/en/images/glory-of-new-covenant-cd.jpg';
  return 'https://www.cfcindia.org/images/bank/weekly_podcast.jpg';
}

async function buildManifests() {
  console.log('\n--- Phase 3: Generating Releases JSON Manifests ---');

  // Query all unique series from tracks
  const seriesRows = db.prepare(`
    SELECT DISTINCT series_id, series_title, language, COUNT(*) as track_count
    FROM audio_tracks
    GROUP BY series_id
    HAVING track_count > 0
    ORDER BY track_count DESC
  `).all();

  console.log(`Found ${seriesRows.length} active series with audio tracks`);

  const catalog = [];

  for (const s of seriesRows) {
    const seriesId = s.series_id;
    const seriesTitle = s.series_title;
    const language = s.language || 'English';
    const category = categorizeSeries(seriesTitle, language);
    const coverUrl = generateSeriesCover(category, seriesTitle);

    // Get all tracks for this series
    const tracks = db.prepare(`
      SELECT id, title, series_id, series_title, speaker, duration_seconds, audio_url,
             scripture_book, scripture_chapter, scripture_verse
      FROM audio_tracks
      WHERE series_id = ?
      ORDER BY id ASC
    `).all(seriesId).map(t => ({
      id: t.id,
      title: t.title,
      seriesId: t.series_id,
      seriesTitle: t.series_title,
      speaker: t.speaker,
      durationSeconds: t.duration_seconds || 0,
      audioUrl: t.audio_url,
      ifCoverUrl: coverUrl,
      scriptureBook: t.scripture_book,
      scriptureChapter: t.scripture_chapter,
      scriptureVerse: t.scripture_verse
    }));

    const seriesObj = {
      id: seriesId,
      title: seriesTitle,
      description: `${seriesTitle} — Audio collection by Zac Poonen and CFC elders.`,
      speaker: tracks[0]?.speaker || 'Zac Poonen',
      trackCount: tracks.length,
      category,
      language,
      coverUrl,
      tracks
    };

    // Write individual series file
    const seriesJson = JSON.stringify(seriesObj, null, 2);
    const seriesFile = path.join(RELEASES_SERIES_DIR, `${seriesId}.json`);
    const assetSeriesFile = path.join(ASSETS_SERIES_DIR, `${seriesId}.json`);
    fs.writeFileSync(seriesFile, seriesJson, 'utf8');
    fs.writeFileSync(assetSeriesFile, seriesJson, 'utf8');

    // Add to catalog summary (without heavy tracks array)
    catalog.push({
      id: seriesId,
      title: seriesTitle,
      description: seriesObj.description,
      speaker: seriesObj.speaker,
      trackCount: tracks.length,
      category,
      language,
      coverUrl
    });
  }

  // Pinned priority order for top featured series
  const priorityIds = [
    'through_the_bible',
    'basic_christian_teachings',
    'all_that_jesus_taught',
    'the_glory_of_the_new_covenant',
    'sermon_on_the_mount',
    'fundamental_biblical_truths',
    'words_of_life',
    'daily_devotion_2024',
    'general_sermons_english'
  ];

  catalog.sort((a, b) => {
    const aIdx = priorityIds.indexOf(a.id);
    const bIdx = priorityIds.indexOf(b.id);
    if (aIdx !== -1 && bIdx !== -1) return aIdx - bIdx;
    if (aIdx !== -1) return -1;
    if (bIdx !== -1) return 1;
    return b.trackCount - a.trackCount;
  });

  // Write master catalog.json to both releases and app source assets
  const catalogJson = JSON.stringify(catalog, null, 2);
  fs.writeFileSync(CATALOG_PATH, catalogJson, 'utf8');
  fs.writeFileSync(ASSETS_CATALOG_PATH, catalogJson, 'utf8');
  console.log(`Wrote master catalog with ${catalog.length} series to ${CATALOG_PATH} and ${ASSETS_CATALOG_PATH}`);
  console.log(`Generated ${seriesRows.length} series tracklist files in ${RELEASES_SERIES_DIR} and ${ASSETS_SERIES_DIR}`);

  // Summary by category
  const categories = {};
  for (const item of catalog) {
    categories[item.category] = (categories[item.category] || 0) + item.trackCount;
  }
  console.log('\nTrack Distribution by Category:');
  for (const [cat, count] of Object.entries(categories)) {
    console.log(`  - ${cat}: ${count} tracks`);
  }
  const totalTracks = Object.values(categories).reduce((a, b) => a + b, 0);
  console.log(`\nTOTAL AUDIO TRACKS IN CATALOG: ${totalTracks}`);
}

async function main() {
  console.log('====================================================');
  console.log('   CFC INDIA AUDIO CATALOG SYNCHRONIZER');
  console.log('====================================================');

  if (!process.argv.includes('--manifests-only')) {
    await crawlStudySeries();
    await crawlSermonsApi();
  }
  await buildManifests();

  console.log('\nAudio catalog synchronization completed successfully!');
}

main().catch(err => {
  console.error('Fatal error in sync_cfc_audio:', err);
  process.exit(1);
});
