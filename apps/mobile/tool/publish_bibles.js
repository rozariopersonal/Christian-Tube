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