/**
 * tool/scrape_tamil_image_books.js — Tamil scanned-image book pipeline
 *
 * The 16 CFC Tamil books that exist only as scanned-page images (Kotobee EPUB
 * readers with no text layer) are converted to image-based books:
 *
 *   releases/books/ta/{bookId}/
 *     toc.json                 # chapters with page ranges
 *     chapters/{n}.json        # one img line per page
 *     pages/p{globalPage}.jpg  # page scans (also feed SQLite.gz packages)
 *
 * Discovery is per-book: the real EPUB folder name is read from the book page
 * (it can differ from the page slug, e.g. "god-centred-praying" ->
 * "god-centered-praying"; "new-wine-new-skin" -> "new-wine-in-new-wineskins").
 *
 * Usage:
 *   node tool/scrape_tamil_image_books.js                 # all 16 books
 *   node tool/scrape_tamil_image_books.js ta_secrets_of_victory   # one book
 */

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const { DatabaseSync } = require("node:sqlite");

const BASE = path.join(__dirname, "..");
const BOOKS_DIR = path.join(BASE, "releases", "books");
const APP_CAT = path.join(BASE, "apps", "mobile", "assets", "books", "catalog.json");
const CAT = path.join(BOOKS_DIR, "catalog.json");
const LANG = "ta";
const LANG_URL = "https://tamil.cfcindia.com/books";
const LANG_DIR = path.join(BOOKS_DIR, LANG);
const PUB_DIR = path.join(LANG_DIR, "published");
const COVERS_DIR = path.join(BOOKS_DIR, "covers");

const FRONT_MATTER = [
  "தலைப்பு", "பொருளடக்கம்", "அட்டவணை", "முகவுரை", "பதிப்பகத்தார்", "காப்புரிமை",
  "அட்டை", "நன்றியுரை", "குறிப்பு",
];
const FRONT_EN = ["cover", "copyright", "contents", "title", "foreword", "publisher", "start of content"];

const SKIP_PAGE_RE = /பக்கம்\s*\d+.*$/i; // "அத்தியாயம் 1 / பக்கம் 2"

// ── Helpers ────────────────────────────────────────────────────────────────

function clean(s) {
  if (!s) return "";
  return s
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .replace(/&rsquo;/g, "\u2019")
    .replace(/&lsquo;/g, "\u2018")
    .replace(/&rdquo;/g, "\u201d")
    .replace(/&ldquo;/g, "\u201c")
    .replace(/&mdash;/g, "\u2014")
    .replace(/&ndash;/g, "\u2013")
    .replace(/&#160;/g, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

async function get(url, bin = false, ms = 20000, tries = 3) {
  let lastErr;
  for (let t = 0; t < tries; t++) {
    try {
      const r = await fetch(url, { signal: AbortSignal.timeout(ms), headers: { "User-Agent": "Mozilla/5.0 ChristianTubeImagePipeline/1.0" } });
      if (!r.ok) throw new Error(`HTTP ${r.status} ${url}`);
      return bin ? Buffer.from(await r.arrayBuffer()) : r.text();
    } catch (e) {
      lastErr = e;
      if (t < tries - 1) await new Promise((r) => setTimeout(r, 800 * (t + 1)));
    }
  }
  throw lastErr;
}

function slug(t) {
  let s = t;
  try { s = decodeURIComponent(s); } catch (e) {}
  return s
    .toLowerCase()
    .replace(/[\u2018\u2019']/g, "") // apostrophes → ""  (god's-work → gods-work)
    .replace(/[^\w\s-]/g, "")
    .trim()
    .replace(/[\s_-]+/g, "_");
}

function isFrontMatter(title) {
  const lower = title.toLowerCase();
  if (FRONT_EN.some((w) => lower.includes(w))) return true;
  if (FRONT_MATTER.some((w) => title.includes(w))) return true;
  return false;
}

// ── SQLite (same schema as the text pipeline) ───────────────────────────────

const CREATE_SQL = `
CREATE TABLE books(id TEXT PRIMARY KEY,title TEXT NOT NULL,author TEXT NOT NULL,subject TEXT NOT NULL DEFAULT '',categories TEXT NOT NULL DEFAULT '[]',description TEXT,cover_file TEXT,total_pages INTEGER NOT NULL,total_lines INTEGER NOT NULL,created_at TEXT NOT NULL);
CREATE TABLE book_chapters(book_id TEXT NOT NULL,chapter_index INTEGER NOT NULL,chapter_title TEXT NOT NULL,start_page INTEGER NOT NULL,start_line INTEGER NOT NULL,end_page INTEGER NOT NULL,end_line INTEGER NOT NULL,PRIMARY KEY(book_id,chapter_index));
CREATE TABLE book_content(book_id TEXT NOT NULL,page_number INTEGER NOT NULL,line_number INTEGER NOT NULL,chapter_index INTEGER NOT NULL,content_type TEXT NOT NULL DEFAULT 'p',text TEXT NOT NULL,PRIMARY KEY(book_id,page_number,line_number));`;

function insertBook(db, meta, chRecs, content) {
  db.prepare("INSERT OR REPLACE INTO books VALUES(?,?,?,?,?,?,?,?,?,?)").run(
    meta.id, meta.title, meta.author, meta.subject, JSON.stringify(meta.categories), meta.description, meta.coverFile, meta.totalPages, meta.totalLines, new Date().toISOString()
  );
  const ic = db.prepare("INSERT OR REPLACE INTO book_chapters VALUES(?,?,?,?,?,?,?)");
  for (const c of chRecs) ic.run(meta.id, c.chapterIndex, c.title, c.startPage, c.startLine, c.endPage, c.endLine);
  const ir = db.prepare("INSERT OR REPLACE INTO book_content VALUES(?,?,?,?,?,?)");
  for (const r of content) ir.run(meta.id, r.pageNumber, r.lineNumber, r.chapterIndex, r.contentType, r.text);
}

function saveGz(dbPath) {
  const gz = zlib.gzipSync(fs.readFileSync(dbPath), { level: 9 });
  fs.writeFileSync(`${dbPath}.gz`, gz);
  fs.unlinkSync(dbPath);
  return gz;
}

function buildSingle(meta, chRecs, content) {
  fs.mkdirSync(PUB_DIR, { recursive: true });
  const p = path.join(PUB_DIR, `${meta.id}.sqlite`);
  if (fs.existsSync(p)) fs.unlinkSync(p);
  const db = new DatabaseSync(p);
  db.exec(CREATE_SQL);
  db.exec("BEGIN;");
  insertBook(db, meta, chRecs, content);
  db.exec("COMMIT;");
  db.close();
  return saveGz(p);
}

// ── EPUB parsing ────────────────────────────────────────────────────────────

function parseOpf(opf) {
  const title = clean((opf.match(/<dc:title[^>]*>([\s\S]*?)<\/dc:title>/i) || [])[1] || "");
  const author = clean((opf.match(/<dc:creator[^>]*>([\s\S]*?)<\/dc:creator>/i) || [])[1] || "") || "Zac Poonen";
  const desc = clean((opf.match(/<dc:description[^>]*>([\s\S]*?)<\/dc:description>/i) || [])[1] || "");

  const items = [...opf.matchAll(/<item\s+([^>]+)>/gi)].map((m) => {
    const attrs = {};
    for (const a of m[1].matchAll(/(\w+)=["']([^"']*)["']/g)) attrs[a[1]] = a[2];
    return attrs;
  });
  const manifest = new Map();
  for (const it of items) if (it.id && it.href) manifest.set(it.id, it.href);
  const spineIds = [...opf.matchAll(/<itemref\s+[^>]*idref=["']([^"']+)["']/gi)].map((m) => m[1]);

  // nav / ToC file
  let navHref = null;
  for (const it of items) {
    if (it.properties === "nav" || /contents\.xhtml$/i.test(it.href || "")) {
      navHref = it.href;
      break;
    }
  }
  for (const it of items) {
    if (/contents\.xhtml$/i.test(it.href || "") || it.id === "contents" || it.id === "toc") {
      navHref = it.href;
      break;
    }
  }

  return { title, author, desc, manifest, spineIds, navHref };
}

function resolve(base, href) {
  return new URL(href, base).toString();
}

// ── Main book build ─────────────────────────────────────────────────────────

function extOf(url) {
  const p = (url.split("?")[0] || "").toLowerCase();
  const m = p.match(/\.(jpe?g|png|webp|gif)$/);
  return m ? (m[1] === "jpeg" ? "jpg" : m[1]) : "jpg";
}

async function downloadPageImage(imageUrl, dest) {
  if (fs.existsSync(dest)) return true; // resumable
  const buf = await get(imageUrl, true);
  fs.writeFileSync(dest, buf);
  return true;
}

async function processBookPage(bPage, catalog) {
  const bookId = bPage.id;
  console.log(`\n${"=".repeat(62)}`);
  console.log(`ID:    ${bookId}`);
  console.log(`Title: ${bPage.title}`);

  const coverFile = `${bookId}.${extOf(bPage.coverUrl || "x.jpg")}`;
  const coverDest = path.join(COVERS_DIR, coverFile);
  if (bPage.coverUrl && !fs.existsSync(coverDest)) {
    // tamil.cfcindia.com mirrors some resources on www.cfcindia.org instead
    const sources = [bPage.coverUrl, bPage.coverUrl.replace("//tamil.cfcindia.com/", "//www.cfcindia.org/")];
    let saved = false;
    for (const src of [...new Set(sources)]) {
      try {
        const buf = await get(src, true);
        fs.writeFileSync(coverDest, buf);
        console.log(`  Cover: saved (${(buf.length / 1024).toFixed(1)} KB)`);
        saved = true;
        break;
      } catch (e) {
        console.warn(`  Cover failed: ${e.message}`);
      }
    }
    if (!saved) console.warn("  Cover: all sources failed");
  }

  // Discover the real EPUB reader URL from the book page
  let pageHtml = "";
  try {
    pageHtml = await get(bPage.pageUrl);
  } catch (e) {
    console.warn(`  Page fetch warning: ${e.message}`);
  }
  let kUrl = bPage.kotobeeUrl;
  if (!kUrl && pageHtml) {
    const km = pageHtml.match(/href=["'](https?:\/\/[^"']*\/epub\/[^"']+\/index\.html)["']/i);
    if (km) kUrl = km[1];
  }
  if (!kUrl) {
    console.warn("  No Kotobee reader URL found. Skipping.");
    return null;
  }
  const base = kUrl.replace(/\/index\.html.*$/i, "");
  console.log(`  Reader: ${base}`);

  const opfText = await get(`${base}/epub/EPUB/package.opf`);
  const { title, author, desc, manifest, spineIds, navHref } = parseOpf(opfText);
  console.log(`  OPF title: "${title}" author: "${author}"`);

  const spine = spineIds.map((id) => manifest.get(id)).filter(Boolean);
  console.log(`  Spine: ${spine.length} files`);

  if (!navHref) {
    console.warn("  No nav/contents.xhtml found. Skipping.");
    return null;
  }
  const navAbs = resolve(`${base}/epub/EPUB/`, navHref);
  const navHtml = await get(navAbs);
  const navLinks = [...navHtml.matchAll(/<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)]
    .map((m) => ({ href: m[1].replace(/#.*$/i, ""), title: clean(m[2].replace(/<[^>]+>/g, "")) }))
    .filter((l) => l.href && l.title);

  console.log(`  Nav links: ${navLinks.length}`);

  // Resolve nav hrefs to spine indices
  const spineResolved = spine.map((f) => resolve(`${base}/epub/EPUB/`, f));
  const toSpineIndex = new Map();
  for (let i = 0; i < spineResolved.length; i++) {
    toSpineIndex.set(normalize(spineResolved[i]), i);
    // relative-from-nav form: ../epubxx/OEBPS/x.xhtml -> x.xhtml holding OEBPS
  }

  function normalize(u) {
    let s = u.split("?")[0];
    try { s = new URL(s).pathname; } catch (e) {}
    return s;
  }

  const spineNorm = spineResolved.map(normalize);

  const contentChapters = [];
  for (const l of navLinks) {
    if (isFrontMatter(l.title)) continue;
    if (SKIP_PAGE_RE.test(l.title)) continue; // "அத்தியாயம் N / பக்கம் M"
    const norm = normalize(resolve(navAbs, l.href));
    const si = spineNorm.findIndex((s) => s === norm || s.endsWith(norm) || norm.endsWith(s));
    if (si === -1) {
      console.warn(`  ! nav "${l.title}" not in spine (${l.href})`);
      continue;
    }
    contentChapters.push({ title: l.title, si });
  }

  if (contentChapters.length === 0) {
    console.warn("  No content chapters found in nav. Skipping.");
    return null;
  }

  console.log(`  Content chapters: ${contentChapters.length}`);

  // Chapter ranges in spine order
  const ranges = [];
  for (let i = 0; i < contentChapters.length; i++) {
    const start = contentChapters[i].si;
    const end = i + 1 < contentChapters.length ? contentChapters[i + 1].si : spine.length;
    ranges.push({ title: contentChapters[i].title, startIdx: start, endIdx: end });
  }

  // Drop pages before the first chapter (front matter scans already skipped)
  // Page numbering: global sequential from 1.
  const bookDir = path.join(LANG_DIR, bookId);
  const pagesDir = path.join(bookDir, "pages");
  const chapDir = path.join(bookDir, "chapters");
  fs.mkdirSync(pagesDir, { recursive: true });
  fs.mkdirSync(chapDir, { recursive: true });

  const chRecs = [];
  const contentRecords = [];
  const imgRefs = []; // {pageNumber, url, dest}

  let globalPage = 1;
  let numBlank = 0;
  for (let ci = 0; ci < ranges.length; ci++) {
    const r = ranges[ci];
    const startPage = globalPage;
    const lines = [];
    for (let idx = r.startIdx; idx < r.endIdx; idx++) {
      const fileHref = spine[idx];
      const sf = resolve(`${base}/epub/EPUB/`, fileHref);
      const xhtmlPath = new URL(sf).pathname;
      let imgSrc = null;
      try {
        const xhtml = await get(new URL(xhtmlPath, `${base}/epub/EPUB/`).toString());
        const m = xhtml.match(/<img\b[^>]*\bsrc=["']([^"']+)["']/i);
        if (m) {
          const xdir = xhtmlPath.slice(0, xhtmlPath.lastIndexOf("/") + 1); // dir of the xhtml
          imgSrc = new URL(m[1], new URL(xdir, `${base}/epub/EPUB/`).toString()).toString();
        }
      } catch (e) {
        console.warn(`    ! page xhtml fetch failed: ${e.message}`);
      }
      if (!imgSrc) {
        // blank/spacer page (no scan image) — skip so no dangling file refs
        numBlank++;
        continue;
      }
      const pageNum = globalPage++;
      const ext = extOf(imgSrc);
      const fileName = `p${pageNum}.${ext}`;
      lines.push({ line: lines.length + 1, page: pageNum, text: fileName, contentType: "img" });
      imgRefs.push({ pageNumber: pageNum, url: imgSrc, dest: path.join(pagesDir, fileName) });
    }
    const chIdx = ci + 1;
    const endPage = globalPage - 1;
    fs.writeFileSync(
      path.join(chapDir, `${chIdx}.json`),
      JSON.stringify(lines.map((l) => ({
        line: l.line, page: l.page, text: l.text, contentType: "img",
        isHeading: false, headingLevel: 0,
      }))),
      "utf8"
    );
    for (const l of lines) {
      contentRecords.push({
        bookId, pageNumber: l.page, lineNumber: l.line, chapterIndex: chIdx,
        contentType: "img", text: l.text,
      });
    }
    chRecs.push({
      chapterIndex: chIdx, title: r.title, startPage, startLine: 1, endPage, endLine: lines.length,
    });
    console.log(`  ch${chIdx} "${r.title.slice(0, 42)}" pages ${startPage}-${endPage} (${lines.length}p)`);
  }

  const totalPages = globalPage - 1;
  const totalLines = contentRecords.length;
  if (numBlank) console.log(`  (skipped ${numBlank} blank pages with no scan image)`);
  console.log(`  Total: ${totalPages} pages, ${totalLines} img lines`);

  // Download page images (bounded concurrency 4)
  let ok = 0, failed = 0;
  const concurrency = 4;
  for (let i = 0; i < imgRefs.length; i += concurrency) {
    const batch = imgRefs.slice(i, i + concurrency);
    await Promise.all(batch.map(async (img) => {
      try {
        await downloadPageImage(img.url, img.dest);
        ok++;
      } catch (e) {
        failed++;
        console.warn(`  ! page ${img.pageNumber} download failed: ${e.message}`);
      }
    }));
  }
  console.log(`  Images: ${ok} ok, ${failed} failed`);

  const toc = {
    id: bookId,
    title: title || bPage.title,
    author: author,
    subject: "Christian Living",
    totalPages,
    totalLines,
    chapters: chRecs,
  };
  fs.writeFileSync(path.join(bookDir, "toc.json"), JSON.stringify(toc, null, 2), "utf8");

  const meta = {
    id: bookId,
    title: toc.title,
    author: toc.author,
    subject: "Christian Living",
    categories: ["Christian Living"],
    description: desc || bPage.description,
    coverFile,
    lang: LANG,
    totalPages,
    totalLines,
  };

  // Capture per-book gz size for the catalog AFTER images (sqlite references filenames only)
  const gz = buildSingle(meta, chRecs, contentRecords);

  // Compute image payload size for a "content size" hint
  let imgBytes = 0;
  for (const img of imgRefs) {
    try { imgBytes += fs.statSync(img.dest).size; } catch (e) {}
  }

  return {
    meta,
    chRecs,
    contentRecords,
    entry: {
      id: bookId,
      title: toc.title,
      author: toc.author,
      subject: "Christian Living",
      categories: ["Christian Living"],
      description: meta.description,
      coverFile,
      totalPages,
      totalLines,
      downloadSizeFormatted: `${(gz.length / 1024).toFixed(1)} KB`,
      createdAt: new Date().toISOString(),
      lang: LANG,
    },
  };
}

// ── Discovery from tamil.cfcindia.com/books ─────────────────────────────────

async function listTamilBooks() {
  const html = await get(LANG_URL, false, 30000);
  const items = html.split(/class=["'][^"']*single-book-item[^"']*["']/);
  const books = [];
  for (let i = 1; i < items.length; i++) {
    const chunk = items[i];
    const aM = chunk.match(/<h6 class=["']book-title["']>\s*<a\s+([^>]+)>([\s\S]*?)<\/a>/i);
    if (!aM) continue;
    const hM = aM[1].match(/href=["']([^"']+)["']/i);
    if (!hM) continue;
    let pageUrl = hM[1].trim();
    if (!pageUrl.startsWith("http")) pageUrl = `https://tamil.cfcindia.com${pageUrl}`;
    const rawTitle = clean(aM[2]) || "Untitled";
    const imgM = chunk.match(/<figure class=["']book-thumbnail["']>\s*<img\s+[^>]*src=["']([^"']+)["']/i);
    let coverUrl = imgM ? imgM[1].trim() : "";
    if (coverUrl && !coverUrl.startsWith("http")) coverUrl = `https://tamil.cfcindia.com${coverUrl}`;
    const descM = chunk.match(/property=["']schema:summary["']>([\s\S]*?)<\/div>/);
    const kM = chunk.match(/href=["'](https?:\/\/[^"']*\/epub\/[^"']+\/index\.html)["']/i);
    const urlSlug = pageUrl.split("/").filter(Boolean).pop().replace(/-\d+$/, "");
    books.push({
      id: `${LANG}_${slug(urlSlug)}`,
      title: rawTitle,
      author: "Zac Poonen",
      description: descM ? clean(descM[1]) : "",
      pageUrl,
      coverUrl,
      kotobeeUrl: kM ? kM[1] : null,
    });
  }
  return books;
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2);
  const targetId = args.find((a) => !a.startsWith("-"));

  fs.mkdirSync(COVERS_DIR, { recursive: true });
  const catalog = JSON.parse(fs.readFileSync(CAT, "utf8"));

  console.log(`Fetching Tamil book list from site...`);
  const books = await listTamilBooks();
  console.log(`Site has ${books.length} Tamil books.`);

  // Only scanned-image books (not already published with text)
  const existingIds = new Set(catalog.filter((b) => b.lang === LANG).map((b) => b.id));
  let targets = books.filter((b) => !existingIds.has(b.id) && b.id !== LANG + "_heavenly_home");
  if (targetId) {
    targets = books.filter((b) => b.id === targetId);
    if (!targets.length) {
      console.error(`"${targetId}" not found as a missing Tamil book.`);
      process.exit(1);
    }
  }
  console.log(`Targets (${targets.length}): ${targets.map((b) => b.id).join(", ")}\n`);

  const results = [];
  for (const b of targets) {
    try {
      const r = await processBookPage(b, catalog);
      if (r) results.push(r);
    } catch (e) {
      console.error(`  !! ${b.id} failed: ${e.message}`);
    }
    await new Promise((r) => setTimeout(r, 350));
  }

  if (!results.length) {
    console.error("Nothing processed.");
    process.exit(1);
  }

  // Rebuild consolidated SQLite (existing + new)
  const newIds = new Set(results.map((r) => r.meta.id));
  const allBooks = [];
  for (const eb of catalog.filter((b) => b.lang === LANG && !newIds.has(b.id))) {
    const chapDir2 = path.join(LANG_DIR, eb.id, "chapters");
    if (!fs.existsSync(chapDir2)) continue;
    const content = [];
    for (const f of fs.readdirSync(chapDir2).filter((f) => f.endsWith(".json")).sort((a, b) => parseInt(a) - parseInt(b))) {
      const lines = JSON.parse(fs.readFileSync(path.join(chapDir2, f), "utf8"));
      for (const l of lines) {
        content.push({ bookId: eb.id, pageNumber: l.page, lineNumber: l.line, chapterIndex: parseInt(f), contentType: l.contentType, text: l.text });
      }
    }
    const tocPath = path.join(LANG_DIR, eb.id, "toc.json");
    const toc = fs.existsSync(tocPath) ? JSON.parse(fs.readFileSync(tocPath)) : {};
    allBooks.push({ meta: { ...eb, totalPages: toc.totalPages || eb.totalPages, totalLines: toc.totalLines || eb.totalLines }, chRecs: toc.chapters || [], contentRecords: content });
  }
  for (const r of results) allBooks.push({ meta: r.meta, chRecs: r.chRecs, contentRecords: r.contentRecords });

  const dbFile = path.join(LANG_DIR, "books.sqlite");
  if (fs.existsSync(dbFile)) fs.unlinkSync(dbFile);
  const db = new DatabaseSync(dbFile);
  db.exec(CREATE_SQL);
  db.exec("BEGIN;");
  for (const { meta, chRecs, contentRecords } of allBooks) insertBook(db, meta, chRecs, contentRecords);
  db.exec("COMMIT;");
  db.close();
  const gz = saveGz(dbFile);
  console.log(`\n✓ Built ta/books.sqlite.gz (${(gz.length / 1024 / 1024).toFixed(2)} MB)`);

  // Update catalogs
  const finalCatalog = [...catalog.filter((b) => !newIds.has(b.id)), ...results.map((r) => r.entry)];
  fs.writeFileSync(CAT, JSON.stringify(finalCatalog, null, 2), "utf8");
  fs.writeFileSync(APP_CAT, JSON.stringify(finalCatalog, null, 2), "utf8");

  console.log(`\n${"=".repeat(62)}`);
  console.log(`Done. ${results.length} image book(s) processed.\n`);
  console.log("ID".padEnd(45) + "Chs".padEnd(6) + "Pages".padEnd(9) + "ImgLines");
  console.log("-".repeat(70));
  for (const r of results) {
    console.log(r.meta.id.padEnd(45) + String(r.chRecs.length).padEnd(6) + String(r.meta.totalPages).padEnd(9) + r.meta.totalLines);
  }
}

main().catch((e) => {
  console.error("Fatal:", e);
  process.exit(1);
});