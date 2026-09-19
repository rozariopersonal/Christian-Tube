import fs from 'node:fs';
import path from 'node:path';
import { WordTimestamp } from './types.js';

export function getCheckpointDir(workDir: string, videoId: string): string {
  return path.join(workDir, 'checkpoints', videoId);
}

export async function saveSplits(checkpointDir: string, splits: number[]): Promise<void> {
  await fs.promises.mkdir(checkpointDir, { recursive: true });
  const splitsFile = path.join(checkpointDir, 'splits.json');
  await fs.promises.writeFile(splitsFile, JSON.stringify(splits, null, 2), 'utf-8');
}

export async function loadSplits(checkpointDir: string): Promise<number[] | null> {
  const splitsFile = path.join(checkpointDir, 'splits.json');
  if (!fs.existsSync(splitsFile)) {
    return null;
  }
  try {
    const raw = await fs.promises.readFile(splitsFile, 'utf-8');
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export function getChunkFileName(chunkIndex: number): string {
  return `chunk_${String(chunkIndex).padStart(4, '0')}.json`;
}

export async function saveChunkWords(
  checkpointDir: string,
  chunkIndex: number,
  words: WordTimestamp[]
): Promise<void> {
  await fs.promises.mkdir(checkpointDir, { recursive: true });
  const chunkFile = path.join(checkpointDir, getChunkFileName(chunkIndex));
  const tmpFile = `${chunkFile}.tmp`;
  await fs.promises.writeFile(tmpFile, JSON.stringify(words), 'utf-8');
  await fs.promises.rename(tmpFile, chunkFile);
}

export async function loadChunkWords(
  checkpointDir: string,
  chunkIndex: number
): Promise<WordTimestamp[] | null> {
  const chunkFile = path.join(checkpointDir, getChunkFileName(chunkIndex));
  if (!fs.existsSync(chunkFile)) {
    return null;
  }
  try {
    const raw = await fs.promises.readFile(chunkFile, 'utf-8');
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export function hasChunkWords(checkpointDir: string, chunkIndex: number): boolean {
  const chunkFile = path.join(checkpointDir, getChunkFileName(chunkIndex));
  return fs.existsSync(chunkFile);
}

export async function cleanCheckpoints(checkpointDir: string): Promise<void> {
  if (fs.existsSync(checkpointDir)) {
    try {
      await fs.promises.rm(checkpointDir, { recursive: true, force: true });
    } catch (err: any) {
      console.warn(`[Transcriber] Failed to remove checkpoint dir ${checkpointDir}: ${err.message}`);
    }
  }
}
