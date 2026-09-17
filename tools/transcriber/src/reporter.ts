import fs from 'node:fs';
import path from 'node:path';
import { fmtTs } from './sentence_assembler.js';
import { SentenceSegment } from './types.js';

export interface TranscriptionReportData {
  videoId: string;
  title: string;
  audioDurationSec: number;
  downloadTimeMs: number;
  inferenceTimeMs: number;
  totalTimeMs: number;
  silenceCount: number;
  chunkCount: number;
  wordCount: number;
  segments: SentenceSegment[];
}

export interface FormattedReport {
  summary: {
    videoId: string;
    title: string;
    duration: string;
    durationSec: number;
    downloadTimeSec: number;
    inferenceTimeSec: number;
    totalTimeSec: number;
    speedFactor: string;
    silenceCount: number;
    chunkCount: number;
    sentenceCount: number;
    wordCount: number;
    avgWordsPerSentence: number;
    wpm: number;
  };
  sampleSentences: Array<{ time: string; text: string }>;
}

export function buildReport(data: TranscriptionReportData): FormattedReport {
  const durationSec = Math.max(1, Math.round(data.audioDurationSec));
  const totalTimeSec = Math.round((data.totalTimeMs / 1000) * 10) / 10;
  const inferenceSec = Math.round((data.inferenceTimeMs / 1000) * 10) / 10;
  const downloadSec = Math.round((data.downloadTimeMs / 1000) * 10) / 10;

  const speedMultiplier = inferenceSec > 0 ? (durationSec / inferenceSec).toFixed(1) : 'N/A';
  const avgWordsPerSentence =
    data.segments.length > 0 ? Math.round((data.wordCount / data.segments.length) * 10) / 10 : 0;
  const minutes = durationSec / 60;
  const wpm = minutes > 0 ? Math.round(data.wordCount / minutes) : 0;

  const samples: Array<{ time: string; text: string }> = [];
  if (data.segments.length <= 6) {
    for (const s of data.segments) {
      samples.push({ time: `[${fmtTs(s.start)} -> ${fmtTs(s.end)}]`, text: s.text });
    }
  } else {
    // First 3
    for (let i = 0; i < 3; i++) {
      const s = data.segments[i];
      samples.push({ time: `[${fmtTs(s.start)} -> ${fmtTs(s.end)}]`, text: s.text });
    }
    // Last 3
    for (let i = data.segments.length - 3; i < data.segments.length; i++) {
      const s = data.segments[i];
      samples.push({ time: `[${fmtTs(s.start)} -> ${fmtTs(s.end)}]`, text: s.text });
    }
  }

  return {
    summary: {
      videoId: data.videoId,
      title: data.title,
      duration: fmtTs(durationSec),
      durationSec,
      downloadTimeSec: downloadSec,
      inferenceTimeSec: inferenceSec,
      totalTimeSec,
      speedFactor: `${speedMultiplier}x`,
      silenceCount: data.silenceCount,
      chunkCount: data.chunkCount,
      sentenceCount: data.segments.length,
      wordCount: data.wordCount,
      avgWordsPerSentence,
      wpm,
    },
    sampleSentences: samples,
  };
}

export function printConsoleReport(report: FormattedReport): void {
  const s = report.summary;
  const line = '─'.repeat(76);
  const dblLine = '═'.repeat(76);

  console.log(`\n${dblLine}`);
  console.log(`                     TRANSCRIPTION REPORT`);
  console.log(`${dblLine}`);
  console.log(`Video ID:        ${s.videoId}`);
  console.log(`Title:           ${s.title.slice(0, 60)}`);
  console.log(`Audio Duration:  ${s.duration} (${s.durationSec}s)`);
  console.log(`Silence Chunks:  ${s.chunkCount} chunks (${s.silenceCount} natural pauses detected)`);
  console.log(`${line}`);
  console.log(`Timing & Speed:`);
  console.log(`  • Download:    ${s.downloadTimeSec}s`);
  console.log(`  • ASR Time:    ${s.inferenceTimeSec}s  (${s.speedFactor} real-time speed)`);
  console.log(`  • Total Wall:  ${s.totalTimeSec}s`);
  console.log(`${line}`);
  console.log(`Sentence Formations:`);
  console.log(`  • Sentences:   ${s.sentenceCount} formed`);
  console.log(`  • Words:       ${s.wordCount} words total`);
  console.log(`  • Density:     ~${s.avgWordsPerSentence} words / sentence`);
  console.log(`  • Speech Rate: ~${s.wpm} WPM`);
  console.log(`${line}`);
  console.log(`Sample Formations:`);
  for (const sample of report.sampleSentences) {
    console.log(`  ${sample.time.padEnd(20)} ${sample.text.slice(0, 52)}`);
  }
  console.log(`${dblLine}\n`);
}

export async function saveFileReports(
  workDir: string,
  report: FormattedReport,
  allSegments: SentenceSegment[]
): Promise<void> {
  const reportsDir = path.join(workDir, 'reports');
  await fs.promises.mkdir(reportsDir, { recursive: true });

  const s = report.summary;

  // 1. JSON Report
  const jsonPath = path.join(reportsDir, `${s.videoId}.json`);
  const payload = {
    ...report,
    sentences: allSegments,
  };
  await fs.promises.writeFile(jsonPath, JSON.stringify(payload, null, 2), 'utf-8');

  // 2. Markdown Report
  const mdPath = path.join(reportsDir, `${s.videoId}.md`);
  const mdLines = [
    `# Transcription Report: ${s.title}`,
    ``,
    `- **Video ID**: \`${s.videoId}\``,
    `- **Duration**: ${s.duration} (${s.durationSec}s)`,
    `- **Speed**: ${s.speedFactor} real-time (${s.inferenceTimeSec}s inference, ${s.totalTimeSec}s total)`,
    `- **Silence Chunks**: ${s.chunkCount} chunks (${s.silenceCount} pauses detected)`,
    `- **Word Count**: ${s.wordCount} words`,
    `- **Sentence Count**: ${s.sentenceCount} sentences (~${s.avgWordsPerSentence} words/sentence)`,
    `- **Speech Rate**: ~${s.wpm} WPM`,
    ``,
    `## Transcript`,
    ``,
    ...allSegments.map((seg) => `- **[${fmtTs(seg.start)} - ${fmtTs(seg.end)}]** ${seg.text}`),
    ``,
  ];
  await fs.promises.writeFile(mdPath, mdLines.join('\n'), 'utf-8');
}
