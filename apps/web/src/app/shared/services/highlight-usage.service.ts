import { Injectable } from '@angular/core';
import {
  DEFAULT_TOP_SWATCH_INDICES,
  HIGHLIGHT_PALETTE,
  HighlightSwatch,
  findSwatchByHex,
} from '../ui/highlight-palette';

const STORAGE_KEY = 'highlight_color_usage_v1';

interface UsageEntry {
  count: number;
  lastUsed: number;
}

/**
 * Tracks how often each highlight swatch is used so the reader selection
 * popover surfaces the user's top 3 colours first.
 */
@Injectable({ providedIn: 'root' })
export class HighlightUsageService {
  private readonly usage = new Map<number, UsageEntry>();
  private tick = 0;
  private loaded = false;

  private ensureLoaded(): void {
    if (this.loaded) return;
    this.loaded = true;
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return;
      const parsed = JSON.parse(raw) as Record<string, [number, number]>;
      for (const [key, val] of Object.entries(parsed)) {
        const idx = Number(key);
        if (
          !Number.isInteger(idx) ||
          idx < 0 ||
          idx >= HIGHLIGHT_PALETTE.length ||
          !Array.isArray(val) ||
          val.length !== 2
        ) {
          continue;
        }
        const count = Number(val[0]) || 0;
        const lastUsed = Number(val[1]) || 0;
        this.usage.set(idx, { count, lastUsed });
        if (lastUsed > this.tick) this.tick = lastUsed;
      }
    } catch {
      // Ignore corrupt or unavailable localStorage.
    }
  }

  record(hexOrIndex: string | number): void {
    this.ensureLoaded();
    const index =
      typeof hexOrIndex === 'number'
        ? hexOrIndex
        : findSwatchByHex(hexOrIndex)?.index;
    if (index === undefined || index < 0 || index >= HIGHLIGHT_PALETTE.length) {
      return;
    }
    const prev = this.usage.get(index);
    this.usage.set(index, {
      count: (prev?.count ?? 0) + 1,
      lastUsed: ++this.tick,
    });
    this.persist();
  }

  topSwatches(n = 3): HighlightSwatch[] {
    this.ensureLoaded();
    const sortedIndices = [...this.usage.entries()]
      .sort((a, b) => {
        const byCount = b[1].count - a[1].count;
        if (byCount !== 0) return byCount;
        return b[1].lastUsed - a[1].lastUsed;
      })
      .map(([idx]) => idx);

    const chosen: number[] = sortedIndices.slice(0, n);
    for (const d of DEFAULT_TOP_SWATCH_INDICES) {
      if (chosen.length >= n) break;
      if (!chosen.includes(d)) chosen.push(d);
    }
    for (let i = 0; chosen.length < n && i < HIGHLIGHT_PALETTE.length; i++) {
      if (!chosen.includes(i)) chosen.push(i);
    }
    return chosen.map((idx) => HIGHLIGHT_PALETTE[idx]);
  }

  resetForTest(): void {
    this.usage.clear();
    this.tick = 0;
    this.loaded = false;
  }

  private persist(): void {
    try {
      const out: Record<string, [number, number]> = {};
      for (const [idx, entry] of this.usage.entries()) {
        out[String(idx)] = [entry.count, entry.lastUsed];
      }
      localStorage.setItem(STORAGE_KEY, JSON.stringify(out));
    } catch {
      // Ignore storage quota errors.
    }
  }
}
