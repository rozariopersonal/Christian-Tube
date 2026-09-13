import fs from 'fs';
import path from 'path';
import { ChapterStatusRecord, StatusManifest } from './types.js';
import { STANDARD_BOOKS } from './bible_reader.js';

/**
 * Generic per-pass status tracker. Each pass (study / spek) owns a base
 * directory with `chapters/`, `books/<slug>/`, `books/<slug>.json` and a
 * `status.json` manifest.
 */
export class StatusTracker {
  private pass: string;
  private versionId: string;
  private baseDir: string;
  private chaptersDir: string;
  private booksDir: string;
  private statusFilePath: string;
  private manifest: StatusManifest;
  private countLabel: 'total_terms' | 'total_verses' | 'total_items';

  constructor(pass: 'study' | 'spek' | 'feed', versionId: string, baseDir: string) {
    this.pass = pass;
    this.versionId = versionId;
    this.baseDir = baseDir;
    this.chaptersDir = path.join(this.baseDir, 'chapters');
    this.booksDir = path.join(this.baseDir, 'books');
    this.statusFilePath = path.join(this.baseDir, 'status.json');
    this.countLabel = pass === 'study' ? 'total_terms' : pass === 'spek' ? 'total_verses' : 'total_items';

    fs.mkdirSync(this.chaptersDir, { recursive: true });
    fs.mkdirSync(this.booksDir, { recursive: true });

    this.manifest = this.loadOrCreateManifest();
    this.syncAllBooks();
  }

  public getBaseDir(): string {
    return this.baseDir;
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
      fs.copyFileSync(srcFile, path.join(targetDir, `c${String(cNum).padStart(3, '0')}.json`));
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

  public getConsolidatedBookFilePath(bookNumber: number): string {
    return path.join(this.booksDir, `${this.getBookSlug(bookNumber)}.json`);
  }

  public getChapterFilename(book: number, chapter: number): string {
    return `b${String(book).padStart(2, '0')}_c${String(chapter).padStart(3, '0')}.json`;
  }

  public getChapterFilePath(book: number, chapter: number): string {
    return path.join(this.chaptersDir, this.getChapterFilename(book, chapter));
  }

  private loadOrCreateManifest(): StatusManifest {
    if (fs.existsSync(this.statusFilePath)) {
      try {
        return JSON.parse(fs.readFileSync(this.statusFilePath, 'utf8')) as StatusManifest;
      } catch {
        // fall through and recreate
      }
    }

    const initial: StatusManifest = {
      pass: this.pass,
      version_id: this.versionId,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      total_chapters: 1189,
      completed_chapters: 0,
      failed_chapters: 0,
      total_items: 0,
      chapters: {},
    };
    this.saveManifest(initial);
    return initial;
  }

  private saveManifest(manifest: StatusManifest = this.manifest): void {
    manifest.updated_at = new Date().toISOString();

    let completed = 0;
    let failed = 0;
    let totalItems = 0;
    for (const record of Object.values(manifest.chapters)) {
      if (record.status === 'completed') {
        completed++;
        totalItems += record.count || 0;
      } else if (record.status === 'failed') {
        failed++;
      }
    }

    manifest.completed_chapters = completed;
    manifest.failed_chapters = failed;
    manifest.total_items = totalItems;

    const tempPath = `${this.statusFilePath}.tmp`;
    fs.writeFileSync(tempPath, JSON.stringify(manifest, null, 2), 'utf8');
    fs.renameSync(tempPath, this.statusFilePath);
  }

  public isChapterCompleted(book: number, chapter: number): boolean {
    const rec = this.manifest.chapters[this.key(book, chapter)];
    if (rec && rec.status === 'completed') {
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

  public markStarted(book: number, chapter: number, model: string): void {
    const k = this.key(book, chapter);
    const existing = this.manifest.chapters[k];
    this.manifest.chapters[k] = {
      book,
      chapter,
      status: 'in_progress',
      attempts: (existing?.attempts || 0) + 1,
      model,
    };
    this.saveManifest();
  }

  public markCompleted(
    book: number,
    chapter: number,
    output: any,
    count?: number,
    tokenStats?: { inputTokens?: number; outputTokens?: number }
  ): void {
    const filePath = this.getChapterFilePath(book, chapter);
    const tempFile = `${filePath}.tmp`;
    fs.writeFileSync(tempFile, JSON.stringify(output, null, 2), 'utf8');
    fs.renameSync(tempFile, filePath);

    this.syncAllBooks();

    const k = this.key(book, chapter);
    const existing = this.manifest.chapters[k];
    this.manifest.chapters[k] = {
      book,
      chapter,
      status: 'completed',
      count: count ?? 0,
      attempts: existing?.attempts || 1,
      processed_at: new Date().toISOString(),
      model: this.configModel(),
      input_tokens: tokenStats?.inputTokens,
      output_tokens: tokenStats?.outputTokens,
    };
    this.saveManifest();
  }

  private configModel(): string {
    return this.pass;
  }

  public updateConsolidatedBook(bookNumber: number): void {
    const bookInfo = STANDARD_BOOKS.find((b) => b.bookNumber === bookNumber);
    const bookDir = this.getBookDir(bookNumber);
    if (!fs.existsSync(bookDir)) return;

    const files = fs.readdirSync(bookDir).filter((f) => f.endsWith('.json') && !f.endsWith('.tmp'));
    const chapters: any[] = [];
    let totalItems = 0;

    for (const f of files) {
      try {
        const parsed = JSON.parse(fs.readFileSync(path.join(bookDir, f), 'utf8'));
        chapters.push(parsed);
        if (this.pass === 'study') totalItems += parsed.terms?.length || 0;
        else if (this.pass === 'spek') totalItems += parsed.verses?.length || 0;
      } catch {}
    }

    chapters.sort((a, b) => (a.chapter || 0) - (b.chapter || 0));

    const consolidated = {
      pass: this.pass,
      book: bookNumber,
      book_name: bookInfo?.nameTa || `Book ${bookNumber}`,
      english_name: bookInfo?.nameEn || `Book ${bookNumber}`,
      slug: this.getBookSlug(bookNumber),
      total_chapters: bookInfo?.chapters || chapters.length,
      completed_chapters: chapters.length,
      total_items: totalItems,
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
      model: this.configModel(),
    };
    this.saveManifest();
  }

  public getManifest(): StatusManifest {
    return this.manifest;
  }

  public getSummary() {
    return {
      pass: this.manifest.pass,
      version_id: this.manifest.version_id,
      total_chapters: this.manifest.total_chapters,
      completed_chapters: this.manifest.completed_chapters,
      failed_chapters: this.manifest.failed_chapters,
      pending_chapters:
        this.manifest.total_chapters -
        (this.manifest.completed_chapters + this.manifest.failed_chapters),
      total_items: this.manifest.total_items,
      last_updated: this.manifest.updated_at,
    };
  }
}