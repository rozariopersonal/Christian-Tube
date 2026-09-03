import { BibleReader } from './bible_reader.js';
import { GeminiStudyClient } from './gemini_client.js';
import { normalizeSurfaceForm } from './normalizer.js';
import { StatusTracker } from './status_tracker.js';
import { AppConfig, ChapterOutput, InputChapter } from './types.js';

export class ChapterProcessor {
  private config: AppConfig;
  private reader: BibleReader;
  private geminiClient: GeminiStudyClient | null = null;
  private statusTracker: StatusTracker;
  private isInterrupted: boolean = false;

  constructor(
    config: AppConfig,
    reader: BibleReader,
    statusTracker: StatusTracker,
    geminiClient: GeminiStudyClient | null = null
  ) {
    this.config = config;
    this.reader = reader;
    this.statusTracker = statusTracker;
    this.geminiClient = geminiClient;

    // Graceful interrupt handling
    process.on('SIGINT', () => {
      console.log('\n[Processor] Interruption received. Finishing current chapter and exiting cleanly...');
      this.isInterrupted = true;
    });
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  /**
   * Processes a single chapter if not already completed.
   */
  public async processChapter(
    book: number,
    chapter: number,
    force: boolean = false
  ): Promise<'skipped' | 'completed' | 'failed'> {
    if (!force && this.statusTracker.isChapterCompleted(book, chapter)) {
      console.log(`[Processor] Book ${book} Chapter ${chapter} already completed. Skipping.`);
      return 'skipped';
    }

    const chapterData = await this.reader.getChapter(book, chapter);
    if (!chapterData) {
      const err = `Chapter data not found for Book ${book} Chapter ${chapter}`;
      console.error(`[Processor] ${err}`);
      this.statusTracker.markFailed(book, chapter, err);
      return 'failed';
    }

    console.log(
      `[Processor] Processing Book ${book} (${chapterData.book_name}) Chapter ${chapter} (${chapterData.verses.length} verses)...`
    );

    this.statusTracker.markStarted(book, chapter);

    if (this.config.processing.dry_run) {
      console.log(`[Processor] Dry-run enabled. Skipping Gemini API call.`);
      const mockOutput: ChapterOutput = {
        version_id: this.config.version_id,
        book,
        book_name: chapterData.book_name,
        chapter,
        chapter_summary: `[Dry Run] Summary for Book ${book} Chapter ${chapter}`,
        terms: [],
      };
      this.statusTracker.markCompleted(book, chapter, mockOutput);
      return 'completed';
    }

    if (!this.geminiClient) {
      throw new Error('[Processor] Gemini client not initialized.');
    }

    try {
      const { output, inputTokens, outputTokens } = await this.geminiClient.extractChapterStudy(chapterData);

      // Post-process & clean surface forms
      for (const term of output.terms) {
        term.surface_forms = term.surface_forms
          .map((sf) => normalizeSurfaceForm(sf))
          .filter((sf) => sf.length > 0);
      }

      this.statusTracker.markCompleted(book, chapter, output, { inputTokens, outputTokens });
      console.log(
        `[Processor] Successfully completed Book ${book} Chapter ${chapter}: ${output.terms.length} terms extracted. (Tokens: ${inputTokens ?? 0} in, ${outputTokens ?? 0} out)`
      );

      if (this.config.processing.pause_between_requests_ms > 0) {
        await this.sleep(this.config.processing.pause_between_requests_ms);
      }

      return 'completed';
    } catch (err: any) {
      const msg = err.message || String(err);
      console.error(`[Processor] Failed Book ${book} Chapter ${chapter}: ${msg}`);
      this.statusTracker.markFailed(book, chapter, msg);

      if (msg.includes('RESOURCE_EXHAUSTED') || msg.includes('Quota exceeded') || msg.includes('quotaId')) {
        console.warn(`\n[Processor] DAILY FREE TIER QUOTA EXHAUSTED.`);
        console.warn(`[Processor] All completed work is safely saved. Quota resets tomorrow.\n`);
        this.isQuotaExhausted = true;
      }

      return 'failed';
    }
  }

  public isDailyQuotaExhausted(): boolean {
    return this.isQuotaExhausted;
  }

  /**
   * Processes a sequence of chapters with pause/resume support.
   */
  public async processBatch(
    chapters: Array<{ book: number; chapter: number }>,
    force: boolean = false
  ): Promise<{ completed: number; skipped: number; failed: number }> {
    let completed = 0;
    let skipped = 0;
    let failed = 0;

    for (let i = 0; i < chapters.length; i++) {
      if (this.isInterrupted || this.isQuotaExhausted) {
        if (this.isQuotaExhausted) {
          console.log(`[Processor] Stopped batch because daily quota was exhausted.`);
        } else {
          console.log(`[Processor] Processing paused cleanly. Resume anytime with 'npm run resume' or 'npx tsx src/cli.ts resume'.`);
        }
        break;
      }

      const { book, chapter } = chapters[i];
      const res = await this.processChapter(book, chapter, force);
      if (res === 'completed') completed++;
      else if (res === 'skipped') skipped++;
      else if (res === 'failed') failed++;
    }

    return { completed, skipped, failed };
  }
}
