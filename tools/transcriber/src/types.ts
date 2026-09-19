export interface WordTimestamp {
  word: string;
  start: number;
  end: number;
}

export interface SentenceSegment {
  start: number;
  end: number;
  text: string;
}

export interface SilenceInterval {
  start: number;
  end: number;
  mid: number;
}

export interface VideoRow {
  id: string;
  title: string | null;
  description: string | null;
  audioUrl: string | null;
  duration: string | null;
  channelId?: string | null;
  channelLanguage?: string | null;
}

export interface TranscriberConfig {
  dbUrl: string;
  contentVersion: number;
  pollIntervalSec: number;
  batchLimit: number;
  maxRetries: number;
  workDir: string;
  audioComToken: string;
  priorityChannelIds: string[];
  pythonBin: string;
  logSentences: boolean;
}

export interface TranscriptResult {
  source: string;
  transcript: string;
  segments: SentenceSegment[];
  maxSec: number;
  wordCount: number;
  report?: any;
}
