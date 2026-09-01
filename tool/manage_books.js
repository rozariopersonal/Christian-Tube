#!/usr/bin/env node
/**
 * tool/manage_books.js
 *
 * Developer CLI tool for easily adding, removing, listing, and rebuilding books:
 *
 * Commands:
 *  - node tool/manage_books.js list
 *  - node tool/manage_books.js add <id> "<title>" "<author>" <html_path_or_url>
 *  - node tool/manage_books.js remove <id>
 *  - node tool/manage_books.js rebuild
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const RAW_DIR = path.join(__dirname, '..', 'data', 'books_raw');
const CATALOG_PATH = path.join(RAW_DIR, 'catalog.json');
const HTML_DIR = path.join(RAW_DIR, 'html');

function loadCatalog() {
  if (!fs.existsSync(CATALOG_PATH)) return [];
  return JSON.parse(fs.readFileSync(CATALOG_PATH, 'utf8'));
}

function saveCatalog(catalog) {
  fs.writeFileSync(CATALOG_PATH, JSON.stringify(catalog, null, 2), 'utf8');
}

function rebuild() {
  console.log('\n--- Rebuilding Books Database, Links & Individual Packages ---');
  execSync('node tool/ingest_books.js', { stdio: 'inherit' });
  execSync('node tool/extract_scripture_links.js', { stdio: 'inherit' });
  execSync('node tool/publish_books.js', { stdio: 'inherit' });
  console.log('\n✓ Rebuild and publish complete!\n');
}

function listBooks() {
  const catalog = loadCatalog();
  console.log(`\nLibrary Catalog (${catalog.length} books):\n`);
  console.log('ID'.padEnd(36) + 'Pages'.padEnd(8) + 'Title');
  console.log('-'.repeat(80));

  for (const book of catalog) {
    const pages = String(book.totalPages || '-').padEnd(8);
    console.log(`${book.id.padEnd(36)}${pages}${book.title} (${book.author || 'Zac Poonen'})`);
  }
  console.log('-'.repeat(80) + '\n');
}

function addBook(id, title, author, sourcePathOrUrl) {
  if (!id || !title) {
    console.error('Usage: node tool/manage_books.js add <id> "<title>" "<author>" <html_file_path>');
    process.exit(1);
  }

  const catalog = loadCatalog();
  const existingIdx = catalog.findIndex(b => b.id === id);

  const destHtml = path.join(HTML_DIR, `${id}.html`);

  if (sourcePathOrUrl && fs.existsSync(sourcePathOrUrl)) {
    fs.copyFileSync(sourcePathOrUrl, destHtml);
    console.log(`✓ Copied HTML to ${destHtml}`);
  } else if (!fs.existsSync(destHtml)) {
    console.error(`Error: Source HTML file not found at ${sourcePathOrUrl || destHtml}`);
    process.exit(1);
  }

  const newBook = {
    id,
    title,
    author: author || 'Zac Poonen',
    description: `A study on Christian discipleship and spiritual growth.`,
    coverUrl: '',
    localCoverFile: `${id}.jpg`,
    sourceUrl: '',
    totalPages: 0,
    totalLines: 0,
  };

  if (existingIdx >= 0) {
    catalog[existingIdx] = { ...catalog[existingIdx], ...newBook };
    console.log(`✓ Updated existing book: ${id}`);
  } else {
    catalog.push(newBook);
    console.log(`✓ Added new book to catalog: ${id}`);
  }

  saveCatalog(catalog);
  rebuild();
}

function removeBook(id) {
  if (!id) {
    console.error('Usage: node tool/manage_books.js remove <id>');
    process.exit(1);
  }

  const catalog = loadCatalog();
  const filtered = catalog.filter(b => b.id !== id);

  if (filtered.length === catalog.length) {
    console.warn(`Book with id "${id}" not found in catalog.`);
    return;
  }

  saveCatalog(filtered);
  console.log(`✓ Removed "${id}" from catalog.`);

  const htmlFile = path.join(HTML_DIR, `${id}.html`);
  if (fs.existsSync(htmlFile)) {
    fs.unlinkSync(htmlFile);
    console.log(`✓ Deleted HTML source file: ${htmlFile}`);
  }

  rebuild();
}

const args = process.argv.slice(2);
const command = args[0] || 'list';

switch (command) {
  case 'list':
    listBooks();
    break;
  case 'add':
    addBook(args[1], args[2], args[3], args[4]);
    break;
  case 'remove':
    removeBook(args[1]);
    break;
  case 'rebuild':
    rebuild();
    break;
  default:
    console.log(`
Christian Tube Books Manager
Commands:
  node tool/manage_books.js list
  node tool/manage_books.js add <id> "<title>" "<author>" <html_file_path>
  node tool/manage_books.js remove <id>
  node tool/manage_books.js rebuild
`);
}
