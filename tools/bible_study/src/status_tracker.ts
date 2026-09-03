import fs from 'fs';
import path from 'path';
import { AppConfig, ChapterOutput, ChapterStatusRecord, StatusManifest } from './types.js';

import { STANDARD_BOOKS } from './bible_reader.js';

export class StatusTracker {
  private config: AppConfig;
  private versionDir: string;
  private chaptersDir: string;
  private booksDir: string;
  private statusFilePath: string;
  private manifest: StatusManifest;

  constructor(config: AppConfig) {
    this.config = config;
    this.versionDir = path.join(config.output_dir, config.version_id);
    this.chaptersDir = path.join(this.versionDir, 'chapters');
    this.booksDir = path.join(this.versionDir, 'books');
    this.statusFilePath = path.join(this.versionDir, 'status.json');

    // Ensure output directories exist
    fs.mkdirSync(this.chaptersDir, { recursive: true });
    fs.mkdirSync(this.booksDir, { recursive: true });

    this.manifest = this.loadOrCreateManifest();
    this.syncAllBooks();
  }

  public syncAllBooks(): void {
    if (!fs.existsSync(this.chaptersDir)) return;
    const files = fs.readdirSync(this.chaptersDir).filter((f) => f.endsWith('.json') && !f.endsWith('.tmp'));
    const booksAffected = new Set<number>();

    for (const f of files) {
      const match = f.match(/^b(\d+)_c(\d+)\.json$/);
      if (!match) continue;
      const bNum = parseInt(match[1], 10);
      const cNum = parseInt(match[2], 10);
      const srcFile = path.join(this.chaptersDir, f);
      const targetDir = this.getBookDir(bNum);
      fs.mkdirSync(targetDir, { recursive: true });
      const targetFile = this.getBookChapterFilePath(bNum, cNum);
      fs.copyFileSync(srcFile, targetFile);
      booksAffected.add(bNum);
    }

    for (const b of booksAffected) {
      this.updateConsolidatedBook(b);
    }
  }

  private key(book: number, chapter: number): string {
    return `${book}_${chapter}`;
  }

  public getBookSlug(bookNumber: number): string {
    const book = STANDARD_BOOKS.find((b) => b.bookNumber === bookNumber);
    const numStr = String(bookNumber).padStart(2, '0');
    const cleanName = (book?.nameEn || 'book').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
    return `${numStr}_${cleanName}`;
  }

  public getBookDir(bookNumber: number): string {
    return path.join(this.booksDir, this.getBookSlug(bookNumber));
  }

  public getBookChapterFilePath(book: number, chapter: number): string {
    const cStr = String(chapter).padStart(3, '0');
    return path.join(this.getBookDir(book), `c${cStr}.json`);
  }

  public getConsolidatedBookFilePath(bookNumber: number): string {
    return path.join(this.booksDir, `${this.getBookSlug(bookNumber)}.json`);
  }

  public getChapterFilename(book: number, chapter: number): string {
    const bStr = String(book).padStart(2, '0');
    const cStr = String(chapter).padStart(3, '0');
    return `b${bStr}_c${cStr}.json`;
  }

  public getChapterFilePath(book: number, chapter: number): string {
    return path.join(this.chaptersDir, this.getChapterFilename(book, chapter));
  }

  private loadOrCreateManifest(): StatusManifest {
    if (fs.existsSync(this.statusFilePath)) {
      try {
        const raw = fs.readFileSync(this.statusFilePath, 'utf8');
        const parsed = JSON.parse(raw) as StatusManifest;
        return parsed;
      } catch (err) {
        console.warn(`[StatusTracker] Failed reading status.json, creating new manifest:`, err);
      }
    }

    const initial: StatusManifest = {
      version_id: this.config.version_id,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      total_chapters: 1189,
      completed_chapters: 0,
      failed_chapters: 0,
      total_terms: 0,
      chapters: {},
    };

    this.saveManifest(initial);
    return initial;
  }

  private saveManifest(manifest: StatusManifest = this.manifest): void {
    manifest.updated_at = new Date().toISOString();

    // Recalculate summary metrics
    let completed = 0;
    let failed = 0;
    let totalTerms = 0;

    for (const record of Object.values(manifest.chapters)) {
      if (record.status === 'completed') {
        completed++;
        totalTerms += record.terms_count || 0;
      } else if (record.status === 'failed') {
        failed++;
      }
    }

    manifest.completed_chapters = completed;
    manifest.failed_chapters = failed;
    manifest.total_terms = totalTerms;

    const tempPath = `${this.statusFilePath}.tmp`;
    fs.writeFileSync(tempPath, JSON.stringify(manifest, null, 2), 'utf8');
    fs.renameSync(tempPath, this.statusFilePath);
  }

  public isChapterCompleted(book: number, chapter: number): boolean {
    const k = this.key(book, chapter);
    const rec = this.manifest.chapters[k];
    if (rec && rec.status === 'completed') {
      // Also verify that the chapter JSON file exists and is non-empty
      const filePath = this.getChapterFilePath(book, chapter);
      if (fs.existsSync(filePath) && fs.statSync(filePath).size > 10) {
        return true;
      }
    }
    return false;
  }

  public getChapterRecord(book: number, chapter: number): ChapterStatusRecord | undefined {
    return this.manifest.chapters[this.key(book, chapter)];
  }

  public markStarted(book: number, chapter: number): void {
    const k = this.key(book, chapter);
    const existing = this.manifest.chapters[k];
    this.manifest.chapters[k] = {
      book,
      chapter,
      status: 'in_progress',
      attempts: (existing?.attempts || 0) + 1,
      model: this.config.gemini.model,
    };
    this.saveManifest();
  }

  public markCompleted(
    book: number,
    chapter: number,
    output: ChapterOutput,
    tokenStats?: { inputTokens?: number; outputTokens?: number }
  ): void {
    // 1. Write the chapter output JSON file
    const filePath = this.getChapterFilePath(book, chapter);
    const tempFile = `${filePath}.tmp`;
    fs.writeFileSync(tempFile, JSON.stringify(output, null, 2), 'utf8');
    fs.renameSync(tempFile, filePath);

    // 2. Write to the book-organized directory: books/<slug>/c<chapter>.json
    const bookDir = this.getBookDir(book);
    fs.mkdirSync(bookDir, { recursive: true });
    const bookChapterFile = this.getBookChapterFilePath(book, chapter);
    const bookTempFile = `${bookChapterFile}.tmp`;
    fs.writeFileSync(bookTempFile, JSON.stringify(output, null, 2), 'utf8');
    fs.renameSync(bookTempFile, bookChapterFile);

    // 3. Compile or update the consolidated book JSON: books/<slug>.json
    this.updateConsolidatedBook(book);

    // 4. Update status record atomically
    const k = this.key(book, chapter);
    const existing = this.manifest.chapters[k];
    this.manifest.chapters[k] = {
      book,
      chapter,
      status: 'completed',
      terms_count: output.terms.length,
      attempts: existing?.attempts || 1,
      processed_at: new Date().toISOString(),
      model: this.config.gemini.model,
      input_tokens: tokenStats?.inputTokens,
      output_tokens: tokenStats?.outputTokens,
    };
    this.saveManifest();
  }

  public updateConsolidatedBook(bookNumber: number): void {
    const bookInfo = STANDARD_BOOKS.find((b) => b.bookNumber === bookNumber);
    const bookDir = this.getBookDir(bookNumber);
    if (!fs.existsSync(bookDir)) return;

    const files = fs.readdirSync(bookDir).filter((f) => f.endsWith('.json') && !f.endsWith('.tmp'));
    const chapters: ChapterOutput[] = [];
    let totalTerms = 0;

    for (const f of files) {
      try {
        const content = fs.readFileSync(path.join(bookDir, f), 'utf8');
        const parsed = JSON.parse(content) as ChapterOutput;
        chapters.push(parsed);
        totalTerms += parsed.terms?.length || 0;
      } catch {}
    }

    chapters.sort((a, b) => a.chapter - b.chapter);

    const consolidated = {
      book: bookNumber,
      book_name: bookInfo?.nameTa || `Book ${bookNumber}`,
      english_name: bookInfo?.nameEn || `Book ${bookNumber}`,
      slug: this.getBookSlug(bookNumber),
      total_chapters: bookInfo?.chapters || chapters.length,
      completed_chapters: chapters.length,
      total_terms: totalTerms,
      last_updated: new Date().toISOString(),
      chapters,
    };

    const targetPath = this.getConsolidatedBookFilePath(bookNumber);
    const tempPath = `${targetPath}.tmp`;
    fs.writeFileSync(tempPath, JSON.stringify(consolidated, null, 2), 'utf8');
    fs.renameSync(tempPath, targetPath);
  }

  public markFailed(book: number, chapter: number, error: string): void {
    const k = this.key(book, chapter);
    const existing = this.manifest.chapters[k];
    this.manifest.chapters[k] = {
      book,
      chapter,
      status: 'failed',
      attempts: existing?.attempts || 1,
      processed_at: new Date().toISOString(),
      error,
      model: this.config.gemini.model,
    };
    this.saveManifest();
  }

  public getManifest(): StatusManifest {
    return this.manifest;
  }

  public getSummary() {
    return {
      version_id: this.manifest.version_id,
      total_chapters: this.manifest.total_chapters,
      completed_chapters: this.manifest.completed_chapters,
      failed_chapters: this.manifest.failed_chapters,
      pending_chapters:
        this.manifest.total_chapters -
        (this.manifest.completed_chapters + this.manifest.failed_chapters),
      total_terms: this.manifest.total_terms,
      last_updated: this.manifest.updated_at,
    };
  }
}
