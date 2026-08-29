const https = require('https');
const fs = require('fs');
const path = require('path');

// getbible.net v2 (public domain bibles). Compact each into
// { "books": [ { "b": 1, "n": "Genesis", "ch": [ [verseText, ...], ... ] } ] }
const TARGETS = {
  web: { id: 'web', targets: ['mobile', 'backend'] },
  kjv: { id: 'kjv', targets: ['mobile', 'backend'] },
  asv: { id: 'asv', targets: ['backend'] },
  bbe: { id: 'basicenglish', targets: ['backend'] },
};

const ROOT = path.join(__dirname, '..', '..', '..');

function fetch(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, (res) => {
        if (res.statusCode !== 200) {
          res.resume();
          reject(new Error(`${url} -> ${res.statusCode}`));
          return;
        }
        let data = '';
        res.setEncoding('utf8');
        res.on('data', (c) => (data += c));
        res.on('end', () => resolve(data));
      })
      .on('error', reject);
  });
}

function convert(raw) {
  const parsed = JSON.parse(raw);
  const books = parsed.books.map((b) => ({
    b: b.nr,
    n: b.name,
    ch: b.chapters.map((c) => c.verses.map((v) => v.text)),
  }));
  return JSON.stringify({ books });
}

(async () => {
  for (const [fileId, { id, targets }] of Object.entries(TARGETS)) {
    console.log(`Fetching ${id}...`);
    const raw = await fetch(`https://api.getbible.net/v2/${id}.json`);
    const out = convert(raw);
    for (const target of targets) {
      const dir =
        target === 'mobile'
          ? path.join(ROOT, 'apps', 'mobile', 'assets', 'data')
          : path.join(ROOT, 'apps', 'backend', 'data', 'bibles');
      fs.mkdirSync(dir, { recursive: true });
      const file = path.join(dir, `bible_${fileId}.json`);
      fs.writeFileSync(file, out);
      console.log(`  wrote ${file} (${out.length} bytes)`);
    }
  }
  console.log('done');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});