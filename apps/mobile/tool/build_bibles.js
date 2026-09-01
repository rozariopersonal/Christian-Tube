const fs = require('fs');
const path = require('path');
const https = require('https');
const AdmZip = require('adm-zip');

const ROOT = path.join(__dirname, '..', '..', '..');
const OUT_BIBLES = path.join(ROOT, 'apps', 'backend', 'data', 'bibles');

// Canonical 66-book order matching the app's bible_book.dart names.
const BOOK_NAMES = [
  'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy', 'Joshua',
  'Judges', 'Ruth', '1 Samuel', '2 Samuel', '1 Kings', '2 Kings',
  '1 Chronicles', '2 Chronicles', 'Ezra', 'Nehemiah', 'Esther', 'Job',
  'Psalms', 'Proverbs', 'Ecclesiastes', 'Song of Solomon', 'Isaiah',
  'Jeremiah', 'Lamentations', 'Ezekiel', 'Daniel', 'Hosea', 'Joel',
  'Amos', 'Obadiah', 'Jonah', 'Micah', 'Nahum', 'Habakkuk', 'Zephaniah',
  'Haggai', 'Zechariah', 'Malachi', 'Matthew', 'Mark', 'Luke', 'John',
  'Acts', 'Romans', '1 Corinthians', '2 Corinthians', 'Galatians',
  'Ephesians', 'Philippians', 'Colossians', '1 Thessalonians',
  '2 Thessalonians', '1 Timothy', '2 Timothy', 'Titus', 'Philemon',
  'Hebrews', 'James', '1 Peter', '2 Peter', '1 John', '2 John', '3 John',
  'Jude', 'Revelation',
];

const USFM_CODES = [
  'GEN', 'EXO', 'LEV', 'NUM', 'DEU', 'JOS', 'JDG', 'RUT', '1SA', '2SA',
  '1KI', '2KI', '1CH', '2CH', 'EZR', 'NEH', 'EST', 'JOB', 'PSA', 'PRO',
  'ECC', 'SNG', 'ISA', 'JER', 'LAM', 'EZE', 'DAN', 'HOS', 'JOE', 'AMO',
  'OBA', 'JON', 'MIC', 'NAH', 'HAB', 'ZEP', 'HAG', 'ZEC', 'MAL', 'MAT',
  'MRK', 'LUK', 'JHN', 'ACT', 'ROM', '1CO', '2CO', 'GAL', 'EPH', 'PHP',
  'COL', '1TH', '2TH', '1TI', '2TI', 'TIT', 'PHM', 'HEB', 'JAS', '1PE',
  '2PE', '1JN', '2JN', '3JN', 'JUD', 'REV',
];

const codeToBook = {};
USFM_CODES.forEach((code, i) => (codeToBook[code] = { b: i + 1, n: BOOK_NAMES[i] }));

function fetchBuffer(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      if (res.statusCode !== 200) {
        res.resume();
        reject(new Error(`${url} -> ${res.statusCode}`));
        return;
      }
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks)));
    }).on('error', reject);
  });
}

function decodeEntities(s) {
  return s
    .replace(/&#160;|&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}

function cleanText(raw) {
  return decodeEntities(raw.replace(/<[^>]+>/g, '')).replace(/\s+/g, ' ').trim();
}

// ---- Parse eBible per-chapter HTML files into {code: chapters[][]} ----
function parseHtmlZip(zip) {
  const bookChapters = {}; // code -> { name, chapters: [] }
  const entries = zip.getEntries().filter((e) => /^[A-Z0-9]+[A-Z]{2,3}\d{2}\.htm$/i.test(e.entryName));
  for (const entry of entries) {
    const m = /^(.+?)(\d{2})\.htm$/i.exec(entry.entryName);
    if (!m) continue;
    let code = m[1];
    // Normalize mixed-case codes (abc -> ABC, 1ch -> 1CH). Regex only captured
    // alphanumeric prefixes ending in letters.
    code = code.toUpperCase();
    const chapter = parseInt(m[2], 10);
    if (chapter === 0) continue; // book intro page
    if (!codeToBook[code]) continue;
    if (!bookChapters[code]) {
      bookChapters[code] = { chapters: [] };
    }
    const html = entry.getData().toString('utf8');
    const spanRe = /<span class="verse" id="V(\d+)">[\s\S]*?<\/span>/g;
    const spans = [];
    let sm;
    while ((sm = spanRe.exec(html)) !== null) spans.push(sm.index + sm[0].length);
    if (spans.length === 0) continue;
    let verses = [];
    for (let i = 0; i < spans.length; i++) {
      const end = i + 1 < spans.length ? html.indexOf('<span class="verse"', spans[i]) : html.length;
      const seg = end === -1 ? html.slice(spans[i]) : html.slice(spans[i], end);
      const segText = seg.slice(0, seg.indexOf('<span class="verse"'));
      const text = cleanText(
        segText
          .split('<span class="verse"')[0]
          .replace(/<a[^>]*class="notemark"[^>]*>[\s\S]*?<\/a>/g, ''),
      );
      if (text) verses.push(text);
    }
    if (verses.length) bookChapters[code].chapters[chapter - 1] = verses;
  }
  return bookChapters;
}

// ---- Parse USFM text into { code -> { chapters: [] } } ----
function parseUsfm(text) {
  const book = { chapters: [] };
  let chapter = -1;
  let code = '';
  const cleaned = text.replace(/\\f \+[\s\S]*?\\f\*/g, '');
  const lines = cleaned.split(/\r?\n/);
  for (const line of lines) {
    const idm = /^\\id\s+([A-Z0-9]+)/.exec(line);
    if (idm) {
      code = idm[1].toUpperCase();
      continue;
    }
    const cm = /^\\c\s+(\d+)/.exec(line);
    if (cm) {
      chapter = parseInt(cm[1], 10);
      continue;
    }
    const vm = /^\\v\s+(\d+)(?:\s+(.*))?$/.exec(line.trim());
    if (vm && chapter > 0) {
      const verseNum = parseInt(vm[1], 10);
      const raw = (vm[2] || '').trim();
      const text = cleanText(raw.replace(/\\[a-z0-9*+\-]+/g, ''));
      if (text && verseNum > 0) {
        if (!book.chapters[chapter - 1]) book.chapters[chapter - 1] = [];
        book.chapters[chapter - 1][verseNum - 1] = text;
      }
    }
  }
  return { code, book };
}

function buildCompact(bookChapters) {
  const books = USFM_CODES.map((code) => {
    const meta = codeToBook[code];
    const chapters = (bookChapters[code] && bookChapters[code].chapters) || [];
    return { b: meta.b, n: meta.n, ch: chapters.map((c) => c || []) };
  });
  const totalVerses = books.reduce(
    (sum, bk) => sum + bk.ch.reduce((s, ch) => s + ch.length, 0),
    0,
  );
  return { books, totalVerses };
}

function writeAsset(fileId, compact) {
  fs.mkdirSync(OUT_BIBLES, { recursive: true });
  const out = JSON.stringify({ books: compact.books });
  const file = path.join(OUT_BIBLES, `bible_${fileId}.json`);
  fs.writeFileSync(file, out);
  console.log(`  ${file} (${out.length} bytes, ${compact.totalVerses} verses)`);
  return { file, verses: compact.totalVerses };
}

async function main() {
  const targetId = (process.argv[2] || '').toLowerCase();

  // 1) eBible.org versions: IRVs (CC BY-SA 4.0) & BSB (Public Domain CC0)
  const irv = [
    { zip: 'https://ebible.org/Scriptures/engbsb_html.zip', outId: 'bsb' },
    { zip: 'https://ebible.org/Scriptures/mal_html.zip', outId: 'mal_irv' },
    { zip: 'https://ebible.org/Scriptures/kanirv_html.zip', outId: 'kan_irv' },
    { zip: 'https://ebible.org/Scriptures/hin2017_html.zip', outId: 'hin_irv' },
    { zip: 'https://ebible.org/Scriptures/tel2017_html.zip', outId: 'tel_irv' },
  ];
  const irvToFetch = targetId ? irv.filter((v) => v.outId === targetId) : irv;
  for (const v of irvToFetch) {
    console.log('Fetching', v.zip);
    const zipBytes = await fetchBuffer(v.zip);
    const zip = new AdmZip(zipBytes);
    const bookChapters = parseHtmlZip(zip);
    const compact = buildCompact(bookChapters);
    writeAsset(v.outId, compact);
  }

  if (targetId && targetId !== 'taobvsi') {
    return;
  }

  // 2) Tamil Old Version (public domain) from USFM on GitHub
  console.log('Fetching Tamil OV USFM files...');
  const tree = await (await fetch(
    'https://api.github.com/repos/berinaniesh/bible-tamil/git/trees/main?recursive=1',
  )).json();
  const usfmFiles = tree.tree
    .filter((t) => t.type === 'blob' && /^usfm\/\d{2}_[^/]+\.usfm$/.test(t.path))
    .sort((a, b) => a.path.localeCompare(b.path));
  console.log(`  ${usfmFiles.length} usfm files`);
  if (usfmFiles.length !== 66) throw new Error('Expected 66 USFM files for Tamil OV');
  const bookChapters = {};
  for (let i = 0; i < usfmFiles.length; i++) {
    const f = usfmFiles[i];
    const url = `https://raw.githubusercontent.com/berinaniesh/bible-tamil/main/${f.path}`;
    const txt = await (await fetch(url)).text();
    const { code, book } = parseUsfm(txt);
    const expected = USFM_CODES[i];
    if (code && code !== expected) {
      console.log(`  note: \\id ${code} differs from expected ${expected} in ${f.path}`);
    }
    bookChapters[expected] = book;
  }
  const tamilCompact = buildCompact(bookChapters);
  writeAsset('taobvsi', tamilCompact);
}

main().then(() => console.log('done')).catch((e) => {
  console.error(e);
  process.exit(1);
});