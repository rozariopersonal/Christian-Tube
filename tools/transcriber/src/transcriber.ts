import fs from 'node:fs';
import path from 'node:path';
import { VideoRow, TranscriberConfig, TranscriptResult, WordTimestamp } from './types.js';
import { AsrClient } from './asr_client.js';
import { downloadAudio, toWav } from './downloader.js';
import { detectSilences, calculateSplitPoints, sliceWav, getWavDuration } from './silence.js';
import {
  getCheckpointDir,
  loadSplits,
  saveSplits,
  hasChunkWords,
  loadChunkWords,
  saveChunkWords,
  cleanCheckpoints,
} from './checkpoint.js';
import { wordsToSentences, buildTranscript, fmtTs } from './sentence_assembler.js';
import { buildReport, printConsoleReport, saveFileReports } from './reporter.js';
import { checkPureEnglish } from './language_filter.js';

export async function processVideo(
  video: VideoRow,
  cfg: TranscriberConfig,
  asrClient: AsrClient,
  onProgress?: (percent: number) => Promise<void>
): Promise<TranscriptResult> {
  const langCheck = checkPureEnglish(video.title, video.description);
  if (!langCheck.isPureEnglish) {
    throw new Error(`Video ${video.id} skipped: ${langCheck.reason}`);
  }

  if (!video.audioUrl) {
    throw new Error(`Video ${video.id} has no audioUrl`);
  }

  const checkpointDir = getCheckpointDir(cfg.workDir, video.id);
  const mp3Path = path.join(cfg.workDir, `${video.id}.mp3`);
  const wavPath = path.join(cfg.workDir, `${video.id}.wav`);

  const startTime = Date.now();
  let downloadTimeMs = 0;
  let inferenceTimeMs = 0;
  let silenceCount = 0;

  try {
    // 1. Download & decode to WAV (reuse if already downloaded from interrupted run)
    if (!fs.existsSync(wavPath)) {
      console.log(`[Transcriber] Downloading audio for ${video.id}...`);
      const d0 = Date.now();
      const downloaded = await downloadAudio(video.audioUrl, mp3Path, cfg.audioComToken);
      if (!downloaded) {
        throw new Error(`Failed to download audio for video ${video.id}`);
      }

      console.log(`[Transcriber] Decoding MP3 to 16kHz WAV...`);
      const decoded = await toWav(mp3Path, wavPath);
      if (!decoded) {
        throw new Error(`Failed to convert audio to WAV for video ${video.id}`);
      }
      downloadTimeMs = Date.now() - d0;

      // Cleanup MP3 early to save disk space
      try {
        await fs.promises.unlink(mp3Path);
      } catch {}
    } else {
      console.log(`[Transcriber] Found existing WAV for ${video.id}, skipping download.`);
    }

    // 2. Determine duration
    const totalDuration = await getWavDuration(wavPath);
    console.log(`[Transcriber] Audio duration: ${totalDuration.toFixed(1)}s`);

    // 3. Load or compute silence-based split points
    let splits = await loadSplits(checkpointDir);
    if (!splits) {
      console.log(`[Transcriber] Detecting speech pauses with ffmpeg...`);
      const silences = await detectSilences(wavPath);
      silenceCount = silences.length;
      console.log(`[Transcriber] Found ${silences.length} silence intervals`);

      splits = calculateSplitPoints(totalDuration, silences, 60.0, 180.0);
      await saveSplits(checkpointDir, splits);
      console.log(`[Transcriber] Divided into ${splits.length - 1} natural chunks`);
    } else {
      console.log(`[Transcriber] Resuming with existing ${splits.length - 1} splits from checkpoint`);
    }

    const totalChunks = splits.length - 1;
    const allWords: WordTimestamp[] = [];

    // 4. Transcribe each chunk (with checkpointing)
    for (let i = 0; i < totalChunks; i++) {
      const startSec = splits[i];
      const endSec = splits[i + 1];

      let chunkWords: WordTimestamp[] | null = null;

      if (hasChunkWords(checkpointDir, i)) {
        chunkWords = await loadChunkWords(checkpointDir, i);
        if (chunkWords) {
          const sliceText = chunkWords.map((w) => w.word).join(' ');
          console.log(
            `[Transcriber] [${i + 1}/${totalChunks}] Loaded from checkpoint (${startSec.toFixed(1)}s - ${endSec.toFixed(1)}s | ${chunkWords.length} words):`
          );
          console.log(`  "${sliceText}"\n`);
        }
      }

      if (!chunkWords) {
        const chunkWav = path.join(checkpointDir, `chunk_${i}.wav`);
        try {
          console.log(
            `[Transcriber] [${i + 1}/${totalChunks}] Slicing & transcribing (${startSec.toFixed(1)}s - ${endSec.toFixed(1)}s)...`
          );
          await sliceWav(wavPath, startSec, endSec, chunkWav);
          const tInf0 = Date.now();
          chunkWords = await asrClient.transcribeChunk(chunkWav, startSec);
          inferenceTimeMs += Date.now() - tInf0;
          await saveChunkWords(checkpointDir, i, chunkWords);

          const sliceText = chunkWords.map((w) => w.word).join(' ');
          console.log(
            `[Transcriber] [${i + 1}/${totalChunks}] Slice Transcript (${startSec.toFixed(1)}s - ${endSec.toFixed(1)}s | ${chunkWords.length} words):`
          );
          console.log(`  "${sliceText}"\n`);
        } finally {
          if (fs.existsSync(chunkWav)) {
            try {
              await fs.promises.unlink(chunkWav);
            } catch {}
          }
        }
      }

      allWords.push(...chunkWords);

      // Report live progress
      const progressPercent = Math.min(95, Math.round(((i + 1) / totalChunks) * 90 + 5));
      if (onProgress) {
        await onProgress(progressPercent);
      }
    }

    // 5. Assemble complete sentences from all words
    console.log(`[Transcriber] Assembling complete sentences from ${allWords.length} words...`);
    const segments = wordsToSentences(allWords, 1.8);
    const transcript = buildTranscript(segments);

    if (cfg.logSentences) {
      console.log(`\n--- Formed Sentences (${segments.length}) ---`);
      for (const seg of segments) {
        console.log(`  [${fmtTs(seg.start)} -> ${fmtTs(seg.end)}] ${seg.text}`);
      }
      console.log(`--------------------------------------------\n`);
    }

    const maxSec = segments.reduce((max, seg) => Math.max(max, seg.end), totalDuration);
    const totalTimeMs = Date.now() - startTime;

    // 6. Build and log comprehensive report
    const report = buildReport({
      videoId: video.id,
      title: video.title || 'Untitled',
      audioDurationSec: totalDuration,
      downloadTimeMs,
      inferenceTimeMs,
      totalTimeMs,
      silenceCount,
      chunkCount: totalChunks,
      wordCount: allWords.length,
      segments,
    });

    printConsoleReport(report);
    await saveFileReports(cfg.workDir, report, segments);

    // 7. Cleanup working files and checkpoints on success
    try {
      if (fs.existsSync(wavPath)) await fs.promises.unlink(wavPath);
      if (fs.existsSync(mp3Path)) await fs.promises.unlink(mp3Path);
      await cleanCheckpoints(checkpointDir);
    } catch {}

    return {
      source: 'parakeet',
      transcript,
      segments,
      maxSec: Math.round(maxSec * 100) / 100,
      wordCount: allWords.length,
      report: report.summary,
    };
  } catch (err: any) {
    // Keep checkpoints and wav on error so resume works on retry
    throw err;
  }
}
