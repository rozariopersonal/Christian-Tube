#!/usr/bin/env node
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';
import { Command } from 'commander';
import { TranscriberConfig, VideoRow } from './types.js';
import {
  createDbPool,
  ensureSchema,
  releaseStaleProcessing,
  fetchEligibleVideos,
  fetchOneVideo,
  markProcessing,
  updateProgress,
  markCompleted,
  markFailed,
  batchSaveSentences,
  batchMarkCompleted,
  batchMarkSkipped,
  BatchCompletedItem,
  BatchSkippedItem,
} from './db.js';
import { AsrClient } from './asr_client.js';
import { processVideo } from './transcriber.js';
import { checkPureEnglish } from './language_filter.js';
import { GitTracker } from './git_tracker.js';
import { parseTranscriptSegments } from './sentence_assembler.js';

dotenv.config();

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function loadConfig(): TranscriberConfig {
  const dbUrl = (
    process.env.DIRECT_URL ||
    process.env.DATABASE_URL ||
    ''
  ).trim();

  const priorityChannelIds = (
    process.env.PRIORITY_CHANNEL_IDS || 'UCpZG4Vl2tqg5cIfGMocI2Ag'
  )
    .split(',')
    .map((c) => c.trim())
    .filter(Boolean);

  return {
    dbUrl,
    contentVersion: parseInt(process.env.CONTENT_VERSION || '2', 10),
    pollIntervalSec: parseInt(process.env.POLL_INTERVAL || '300', 10),
    batchLimit: parseInt(process.env.BATCH_LIMIT || '50', 10),
    maxRetries: parseInt(process.env.MAX_RETRIES || '3', 10),
    workDir: process.env.WORK_DIR || path.join(__dirname, '../.work'),
    audioComToken: process.env.AUDIO_COM_TOKEN || '',
    priorityChannelIds,
    pythonBin: process.env.PYTHON_BIN || 'python',
    logSentences: process.env.LOG_SENTENCES !== 'false',
  };
}

async function main() {
  const program = new Command();

  program
    .name('transcriber')
    .description('Fault-tolerant Parakeet transcription tool with silence slicing and GitHub Releases batch tracker')
    .option('--video <id>', 'Process a specific video ID and exit')
    .option('--once', 'Process one batch from the queue and exit')
    .option('--batch <limit>', 'Maximum videos per batch', (val) => parseInt(val, 10))
    .parse(process.argv);

  const options = program.opts();
  const cfg = loadConfig();

  if (options.batch) {
    cfg.batchLimit = options.batch;
  }

  if (!cfg.dbUrl) {
    console.error('Error: DIRECT_URL or DATABASE_URL is required in environment');
    process.exit(1);
  }

  const pool = createDbPool(cfg.dbUrl);
  await ensureSchema(pool);
  await releaseStaleProcessing(pool);

  // Initialize Git Tracker (WAL)
  const releasesDir = process.env.RELEASES_DIR || path.join(cfg.workDir, 'releases');
  const seedDir = process.env.RELEASES_SEED_DIR || '/app/releases-seed';
  const gitTracker = new GitTracker({
    releasesDir,
    seedDir,
    githubRepo: process.env.GITHUB_REPO || 'rozariopersonal/Christian-Tube-Releases',
    githubToken: process.env.GITHUB_TOKEN,
  });

  try {
    gitTracker.init();
  } catch (err: any) {
    console.warn(`[Transcriber] Warning initializing GitTracker: ${err.message}`);
  }

  const runnerScript = path.join(__dirname, 'asr_runner.py');
  const asrClient = new AsrClient(cfg.pythonBin, runnerScript);

  let isStopping = false;

  // In-memory batch buffers
  const completedBuffer: BatchCompletedItem[] = [];
  const skippedBuffer: BatchSkippedItem[] = [];

  const flushBatch = async () => {
    if (completedBuffer.length === 0 && skippedBuffer.length === 0) return;

    console.log(
      `\n[Transcriber] === FLUSHING BATCH (${completedBuffer.length} completed, ${skippedBuffer.length} skipped) ===`
    );

    // 1. Push to GitHub remote (with rebase and retry)
    if (completedBuffer.length > 0) {
      const pushed = await gitTracker.pushWithRetry(5);
      if (!pushed) {
        console.warn('[Transcriber] Warning: Remote push did not succeed, but transcripts are committed locally in WAL.');
      }
    }

    // 2. Batch update Neon DB (sentences first, then video status)
    if (completedBuffer.length > 0) {
      const sentenceCount = await batchSaveSentences(pool, completedBuffer);
      console.log(`[Transcriber] Database updated: ${sentenceCount} sentences saved.`);
      const count = await batchMarkCompleted(pool, completedBuffer);
      console.log(`[Transcriber] Database updated: ${count} videos marked completed.`);
      completedBuffer.length = 0;
    }

    if (skippedBuffer.length > 0) {
      const count = await batchMarkSkipped(pool, skippedBuffer);
      console.log(`[Transcriber] Database updated: ${count} videos marked skipped.`);
      skippedBuffer.length = 0;
    }
  };

  const shutdown = async () => {
    if (isStopping) return;
    console.log('\n[Transcriber] Graceful shutdown requested...');
    isStopping = true;

    try {
      await flushBatch();
    } catch (err: any) {
      console.error('[Transcriber] Error flushing batch during shutdown:', err.message);
    }

    asrClient.close();
    pool.end().finally(() => {
      console.log('[Transcriber] Stopped.');
      process.exit(0);
    });
  };

  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);

  try {
    // 1. Single-video mode
    if (options.video) {
      const video = await fetchOneVideo(pool, options.video);
      if (!video) {
        console.error(`Video ${options.video} not found in database.`);
        process.exit(1);
      }

      const langCheck = checkPureEnglish(video.title || '', video.description || '', video.channelLanguage);
      if (!langCheck.isPureEnglish) {
        console.log(`[Transcriber] Skipping non-pure-English video ${video.id}: ${langCheck.reason}`);
        await markCompleted(
          pool,
          video.id,
          '',
          { skipped: true, reason: langCheck.reason, channelLanguage: video.channelLanguage },
          cfg.contentVersion
        );
        await shutdown();
        return;
      }

      await markProcessing(pool, video.id);
      const result = await processVideo(video, cfg, asrClient);
      const detail = {
        source: result.source,
        maxSec: result.maxSec,
        contentVersion: cfg.contentVersion,
        wordCount: result.wordCount,
        segmentCount: result.segments.length,
        report: result.report || {},
      };

      gitTracker.commitTranscript(video, result.transcript, detail);
      await gitTracker.pushWithRetry(3);
      await markCompleted(pool, video.id, result.transcript, detail, cfg.contentVersion);
      console.log(`[Transcriber] Single video ${video.id} completed.`);
      await shutdown();
      return;
    }

    // 2. Continuous daemon / batch mode
    while (!isStopping) {
      console.log(`[Transcriber] Polling database for eligible videos (batch limit: ${cfg.batchLimit})...`);
      const rows = await fetchEligibleVideos(pool, cfg);

      if (rows.length === 0) {
        // Flush any remaining buffered videos before sleeping/exiting
        await flushBatch();

        if (options.once) {
          console.log('[Transcriber] No eligible videos found. Exiting (--once).');
          break;
        }
        console.log(`[Transcriber] No eligible videos. Sleeping ${cfg.pollIntervalSec}s...`);
        for (let i = 0; i < cfg.pollIntervalSec && !isStopping; i++) {
          await new Promise((r) => setTimeout(r, 1000));
        }
        continue;
      }

      console.log(`[Transcriber] Found ${rows.length} video(s) to process.`);
      for (const video of rows) {
        if (isStopping) break;

        // Crash recovery check: Has this video already been committed to local Git?
        if (gitTracker.hasTranscript(video.id)) {
          const cachedTranscript = gitTracker.readTranscript(video.id) || '';
          const segments = parseTranscriptSegments(cachedTranscript);
          console.log(`[Transcriber] Video ${video.id} already committed in Git tracker (${segments.length} sentences). Queuing for DB update.`);
          completedBuffer.push({
            videoId: video.id,
            transcript: cachedTranscript,
            detail: { source: 'git_cached', contentVersion: cfg.contentVersion },
            contentVersion: cfg.contentVersion,
            segments,
          });

          if (completedBuffer.length + skippedBuffer.length >= cfg.batchLimit) {
            await flushBatch();
          }
          continue;
        }

        // Language check
        const langCheck = checkPureEnglish(video.title || '', video.description || '', video.channelLanguage);
        if (!langCheck.isPureEnglish) {
          console.log(
            `[Transcriber] Skipping non-pure-English video ${video.id} ("${video.title}"): ${langCheck.reason}`
          );
          skippedBuffer.push({
            videoId: video.id,
            reason: langCheck.reason,
            channelLanguage: video.channelLanguage,
            contentVersion: cfg.contentVersion,
          });

          if (completedBuffer.length + skippedBuffer.length >= cfg.batchLimit) {
            await flushBatch();
          }
          continue;
        }

        // Process pure English video
        console.log(`\n------------------------------------------------------------`);
        console.log(`Processing ${video.id}: ${(video.title || '').slice(0, 70)}`);
        console.log(`------------------------------------------------------------`);

        try {
          await markProcessing(pool, video.id);

          const result = await processVideo(video, cfg, asrClient, async (pct) => {
            await updateProgress(pool, video.id, pct);
          });

          const detail = {
            source: result.source,
            maxSec: result.maxSec,
            contentVersion: cfg.contentVersion,
            wordCount: result.wordCount,
            segmentCount: result.segments.length,
            report: result.report || {},
          };

          // 1. Commit immediately to local Git WAL
          gitTracker.commitTranscript(video, result.transcript, detail);

          // 2. Add to batch buffer
          completedBuffer.push({
            videoId: video.id,
            transcript: result.transcript,
            detail,
            contentVersion: cfg.contentVersion,
            segments: result.segments,
          });

          console.log(
            `[Transcriber] Completed ${video.id}: ${result.segments.length} sentences, ${result.wordCount} words (Buffered: ${completedBuffer.length + skippedBuffer.length}/${cfg.batchLimit})`
          );

          // 3. If batch reached limit, flush (push to GitHub + batch update DB)
          if (completedBuffer.length + skippedBuffer.length >= cfg.batchLimit) {
            await flushBatch();
          }
        } catch (err: any) {
          console.error(`[Transcriber] Failed ${video.id}: ${err.message}`);
          await markFailed(pool, video.id, err.message);
        }
      }

      // If finished this batch, flush any remaining items
      await flushBatch();

      if (options.once) {
        console.log('[Transcriber] Batch finished. Exiting (--once).');
        break;
      }
    }
  } finally {
    await shutdown();
  }
}

main().catch((err) => {
  console.error('[Transcriber Fatal Error]', err);
  process.exit(1);
});
