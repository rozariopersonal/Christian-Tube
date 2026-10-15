const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { DatabaseSync } = require('node:sqlite');

const BASE_DIR = path.join(__dirname, '..');
const RELEASES_DIR = path.join(BASE_DIR, 'releases');
const ARTICLES_DIR = path.join(RELEASES_DIR, 'articles');
const COMBINED_INDEX_PATH = path.join(ARTICLES_DIR, 'articles_index.json');
const RECENT_OUT_PATH = path.join(ARTICLES_DIR, 'recent.json');

function ensureDir(dirPath) {
  if (!fs.existsSync(dirPath)) fs.mkdirSync(dirPath, { recursive: true });
}

function buildRecentJson() {
  if (!fs.existsSync(COMBINED_INDEX_PATH)) {
    console.warn('articles_index.json not found; skipping recent.json');
    return;
  }
  const all = JSON.parse(fs.readFileSync(COMBINED_INDEX_PATH, 'utf8'));
  const recent = all.slice(0, 30);
  fs.writeFileSync(RECENT_OUT_PATH, JSON.stringify(recent), 'utf8');
  console.log(`✓ Wrote releases/articles/recent.json (${recent.length} entries, ${(fs.statSync(RECENT_OUT_PATH).size / 1024).toFixed(1)} KB)`);
}

function buildSqliteForLang(langCode, sourceDir, targetDir) {
  if (!fs.existsSync(sourceDir)) return;
  const files = fs.readdirSync(sourceDir).filter(f => f.endsWith('.json') && f !== 'index.json');
  if (files.length === 0) return;

  ensureDir(targetDir);
  const dbPath = path.join(targetDir, 'articles.sqlite');
  const gzPath = path.join(targetDir, 'articles.sqlite.gz');
  if (fs.existsSync(dbPath)) fs.unlinkSync(dbPath);

  const db = new DatabaseSync(dbPath);
  db.exec(`
    PRAGMA journal_mode = OFF;
    CREATE TABLE articles (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      date TEXT NOT NULL,
      author TEXT,
      body TEXT NOT NULL,
      lines_json TEXT
    );
    CREATE VIRTUAL TABLE articles_fts USING fts5(
      id UNINDEXED, title, body
    );
  `);

  const insertArticle = db.prepare(
    'INSERT INTO articles (id, title, date, author, body, lines_json) VALUES (?, ?, ?, ?, ?, ?)'
  );
  const insertFts = db.prepare(
    'INSERT INTO articles_fts (id, title, body) VALUES (?, ?, ?)'
  );

  db.exec('BEGIN');
  let count = 0;
  try {
    for (const f of files) {
      try {
        const raw = fs.readFileSync(path.join(sourceDir, f), 'utf8');
        const art = JSON.parse(raw);
        const id = art.id || f.replace('.json', '');
        const title = art.title || '';
        const date = art.date || '';
        const author = art.author || 'Zac Poonen';
        const lines = Array.isArray(art.lines) ? art.lines : [];
        const body = lines.map(l => (typeof l === 'string' ? l : (l.text || ''))).join('\n\n');
        const linesJson = JSON.stringify(lines);

        insertArticle.run(id, title, date, author, body, linesJson);
        insertFts.run(id, title, body);
        count++;
      } catch (e) {
        // skip corrupted
      }
    }
    db.exec('COMMIT');
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }

  db.exec('ANALYZE');
  db.close();

  const raw = fs.readFileSync(dbPath);
  const gz = zlib.gzipSync(raw, { level: 9 });
  fs.writeFileSync(gzPath, gz);

  function safeUnlink(p) {
    for (let i = 0; i < 5; i++) {
      try {
        if (fs.existsSync(p)) fs.unlinkSync(p);
        return;
      } catch (e) {
        if (i === 4) return;
        const start = Date.now();
        while (Date.now() - start < 100) {}
      }
    }
  }

  safeUnlink(dbPath);
  console.log(`✓ Wrote ${path.relative(RELEASES_DIR, gzPath)} (${(gz.length / 1024).toFixed(1)} KB gz from ${count} articles)`);
}

function main() {
  console.log('=== Building Articles Recent Preview & Per-Language SQLite Packages ===\n');

  buildRecentJson();

  // 1. English (source in articles/wftw/, emit into articles/en/ and articles/wftw/)
  console.log('\nProcessing English (en)...');
  const enSource = path.join(ARTICLES_DIR, 'wftw');
  buildSqliteForLang('en', enSource, path.join(ARTICLES_DIR, 'en'));

  // 2. All other languages in releases/articles/
  const entries = fs.readdirSync(ARTICLES_DIR, { withFileTypes: true });
  for (const ent of entries) {
    if (ent.isDirectory() && ent.name !== 'wftw' && ent.name !== 'en') {
      const code = ent.name;
      console.log(`Processing ${code}...`);
      const langDir = path.join(ARTICLES_DIR, code);
      buildSqliteForLang(code, langDir, langDir);
    }
  }

  console.log('\nAll article SQLite packages generated successfully!');
}

main();
