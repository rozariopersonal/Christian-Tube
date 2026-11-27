import { Injectable, signal } from '@angular/core';

const AUTO_FULLSCREEN_KEY = 'reader-auto-fullscreen-seconds';

/** Coordinates app-viewport fullscreen and idle auto-entry for web readers. */
@Injectable({ providedIn: 'root' })
export class ReaderFullscreenService {
  readonly activeReader = signal<string | null>(null);
  readonly autoFullscreenSeconds = signal<number>(this.readPreference());

  private owner: string | null = null;
  private autoEnter?: () => void;
  private idleTimer?: ReturnType<typeof setTimeout>;

  registerReader(readerId: string, autoEnter: () => void): () => void {
    this.clearIdleTimer();
    this.owner = readerId;
    this.autoEnter = autoEnter;
    this.activeReader.set(null);
    this.scheduleAutoEntry();
    return () => this.unregisterReader(readerId);
  }

  unregisterReader(readerId: string): void {
    if (this.owner !== readerId) return;
    this.clearIdleTimer();
    this.owner = null;
    this.autoEnter = undefined;
    this.activeReader.set(null);
  }

  setFullscreen(readerId: string, fullscreen: boolean): void {
    if (this.owner !== readerId) return;
    this.clearIdleTimer();
    this.activeReader.set(fullscreen ? readerId : null);
    if (!fullscreen) this.scheduleAutoEntry();
  }

  noteActivity(readerId: string): void {
    if (this.owner !== readerId || this.activeReader() === readerId) return;
    this.scheduleAutoEntry();
  }

  toggleAutoFullscreen(): void {
    const delays = [0, 30, 60, 120];
    const current = this.autoFullscreenSeconds();
    const next = delays[(delays.indexOf(current) + 1) % delays.length];
    this.setAutoFullscreenSeconds(next);
  }

  setAutoFullscreenSeconds(seconds: number): void {
    this.autoFullscreenSeconds.set(seconds);
    try {
      localStorage.setItem(AUTO_FULLSCREEN_KEY, String(seconds));
    } catch {
      // The setting remains active in memory when storage is unavailable.
    }
    this.scheduleAutoEntry();
  }

  private scheduleAutoEntry(): void {
    this.clearIdleTimer();
    const delay = this.autoFullscreenSeconds();
    if (!this.owner || !this.autoEnter || delay <= 0 || this.activeReader() === this.owner) {
      return;
    }
    const owner = this.owner;
    this.idleTimer = setTimeout(() => {
      if (this.owner === owner && this.activeReader() !== owner) this.autoEnter?.();
    }, delay * 1000);
  }

  private clearIdleTimer(): void {
    if (this.idleTimer) clearTimeout(this.idleTimer);
    this.idleTimer = undefined;
  }

  private readPreference(): number {
    try {
      const value = Number(localStorage.getItem(AUTO_FULLSCREEN_KEY) ?? 0);
      return [0, 30, 60, 120].includes(value) ? value : 0;
    } catch {
      return 0;
    }
  }
}
