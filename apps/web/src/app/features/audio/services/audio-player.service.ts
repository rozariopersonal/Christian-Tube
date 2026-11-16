import { Injectable, computed, inject, signal } from '@angular/core';
import { AudioTrack } from '../models/audio.model';
import { AudioLibraryService } from './audio-library.service';

const KEY_LAST_TRACK = 'audio_last_track';

@Injectable({ providedIn: 'root' })
export class AudioPlayerService {
  private readonly library = inject(AudioLibraryService);
  private readonly audio =
    typeof Audio !== 'undefined' ? new Audio() : null;

  readonly currentTrack = signal<AudioTrack | null>(this.readLastTrack());
  readonly queue = signal<AudioTrack[]>([]);
  readonly isPlaying = signal<boolean>(false);
  readonly position = signal<number>(0);
  readonly duration = signal<number>(0);
  readonly playbackRate = signal<number>(1);
  readonly expanded = signal<boolean>(false);
  readonly error = signal<string | null>(null);

  readonly progressPercent = computed(() => {
    const d = this.duration();
    return d > 0 ? Math.min(100, (this.position() / d) * 100) : 0;
  });

  constructor() {
    if (this.audio) {
      this.audio.preload = 'auto';
      this.audio.addEventListener('timeupdate', () => {
        this.position.set(this.audio!.currentTime || 0);
      });
      this.audio.addEventListener('loadedmetadata', () => {
        this.duration.set(
          this.audio!.duration || this.currentTrack()?.durationSeconds || 0,
        );
      });
      this.audio.addEventListener('play', () => {
        this.error.set(null);
        this.isPlaying.set(true);
      });
      this.audio.addEventListener('pause', () => this.isPlaying.set(false));
      this.audio.addEventListener('ended', () => this.next());
      this.audio.addEventListener('error', () => {
        this.isPlaying.set(false);
        this.error.set('Unable to play this audio track.');
      });
    }
  }

  playTrack(track: AudioTrack, queue: AudioTrack[] = []): void {
    this.error.set(null);
    this.currentTrack.set(track);
    if (queue.length > 0) {
      this.queue.set(queue);
    }
    this.saveLastTrack(track);
    if (!this.audio) return;

    const src = this.library.resolveStreamUrl(
      track.id,
      track.streamUrl || track.audioUrl,
    );
    if (this.audio.src !== src) {
      this.audio.src = src;
      this.audio.load();
    }
    this.audio.playbackRate = this.playbackRate();
    void this.audio.play().catch((err: unknown) => {
      this.isPlaying.set(false);
      if (err instanceof DOMException && err.name === 'AbortError') return;
      this.error.set(
        err instanceof Error ? err.message : 'Unable to play this audio track.',
      );
    });
  }

  togglePlay(): void {
    const track = this.currentTrack();
    if (!this.audio || !track) return;
    if (!this.audio.src) {
      this.playTrack(track, this.queue());
      return;
    }
    if (this.audio.paused) {
      this.error.set(null);
      void this.audio.play().catch((err: unknown) => {
        this.isPlaying.set(false);
        this.error.set(
          err instanceof Error ? err.message : 'Unable to play this audio track.',
        );
      });
    } else {
      this.audio.pause();
    }
  }

  seekTo(seconds: number): void {
    if (!this.audio) return;
    this.audio.currentTime = seconds;
    this.position.set(seconds);
  }

  setRate(rate: number): void {
    this.playbackRate.set(rate);
    if (this.audio) {
      this.audio.playbackRate = rate;
    }
  }

  next(): void {
    const q = this.queue();
    const cur = this.currentTrack();
    if (!cur || q.length === 0) return;
    const idx = q.findIndex((t) => t.id === cur.id);
    if (idx >= 0 && idx + 1 < q.length) {
      this.playTrack(q[idx + 1], q);
    } else {
      this.isPlaying.set(false);
    }
  }

  previous(): void {
    const q = this.queue();
    const cur = this.currentTrack();
    if (!cur || q.length === 0) return;
    const idx = q.findIndex((t) => t.id === cur.id);
    if (idx > 0) {
      this.playTrack(q[idx - 1], q);
    } else {
      this.seekTo(0);
    }
  }

  private saveLastTrack(track: AudioTrack): void {
    try {
      localStorage.setItem(KEY_LAST_TRACK, JSON.stringify(track));
    } catch {
      // ignore
    }
  }

  private readLastTrack(): AudioTrack | null {
    try {
      const raw = localStorage.getItem(KEY_LAST_TRACK);
      return raw ? (JSON.parse(raw) as AudioTrack) : null;
    } catch {
      return null;
    }
  }
}
