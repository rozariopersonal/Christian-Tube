import { Injectable, inject, signal } from '@angular/core';
import { ReleaseDataService } from '../../../core/api/release-data.service';
import { Song } from '../models/song.model';

interface RawSong {
  id?: unknown;
  title?: unknown;
  titleRoman?: unknown;
  author?: unknown;
  album?: unknown;
  collection?: unknown;
  language?: unknown;
  category?: unknown;
  verses?: unknown;
  versesRoman?: unknown;
  audioUrl?: unknown;
}

function normalizeSong(raw: RawSong): Song {
  const verses = Array.isArray(raw.verses) ? raw.verses.map((v) => String(v)) : [];
  const versesRoman = Array.isArray(raw.versesRoman)
    ? raw.versesRoman.map((v) => String(v))
    : [];
  return {
    id: String(raw.id ?? ''),
    title: String(raw.title ?? ''),
    titleRoman: raw.titleRoman ? String(raw.titleRoman) : undefined,
    author: raw.author ? String(raw.author) : undefined,
    album: raw.album ? String(raw.album) : undefined,
    collection: raw.collection ? String(raw.collection) : undefined,
    language: String(raw.language ?? 'en').trim().toLowerCase() || 'en',
    category: raw.category ? String(raw.category) : undefined,
    verses,
    versesRoman,
    audioUrl: raw.audioUrl ? String(raw.audioUrl) : undefined,
  };
}

@Injectable({ providedIn: 'root' })
export class SongsService {
  private readonly releaseData = inject(ReleaseDataService);
  private readonly songCache = new Map<string, Song>();

  readonly songs = signal<Song[]>([]);
  readonly loading = signal<boolean>(false);
  readonly error = signal<string | null>(null);

  async loadCatalog(force = false): Promise<Song[]> {
    if (!force && this.songs().length > 0) {
      return this.songs();
    }
    this.loading.set(true);
    this.error.set(null);
    try {
      let raw: unknown;
      try {
        raw = await this.releaseData.getJson<unknown>('songs/catalog_lite.json', !force);
      } catch {
        raw = await this.releaseData.getJson<unknown>('songs/catalog.json', !force);
      }
      const list = Array.isArray(raw)
        ? raw
        : raw && typeof raw === 'object' && Array.isArray((raw as { songs?: unknown }).songs)
          ? (raw as { songs: unknown[] }).songs
          : [];
      const parsed = list.map((item) => normalizeSong(item as RawSong)).filter((s) => s.id);
      for (const song of parsed) {
        if (song.verses.length > 0) {
          this.songCache.set(song.id, song);
        }
      }
      this.songs.set(parsed);
      return parsed;
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Unable to load songs catalog';
      this.error.set(msg);
      return [];
    } finally {
      this.loading.set(false);
    }
  }

  async getSong(id: string): Promise<Song | null> {
    const cached = this.songCache.get(id);
    if (cached && cached.verses.length > 0) {
      return cached;
    }
    try {
      const raw = await this.releaseData.getJson<RawSong>(`songs/${encodeURIComponent(id)}.json`);
      const song = normalizeSong(raw);
      if (song.id) {
        this.songCache.set(song.id, song);
        return song;
      }
    } catch {
      // Fallback to catalog item if already loaded
    }
    const catalog = await this.loadCatalog();
    return catalog.find((s) => s.id === id) ?? null;
  }
}
