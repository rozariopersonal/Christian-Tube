import { WordTimestamp, SentenceSegment } from './types.js';

/**
 * Formats a duration in seconds as [HH:]MM:SS
 */
export function fmtTs(sec: number): string {
  const s = Math.max(0, Math.floor(sec));
  const hrs = Math.floor(s / 3600);
  const mins = Math.floor((s % 3600) / 60);
  const secs = s % 60;

  const mm = String(mins).padStart(2, '0');
  const ss = String(secs).padStart(2, '0');

  if (hrs > 0) {
    return `${hrs}:${mm}:${ss}`;
  }
  return `${mm}:${ss}`;
}

/**
 * Checks if a word ends with terminal punctuation (. ? !)
 * handles trailing quotes like ." or .' or )
 */
export function hasTerminalPunctuation(word: string): boolean {
  const stripped = word.replace(/["'»”’)]+$/g, '');
  return (
    stripped.endsWith('.') ||
    stripped.endsWith('?') ||
    stripped.endsWith('!')
  );
}

/**
 * Groups a stream of word-level timestamps into complete, punctuated sentence segments.
 *
 * Slices when:
 * 1. A word ends with terminal punctuation (. ? !), OR
 * 2. There is a conversational pause between words greater than maxPauseSec (default 1.8s)
 */
export function wordsToSentences(
  words: WordTimestamp[],
  maxPauseSec = 1.8
): SentenceSegment[] {
  const sentences: SentenceSegment[] = [];
  let currentWords: string[] = [];
  let sentenceStart: number | null = null;
  let lastEnd = 0;

  for (const item of words) {
    const word = item.word.trim();
    const start = Number(item.start);
    const end = Number(item.end);

    if (!word) {
      continue;
    }

    if (sentenceStart === null) {
      sentenceStart = start;
    }

    // Long pause check: split if speaker paused significantly before this word
    const pause = start - lastEnd;
    if (currentWords.length > 0 && pause > maxPauseSec) {
      sentences.push({
        start: sentenceStart,
        end: lastEnd,
        text: currentWords.join(' '),
      });
      currentWords = [];
      sentenceStart = start;
    }

    currentWords.push(word);
    lastEnd = end;

    // Terminal punctuation check: ends a complete sentence
    if (hasTerminalPunctuation(word)) {
      sentences.push({
        start: sentenceStart,
        end: end,
        text: currentWords.join(' '),
      });
      currentWords = [];
      sentenceStart = null;
    }
  }

  // Flush any remaining words at the end of the audio
  if (currentWords.length > 0 && sentenceStart !== null) {
    sentences.push({
      start: sentenceStart,
      end: lastEnd,
      text: currentWords.join(' '),
    });
  }

  return sentences;
}

/**
 * Formats a list of sentence segments into the standard timestamped transcript:
 * [00:00 00:05] First sentence.
 * [00:05 00:12] Second sentence.
 */
export function buildTranscript(segments: SentenceSegment[]): string {
  return segments
    .map((seg) => `[${fmtTs(seg.start)} ${fmtTs(seg.end)}] ${seg.text.trim()}`)
    .join('\n');
}

export function parseTranscriptSegments(transcript: string): SentenceSegment[] {
  const segments: SentenceSegment[] = [];
  const lines = transcript.split('\n');
  const regex = /\[(\d{1,2}):(\d{2})(?:\s*->\s*|\s+)(\d{1,2}):(\d{2})\]\s*(.*)/;
  for (const line of lines) {
    const m = line.match(regex);
    if (m) {
      const start = parseInt(m[1], 10) * 60 + parseInt(m[2], 10);
      const end = parseInt(m[3], 10) * 60 + parseInt(m[4], 10);
      const text = m[5].trim();
      if (text) {
        segments.push({ start, end, text });
      }
    }
  }
  return segments;
}

