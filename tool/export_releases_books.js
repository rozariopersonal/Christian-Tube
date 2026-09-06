const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

const BASE_DIR = path.join(__dirname, '..');
const DB_PATH = path.join(BASE_DIR, 'data', 'books.sqlite');
const RELEASES_BOOKS_DIR = path.join(BASE_DIR, 'releases', 'books');
const PUBLISHED_DIR = path.join(BASE_DIR, 'data', 'books_published');

function ensureDir(dirPath) {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
}

function writeJson(filePath, data) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf8');
}

function run() {
  if (!fs.existsSync(DB_PATH)) {
    console.error(`Database not found at ${DB_PATH}`);
    process.exit(1);
  }

  const db = new DatabaseSync(DB_PATH);

  // 1. Get all books
  const books = db.prepare(`
    SELECT id, title, author, subject, categories, description, cover_file, 
           total_pages, total_lines, created_at 
    FROM books 
    ORDER BY title ASC
  `).all();

  console.log(`Exporting ${books.length} books to ${RELEASES_BOOKS_DIR}...`);

  for (const b of books) {
    const chapters = db.prepare(`
      SELECT chapter_index, chapter_title, start_line, end_line, start_page, end_page, subtitles 
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
      chapters: chapters.map(c => {
        let subs = [];
        try {
          subs = JSON.parse(c.subtitles || '[]');
        } catch (_) {}
        return {
          chapterIndex: c.chapter_index,
          title: c.chapter_title,
          startLine: c.start_line,
          endLine: c.end_line,
          startPage: c.start_page,
          endPage: c.end_page,
          subtitles: subs,
        };
      }),
    };

    // Write toc.json
    writeJson(path.join(RELEASES_BOOKS_DIR, b.id, 'toc.json'), toc);

    // Write chapter chunks
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

      writeJson(path.join(RELEASES_BOOKS_DIR, b.id, 'chapters', `${c.chapter_index}.json`), chunk);
    }
  }

  // Copy books.sqlite.gz to releases
  const gzSrc = path.join(BASE_DIR, 'data', 'books.sqlite.gz');
  if (fs.existsSync(gzSrc)) {
    fs.copyFileSync(gzSrc, path.join(RELEASES_BOOKS_DIR, 'books.sqlite.gz'));
    const enDir = path.join(RELEASES_BOOKS_DIR, 'en');
    ensureDir(enDir);
    fs.copyFileSync(gzSrc, path.join(enDir, 'books.sqlite.gz'));
    console.log('✓ Copied books.sqlite.gz to releases/books and releases/books/en');
  }

  // Copy published packages
  if (fs.existsSync(PUBLISHED_DIR)) {
    const publishedDest = path.join(RELEASES_BOOKS_DIR, 'published');
    const enPublishedDest = path.join(RELEASES_BOOKS_DIR, 'en', 'published');
    ensureDir(publishedDest);
    ensureDir(enPublishedDest);

    const pubFiles = fs.readdirSync(PUBLISHED_DIR).filter(f => f.endsWith('.sqlite.gz'));
    for (const f of pubFiles) {
      fs.copyFileSync(path.join(PUBLISHED_DIR, f), path.join(publishedDest, f));
      fs.copyFileSync(path.join(PUBLISHED_DIR, f), path.join(enPublishedDest, f));
    }
    console.log(`✓ Copied ${pubFiles.length} published packages to releases`);
  }

  // Update releases/books/catalog.json and apps/mobile/assets/books/catalog.json
  const rawCatalogPath = path.join(BASE_DIR, 'data', 'books_raw', 'catalog.json');
  if (fs.existsSync(rawCatalogPath)) {
    const rawCatalog = JSON.parse(fs.readFileSync(rawCatalogPath, 'utf8'));
    
    // In releases/books/catalog.json, update the 38 English books
    const relCatalogPath = path.join(RELEASES_BOOKS_DIR, 'catalog.json');
    if (fs.existsSync(relCatalogPath)) {
      const relCatalog = JSON.parse(fs.readFileSync(relCatalogPath, 'utf8'));
      const enMap = new Map(rawCatalog.map(b => [b.id, b]));
      
      const updatedRelCatalog = relCatalog.map(item => {
        if (enMap.has(item.id)) {
          const fresh = enMap.get(item.id);
          return {
            ...item,
            title: fresh.title,
            author: fresh.author,
            subject: fresh.subject,
            totalPages: fresh.totalPages,
            totalLines: fresh.totalLines,
          };
        }
        return item;
      });

      fs.writeFileSync(relCatalogPath, JSON.stringify(updatedRelCatalog, null, 2), 'utf8');
      console.log('✓ Updated releases/books/catalog.json');
    }

    // In apps/mobile/assets/books/catalog.json, update English books
    const appCatalogPath = path.join(BASE_DIR, 'apps', 'mobile', 'assets', 'books', 'catalog.json');
    if (fs.existsSync(appCatalogPath)) {
      const appCatalog = JSON.parse(fs.readFileSync(appCatalogPath, 'utf8'));
      const enMap = new Map(rawCatalog.map(b => [b.id, b]));
      
      const updatedAppCatalog = appCatalog.map(item => {
        if (enMap.has(item.id)) {
          const fresh = enMap.get(item.id);
          return {
            ...item,
            title: fresh.title,
            author: fresh.author,
            subject: fresh.subject,
            totalPages: fresh.totalPages,
            totalLines: fresh.totalLines,
          };
        }
        return item;
      });

      fs.writeFileSync(appCatalogPath, JSON.stringify(updatedAppCatalog, null, 2), 'utf8');
      console.log('✓ Updated apps/mobile/assets/books/catalog.json');
    }
  }

  console.log('\n========================================');
  console.log('✓ Export to releases completed successfully!');
  console.log('========================================\n');
}

run();
