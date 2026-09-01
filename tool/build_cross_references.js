#!/usr/bin/env node
/**
 * build_cross_references.js
 *
 * Fetches the HelloAO `open-cross-ref` dataset (OpenBible.info cross
 * references, CC-BY 4.0) book by book / chapter by chapter and consolidates it
 * into the single cross_references.json that the Flutter app downloads from
 * the releases repo (`data/cross_references.json`).
 *
 * Output format (compact, matched by CrossReferenceService/_parseReferences):
 *   {
 *     "sha256": "<sha256 of canonical references payload>",
 *     "references": {
 *       "GEN": {
 *         "1": [ { "v": 1, "refs": [
 *             { "bt":"JHN", "c":1, "v":1, "e":3, "s":349 }, ...
 *         ]}, ... ],
 *         ...
 *       },
 *       ...
 *     }
 *   }
 *
 * Usage:
 *   node tool/build_cross_references.js [output.json]
 *   (default output: data/cross_references.json in the repo root)
 *
 * The integrity `sha256` is the hash of the canonical JSON of the `references`
 * object, encoded identically to Dart's `jsonEncode` (compact, insertion
 * order) so the app can verify downloads.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const API_BASE = 'https://bible.helloao.org/api/d/open-cross-ref';
const BOOKS_URL = `${API_BASE}/books.json`;
const DEFAULT_OUT = path.join(__dirname, '..', 'data', 'cross_references.json');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function getJson(url, attempts = 3) {
  for (let i = 1; i <= attempts; i++) {
    try {
      const res = await fetch(url);
      if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
      return await res.json();
    } catch (e) {
      if (i === attempts) throw e;
      await sleep(1000 * i);
    }
  }
}

async function main() {
  const outPath = process.argv[2] || DEFAULT_OUT;

  process.stdout.write('Fetching book list...\n');
  const books = await getJson(BOOKS_URL);
  // books.json -> { "books": [ { "id": "GEN", "order": 1, ... }, ... ] }
  const bookList = (books.books || books).slice();

  const references = {};
  let totalRefs = 0;
  let totalVerses = 0;
  let chapters = 0;

  for (const book of bookList) {
    const id = book.id;
    const chaptersInBook = book.numberOfChapters;
    const bookMap = {};
    process.stdout.write(`Fetching ${id} (${chaptersInBook} chapters)...\n`);

    for (let ch = 1; ch <= chaptersInBook; ch++) {
      const data = await getJson(`${API_BASE}/${id}/${ch}.json`);
      const content = data.chapter.content || [];
      const verseEntries = [];
      for (const entry of content) {
        const refs = (entry.references || []).map((r) => ({
          bt: r.book,
          c: r.chapter,
          v: r.verse,
          ...(r.endVerse != null ? { e: r.endVerse } : {}),
          s: r.score,
        }));
        if (refs.length) {
          verseEntries.push({ v: entry.verse, refs });
          totalVerses++;
          totalRefs += refs.length;
        }
      }
      bookMap[String(ch)] = verseEntries;
      chapters++;
      await sleep(120); // be gentle with the public API
    }

    references[id] = bookMap;
  }

  const canonical = JSON.stringify(references);
  const sha256 = crypto.createHash('sha256').update(canonical, 'utf8').digest('hex');

  const output = {
    sha256,
    references,
  };

  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(output));

  const sizeMb = (fs.statSync(outPath).size / (1024 * 1024)).toFixed(2);
  process.stdout.write(
    `\nDone.\n  books:     ${bookList.length}\n` +
      `  chapters:  ${chapters}\n  verses w/ refs: ${totalVerses}\n` +
      `  references: ${totalRefs}\n  Sha256:    ${sha256}\n` +
      `  output:    ${outPath} (${sizeMb} MB)\n`,
  );
}

main().catch((e) => {
  console.error('build_cross_references failed:', e);
  process.exit(1);
});
