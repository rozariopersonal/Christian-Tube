import { BibleReader } from './bible_reader.js';
import { OllamaStudyClient } from './ollama_client.js';
import { StatusTracker } from './status_tracker.js';
import { FeedAnalyzer } from './feed_analyzer.js';
import { StudyAnalyzer } from './study_analyzer.js';
import { SpekAnalyzer } from './spek_analyzer.js';
import { AppConfig } from './types.js';
import { createResearchProvider, ResearchProvider, renderBrief } from './research.js';
import { passDirs } from './config.js';

export class ChapterProcessor {
  private config: AppConfig;
  private reader: BibleReader;
  private llm: OllamaStudyClient;
  private researchProvider: ResearchProvider;
  private feedAnalyzer: FeedAnalyzer | null = null;
  private studyTracker: StatusTracker | null = null;
  private spekTracker: StatusTracker | null = null;
  private studyAnalyzer: StudyAnalyzer | null = null;
  private spekAnalyzer: SpekAnalyzer | null = null;
  private isInterrupted = false;

  constructor(config: AppConfig, reader: BibleReader, llm: OllamaStudyClient) {
    this.config = config;
    this.reader = reader;
    this.llm = llm;
    this.researchProvider = createResearchProvider(config);

    if (config.passes.feed.enabled) {
      this.feedAnalyzer = new FeedAnalyzer(config, llm);
    }
    if (config.passes.study.enabled) {
      const dirs = passDirs(config);
      this.studyAnalyzer = new StudyAnalyzer(llm);
      this.studyTracker = new StatusTracker('study', config.version_id, dirs.study.baseDir);
    }
    if (config.passes.spek.enabled) {
      const dirs = passDirs(config);
      this.spekAnalyzer = new SpekAnalyzer(llm);
      this.spekTracker = new StatusTracker('spek', config.version_id, dirs.spek.baseDir);
    }

    process.on('SIGINT', () => {
      console.log('\n[Processor] Interrupt received. Finishing current pass, then exiting cleanly.');
      this.isInterrupted = true;
    });
  }

  public enabledPasses(): string[] {
    const out: string[] = [];
    if (this.config.passes.feed.enabled) out.push('feed');
    if (this.config.passes.study.enabled) out.push('study');
    if (this.config.passes.spek.enabled) out.push('spek');
    return out;
  }

  public getStudyTracker(): StatusTracker | null {
    return this.studyTracker;
  }

  public getSpekTracker(): StatusTracker | null {
    return this.spekTracker;
  }

  public getResearchProviderName(): string {
    return this.researchProvider.name;
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  /**
   * Runs all enabled passes for one chapter. Returns per-pass results.
   */
  public async processChapter(
    book: number,
    chapter: number,
    force = false
  ): Promise<Record<string, 'skipped' | 'completed' | 'cached' | 'failed' | 'empty'>> {
    const results: Record<string, any> = {};
    const dryRun = this.config.processing.dry_run;

    // ---- Pass 1: feed ---------------------------------------------------
    if (this.feedAnalyzer && this.config.passes.feed.enabled) {
      const src = this.config.passes.feed.source_version;
      const chap = await this.reader.getChapter(book, chapter, src);
      if (!chap) {
        results.feed = 'failed';
        console.error(`[Feed] Chapter data missing for ${book}:${chapter} (${src}).`);
      } else if (dryRun) {
        results.feed = 'completed';
        console.log(`[Feed] dry-run skipped Book ${book} Chapter ${chapter}.`);
      } else {
        const bookName = this.reader.getBookName(book);
        const res = await this.feedAnalyzer.analyzeChapter(chap, bookName, force);
        results.feed = res;
      }
    }

    // ---- Pass 2: study --------------------------------------------------
    if (this.studyAnalyzer && this.studyTracker && this.config.passes.study.enabled) {
      if (!force && this.studyTracker.isChapterCompleted(book, chapter)) {
        results.study = 'skipped';
      } else {
        const src = this.config.passes.study.source_version;
        const chap = await this.reader.getChapter(book, chapter, src);
        if (!chap) {
          results.study = 'failed';
          this.studyTracker.markFailed(book, chapter, `Chapter data missing (${src})`);
          console.error(`[Study] Chapter data missing for ${book}:${chapter} (${src}).`);
        } else if (dryRun) {
          results.study = 'skipped';
          console.log(`[Study] dry-run skipped Book ${book} Chapter ${chapter}.`);
        } else {
          console.log(`[Study] Processing Book ${book} (${chap.book_name}) Chapter ${chapter} (${chap.verses.length} verses)...`);
          this.studyTracker.markStarted(book, chapter, this.llm.model());
          try {
            const { output, inputTokens, outputTokens } = await this.studyAnalyzer.analyzeChapter(chap);
            this.studyTracker.markCompleted(book, chapter, output, output.terms?.length || 0, { inputTokens, outputTokens });
            console.log(`[Study] Completed Book ${book} Chapter ${chapter}: ${output.terms?.length || 0} terms (${inputTokens ?? 0} in, ${outputTokens ?? 0} out).`);
            results.study = 'completed';
          } catch (err: any) {
            this.studyTracker.markFailed(book, chapter, err.message);
            results.study = 'failed';
          }
        }
      }
    }

    // ---- Pass 3: spek ---------------------------------------------------
    if (this.spekAnalyzer && this.spekTracker && this.config.passes.spek.enabled) {
      if (!force && this.spekTracker.isChapterCompleted(book, chapter)) {
        results.spek = 'skipped';
      } else {
        const src = this.config.passes.spek.source_version;
        const chap = await this.reader.getChapter(book, chapter, src);
        if (!chap) {
          results.spek = 'failed';
          this.spekTracker.markFailed(book, chapter, `Chapter data missing (${src})`);
          console.error(`[Spek] Chapter data missing for ${book}:${chapter} (${src}).`);
        } else if (dryRun) {
          results.spek = 'skipped';
          console.log(`[Spek] dry-run skipped Book ${book} Chapter ${chapter}.`);
        } else {
          console.log(`[Spek] Processing Book ${book} (${chap.book_name}) Chapter ${chapter} (${chap.verses.length} verses)...`);
          this.spekTracker.markStarted(book, chapter, this.llm.model());
          try {
            let brief: string | null = null;
            if (this.researchProvider.name !== 'none') {
              console.log(`[Spek]   Researching via ${this.researchProvider.name}...`);
              const research = await this.researchProvider.research(chap);
              if (research.error) {
                console.warn(`[Spek]   Research error (${research.error}). Continuing without brief.`);
              } else {
                brief = renderBrief(research);
              }
            }
            const { output, inputTokens, outputTokens } = await this.spekAnalyzer.analyzeChapter(chap, brief);
            this.spekTracker.markCompleted(book, chapter, output, output.verses?.length || 0, { inputTokens, outputTokens });
            console.log(`[Spek] Completed Book ${book} Chapter ${chapter}: ${output.verses?.length || 0} verses analyzed (${inputTokens ?? 0} in, ${outputTokens ?? 0} out).`);
            results.spek = 'completed';
          } catch (err: any) {
            this.spekTracker.markFailed(book, chapter, err.message);
            results.spek = 'failed';
          }
        }
      }
    }

    if (this.config.processing.pause_between_requests_ms > 0 && !dryRun) {
      await this.sleep(this.config.processing.pause_between_requests_ms);
    }

    return results;
  }

  /**
   * Processes a list of chapters with pause/resume (SIGINT-safe).
   */
  public async processBatch(
    chapters: Array<{ book: number; chapter: number }>,
    force = false
  ): Promise<{ completed: number; skipped: number; failed: number; processed: number }> {
    let completed = 0;
    let skipped = 0;
    let failed = 0;
    let processed = 0;

    for (const { book, chapter } of chapters) {
      if (this.isInterrupted) {
        console.log('[Processor] Paused cleanly. Resume later with `resume`.');
        break;
      }
      processed++;
      const res = await this.processChapter(book, chapter, force);
      const values = Object.values(res);
      if (values.every((v) => v === 'skipped')) skipped++;
      else if (values.some((v) => v === 'failed') && !values.some((v) => v === 'completed' || v === 'cached')) failed++;
      else completed++;
    }

    return { completed, skipped, failed, processed };
  }

  public emitFeed(dryRun: boolean, opts?: { allowPartial?: boolean }) {
    if (!this.feedAnalyzer) return;
    const bookNames: Record<number, string> = {};
    for (let b = 1; b <= 66; b++) bookNames[b] = this.reader.getBookName(b);
    this.feedAnalyzer.emitScripture(bookNames, dryRun, { ...opts, expectedChapters: this.reader.getAllChapters().length });
  }

  public feedCachedChapters(): number {
    return this.feedAnalyzer ? this.feedAnalyzer.cachedChapters() : 0;
  }
}