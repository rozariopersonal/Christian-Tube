import { spawn } from 'node:child_process';
import { SilenceInterval } from './types.js';

/**
 * Runs ffprobe or ffmpeg to get the duration of a WAV file in seconds.
 */
export function getWavDuration(wavPath: string): Promise<number> {
  return new Promise((resolve, reject) => {
    const proc = spawn('ffmpeg', ['-i', wavPath], { stdio: ['ignore', 'pipe', 'pipe'] });
    let stderr = '';

    proc.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });

    proc.on('close', () => {
      // Look for "Duration: 00:03:45.12"
      const match = stderr.match(/Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)/i);
      if (match) {
        const hrs = parseInt(match[1], 10);
        const mins = parseInt(match[2], 10);
        const secs = parseFloat(match[3]);
        resolve(hrs * 3600 + mins * 60 + secs);
      } else {
        reject(new Error(`Could not determine WAV duration for ${wavPath}`));
      }
    });

    proc.on('error', (err) => {
      reject(new Error(`Failed to spawn ffmpeg: ${err.message}`));
    });
  });
}

/**
 * Parses stderr output from ffmpeg silencedetect filter.
 */
export function parseSilenceDetectOutput(stderr: string): SilenceInterval[] {
  const intervals: SilenceInterval[] = [];
  const startRegex = /silence_start:\s*(-?\d+(?:\.\d+)?)/g;
  const endRegex = /silence_end:\s*(-?\d+(?:\.\d+)?)\s*\|\s*silence_duration:\s*(\d+(?:\.\d+)?)/g;

  const starts: number[] = [];
  let m: RegExpExecArray | null;

  while ((m = startRegex.exec(stderr)) !== null) {
    starts.push(Math.max(0, parseFloat(m[1])));
  }

  let startIdx = 0;
  while ((m = endRegex.exec(stderr)) !== null) {
    const end = parseFloat(m[1]);
    const start = startIdx < starts.length ? starts[startIdx] : Math.max(0, end - parseFloat(m[2]));
    startIdx++;

    intervals.push({
      start,
      end,
      mid: Math.round(((start + end) / 2) * 100) / 100,
    });
  }

  return intervals;
}

/**
 * Detects silent intervals in an audio file using ffmpeg's silencedetect filter.
 */
export function detectSilences(
  wavPath: string,
  noiseDb = -32,
  minDurationSec = 0.4
): Promise<SilenceInterval[]> {
  return new Promise((resolve, reject) => {
    const args = [
      '-i',
      wavPath,
      '-af',
      `silencedetect=noise=${noiseDb}dB:d=${minDurationSec}`,
      '-f',
      'null',
      '-',
    ];

    const proc = spawn('ffmpeg', args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let stderr = '';

    proc.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });

    proc.on('close', (code) => {
      if (code === 0 || stderr.includes('silence_')) {
        const intervals = parseSilenceDetectOutput(stderr);
        resolve(intervals);
      } else {
        reject(new Error(`ffmpeg silencedetect failed with code ${code}: ${stderr.slice(-300)}`));
      }
    });

    proc.on('error', (err) => {
      reject(new Error(`ffmpeg execution error: ${err.message}`));
    });
  });
}

/**
 * Calculates optimal split timestamps, targeting chunks between minChunkSec and maxChunkSec,
 * cutting strictly during natural speech pauses.
 *
 * Returns an array of boundaries: [0, split1, split2, ..., totalDuration]
 */
export function calculateSplitPoints(
  totalDurationSec: number,
  silences: SilenceInterval[],
  minChunkSec = 60.0,
  maxChunkSec = 180.0
): number[] {
  if (totalDurationSec <= maxChunkSec) {
    return [0, totalDurationSec];
  }

  const splits: number[] = [0];
  let currentStart = 0;

  while (currentStart + maxChunkSec < totalDurationSec) {
    const idealWindowStart = currentStart + minChunkSec;
    const idealWindowEnd = currentStart + maxChunkSec;

    // Find silences within the ideal window
    const candidates = silences.filter(
      (s) => s.mid >= idealWindowStart && s.mid <= idealWindowEnd
    );

    let chosenSplit: number;

    if (candidates.length > 0) {
      // Choose the silence closest to the middle of the ideal window
      const targetMid = (idealWindowStart + idealWindowEnd) / 2;
      candidates.sort((a, b) => Math.abs(a.mid - targetMid) - Math.abs(b.mid - targetMid));
      chosenSplit = candidates[0].mid;
    } else {
      // Fallback 1: look for any silence between idealWindowEnd and 1.3 * maxChunkSec
      const extendedCandidates = silences.filter(
        (s) => s.mid > idealWindowEnd && s.mid <= currentStart + maxChunkSec * 1.3
      );

      if (extendedCandidates.length > 0) {
        chosenSplit = extendedCandidates[0].mid;
      } else {
        // Fallback 2: look for any silence between currentStart + 30s and idealWindowStart
        const earlierCandidates = silences.filter(
          (s) => s.mid >= currentStart + 30.0 && s.mid < idealWindowStart
        );
        if (earlierCandidates.length > 0) {
          chosenSplit = earlierCandidates[earlierCandidates.length - 1].mid;
        } else {
          // Hard cut fallback when speaker speaks without pausing for 3 minutes
          chosenSplit = Math.round((currentStart + maxChunkSec) * 100) / 100;
        }
      }
    }

    if (chosenSplit <= currentStart) {
      chosenSplit = currentStart + maxChunkSec;
    }

    splits.push(chosenSplit);
    currentStart = chosenSplit;
  }

  if (splits[splits.length - 1] < totalDurationSec) {
    splits.push(totalDurationSec);
  }

  return splits;
}

/**
 * Slices a chunk of audio from srcWav and writes it to destWav.
 */
export function sliceWav(
  srcWav: string,
  startSec: number,
  endSec: number,
  destWav: string
): Promise<void> {
  return new Promise((resolve, reject) => {
    const duration = endSec - startSec;
    const args = [
      '-y',
      '-ss',
      String(startSec),
      '-t',
      String(duration),
      '-i',
      srcWav,
      '-ar',
      '16000',
      '-ac',
      '1',
      '-f',
      'wav',
      destWav,
    ];

    const proc = spawn('ffmpeg', args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let stderr = '';

    proc.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });

    proc.on('close', (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`ffmpeg slice failed (code ${code}): ${stderr.slice(-300)}`));
      }
    });

    proc.on('error', (err) => {
      reject(new Error(`Failed to slice audio: ${err.message}`));
    });
  });
}
