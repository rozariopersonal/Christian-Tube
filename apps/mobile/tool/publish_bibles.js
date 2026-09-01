// Stages compiled bible + feed assets for the Christian-App releases repo.
// Usage: node publish_bibles.js <stagingDir>
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..', '..');
const BIBLES = path.join(ROOT, 'apps', 'backend', 'data', 'bibles');
const SCRIPTURES = path.join(ROOT, 'apps', 'backend', 'data', 'scriptures.json');

const staging = process.argv[2];
if (!staging) {
  console.error('usage: node publish_bibles.js <stagingDir>');
  process.exit(1);
}

// fileId -> { name, language, languageCode, license, source }
const META = {
  bsb: {
    name: 'Berean Standard Bible',
    language: 'English',
    languageCode: 'en',
    license: 'Public Domain (CC0)',
    source: 'https://berean.bible',
  },
  web: {
    name: 'World English Bible',
    language: 'English',
    languageCode: 'en',
    license: 'Public Domain',
    source: 'https://ebible.org/WEB/',
  },
  kjv: {
    name: 'King James Version',
    language: 'English',
    languageCode: 'en',
    license: 'Public Domain',
    source: 'https://ebible.org/KJV/',
  },
  asv: {
    name: 'American Standard Version',
    language: 'English',
    languageCode: 'en',
    license: 'Public Domain',
    source: 'https://ebible.org/ASV/',
  },
  bbe: {
    name: 'Bible in Basic English',
    language: 'English',
    languageCode: 'en',
    license: 'Public Domain',
    source: 'https://ebible.org/BBE/',
  },
  taobvsi: {
    name: 'Tamil Old Version (பரிசுத்த வேதாகமம்)',
    language: 'Tamil',
    languageCode: 'tam',
    license: 'Public Domain (India)',
    source: 'https://github.com/berinaniesh/bible-tamil',
  },
  ylt: {
    name: "Young's Literal Translation",
    language: 'English',
    languageCode: 'en',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/ylt.json',
  },
  wb: {
    name: "Webster's Bible",
    language: 'English',
    languageCode: 'en',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/wb.json',
  },
  luther1545: {
    name: 'Lutherbibel (1545)',
    language: 'German',
    languageCode: 'de',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/luther1545.json',
  },
  elberfelder1905: {
    name: 'Elberfelder Bibel (1905)',
    language: 'German',
    languageCode: 'de',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/elberfelder1905.json',
  },
  elberfelder: {
    name: 'Elberfelder Bibel (1871)',
    language: 'German',
    languageCode: 'de',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/elberfelder.json',
  },
  sse: {
    name: 'Sagradas Escrituras (1569)',
    language: 'Spanish',
    languageCode: 'es',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/sse.json',
  },
  martin: {
    name: 'Bible Martin (1744)',
    language: 'French',
    languageCode: 'fr',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/martin.json',
  },
  riveduta: {
    name: 'Riveduta (1927)',
    language: 'Italian',
    languageCode: 'it',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/riveduta.json',
  },
  diodati: {
    name: 'Bibbia Diodati',
    language: 'Italian',
    languageCode: 'it',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/diodati.json',
  },
  statenvertaling: {
    name: 'Statenvertaling',
    language: 'Dutch',
    languageCode: 'nl',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/statenvertaling.json',
  },
  polgdanska: {
    name: 'Biblia Gdańska',
    language: 'Polish',
    languageCode: 'pl',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/polgdanska.json',
  },
  karoli: {
    name: 'Károlyi Biblia',
    language: 'Hungarian',
    languageCode: 'hu',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/karoli.json',
  },
  swedish: {
    name: 'Svenska Bibeln (1917)',
    language: 'Swedish',
    languageCode: 'sv',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/swedish.json',
  },
  danish: {
    name: 'Dansk Bibel',
    language: 'Danish',
    languageCode: 'da',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/danish.json',
  },
  pyharaamattu1933: {
    name: 'Pyhä Raamattu (1933/1938)',
    language: 'Finnish',
    languageCode: 'fi',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/pyharaamattu1933.json',
  },
  bkr: {
    name: 'Bible kralická',
    language: 'Czech',
    languageCode: 'cs',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/bkr.json',
  },
  croatia: {
    name: 'Biblija (Croatian)',
    language: 'Croatian',
    languageCode: 'hr',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/croatia.json',
  },
  alb: {
    name: 'Bibla Shqipe',
    language: 'Albanian',
    languageCode: 'sq',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/alb.json',
  },
  korean: {
    name: 'Korean Bible',
    language: 'Korean',
    languageCode: 'ko',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/korean.json',
  },
  vietnamese: {
    name: 'Kinh Thánh (1934)',
    language: 'Vietnamese',
    languageCode: 'vi',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/vietnamese.json',
  },
  tagalog: {
    name: 'Ang Dating Biblia (1905)',
    language: 'Tagalog',
    languageCode: 'tl',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/tagalog.json',
  },
  esperanto: {
    name: 'Esperanta Biblio',
    language: 'Esperanto',
    languageCode: 'eo',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/esperanto.json',
  },
  cut: {
    name: 'Union Version (Traditional)',
    language: 'Chinese',
    languageCode: 'zh-Hant',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/cut.json',
  },
  japkougo: {
    name: '口語訳聖書 (1954/1955)',
    language: 'Japanese',
    languageCode: 'ja',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/japkougo.json',
  },
  mal1910: {
    name: 'Sathyavedapusthakam (1910)',
    language: 'Malayalam',
    languageCode: 'ml',
    license: 'Public Domain',
    source: 'https://api.getbible.net/v2/mal1910.json',
  },
  mal_irv: {
    name: 'Malayalam IRV',
    language: 'Malayalam',
    languageCode: 'mal',
    license: 'CC BY-SA 4.0 (2017, Bridge Connectivity Solutions)',
    source: 'https://ebible.org/mal/',
  },
  kan_irv: {
    name: 'Kannada IRV',
    language: 'Kannada',
    languageCode: 'kan',
    license: 'CC BY-SA 4.0 (2017, Bridge Connectivity Solutions)',
    source: 'https://ebible.org/kanirv/',
  },
  tel_irv: {
    name: 'Telugu IRV',
    language: 'Telugu',
    languageCode: 'tel',
    license: 'CC BY-SA 4.0 (2019, Bridge Connectivity Solutions)',
    source: 'https://ebible.org/tel2017/',
  },
  hin_irv: {
    name: 'Hindi IRV',
    language: 'Hindi',
    languageCode: 'hin',
    license: 'CC BY-SA 4.0 (2017, Bridge Connectivity Solutions)',
    source: 'https://ebible.org/hin2017/',
  },
};

function countVerses(pathStr) {
  const s = fs.readFileSync(pathStr, 'utf8');
  const parsed = JSON.parse(s);
  const books = Array.isArray(parsed) ? parsed : parsed.books;
  return books.reduce((sum, b) => sum + b.ch.reduce((s2, c) => s2 + c.length, 0), 0);
}

function findSource(fileId) {
  const p = path.join(BIBLES, `bible_${fileId}.json`);
  if (fs.existsSync(p)) return p;
  throw new Error(`No source for bible_${fileId}.json`);
}

const biblesDir = path.join(staging, 'bibles');
fs.mkdirSync(biblesDir, { recursive: true });

const indexBibles = [];
for (const [fileId, meta] of Object.entries(META)) {
  const src = findSource(fileId);
  const destName = `bible_${fileId}.json`;
  fs.copyFileSync(src, path.join(biblesDir, destName));
  const sizeBytes = fs.statSync(src).size;
  indexBibles.push({
    id: fileId,
    file: `bibles/${destName}`,
    ...meta,
    verseCount: countVerses(src),
    sizeBytes,
  });
}

fs.copyFileSync(SCRIPTURES, path.join(staging, 'scriptures.json'));
const scripturesRows = JSON.parse(fs.readFileSync(SCRIPTURES, 'utf8'));

const index = {
  updatedAt: new Date().toISOString(),
  scriptures: {
    file: 'scriptures.json',
    rows: scripturesRows.length,
    sizeBytes: fs.statSync(SCRIPTURES).size,
  },
  bibles: indexBibles,
};

fs.writeFileSync(path.join(staging, 'index.json'), JSON.stringify(index, null, 2));
console.log(`Staged into ${staging}`);
console.log(`  scriptures.json (${scripturesRows.length} rows)`);
for (const b of indexBibles) {
  console.log(`  ${b.file} (${b.verseCount} verses, ${b.sizeBytes} bytes)`);
}