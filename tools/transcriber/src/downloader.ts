import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { pipeline } from 'node:stream/promises';
import { Readable } from 'node:stream';

export function extractAudioId(audioUrl: string): string | null {
  const match = audioUrl.trim().replace(/\/+$/, '').match(/(\d{6,})$/);
  return match ? match[1] : null;
}

/**
 * Resolves an Audio.com landing page URL to its direct CDN stream URL.
 */
export async function resolveStreamUrl(
  pageUrl: string,
  token: string,
  timeoutMs = 30000
): Promise<string> {
  const audioId = extractAudioId(pageUrl);
  if (!audioId) {
    return pageUrl; // Already a direct stream URL
  }

  const cleanToken = token.toLowerCase().startsWith('bearer ') ? token.slice(7).trim() : token.trim();
  const headers: Record<string, string> = {
    Accept: 'application/json',
  };
  if (cleanToken) {
    headers.Authorization = `Bearer ${cleanToken}`;
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const res = await fetch(`https://api.audio.com/v1/audio/view?id=${audioId}`, {
      headers,
      signal: controller.signal,
    });

    if (!res.ok) {
      throw new Error(`Audio.com API returned HTTP ${res.status}: ${await res.text()}`);
    }

    const data = (await res.json()) as any;
    const play = data?.play || {};
    const stream = play.url || play.stream_url || play.streamUrl;

    if (!stream) {
      throw new Error(`Audio.com stream URL not resolvable for ${pageUrl}`);
    }

    return stream;
  } finally {
    clearTimeout(timeout);
  }
}

/**
 * Robust atomic download with retries, exponential backoff, and Content-Length verification.
 */
export async function downloadAudio(
  audioUrl: string,
  destPath: string,
  token = '',
  maxAttempts = 3
): Promise<boolean> {
  const partPath = `${destPath}.part`;
  await fs.promises.mkdir(path.dirname(destPath), { recursive: true });

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      // 1. Freshly resolve stream URL (handles expired tokens/links)
      let resource = audioUrl;
      if (audioUrl.includes('audio.com/')) {
        resource = await resolveStreamUrl(audioUrl, token);
      }

      // 2. Fetch the stream
      const res = await fetch(resource);
      if (!res.ok) {
        throw new Error(`HTTP ${res.status} ${res.statusText}`);
      }

      const contentLengthHeader = res.headers.get('content-length');
      const expectedBytes = contentLengthHeader ? parseInt(contentLengthHeader, 10) : 0;

      if (!res.body) {
        throw new Error('Response body is null');
      }

      // 3. Write stream to temporary .part file
      const fileStream = fs.createWriteStream(partPath);
      // @ts-ignore Node 18+ Web Stream to Node Stream conversion
      const nodeReadable = Readable.fromWeb(res.body);
      await pipeline(nodeReadable, fileStream);

      // 4. Verify file integrity
      const stat = await fs.promises.stat(partPath);
      if (expectedBytes > 0 && stat.size < expectedBytes) {
        throw new Error(`Incomplete download: got ${stat.size} bytes, expected ${expectedBytes}`);
      }

      if (stat.size < 1000) {
        throw new Error(`Downloaded audio file unrealistically small (${stat.size} bytes)`);
      }

      // 5. Atomic rename: only completed, verified files become destPath
      await fs.promises.rename(partPath, destPath);
      return true;
    } catch (err: any) {
      console.warn(`[Transcriber] Download attempt ${attempt}/${maxAttempts} failed: ${err.message}`);
      if (fs.existsSync(partPath)) {
        try {
          await fs.promises.unlink(partPath);
        } catch {}
      }

      if (attempt < maxAttempts) {
        const delayMs = Math.pow(2, attempt) * 1000;
        await new Promise((r) => setTimeout(r, delayMs));
      }
    }
  }

  return false;
}

/**
 * Decodes MP3 audio into 16kHz mono WAV suitable for Parakeet ASR.
 */
export function toWav(mp3Path: string, wavPath: string): Promise<boolean> {
  return new Promise((resolve) => {
    const tmpWav = `${wavPath}.tmp.wav`;
    const args = ['-y', '-i', mp3Path, '-ar', '16000', '-ac', '1', '-f', 'wav', tmpWav];

    const proc = spawn('ffmpeg', args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let stderr = '';

    proc.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });

    proc.on('close', async (code) => {
      if (code === 0 && fs.existsSync(tmpWav)) {
        try {
          await fs.promises.rename(tmpWav, wavPath);
          resolve(true);
        } catch {
          resolve(false);
        }
      } else {
        console.warn(`[Transcriber] ffmpeg to_wav failed: ${stderr.slice(-300)}`);
        if (fs.existsSync(tmpWav)) {
          try {
            await fs.promises.unlink(tmpWav);
          } catch {}
        }
        resolve(false);
      }
    });

    proc.on('error', (err) => {
      console.error(`[Transcriber] ffmpeg spawn failed: ${err.message}`);
      resolve(false);
    });
  });
}
