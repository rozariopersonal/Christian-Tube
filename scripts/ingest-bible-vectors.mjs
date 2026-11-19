#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return;
  const lines = fs.readFileSync(filePath, 'utf8').split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    const val = trimmed.slice(eq + 1).trim();
    if (!process.env[key]) {
      process.env[key] = val;
    }
  }
}

function parseArgs(argv) {
  const opts = {
    file: 'releases/bibles/bible_web.json',
    batch: 100,
    maxVerses: 4900,
    namespace: '',
    namespaceExplicit: false,
    maxVersesExplicit: false,
    mode: 'verses',
    windowSize: 5,
    stride: 3,
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--file' && argv[i + 1]) opts.file = argv[++i];
    else if (a === '--batch' && argv[i + 1]) opts.batch = Math.max(1, Math.min(500, parseInt(argv[++i], 10)));
    else if (a === '--max-verses' && argv[i + 1]) {
      opts.maxVerses = Math.max(1, parseInt(argv[++i], 10));
      opts.maxVersesExplicit = true;
    } else if (a === '--namespace' && argv[i + 1]) {
      opts.namespace = argv[++i];
      opts.namespaceExplicit = true;
    } else if (a === '--mode' && argv[i + 1]) {
      const m = argv[++i];
      if (m === 'verses' || m === 'windows') opts.mode = m;
      else throw new Error(`Invalid --mode "${m}". Expected "verses" or "windows".`);
    } else if (a === '--window-size' && argv[i + 1]) {
      opts.windowSize = Math.max(2, parseInt(argv[++i], 10));
    } else if (a === '--stride' && argv[i + 1]) {
      opts.stride = Math.max(1, parseInt(argv[++i], 10));
    }
  }
  if (opts.mode === 'windows') {
    if (!opts.namespaceExplicit) opts.namespace = 'windows';
    if (!opts.maxVersesExplicit) opts.maxVerses = 15000;
  }
  return opts;
}

async function fetchExistingIds(restUrl, restToken, namespace) {
  const existing = new Set();
  let cursor = '0';
  const endpoint = namespace ? `${restUrl}/range/${encodeURIComponent(namespace)}` : `${restUrl}/range`;

  while (true) {
    const res = await fetch(endpoint, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${restToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        cursor,
        limit: 1000,
        includeVectors: false,
        includeMetadata: false,
      }),
    });
    if (!res.ok) {
      throw new Error(`Range query failed (${res.status}): ${await res.text()}`);
    }
    const data = await res.json();
    const result = data?.result || {};
    const vectors = Array.isArray(result.vectors) ? result.vectors : [];
    for (const v of vectors) {
      if (v?.id) existing.add(String(v.id));
    }
    const nextCursor = result.nextCursor;
    if (!nextCursor || nextCursor === '' || nextCursor === '0' || vectors.length === 0) {
      break;
    }
    cursor = String(nextCursor);
  }
  return existing;
}

function priorityScore(bookNumber) {
  if (bookNumber >= 40) return 0; // New Testament first
  if (bookNumber === 19 || bookNumber === 20) return 1; // Psalms & Proverbs next
  return 2; // Remaining Old Testament
}

async function main() {
  const opts = parseArgs(process.argv);
  loadEnvFile(path.resolve('apps/backend/.env'));
  loadEnvFile(path.resolve('envs/neon.env'));

  const restUrl = (process.env.UPSTASH_VECTOR_REST_URL || '').trim().replace(/\/+$/, '');
  const restToken = (process.env.UPSTASH_VECTOR_REST_TOKEN || '').trim();
  if (!restUrl || !restToken) {
    console.error('UPSTASH_VECTOR_REST_URL and UPSTASH_VECTOR_REST_TOKEN are required.');
    process.exit(1);
  }

  const biblePath = path.resolve(opts.file);
  const bible = JSON.parse(fs.readFileSync(biblePath, 'utf8'));
  const books = [...(bible.books || [])].sort(
    (a, b) => priorityScore(a.b) - priorityScore(b.b) || a.b - b.b,
  );

  console.log(`Scanning existing vectors in Upstash Vector (${restUrl})...`);
  const existing = await fetchExistingIds(restUrl, restToken, opts.namespace);
  console.log(`Found ${existing.size} existing verse vector(s).`);

  const items = [];
  for (const book of books) {
    const chapters = Array.isArray(book.ch) ? book.ch : [];
    for (let cIdx = 0; cIdx < chapters.length; cIdx++) {
      const verses = Array.isArray(chapters[cIdx]) ? chapters[cIdx] : [];
      const c = cIdx + 1;

      if (opts.mode === 'windows') {
        const clean = [];
        for (let vIdx = 0; vIdx < verses.length; vIdx++) {
          const text = String(verses[vIdx] || '').trim();
          if (text) clean.push({ v: vIdx + 1, text });
        }
        if (clean.length <= 1) continue;
        for (let start = 0; start < clean.length; start += opts.stride) {
          const slice = clean.slice(start, Math.min(start + opts.windowSize, clean.length));
          const startV = slice[0].v;
          const endV = slice[slice.length - 1].v;
          const id = `w:${book.b}:${c}:${startV}-${endV}`;
          if (!existing.has(id)) {
            const joined = slice.map((item) => `${item.v}. ${item.text}`).join(' ');
            items.push({
              id,
              data: `${book.n} ${c}:${startV}-${endV} — ${joined}`,
              metadata: {
                b: book.b,
                n: book.n,
                c,
                v: startV,
                endV,
                text: joined,
                kind: 'window',
              },
            });
          }
          if (start + opts.windowSize >= clean.length) break;
        }
        continue;
      }

      for (let vIdx = 0; vIdx < verses.length; vIdx++) {
        const text = String(verses[vIdx] || '').trim();
        if (!text) continue;
        const v = vIdx + 1;
        const id = `${book.b}:${c}:${v}`;
        if (existing.has(id)) continue;
        items.push({
          id,
          data: `${book.n} ${c}:${v} — ${text}`,
          metadata: {
            b: book.b,
            n: book.n,
            c,
            v,
            text,
          },
        });
      }
    }
  }

  const label = opts.mode === 'windows' ? 'windows' : 'verses';
  console.log(`Remaining ${label} to ingest (${opts.namespace || 'default'}): ${items.length}`);
  if (items.length === 0) {
    console.log(`All ${label} are already indexed!`);
    return;
  }

  const toUpload = items.slice(0, opts.maxVerses);
  const upsertEndpoint = opts.namespace
    ? `${restUrl}/upsert-data/${encodeURIComponent(opts.namespace)}`
    : `${restUrl}/upsert-data`;

  let uploaded = 0;
  for (let i = 0; i < toUpload.length; i += opts.batch) {
    const chunk = toUpload.slice(i, i + opts.batch);
    const res = await fetch(upsertEndpoint, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${restToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(chunk),
    });

    if (!res.ok) {
      const errText = await res.text().catch(() => '');
      console.error(`Stopped at ${uploaded} uploaded (${res.status}): ${errText}`);
      if (res.status === 429 || errText.toLowerCase().includes('limit')) {
        console.log('Daily quota reached; re-run tomorrow to resume automatically.');
        break;
      }
      process.exit(1);
    }

    uploaded += chunk.length;
    if (uploaded % 500 === 0 || i + opts.batch >= toUpload.length) {
      console.log(`Uploaded ${uploaded}/${toUpload.length} ${label} in this run (total indexed: ${existing.size + uploaded})`);
    }
  }

  const remaining = items.length - uploaded;
  console.log(`Done! Uploaded ${uploaded} ${label}. Remaining for future runs: ${remaining}.`);
}

main().catch((err) => {
  console.error('[Bible Vector Ingest Fatal]', err);
  process.exit(1);
});
