/**
 * tool/scrape_tamil_book.js — Robust Per-book and All-books Tamil Scraper
 *
 * Handles both:
 *   - Kotobee EPUB readers (16 books) with multi-page chapter consolidation
 *   - Inline HTML chapter pages (14 books) with <h4> and <div> extraction
 *
 * Usage:
 *   node tool/scrape_tamil_book.js                         # Scrape all 30 Tamil books
 *   node tool/scrape_tamil_book.js ta_a_good_foundation     # Scrape one book by ID
 *   node tool/scrape_tamil_book.js --fix-headers           # Strip prefix from chapter files only
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
const PER_PAGE = 1500;

const PREF_RE = /^அதிகாரம்\s+\d+\s*|^chapter\s+\d+\s*|^\d+[\.\)]\s*/iu;
const SKIP_TA = ["அட்டை", "தலைப்பு", "காப்புரிமை", "பொருளடக்கம்", "முகவுரை", "அட்டவணை"];
const SKIP_EN = ["cover", "copyright", "contents", "title page", "start of content"];

// ── Helpers ────────────────────────────────────────────────────────────────

function clean(html) {
  if (!html) return "";
  return html
    .replace(/<a\b[^>]*>(.*?)<\/a>/gi, "$1")
    .replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#039;/g, "'")
    .replace(/&rsquo;/g, "\u2019").replace(/&lsquo;/g, "\u2018")
    .replace(/&rdquo;/g, "\u201d").replace(/&ldquo;/g, "\u201c")
    .replace(/&mdash;/g, "\u2014").replace(/&ndash;/g, "\u2013")
    .replace(/&#160;/g, " ")
    .replace(/<[^>]+>/g, "")
    .replace(/\r?\n|\r/g, " ").replace(/\s+/g, " ").trim();
}

async function get(url, bin = false, ms = 15000) {
  const r = await fetch(url, {
    signal: AbortSignal.timeout(ms),
    headers: { "User-Agent": "Mozilla/5.0 ChristianTubeBookPipeline/2.0" },
  });
  if (!r.ok) throw new Error(`HTTP ${r.status} ${url}`);
  return bin ? Buffer.from(await r.arrayBuffer()) : r.text();
}

function slug(t) {
  return t.toLowerCase().replace(/[^\w\s-]/g, "").trim().replace(/[\s_-]+/g, "_");
}

function splitP(text) {
  if (text.length <= PER_PAGE) return [text];
  const ss = text.match(/[^.!?]+[.!?]+["'\u201d]?\s*/g) || [text];
  const chunks = [];
  let cur = "";
  for (const s of ss) {
    if (!cur) cur = s.trim();
    else if (cur.length + s.length <= PER_PAGE) cur += " " + s.trim();
    else { chunks.push(cur); cur = s.trim(); }
  }
  if (cur) chunks.push(cur);
  return chunks.length ? chunks : [text];
}

// ── Kotobee Extraction ─────────────────────────────────────────────────────

async function extractKotobee(kUrl) {
  const base = kUrl.replace(/\/index\.html.*$/, "");
  const opf = await get(`${base}/epub/EPUB/package.opf`);

  const title = clean((opf.match(/<dc:title[^>]*>([\s\S]*?)<\/dc:title>/i) || [])[1] || "");
  const author = clean((opf.match(/<dc:creator[^>]*>([\s\S]*?)<\/dc:creator>/i) || [])[1] || "") || "Zac Poonen";
  const desc = clean((opf.match(/<dc:description[^>]*>([\s\S]*?)<\/dc:description>/i) || [])[1] || "");

  const manifest = new Map();
  for (const m of opf.matchAll(/<item\s+[^>]*id=["']([^"']+)["'][^>]*href=["']([^"']+)["']/gi)) manifest.set(m[1], m[2]);
  for (const m of opf.matchAll(/<item\s+[^>]*href=["']([^"']+)["'][^>]*id=["']([^"']+)["']/gi)) manifest.set(m[2], m[1]);

  const spineIds = [...opf.matchAll(/<itemref\s+[^>]*idref=["']([^"']+)["']/gi)].map(m => m[1]);
  const spine = spineIds.map(id => manifest.get(id)).filter(Boolean);
  console.log(`  Spine: ${spine.length} files`);

  let tocHref = null;
  for (const [id, href] of manifest) {
    if (href.endsWith("contents.xhtml") || href.endsWith("toc.xhtml") || id === "contents" || id === "toc") {
      tocHref = href;
      break;
    }
  }

  const milestones = [];
  if (tocHref) {
    const tocUrl = new URL(tocHref, `${base}/epub/EPUB/`).toString();
    const tocHtml = await get(tocUrl);
    const li = [...tocHtml.matchAll(/<li\b[^>]*>\s*<a\s+[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)];
    console.log(`  TOC entries: ${li.length}`);
    for (const m of li) {
      const rawHref = m[1].replace(/#.*$/, "");
      const chTitle = clean(m[2]);
      if (!chTitle || chTitle.length < 2) continue;

      const isFM = SKIP_TA.some(w => chTitle.includes(w)) || SKIP_EN.some(w => chTitle.toLowerCase().includes(w));
      if (isFM) { console.log(`    skip(front): "${chTitle}"`); continue; }

      // Skip internal page milestones (e.g. "அத்தியாயம் 1 / பக்கம் 2")
      if (/பக்கம்\s*\d+/i.test(chTitle) || /page\s*\d+/i.test(chTitle)) {
        continue;
      }

      const abs = new URL(rawHref, tocUrl).toString();
      const rel = abs.replace(`${base}/epub/EPUB/`, "");
      milestones.push({ title: chTitle, file: rel });
      console.log(`    chapter: "${chTitle}" -> ${rel}`);
    }
  } else {
    console.warn("  No TOC found in manifest");
  }

  // Map milestones to spine indices
  const mIdx = [];
  for (const ms of milestones) {
    const i = spine.findIndex(f => f.toLowerCase() === ms.file.toLowerCase());
    if (i !== -1) mIdx.push({ title: ms.title, si: i });
    else console.warn(`  ! not in spine: ${ms.file}`);
  }

  const groups = [];
  if (mIdx.length > 0) {
    for (let i = 0; i < mIdx.length; i++) {
      const s = mIdx[i].si;
      const e = i + 1 < mIdx.length ? mIdx[i + 1].si : spine.length;
      groups.push({ title: mIdx[i].title, files: spine.slice(s, e) });
    }
  } else {
    for (const f of spine) {
      const lf = f.toLowerCase();
      if (lf.includes("cover") || lf.includes("titlepage") || lf.includes("copyright")) continue;
      groups.push({ title: `Chapter ${groups.length + 1}`, files: [f] });
    }
  }
  console.log(`  Chapter groups: ${groups.length}`);

  const chapters = [];
  for (let gi = 0; gi < groups.length; gi++) {
    const cg = groups[gi];
    const elems = [];
    for (const f of cg.files) {
      try {
        const xhtml = await get(`${base}/epub/EPUB/${f}`);
        const re = /<(h1|h2|h3|h4|h5|blockquote|p|li)(?:\s+[^>]*)?>([^<]*(?:<(?!\/?(h1|h2|h3|h4|h5|blockquote|p|li))[^>]*>[^<]*)*)<\/\1>/gi;
        let m;
        while ((m = re.exec(xhtml)) !== null) {
          const tag = m[1].toLowerCase();
          const text = clean(m[2]);
          if (!text || text.length < 2) continue;
          if (text.includes("cfcindia") || text.includes("austincfc")) continue;
          let type = "p";
          if (tag === "h1" || tag === "h2") type = "h2";
          else if (tag === "h3" || tag === "h4") type = "h3";
          else if (tag === "blockquote") type = "blockquote";
          elems.push({ type, text });
        }
      } catch (e) { console.warn(`    ! fetch ${f}: ${e.message}`); }
    }
    if (elems.length > 0) {
      const cleanTitle = cg.title.replace(PREF_RE, "").trim() || cg.title;
      chapters.push({ title: cleanTitle, elems });
      console.log(`  ch${chapters.length} "${cleanTitle.slice(0, 45)}" -> ${elems.length} elems`);
    } else {
      console.warn(`  group "${cg.title.slice(0, 45)}" -> EMPTY, skipped`);
    }
  }

  return { title, author, desc, chapters };
}

// ── HTML Page Extraction ───────────────────────────────────────────────────

function parsePageHtmlChapters(htmlContent) {
  const chapters = [];

  // Strategy A: Split on <h4 class="books-chapter-title">
  const parts = htmlContent.split(/<h4\b[^>]*\bclass=["'][^"']*\bbooks-chapter-title\b[^"']*["'][^>]*>/i);
  if (parts.length > 1) {
    for (let i = 1; i < parts.length; i++) {
      const part = parts[i];
      const endH4 = part.indexOf("</h4>");
      if (endH4 === -1) continue;
      const headingHtml = part.slice(0, endH4);
      const bodyHtml = part.slice(endH4 + 5);

      const numMatch = headingHtml.match(/<div class=["']chapter-number["']>([\s\S]*?)<\/div>/i);
      const rawTitle = headingHtml.replace(/<div class=["']chapter-number["']>[\s\S]*?<\/div>/i, "");
      let chapterTitle = clean(rawTitle);
      chapterTitle = chapterTitle.replace(PREF_RE, "").trim() || (numMatch ? clean(numMatch[1]) : `Chapter ${i}`);

      const elems = [];
      const elemRegex = /<(h2|h3|h4|h5|blockquote|p|li)(?:\s+[^>]*)?>([^<]*(?:<(?!\/?(h2|h3|h4|h5|blockquote|p|li))[^>]*>[^<]*)*)<\/\1>/gi;
      let match;
      while ((match = elemRegex.exec(bodyHtml)) !== null) {
        if (match[0].includes("books-chapter-title") || match[0].includes("table-of-content")) continue;
        const tag = match[1].toLowerCase();
        const text = clean(match[2]);
        if (!text || text.length < 2) continue;
        if (text.includes("cfcindia") || text.includes("austincfc")) continue;
        let type = "p";
        if (tag === "h2") type = "h2";
        else if (tag === "h3" || tag === "h4" || tag === "h5") type = "h3";
        else if (tag === "blockquote") type = "blockquote";
        elems.push({ type, text });
      }

      if (elems.length > 0) {
        chapters.push({ title: chapterTitle, elems });
      }
    }
    return chapters;
  }

  // Strategy B: Split on <div class="chapter clearfix">
  const divParts = htmlContent.split(/<div\b[^>]*\bclass=["'][^"']*\bchapter\s+clearfix[^"']*["'][^>]*>/i);
  if (divParts.length > 1) {
    for (let i = 1; i < divParts.length; i++) {
      const chunk = divParts[i];
      const titleMatch = chunk.match(/<h[2-6][^>]*>([\s\S]*?)<\/h[2-6]>/i);
      let title = titleMatch ? clean(titleMatch[1]).replace(PREF_RE, "").trim() : `Chapter ${i}`;

      const elems = [];
      const elemRegex = /<(h2|h3|h4|h5|blockquote|p|li)(?:\s+[^>]*)?>([^<]*(?:<(?!\/?(h2|h3|h4|h5|blockquote|p|li))[^>]*>[^<]*)*)<\/\1>/gi;
      let match;
      while ((match = elemRegex.exec(chunk)) !== null) {
        if (match[0].includes("table-of-content") || match[0].includes("share")) continue;
        const tag = match[1].toLowerCase();
        const text = clean(match[2]);
        if (!text || text.length < 2) continue;
        if (text.includes("cfcindia") || text.includes("austincfc")) continue;
        let type = "p";
        if (tag === "h2") type = "h2";
        else if (tag === "h3" || tag === "h4" || tag === "h5") type = "h3";
        else if (tag === "blockquote") type = "blockquote";
        elems.push({ type, text });
      }
      if (elems.length > 0) chapters.push({ title, elems });
    }
    return chapters;
  }

  // Strategy C: Single-chapter booklet
  const bodyMatch = htmlContent.match(/<div[^>]*class=["'][^"']*(?:field-name-body|node-book)[^"']*["'][^>]*>([\s\S]*?)<\/div>\s*<\/div>/i);
  const targetHtml = bodyMatch ? bodyMatch[1] : htmlContent;
  const elems = [];
  const elemRegex = /<(h2|h3|h4|h5|blockquote|p|li)(?:\s+[^>]*)?>([^<]*(?:<(?!\/?(h2|h3|h4|h5|blockquote|p|li))[^>]*>[^<]*)*)<\/\1>/gi;
  let match;
  while ((match = elemRegex.exec(targetHtml)) !== null) {
    if (match[0].includes("table-of-content") || match[0].includes("share")) continue;
    const tag = match[1].toLowerCase();
    const text = clean(match[2]);
    if (!text || text.length < 2) continue;
    if (text.includes("cfcindia") || text.includes("austincfc")) continue;
    let type = "p";
    if (tag === "h2") type = "h2";
    else if (tag === "h3" || tag === "h4" || tag === "h5") type = "h3";
    else if (tag === "blockquote") type = "blockquote";
    elems.push({ type, text });
  }
  if (elems.length >= 5) {
    chapters.push({ title: "General", elems });
  }

  return chapters;
}

// ── Pagination ─────────────────────────────────────────────────────────────

function paginate(bookId, chapters) {
  let page = 1, line = 1, chars = 0;
  const chRecs = [], content = [];
  for (let ci = 0; ci < chapters.length; ci++) {
    const ch = chapters[ci];
    if (chars > 0 || line > 1) { page++; line = 1; chars = 0; }
    const sp = page, sl = line;
    const title = ch.title.replace(PREF_RE, "").trim() || ch.title;
    content.push({ bookId, pageNumber: page, lineNumber: line, chapterIndex: ci + 1, contentType: "chapter_header", text: title });
    line++; chars += title.length;
    for (const e of ch.elems) {
      const chunks = e.type === "p" && e.text.length > PER_PAGE ? splitP(e.text) : [e.text];
      for (const c of chunks) {
        if (chars > 0 && chars + c.length > PER_PAGE) { page++; line = 1; chars = 0; }
        content.push({ bookId, pageNumber: page, lineNumber: line, chapterIndex: ci + 1, contentType: e.type, text: c });
        line++; chars += c.length;
      }
    }
    chRecs.push({ chapterIndex: ci + 1, title, startPage: sp, startLine: sl, endPage: page, endLine: Math.max(1, line - 1) });
  }
  return { totalPages: page, totalLines: content.length, chRecs, content };
}

// ── SQLite ─────────────────────────────────────────────────────────────────

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

function buildConsolidated(allBooks) {
  const p = path.join(LANG_DIR, "books.sqlite");
  if (fs.existsSync(p)) fs.unlinkSync(p);
  const db = new DatabaseSync(p);
  db.exec(CREATE_SQL);
  db.exec("BEGIN;");
  for (const { meta, chRecs, content } of allBooks) insertBook(db, meta, chRecs, content);
  db.exec("COMMIT;");
  db.close();
  const gz = saveGz(p);
  console.log(`  Consolidated ta/books.sqlite.gz: ${(gz.length / 1024 / 1024).toFixed(2)} MB`);
}

// ── Write Files ────────────────────────────────────────────────────────────

function writeFiles(bookId, meta, chRecs, content) {
  const bookDir = path.join(LANG_DIR, bookId);
  const chapDir = path.join(bookDir, "chapters");
  fs.mkdirSync(chapDir, { recursive: true });
  for (const f of fs.readdirSync(chapDir)) {
    if (f.endsWith(".json")) fs.unlinkSync(path.join(chapDir, f));
  }
  fs.writeFileSync(
    path.join(bookDir, "toc.json"),
    JSON.stringify({ id: bookId, title: meta.title, author: meta.author, subject: meta.subject, totalPages: meta.totalPages, totalLines: meta.totalLines, chapters: chRecs }, null, 2),
    "utf8"
  );
  for (const ch of chRecs) {
    const lines = content.filter(r => r.chapterIndex === ch.chapterIndex).map(l => ({
      line: l.lineNumber, page: l.pageNumber, text: l.text, contentType: l.contentType,
      isHeading: ["chapter_header", "h2", "h3"].includes(l.contentType),
      headingLevel: l.contentType === "chapter_header" ? 1 : l.contentType === "h2" ? 2 : l.contentType === "h3" ? 3 : 0,
    }));
    fs.writeFileSync(path.join(chapDir, `${ch.chapterIndex}.json`), JSON.stringify(lines), "utf8");
  }
}

// ── Fix-Headers Mode ───────────────────────────────────────────────────────

function fixHeaders() {
  console.log("=== Strip chapter_header prefix from chapter JSON files ===\n");
  const dirs = fs.readdirSync(LANG_DIR).filter(d => d !== "published" && fs.statSync(path.join(LANG_DIR, d)).isDirectory());
  for (const bookId of dirs) {
    const chapDir = path.join(LANG_DIR, bookId, "chapters");
    if (!fs.existsSync(chapDir)) continue;
    let changed = 0;
    for (const f of fs.readdirSync(chapDir).filter(f => f.endsWith(".json"))) {
      const fp = path.join(chapDir, f);
      const lines = JSON.parse(fs.readFileSync(fp, "utf8"));
      let dirty = false;
      for (const l of lines) {
        if (l.contentType === "chapter_header" && PREF_RE.test(l.text)) {
          l.text = l.text.replace(PREF_RE, "").trim();
          dirty = true;
        }
      }
      if (dirty) { fs.writeFileSync(fp, JSON.stringify(lines), "utf8"); changed++; }
    }
    const status = changed > 0 ? `stripped prefix in ${changed} file(s)` : "already clean";
    console.log(`  ${bookId}: ${status}`);
  }
  console.log("\nDone.");
}

// ── Site Discovery ─────────────────────────────────────────────────────────

async function listTamilBooks() {
  const html = await get(LANG_URL, false, 20000);
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

// ── Process Book ───────────────────────────────────────────────────────────

async function processBook(b, catalog) {
  console.log(`\n${"=".repeat(60)}`);
  console.log(`ID:    ${b.id}`);
  console.log(`Title: ${b.title}`);
  console.log(`URL:   ${b.pageUrl}`);

  // Cover
  const coverFile = `${b.id}.jpg`;
  const coverDest = path.join(BOOKS_DIR, "covers", coverFile);
  if (b.coverUrl && !fs.existsSync(coverDest)) {
    try {
      const buf = await get(b.coverUrl, true);
      fs.writeFileSync(coverDest, buf);
      console.log(`  Cover: saved (${(buf.length / 1024).toFixed(1)} KB)`);
    } catch (e) {
      console.warn(`  Cover failed: ${e.message}`);
    }
  } else {
    console.log(`  Cover: ${fs.existsSync(coverDest) ? "exists" : "no URL"}`);
  }

  // Fetch page HTML to check reader or HTML chapters
  let pageHtml = "";
  try {
    pageHtml = await get(b.pageUrl);
  } catch (e) {
    console.warn(`  Page fetch warning: ${e.message}`);
  }

  // Determine reader URL (Kotobee)
  let kUrl = b.kotobeeUrl;
  if (!kUrl && pageHtml) {
    const km = pageHtml.match(/href=["'](https?:\/\/[^"']*\/epub\/[^"']+\/index\.html)["']/i);
    if (km) kUrl = km[1];
  }

  // If kUrl points to tamil.cfcindia.com/epub/nuggets-of-pearls, redirect to real host www.cfcindia.org
  if (kUrl && kUrl.includes("tamil.cfcindia.com/epub/nuggets-of-pearls")) {
    kUrl = "https://www.cfcindia.org/resources/ta/books/epub/nuggets-of-pearls/index.html";
  }

  let extractedData = null;

  if (kUrl) {
    console.log(`  Kotobee reader: ${kUrl}`);
    try {
      extractedData = await extractKotobee(kUrl);
    } catch (e) {
      console.warn(`  Kotobee extraction failed (${e.message}), falling back to HTML page parsing...`);
    }
  }

  if (!extractedData || !extractedData.chapters.length) {
    if (pageHtml) {
      console.log(`  Parsing HTML page chapters directly...`);
      const htmlChapters = parsePageHtmlChapters(pageHtml);
      if (htmlChapters.length > 0) {
        extractedData = {
          title: b.title,
          author: b.author,
          desc: b.description,
          chapters: htmlChapters,
        };
      }
    }
  }

  if (!extractedData || !extractedData.chapters.length) {
    console.warn(`  ⚠ No readable chapters found for "${b.title}". Skipping.`);
    return null;
  }

  console.log(`  Total chapters: ${extractedData.chapters.length}`);

  const { totalPages, totalLines, chRecs, content } = paginate(b.id, extractedData.chapters);
  console.log(`  Pages: ${totalPages}, Lines: ${totalLines}`);

  if (totalPages <= 1 && totalLines <= 5) {
    console.warn(`  ⚠ Book "${b.title}" has insufficient text content (${totalPages} pages, ${totalLines} lines). Skipping.`);
    return null;
  }

  const existing = catalog.find(c => c.id === b.id) || {};
  const meta = {
    id: b.id,
    title: extractedData.title || b.title,
    author: extractedData.author || b.author,
    subject: existing.subject || "Christian Living",
    categories: existing.categories || ["Christian Living"],
    description: extractedData.desc || b.description,
    coverFile,
    lang: LANG,
    totalPages,
    totalLines,
  };

  writeFiles(b.id, meta, chRecs, content);
  const gz = buildSingle(meta, chRecs, content);
  console.log(`  Published: ${b.id}.sqlite.gz (${(gz.length / 1024).toFixed(1)} KB)`);

  return {
    meta,
    chRecs,
    content,
    entry: {
      id: b.id,
      title: meta.title,
      author: meta.author,
      subject: meta.subject,
      categories: meta.categories,
      description: meta.description,
      coverFile,
      totalPages,
      totalLines,
      downloadSizeFormatted: `${(gz.length / 1024).toFixed(1)} KB`,
      createdAt: existing.createdAt || new Date().toISOString(),
      lang: LANG,
    },
  };
}

// ── Main ───────────────────────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2);
  if (args.includes("--fix-headers")) {
    fixHeaders();
    return;
  }

  const targetId = args.find(a => !a.startsWith("-"));

  fs.mkdirSync(path.join(BOOKS_DIR, "covers"), { recursive: true });

  const catalog = JSON.parse(fs.readFileSync(CAT, "utf8"));

  console.log(`Fetching Tamil book list from site...`);
  let books = await listTamilBooks();
  console.log(`Site has ${books.length} Tamil books.`);

  if (targetId) {
    books = books.filter(b => b.id === targetId);
    if (!books.length) {
      console.error(`"${targetId}" not found on site.`);
      process.exit(1);
    }
  }

  const results = [];
  for (const b of books) {
    const r = await processBook(b, catalog);
    if (r) results.push(r);
    await new Promise(r => setTimeout(r, 200));
  }

  if (!results.length) {
    console.error("Nothing processed.");
    process.exit(1);
  }

  // Rebuild consolidated database
  const updatedIds = new Set(results.map(r => r.meta.id));
  const allForConsolidated = [];
  for (const eb of catalog.filter(b => b.lang === LANG && !updatedIds.has(b.id))) {
    const chapDir = path.join(LANG_DIR, eb.id, "chapters");
    if (!fs.existsSync(chapDir)) continue;
    const content = [];
    for (const f of fs.readdirSync(chapDir).filter(f => f.endsWith(".json")).sort((a, b) => parseInt(a) - parseInt(b))) {
      const lines = JSON.parse(fs.readFileSync(path.join(chapDir, f), "utf8"));
      for (const l of lines) content.push({ bookId: eb.id, pageNumber: l.page, lineNumber: l.line, chapterIndex: parseInt(f), contentType: l.contentType, text: l.text });
    }
    const tocPath = path.join(LANG_DIR, eb.id, "toc.json");
    const toc = fs.existsSync(tocPath) ? JSON.parse(fs.readFileSync(tocPath)) : {};
    allForConsolidated.push({
      meta: { ...eb, totalPages: toc.totalPages || eb.totalPages, totalLines: toc.totalLines || eb.totalLines },
      chRecs: toc.chapters || [],
      content,
    });
  }
  for (const r of results) allForConsolidated.push({ meta: r.meta, chRecs: r.chRecs, content: r.content });
  buildConsolidated(allForConsolidated);

  // Update catalogs
  const newIds = new Set(results.map(r => r.meta.id));
  const finalCatalog = [...catalog.filter(b => !newIds.has(b.id)), ...results.map(r => r.entry)];
  fs.writeFileSync(CAT, JSON.stringify(finalCatalog, null, 2), "utf8");
  fs.writeFileSync(APP_CAT, JSON.stringify(finalCatalog, null, 2), "utf8");

  console.log(`\n${"=".repeat(60)}`);
  console.log(`Done. ${results.length} book(s) processed.\n`);
  console.log("ID".padEnd(50) + "Chs".padEnd(6) + "Pages".padEnd(8) + "Lines");
  console.log("-".repeat(70));
  for (const r of results) {
    console.log(r.meta.id.padEnd(50) + String(r.chRecs.length).padEnd(6) + String(r.meta.totalPages).padEnd(8) + r.meta.totalLines);
  }
}

main().catch(e => {
  console.error("Fatal:", e);
  process.exit(1);
});
