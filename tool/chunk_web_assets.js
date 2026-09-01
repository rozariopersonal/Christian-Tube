const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

const BASE_DIR = path.join(__dirname, '..');
const REPO_DIR = path.join(
  process.env.USERPROFILE || 'C:\\Users\\Arul Rozario',
  '.gemini\\antigravity-ide\\brain\\cb507cb7-2230-4248-aea5-7c55031079fc\\scratch\\releases_repo'
);

function ensureDir(dirPath) {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
}

function writeJson(filePath, data) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, JSON.stringify(data));
}

// -------------------------------------------------------------
// 1. CHUNK BIBLES
// -------------------------------------------------------------
function chunkBibles() {
  console.log('\n--- 1. Chunking Bibles ---');
  const biblesSrcDir = path.join(REPO_DIR, 'bibles');
  if (!fs.existsSync(biblesSrcDir)) {
    console.warn(`Bibles directory not found at ${biblesSrcDir}`);
    return;
  }

  const files = fs.readdirSync(biblesSrcDir).filter(f => f.startsWith('bible_') && f.endsWith('.json'));
  console.log(`Found ${files.length} bible files to chunk.`);

  for (const file of files) {
    const versionId = file.replace('bible_', '').replace('.json', '').toLowerCase();
    const filePath = path.join(biblesSrcDir, file);
    console.log(`Processing Bible [${versionId}] from ${file}...`);

    try {
      const raw = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      const books = raw.books || [];
      const booksMeta = [];

      for (const book of books) {
        const bookNum = book.b;
        const bookName = book.n;
        const chapters = book.ch || [];

        booksMeta.push({
          bookNumber: bookNum,
          name: bookName,
          chapters: chapters.length,
        });

        for (let cIdx = 0; cIdx < chapters.length; cIdx++) {
          const chapterNum = cIdx + 1;
          const rawVerses = chapters[cIdx] || [];
          const verses = rawVerses.map((text, vIdx) => ({
            verse: vIdx + 1,
            text: typeof text === 'string' ? text.trim() : String(text || ''),
          }));

          const outPath = path.join(REPO_DIR, 'bibles', versionId, String(bookNum), `${chapterNum}.json`);
          writeJson(outPath, verses);
        }
      }

      const metaPath = path.join(REPO_DIR, 'bibles', versionId, 'books.json');
      writeJson(metaPath, booksMeta);
      console.log(`  ✓ Version [${versionId}]: ${books.length} books chunked.`);
    } catch (e) {
      console.error(`  ✗ Error chunking [${versionId}]:`, e.message);
    }
  }
}

// -------------------------------------------------------------
// 2. CHUNK BOOKS & COMMENTARIES (from books.sqlite)
// -------------------------------------------------------------
function chunkBooksAndCommentaries() {
  console.log('\n--- 2. Chunking Books & Commentaries ---');
  const dbPath = path.join(BASE_DIR, 'data', 'books.sqlite');
  if (!fs.existsSync(dbPath)) {
    console.warn(`books.sqlite not found at ${dbPath}`);
    return;
  }

  const db = new DatabaseSync(dbPath);

  // A. Books catalog & chapters
  const books = db.prepare(`
    SELECT id, title, author, subject, categories, description, cover_file, 
           total_pages, total_lines, created_at 
    FROM books 
    ORDER BY title ASC
  `).all();

  console.log(`Found ${books.length} books.`);
  const catalogList = books.map(b => ({
    id: b.id,
    title: b.title,
    author: b.author,
    subject: b.subject,
    categories: JSON.parse(b.categories || '[]'),
    description: b.description,
    coverFile: b.cover_file,
    totalPages: b.total_pages,
    totalLines: b.total_lines,
  }));

  writeJson(path.join(REPO_DIR, 'books', 'catalog.json'), catalogList);

  for (const b of books) {
    const chapters = db.prepare(`
      SELECT chapter_index, chapter_title, start_line, end_line, start_page, end_page 
      FROM book_chapters 
      WHERE book_id = ? 
      ORDER BY chapter_index ASC
    `).all(b.id);

    const toc = {
      id: b.id,
      title: b.title,
      author: b.author,
      subject: b.subject,
      totalPages: b.total_pages,
      totalLines: b.total_lines,
      chapters: chapters.map(c => ({
        chapterIndex: c.chapter_index,
        title: c.chapter_title,
        startLine: c.start_line,
        endLine: c.end_line,
        startPage: c.start_page,
        endPage: c.end_page,
      })),
    };
    writeJson(path.join(REPO_DIR, 'books', b.id, 'toc.json'), toc);

    for (const c of chapters) {
      const lines = db.prepare(`
        SELECT line_number, page_number, text, content_type 
        FROM book_content 
        WHERE book_id = ? AND chapter_index = ? 
        ORDER BY line_number ASC
      `).all(b.id, c.chapter_index);

      const chunk = lines.map(l => {
        const isHeading = l.content_type === 'chapter_header' || l.content_type === 'h2' || l.content_type === 'h3';
        let headingLevel = 0;
        if (l.content_type === 'chapter_header') headingLevel = 1;
        else if (l.content_type === 'h2') headingLevel = 2;
        else if (l.content_type === 'h3') headingLevel = 3;

        return {
          line: l.line_number,
          page: l.page_number,
          text: l.text,
          contentType: l.content_type,
          isHeading,
          headingLevel,
        };
      });

      writeJson(path.join(REPO_DIR, 'books', b.id, 'chapters', `${c.chapter_index}.json`), chunk);
    }
  }
  console.log(`  ✓ Exported catalog and chapter chunks for ${books.length} books.`);

  // B. Verse Commentaries
  console.log('\n--- 2B. Chunking Verse Commentaries ---');
  const links = db.prepare(`
    SELECT l.book_number, l.chapter, l.verse, l.end_verse, l.book_id, l.page_number,
           l.start_line, l.end_line, l.headline, b.title as book_title, 
           c.chapter_index, c.chapter_title 
    FROM book_scripture_links l 
    JOIN books b ON l.book_id = b.id 
    LEFT JOIN book_chapters c ON l.book_id = c.book_id AND l.page_number >= c.start_page AND l.page_number <= c.end_page
    ORDER BY l.book_number ASC, l.chapter ASC, l.verse ASC
  `).all();

  console.log(`Total commentary scripture links: ${links.length}`);
  const commMap = new Map(); // key: "b_c" -> Map(verse -> array of links)

  for (const l of links) {
    const key = `${l.book_number}_${l.chapter}`;
    if (!commMap.has(key)) {
      commMap.set(key, new Map());
    }
    const chMap = commMap.get(key);
    const vStr = String(l.verse);
    if (!chMap.has(vStr)) {
      chMap.set(vStr, []);
    }
    chMap.get(vStr).push({
      bookId: l.book_id,
      bookTitle: l.book_title,
      chapterIndex: l.chapter_index || 1,
      chapterTitle: l.chapter_title || '',
      pageNumber: l.page_number,
      startLine: l.start_line,
      endLine: l.end_line,
      headline: l.headline || '',
      endVerse: l.end_verse,
    });
  }

  let commChaptersWritten = 0;
  for (const [key, chMap] of commMap.entries()) {
    const [bStr, cStr] = key.split('_');
    const outObj = {};
    for (const [v, arr] of chMap.entries()) {
      outObj[v] = arr;
    }
    writeJson(path.join(REPO_DIR, 'commentaries', bStr, `${cStr}.json`), outObj);
    commChaptersWritten++;
  }
  console.log(`  ✓ Wrote ${commChaptersWritten} commentary chapter JSON files.`);
}

// -------------------------------------------------------------
// 3. CHUNK DICTIONARIES
// -------------------------------------------------------------
function chunkDictionaries() {
  console.log('\n--- 3. Chunking Dictionaries ---');
  const dictDir = path.join(BASE_DIR, 'data', 'dictionaries_published');
  if (!fs.existsSync(dictDir)) {
    console.warn(`Dictionaries directory not found at ${dictDir}`);
    return;
  }

  const files = fs.readdirSync(dictDir).filter(f => f.startsWith('dict_') && f.endsWith('.sqlite'));
  console.log(`Found ${files.length} dictionary databases to shard.`);

  for (const file of files) {
    const dictId = file.replace('dict_', '').replace('.sqlite', '');
    const dbPath = path.join(dictDir, file);
    console.log(`Sharding dictionary [${dictId}]...`);

    try {
      const db = new DatabaseSync(dbPath);
      const rows = db.prepare('SELECT headword, part_of_speech, phonetic, definition, examples FROM dictionary_entries').all();
      console.log(`  [${dictId}] has ${rows.length} entries.`);

      const shards = new Map();

      for (const row of rows) {
        const hw = (row.headword || '').trim();
        if (!hw) continue;

        // Prefix logic: first 2 chars lowercase for latin, or first char for non-latin
        let prefix = '';
        const clean = hw.toLowerCase();
        if (/^[a-z0-9]/.test(clean)) {
          prefix = clean.slice(0, 2);
        } else {
          // Indian / Non-Latin scripts
          prefix = clean.slice(0, 1);
        }
        if (!prefix) prefix = '_';

        if (!shards.has(prefix)) {
          shards.set(prefix, []);
        }
        shards.get(prefix).push({
          headword: row.headword,
          partOfSpeech: row.part_of_speech || '',
          phonetic: row.phonetic || '',
          definition: row.definition,
          examples: row.examples || '',
        });
      }

      const prefixes = Array.from(shards.keys()).sort();
      for (const p of prefixes) {
        // Encode prefix safely for file path
        const safeP = encodeURIComponent(p);
        writeJson(path.join(REPO_DIR, 'dictionaries', dictId, `${safeP}.json`), shards.get(p));
      }

      writeJson(path.join(REPO_DIR, 'dictionaries', dictId, 'index.json'), {
        dictId,
        totalEntries: rows.length,
        prefixes,
      });

      console.log(`  ✓ [${dictId}]: Sharded into ${prefixes.length} prefix files.`);
    } catch (e) {
      console.error(`  ✗ Error sharding [${dictId}]:`, e.message);
    }
  }
}

// -------------------------------------------------------------
// 4. CHUNK CROSS-REFERENCES (from data/cross_references.json)
// -------------------------------------------------------------
function chunkCrossReferences() {
  console.log('\n--- 4. Chunking Cross-References ---');
  const filePath = path.join(BASE_DIR, 'data', 'cross_references.json');
  if (!fs.existsSync(filePath)) {
    console.warn(`cross_references.json not found at ${filePath}`);
    return;
  }

  try {
    const raw = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    const refs = raw.references || {};
    let chaptersCount = 0;

    for (const bStr of Object.keys(refs)) {
      const bookData = refs[bStr] || {};
      for (const cStr of Object.keys(bookData)) {
        const list = bookData[cStr] || [];
        const outPath = path.join(REPO_DIR, 'cross_references', bStr, `${cStr}.json`);
        writeJson(outPath, list);
        chaptersCount++;
      }
    }
    console.log(`  ✓ Sliced cross-references into ${chaptersCount} chapter files.`);
  } catch (e) {
    console.error(`  ✗ Error slicing cross-references:`, e.message);
  }
}

// -------------------------------------------------------------
// 5. CHUNK BIBLE BACKGROUNDS (from data/bible_backgrounds.json)
// -------------------------------------------------------------
function chunkBackgrounds() {
  console.log('\n--- 5. Chunking Bible Backgrounds ---');
  const filePath = path.join(BASE_DIR, 'data', 'bible_backgrounds.json');
  if (!fs.existsSync(filePath)) {
    console.warn(`bible_backgrounds.json not found at ${filePath}`);
    return;
  }

  try {
    const raw = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    const bg = raw.backgrounds || {};
    let count = 0;

    for (const bookCode of Object.keys(bg)) {
      const bookChapters = bg[bookCode] || {};
      for (const chStr of Object.keys(bookChapters)) {
        const item = bookChapters[chStr];
        const outPath = path.join(REPO_DIR, 'backgrounds', bookCode.toLowerCase(), `${chStr}.json`);
        writeJson(outPath, item);
        count++;
      }
    }
    console.log(`  ✓ Sliced backgrounds into ${count} chapter files.`);
  } catch (e) {
    console.error(`  ✗ Error slicing backgrounds:`, e.message);
  }
}

// -------------------------------------------------------------
// 6. CHUNK WORDS FEED (from scriptures.json)
// -------------------------------------------------------------
function chunkWordsFeed() {
  console.log('\n--- 6. Chunking Words Feed ---');
  const filePath = path.join(REPO_DIR, 'scriptures.json');
  if (!fs.existsSync(filePath)) {
    console.warn(`scriptures.json not found at ${filePath}`);
    return;
  }

  try {
    const raw = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    console.log(`Found ${raw.length} scripture devotionals.`);

    // Top 365 daily devotionals for fast calendar load
    const daily = raw.slice(0, 365).map((item, idx) => ({
      dayOfYear: idx + 1,
      bookNumber: item.bookNumber,
      bookName: item.bookName,
      chapter: item.chapter,
      startVerse: item.startVerse,
      endVerse: item.endVerse,
      referenceLabel: item.referenceLabel,
      category: item.category,
      backgroundPreset: item.backgroundPreset || 'ocean_calm',
    }));
    writeJson(path.join(REPO_DIR, 'words_feed', 'daily.json'), daily);

    // Group into letter shards and curated topics
    const letterMap = new Map();
    const topicMap = new Map();

    for (const item of raw) {
      const cat = (item.category || 'General').trim();
      let slug = cat.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '') || 'general';
      if (slug.length > 30) slug = slug.slice(0, 30).replace(/_+$/, '');

      const letter = (slug[0] || 'a').toLowerCase();
      if (!letterMap.has(letter)) {
        letterMap.set(letter, []);
      }

      const devotional = {
        bookNumber: item.bookNumber,
        bookName: item.bookName,
        chapter: item.chapter,
        startVerse: item.startVerse,
        endVerse: item.endVerse,
        referenceLabel: item.referenceLabel,
        category: item.category,
        backgroundPreset: item.backgroundPreset || 'ocean_calm',
      };

      letterMap.get(letter).push(devotional);

      if (!topicMap.has(slug)) {
        topicMap.set(slug, { name: cat, items: [] });
      }
      topicMap.get(slug).items.push(devotional);
    }

    // Write letter shards
    for (const [letter, items] of letterMap.entries()) {
      writeJson(path.join(REPO_DIR, 'words_feed', 'by_letter', `${letter}.json`), items);
    }

    // Export top 100 popular topics
    const sortedTopics = Array.from(topicMap.entries())
      .map(([slug, data]) => ({ slug, name: data.name, count: data.items.length, items: data.items }))
      .sort((a, b) => b.count - a.count);

    const topTopics = sortedTopics.slice(0, 100);
    for (const t of topTopics) {
      writeJson(path.join(REPO_DIR, 'words_feed', 'topics', `${t.slug}.json`), t.items);
    }

    writeJson(path.join(REPO_DIR, 'words_feed', 'manifest.json'), {
      totalItems: raw.length,
      letters: Array.from(letterMap.keys()).sort(),
      topTopics: topTopics.map(t => ({ slug: t.slug, name: t.name, count: t.count })),
    });

    console.log(`  ✓ Created daily.json (365), ${letterMap.size} letter shards, and top 100 topic files.`);
  } catch (e) {
    console.error(`  ✗ Error chunking words feed:`, e.message);
  }
}

// -------------------------------------------------------------
// 7. GENERATE GLOBAL INDEX MANIFEST
// -------------------------------------------------------------
function generateGlobalIndex() {
  console.log('\n--- 7. Generating Global index.json ---');
  const indexData = {
    repository: 'Christian-Tube-Releases',
    cdnBase: 'https://cdn.jsdelivr.net/gh/rozariopersonal/Christian-Tube-Releases@main',
    updatedAt: new Date().toISOString(),
    endpoints: {
      bibles: {
        booksMeta: '/bibles/{version}/books.json',
        chapter: '/bibles/{version}/{bookNumber}/{chapter}.json',
      },
      books: {
        catalog: '/books/catalog.json',
        toc: '/books/{bookId}/toc.json',
        chapter: '/books/{bookId}/chapters/{chapterIndex}.json',
      },
      commentaries: {
        chapter: '/commentaries/{bookNumber}/{chapter}.json',
      },
      dictionaries: {
        index: '/dictionaries/{dictId}/index.json',
        prefixShard: '/dictionaries/{dictId}/{prefix}.json',
      },
      crossReferences: {
        chapter: '/cross_references/{bookNumber}/{chapter}.json',
      },
      backgrounds: {
        chapter: '/backgrounds/{bookCode}/{chapter}.json',
      },
      wordsFeed: {
        manifest: '/words_feed/manifest.json',
        daily: '/words_feed/daily.json',
        topic: '/words_feed/topics/{topicSlug}.json',
      },
    },
  };

  writeJson(path.join(REPO_DIR, 'index.json'), indexData);
  console.log('  ✓ Generated root index.json manifest.');
}

function runAll() {
  const startTime = Date.now();
  console.log('====================================================');
  console.log('Starting Unified Asset Chunking for CDN & Web Access');
  console.log('====================================================');

  chunkBibles();
  chunkBooksAndCommentaries();
  // Dictionaries use live online APIs (FreeDictionaryAPI / Wiktionary) on web and SQLite when downloaded
  chunkCrossReferences();
  chunkBackgrounds();
  chunkWordsFeed();
  generateGlobalIndex();

  const durationSec = ((Date.now() - startTime) / 1000).toFixed(1);
  console.log('\n====================================================');
  console.log(`✓ All assets successfully chunked in ${durationSec}s!`);
  console.log(`Target directory: ${REPO_DIR}`);
  console.log('====================================================');
}

runAll();
