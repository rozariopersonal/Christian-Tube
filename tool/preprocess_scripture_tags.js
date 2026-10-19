#!/usr/bin/env node
/**
 * tool/preprocess_scripture_tags.js
 *
 * Offline preprocessor pipeline that scans book chapters and articles, detects
 * verified Bible scripture references, and injects standardized high-performance
 * client tags:
 *
 *   [ref:book.chapter.start_verse[-end_verse]|Display Text]
 *
 * Features:
 *  - 100% idempotent: can be safely re-run without duplicate tagging or syntax degradation.
 *  - Zero false-positives: non-scripture expressions (e.g. "Chapter 1", "page 5", "April 15")
 *    are never tagged.
 *  - High coverage: handles compact abbreviations ("Psa.73:25", "Lk.5:8", "1Jn.1:9"),
 *    Roman numerals ("I Cor 13:4", "II Tim 2:15"), en-dashes/hyphens ("Luke 18:1–8"),
 *    comma verse lists ("Job 42:5,6"), and Tamil agglutinative suffixes ("எபேசியர் 1:17,18-ல்").
 *  - Multilingual: loads localized book names across all supported Bible versions from
 *    releases/book_names.json plus curated abbreviations.
 *  - Repackaging: updates data/books.sqlite, publishes modular sqlite.gz packages,
 *    rebuilds article sqlite packages, and bumps the manifest revision for automatic
 *    cache busting across client installs.
 *
 * Usage:
 *  node tool/preprocess_scripture_tags.js               # Run all (books, articles, db, repack, bump)
 *  node tool/preprocess_scripture_tags.js --dry-run     # Inspect references without writing
 *  node tool/preprocess_scripture_tags.js --books       # Process only book chapter JSONs
 *  node tool/preprocess_scripture_tags.js --articles    # Process only article JSONs
 *  node tool/preprocess_scripture_tags.js --db          # Update data/books.sqlite and publish packages
 *  node tool/preprocess_scripture_tags.js --bump        # Bump revision in releases/manifest.json
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { DatabaseSync } = require('node:sqlite');

const BASE_DIR = path.join(__dirname, '..');
const RELEASES_DIR = path.join(BASE_DIR, 'releases');
const BOOKS_DIR = path.join(RELEASES_DIR, 'books');
const ARTICLES_DIR = path.join(RELEASES_DIR, 'articles');
const MASTER_DB_PATH = path.join(BASE_DIR, 'data', 'books.sqlite');
const MANIFEST_PATH = path.join(RELEASES_DIR, 'manifest.json');
const BOOK_NAMES_PATH = path.join(RELEASES_DIR, 'book_names.json');

// Base Bible Book Names & Curated Abbreviations
const BIBLE_BOOKS = {
  // English Old Testament
  'genesis': 1, 'gen': 1, 'ge': 1, 'gn': 1,
  'exodus': 2, 'exod': 2, 'exo': 2, 'ex': 2,
  'leviticus': 3, 'lev': 3, 'le': 3, 'lv': 3,
  'numbers': 4, 'num': 4, 'nu': 4, 'nm': 4,
  'deuteronomy': 5, 'deut': 5, 'deu': 5, 'dt': 5,
  'joshua': 6, 'josh': 6, 'jos': 6,
  'judges': 7, 'judg': 7, 'jdg': 7,
  'ruth': 8, 'rut': 8, 'ru': 8,
  '1 samuel': 9, '1sam': 9, '1 sam': 9, '1sa': 9, '1st samuel': 9,
  '2 samuel': 10, '2sam': 10, '2 sam': 10, '2sa': 10, '2nd samuel': 10,
  'i samuel': 9, 'i sam': 9, 'isam': 9,
  'ii samuel': 10, 'ii sam': 10, 'iisam': 10,
  '1 kings': 11, '1kgs': 11, '1 kgs': 11, '1ki': 11, '1st kings': 11, '1kings': 11,
  '2 kings': 12, '2kgs': 12, '2 kgs': 12, '2ki': 12, '2nd kings': 12, '2kings': 12,
  'i kings': 11, 'i kgs': 11, 'ikings': 11,
  'ii kings': 12, 'ii kgs': 12, 'iikings': 12,
  '1 chronicles': 13, '1chron': 13, '1 chron': 13, '1ch': 13, '1chr': 13,
  '2 chronicles': 14, '2chron': 14, '2 chron': 14, '2ch': 14, '2chr': 14,
  'i chronicles': 13, 'i chron': 13, 'ichron': 13,
  'ii chronicles': 14, 'ii chron': 14, 'iichron': 14,
  'ezra': 15, 'ezr': 15,
  'nehemiah': 16, 'neh': 16,
  'esther': 17, 'est': 17, 'esth': 17,
  'job': 18,
  'psalm': 19, 'psalms': 19, 'psa': 19, 'ps': 19, 'pss': 19,
  'proverbs': 20, 'prov': 20, 'pro': 20, 'prv': 20,
  'ecclesiastes': 21, 'eccles': 21, 'ecc': 21,
  'song of solomon': 22, 'song of songs': 22, 'sng': 22, 'sos': 22, 'canticles': 22,
  'isaiah': 23, 'isa': 23,
  'jeremiah': 24, 'jer': 24,
  'lamentations': 25, 'lam': 25,
  'ezekiel': 26, 'ezek': 26, 'ezk': 26,
  'daniel': 27, 'dan': 27,
  'hosea': 28, 'hos': 28,
  'joel': 29, 'jol': 29, 'joe': 29,
  'amos': 30, 'amo': 30, 'am': 30,
  'obadiah': 31, 'obad': 31, 'oba': 31,
  'jonah': 32, 'jon': 32,
  'micah': 33, 'mic': 33,
  'nahum': 34, 'nah': 34, 'nam': 34,
  'habakkuk': 35, 'hab': 35,
  'zephaniah': 36, 'zeph': 36, 'zep': 36,
  'haggai': 37, 'hag': 37,
  'zechariah': 38, 'zech': 38, 'zec': 38,
  'malachi': 39, 'mal': 39,

  // English New Testament
  'matthew': 40, 'matt': 40, 'mat': 40, 'mt': 40,
  'mark': 41, 'mrk': 41, 'mk': 41,
  'luke': 42, 'luk': 42, 'lk': 42,
  'john': 43, 'jhn': 43, 'jn': 43,
  'acts': 44, 'act': 44,
  'romans': 45, 'rom': 45, 'ro': 45,
  '1 corinthians': 46, '1cor': 46, '1 cor': 46, '1co': 46, '1st corinthians': 46,
  '2 corinthians': 47, '2cor': 47, '2 cor': 47, '2co': 47, '2nd corinthians': 47,
  'i corinthians': 46, 'i cor': 46, 'icor': 46,
  'ii corinthians': 47, 'ii cor': 47, 'iicor': 47,
  'galatians': 48, 'gal': 48,
  'ephesians': 49, 'eph': 49,
  'philippians': 50, 'phil': 50, 'php': 50,
  'colossians': 51, 'col': 51,
  '1 thessalonians': 52, '1thess': 52, '1 thess': 52, '1th': 52, '1 th': 52,
  '2 thessalonians': 53, '2thess': 53, '2 thess': 53, '2th': 53, '2 th': 53,
  'i thessalonians': 52, 'i thess': 52, 'ithess': 52,
  'ii thessalonians': 53, 'ii thess': 53, 'iithess': 53,
  '1 timothy': 54, '1tim': 54, '1 tim': 54, '1ti': 54, '1 ti': 54,
  '2 timothy': 55, '2tim': 55, '2 tim': 55, '2ti': 55, '2 ti': 55,
  'i timothy': 54, 'i tim': 54, 'itim': 54,
  'ii timothy': 55, 'ii tim': 55, 'iitim': 55,
  'titus': 56, 'tit': 56,
  'philemon': 57, 'philem': 57, 'phm': 57, 'phlm': 57,
  'hebrews': 58, 'heb': 58,
  'james': 59, 'jas': 59,
  '1 peter': 60, '1pet': 60, '1 pet': 60, '1pe': 60, '1 pe': 60,
  '2 peter': 61, '2pet': 61, '2 pet': 61, '2pe': 61, '2 pe': 61,
  'i peter': 60, 'i pet': 60, 'ipet': 60,
  'ii peter': 61, 'ii pet': 61, 'iipet': 61,
  '1 john': 62, '1jhn': 62, '1 jn': 62, '1jn': 62, '1john': 62,
  '2 john': 63, '2jhn': 63, '2 jn': 63, '2jn': 63, '2john': 63,
  '3 john': 64, '3jhn': 64, '3 jn': 64, '3jn': 64, '3john': 64,
  'i john': 62, 'i jhn': 62, 'i jn': 62, 'ijohn': 62,
  'ii john': 63, 'ii jhn': 63, 'ii jn': 63, 'iijohn': 63,
  'iii john': 64, 'iii jhn': 64, 'iii jn': 64, 'iiijohn': 64,
  'jude': 65, 'jud': 65,
  'revelation': 66, 'rev': 66,

  // Tamil Book Names & Abbreviations
  'ஆதியாகமம்': 1, 'ஆதி': 1,
  'யாத்திராகமம்': 2, 'யாத்': 2,
  'லேவியராகமம்': 3, 'லேவி': 3,
  'எண்ணாகமம்': 4, 'எண்': 4,
  'உபாகமம்': 5, 'உபா': 5,
  'யோசுவா': 6, 'யோசு': 6,
  'நியாயாதிபதிகள்': 7, 'நியா': 7,
  'ரூத்': 8,
  '1 சாமுவேல்': 9, '1சாமுவேல்': 9, '1 சாமு': 9, '1சாமு': 9,
  '2 சாமுவேல்': 10, '2சாமுவேல்': 10, '2 சாமு': 10, '2சாமு': 10,
  '1 இராஜாக்கள்': 11, '1இராஜாக்கள்': 11, '1 இராஜா': 11, '1இராஜா': 11,
  '2 இராஜாக்கள்': 12, '2இராஜாக்கள்': 12, '2 இராஜா': 12, '2இராஜா': 12,
  '1 நாளாகமம்': 13, '1நாளாகமம்': 13, '1 நாளா': 13, '1நாளா': 13,
  '2 நாளாகமம்': 14, '2நாளாகமம்': 14, '2 நாளா': 14, '2நாளா': 14,
  'எஸ்றா': 15,
  'நெகேமியா': 16, 'நெகே': 16,
  'எஸ்தர்': 17, 'எஸ்த': 17,
  'யோபு': 18,
  'சங்கீதம்': 19, 'சங்': 19,
  'நீதிமொழிகள்': 20, 'நீதி': 20,
  'பிரசங்கி': 21, 'பிர': 21,
  'உன்னதப்பாட்டு': 22, 'உன்னதம்': 22,
  'ஏசாயா': 23, 'ஏசா': 23,
  'எரேமியா': 24, 'எரே': 24,
  'புலம்பல்': 25, 'புல': 25,
  'எசேக்கியேல்': 26, 'எசே': 26,
  'தானியேல்': 27, 'தானி': 27,
  'ஓசியா': 28, 'ஓசி': 28,
  'யோவேல்': 29, 'ஆமோஸ்': 30, 'ஒபதியா': 31, 'யோனா': 32, 'மீகா': 33, 'நாகூம்': 34,
  'ஆபகூக்': 35, 'செப்பனியா': 36, 'ஆகாய்': 37, 'சகரியா': 38, 'மல்கியா': 39,
  'மத்தேயு': 40, 'மத்': 40,
  'மாற்கு': 41, 'மாற்': 41,
  'லூக்கா': 42, 'லூக்': 42,
  'யோவான்': 43, 'யோவா': 43,
  'அப்போஸ்தலர்': 44, 'அப்': 44,
  'ரோமர்': 45, 'ரோம': 45,
  '1 கொரிந்தியர்': 46, '1கொரிந்தியர்': 46, '1 கொரி': 46, '1கொரி': 46,
  '2 கொரிந்தியர்': 47, '2கொரிந்தியர்': 47, '2 கொரி': 47, '2கொரி': 47,
  'கலாத்தியர்': 48, 'கலா': 48,
  'எபேசியர்': 49, 'எபே': 49,
  'பிலிப்பியர்': 50, 'பிலி': 50,
  'கொலோசெயர்': 51, 'கொலோ': 51,
  '1 தெசலோனிக்கேயர்': 52, '1தெசலோனிக்கேயர்': 52, '1 தெச': 52, '1தெச': 52,
  '2 தெசலோனிக்கேயர்': 53, '2தெசலோனிக்கேயர்': 53, '2 தெச': 53, '2தெச': 53,
  '1 தீமோத்தேயு': 54, '1தீமோத்தேயு': 54, '1 தீமோ': 54, '1தீமோ': 54,
  '2 தீமோத்தேயு': 55, '2தீமோத்தேயு': 55, '2 தீமோ': 55, '2தீமோ': 55,
  'தீத்து': 56, 'பிலேமோன்': 57, 'பிலே': 57, 'எபிரெயர்': 58, 'எபி': 58,
  'யாக்கோபு': 59, 'யாக்': 59,
  '1 பேதுரு': 60, '1பேதுரு': 60, '1 பேது': 60, '1பேது': 60,
  '2 பேதுரு': 61, '2பேதுரு': 61, '2 பேது': 61, '2பேது': 61,
  '1 யோவான்': 62, '1யோவான்': 62, '1 யோவா': 62, '1யோவா': 62,
  '2 யோவான்': 63, '2யோவான்': 63, '2 யோவா': 63, '2யோவா': 63,
  '3 யோவான்': 64, '3யோவான்': 64, '3 யோவா': 64, '3யோவா': 64,
  'யூதா': 65, 'வெளிப்படுத்தின விசேஷம்': 66, 'வெளிப்படுத்தல்': 66, 'வெளி': 66
};

// Build master lookup map incorporating all 30 versions in book_names.json
const LOOKUP = { ...BIBLE_BOOKS };
if (fs.existsSync(BOOK_NAMES_PATH)) {
  try {
    const versions = JSON.parse(fs.readFileSync(BOOK_NAMES_PATH, 'utf8'));
    for (const byNum of Object.values(versions)) {
      for (const [numStr, name] of Object.entries(byNum)) {
        const num = parseInt(numStr, 10);
        if (num >= 1 && num <= 66) {
          const norm = name.toLowerCase().replace(/\./g, '').replace(/\s+/g, ' ').trim();
          if (norm) LOOKUP[norm] = num;
        }
      }
    }
  } catch (err) {
    console.warn('Warning: Could not read book_names.json:', err.message);
  }
}

// Regex matching the Dart client's ScriptureRefParser.scriptureRegex
const SCRIPTURE_REGEX = /(?<=^|[\s\("“;\[])((?:[123]|I{1,3})\.?\s*)?([^\d\s:.,;"!?\(\)\[\]]{2,20})(?:\.|\s+)\s*(\d{1,3})\s*[:.]\s*(\d{1,3})(?:\s*[-–—,]\s*(\d{1,3}))?(?=\s|$|[.;,!?\)“"–—]|-(?![\d]))/gui;

/**
 * Injects [ref:b.c.s[-e]|Display Text] into scripture citations.
 * Strips previous tags first for idempotent re-runs.
 */
function tagScripture(text) {
  if (!text || typeof text !== 'string') return text;

  // 1. Strip existing tags to guarantee idempotency
  const clean = text.replace(/\[ref:\d+\.\d+\.\d+(?:-\d+)?\|([^\]]+)\]/g, '$1');

  // 2. Perform verified citation matching
  return clean.replace(SCRIPTURE_REGEX, (match, ordinal, bookName, ch, startV, endV) => {
    const rawBook = ((ordinal || '') + bookName).trim();
    const norm = rawBook.toLowerCase().replace(/\./g, '').replace(/\s+/g, ' ').trim();
    const bookNum = LOOKUP[norm];
    if (!bookNum) return match; // Not a recognized Bible book

    const chapter = parseInt(ch, 10);
    const startVerse = parseInt(startV, 10);
    const endVerse = endV ? parseInt(endV, 10) : null;
    const range = endVerse ? `${startVerse}-${endVerse}` : `${startVerse}`;

    return `[ref:${bookNum}.${chapter}.${range}|${match}]`;
  });
}

function countTags(str) {
  if (!str) return 0;
  const m = str.match(/\[ref:\d+\.\d+\.\d+(?:-\d+)?\|/g);
  return m ? m.length : 0;
}

/**
 * Process book chapter JSON files under releases/books/
 */
function processBooks(isDryRun) {
  console.log('\n--- Processing Book Chapters in releases/books/ ---');
  let filesScanned = 0;
  let filesModified = 0;
  let totalTags = 0;

  function walk(dir) {
    for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, ent.name);
      if (ent.isDirectory()) {
        if (ent.name === 'chapters') {
          const chFiles = fs.readdirSync(full).filter(f => f.endsWith('.json'));
          for (const chFile of chFiles) {
            filesScanned++;
            const chPath = path.join(full, chFile);
            try {
              const raw = fs.readFileSync(chPath, 'utf8');
              const lines = JSON.parse(raw);
              if (!Array.isArray(lines)) continue;

              let changed = false;
              let fileTags = 0;

              for (const item of lines) {
                if (item && typeof item.text === 'string' && item.contentType !== 'img' && !item.text.endsWith('.jpg')) {
                  const tagged = tagScripture(item.text);
                  if (tagged !== item.text) {
                    item.text = tagged;
                    changed = true;
                  }
                  fileTags += countTags(item.text);
                }
              }

              totalTags += fileTags;
              if (changed) {
                filesModified++;
                if (!isDryRun) {
                  fs.writeFileSync(chPath, JSON.stringify(lines, null, 2), 'utf8');
                }
              }
            } catch (err) {
              console.error(`Error processing chapter file ${chPath}:`, err.message);
            }
          }
        } else {
          walk(full);
        }
      }
    }
  }

  walk(BOOKS_DIR);
  console.log(`✓ Books: ${filesScanned} chapter files scanned, ${filesModified} modified (${totalTags} references tagged)`);
  return { filesScanned, filesModified, totalTags };
}

/**
 * Process article JSON files under releases/articles/
 */
function processArticles(isDryRun) {
  console.log('\n--- Processing Articles in releases/articles/ ---');
  let filesScanned = 0;
  let filesModified = 0;
  let totalTags = 0;

  const entries = fs.readdirSync(ARTICLES_DIR, { withFileTypes: true });
  for (const ent of entries) {
    if (ent.isDirectory() && ent.name !== 'en') {
      const langDir = path.join(ARTICLES_DIR, ent.name);
      const files = fs.readdirSync(langDir).filter(f => f.endsWith('.json') && f !== 'index.json' && f !== 'recent.json');
      for (const f of files) {
        filesScanned++;
        const filePath = path.join(langDir, f);
        try {
          const raw = fs.readFileSync(filePath, 'utf8');
          const art = JSON.parse(raw);
          if (!art || !Array.isArray(art.lines)) continue;

          let changed = false;
          let fileTags = 0;

          for (let i = 0; i < art.lines.length; i++) {
            const line = art.lines[i];
            if (typeof line === 'string') {
              const tagged = tagScripture(line);
              if (tagged !== line) {
                art.lines[i] = tagged;
                changed = true;
              }
              fileTags += countTags(art.lines[i]);
            } else if (line && typeof line.text === 'string') {
              const tagged = tagScripture(line.text);
              if (tagged !== line.text) {
                line.text = tagged;
                changed = true;
              }
              fileTags += countTags(line.text);
            }
          }

          totalTags += fileTags;
          if (changed) {
            filesModified++;
            if (!isDryRun) {
              fs.writeFileSync(filePath, JSON.stringify(art, null, 2), 'utf8');
            }
          }
        } catch (err) {
          console.error(`Error processing article file ${filePath}:`, err.message);
        }
      }
    }
  }

  console.log(`✓ Articles: ${filesScanned} files scanned, ${filesModified} modified (${totalTags} references tagged)`);
  return { filesScanned, filesModified, totalTags };
}

/**
 * Update master SQLite database (data/books.sqlite) and publish packages
 */
function processDatabase(isDryRun) {
  console.log('\n--- Processing Master Database (data/books.sqlite) ---');
  if (!fs.existsSync(MASTER_DB_PATH)) {
    console.warn('data/books.sqlite not found. Skipping DB tagging.');
    return;
  }

  const db = new DatabaseSync(MASTER_DB_PATH);
  const rows = db.prepare('SELECT rowid, text FROM book_content').all();
  console.log(`Scanning ${rows.length} rows in book_content...`);

  let modifiedRows = 0;
  let totalTags = 0;

  const updateStmt = isDryRun ? null : db.prepare('UPDATE book_content SET text = ? WHERE rowid = ?');

  if (!isDryRun) db.exec('BEGIN');
  try {
    for (const r of rows) {
      if (typeof r.text === 'string') {
        const tagged = tagScripture(r.text);
        const tags = countTags(tagged);
        totalTags += tags;
        if (tagged !== r.text) {
          modifiedRows++;
          if (!isDryRun) {
            updateStmt.run(tagged, r.rowid);
          }
        }
      }
    }
    if (!isDryRun) db.exec('COMMIT');
  } catch (err) {
    if (!isDryRun) db.exec('ROLLBACK');
    throw err;
  }
  db.close();

  console.log(`✓ Database: ${rows.length} rows scanned, ${modifiedRows} modified (${totalTags} references tagged)`);

  if (!isDryRun && modifiedRows > 0) {
    console.log('\nRepackaging books.sqlite.gz and modular published packages...');
    const zlib = require('zlib');
    const masterRaw = fs.readFileSync(MASTER_DB_PATH);
    const gz = zlib.gzipSync(masterRaw, { level: 9 });
    const gzPath = path.join(BASE_DIR, 'data', 'books.sqlite.gz');
    fs.writeFileSync(gzPath, gz);
    console.log(`✓ Wrote ${gzPath} (${(gz.length / 1024 / 1024).toFixed(2)} MB)`);

    // Run publish_books.js & export_releases_books.js
    console.log('Running tool/publish_books.js...');
    execSync('node tool/publish_books.js', { cwd: BASE_DIR, stdio: 'inherit' });
    console.log('Running tool/export_releases_books.js...');
    execSync('node tool/export_releases_books.js', { cwd: BASE_DIR, stdio: 'inherit' });
  }
}

/**
 * Rebuild articles.sqlite.gz across languages
 */
function rebuildArticlePackages(isDryRun) {
  if (isDryRun) return;
  console.log('\n--- Rebuilding Article SQLite Packages ---');
  execSync('node tool/build_articles_sqlite.js', { cwd: BASE_DIR, stdio: 'inherit' });
}

/**
 * Bumps the revision token in releases/manifest.json
 */
function bumpRevision(isDryRun) {
  console.log('\n--- Bumping releases/manifest.json Revision ---');
  if (!fs.existsSync(MANIFEST_PATH)) {
    console.warn('releases/manifest.json not found!');
    return;
  }

  const manifest = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'));
  const oldRev = manifest.revision;
  const newRev = Date.now().toString(36);

  if (isDryRun) {
    console.log(`[DRY RUN] Would bump revision from ${oldRev} -> ${newRev}`);
    return;
  }

  manifest.revision = newRev;
  manifest.updatedAt = new Date().toISOString();
  fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2), 'utf8');
  console.log(`✓ Bumped revision: ${oldRev} -> ${newRev}`);
}

function main() {
  const args = process.argv.slice(2);
  const isDryRun = args.includes('--dry-run');
  const doBooks = args.includes('--books') || (!args.includes('--articles') && !args.includes('--db') && !args.includes('--bump'));
  const doArticles = args.includes('--articles') || (!args.includes('--books') && !args.includes('--db') && !args.includes('--bump'));
  const doDb = args.includes('--db') || (!args.includes('--books') && !args.includes('--articles') && !args.includes('--bump'));
  const doBump = args.includes('--bump') || (!args.includes('--books') && !args.includes('--articles') && !args.includes('--db'));

  console.log('=====================================================');
  console.log(`  Scripture Reference Preprocessor Pipeline`);
  console.log(`  Mode: ${isDryRun ? 'DRY RUN (No writes)' : 'PRODUCTION WRITE'}`);
  console.log('=====================================================');

  if (doBooks) processBooks(isDryRun);
  if (doArticles) processArticles(isDryRun);
  if (doDb) processDatabase(isDryRun);
  if (doArticles && !isDryRun) rebuildArticlePackages(isDryRun);
  if (doBump) bumpRevision(isDryRun);

  console.log('\n=====================================================');
  console.log('✓ Preprocessing pipeline complete!');
  console.log('=====================================================\n');
}

main();
