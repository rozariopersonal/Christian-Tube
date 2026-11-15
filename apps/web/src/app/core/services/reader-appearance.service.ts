import { Injectable, inject, signal } from '@angular/core';
import { ReleaseDataService } from '../api/release-data.service';
import { AppConfig } from '../config/app-config';

export interface ReaderFontOption {
  id: string;
  label: string;
  cssFamily: string;
  releaseFile?: string;
}

export const READER_FONTS: readonly ReaderFontOption[] = [
  { id: 'system', label: 'System Sans', cssFamily: "'Inter', system-ui, sans-serif" },
  {
    id: 'literata',
    label: 'Literata (Serif)',
    cssFamily: "'Literata', Georgia, serif",
    releaseFile: 'Literata_Regular.ttf',
  },
  {
    id: 'merriweather',
    label: 'Merriweather (Serif)',
    cssFamily: "'Merriweather', Georgia, serif",
    releaseFile: 'Merriweather_Regular.ttf',
  },
  {
    id: 'noto-tamil',
    label: 'Noto Sans Tamil',
    cssFamily: "'Noto Sans Tamil', 'Inter', sans-serif",
    releaseFile: 'NotoSansTamil_Regular.ttf',
  },
];

const KEY_FONT_ID = 'reader_font_id';
const KEY_FONT_SIZE = 'reader_font_size';
const KEY_LINE_HEIGHT = 'reader_line_height';
const KEY_PRIMARY_BIBLE = 'primary_bible_version';

@Injectable({ providedIn: 'root' })
export class ReaderAppearanceService {
  private readonly releases = inject(ReleaseDataService);

  readonly fontId = signal<string>(this.readStr(KEY_FONT_ID, 'system'));
  readonly fontSize = signal<number>(this.readNum(KEY_FONT_SIZE, 17, 13, 28));
  readonly lineHeight = signal<number>(this.readNum(KEY_LINE_HEIGHT, 1.65, 1.3, 2.2));
  readonly primaryBibleVersion = signal<string>(
    this.readStr(KEY_PRIMARY_BIBLE, AppConfig.defaultBibleVersion),
  );

  constructor() {
    const initialFont = READER_FONTS.find((f) => f.id === this.fontId());
    if (initialFont?.releaseFile) {
      void this.releases.loadFont(initialFont.label.split(' ')[0], initialFont.releaseFile);
    }
  }

  activeFont(): ReaderFontOption {
    return READER_FONTS.find((f) => f.id === this.fontId()) ?? READER_FONTS[0];
  }

  setFont(id: string): void {
    const opt = READER_FONTS.find((f) => f.id === id) ?? READER_FONTS[0];
    this.fontId.set(opt.id);
    this.writeStr(KEY_FONT_ID, opt.id);
    if (opt.releaseFile) {
      const familyName = opt.cssFamily.split(',')[0].replace(/['"]/g, '').trim();
      void this.releases.loadFont(familyName, opt.releaseFile);
    }
  }

  setFontSize(size: number): void {
    const clamped = Math.min(28, Math.max(13, Math.round(size)));
    this.fontSize.set(clamped);
    this.writeStr(KEY_FONT_SIZE, String(clamped));
  }

  setLineHeight(lh: number): void {
    const clamped = Math.min(2.2, Math.max(1.3, Number(lh.toFixed(2))));
    this.lineHeight.set(clamped);
    this.writeStr(KEY_LINE_HEIGHT, String(clamped));
  }

  setPrimaryBibleVersion(version: string): void {
    this.primaryBibleVersion.set(version);
    this.writeStr(KEY_PRIMARY_BIBLE, version);
  }

  private readStr(key: string, fallback: string): string {
    try {
      return localStorage.getItem(key) ?? fallback;
    } catch {
      return fallback;
    }
  }

  private writeStr(key: string, value: string): void {
    try {
      localStorage.setItem(key, value);
    } catch {
      // ignore
    }
  }

  private readNum(key: string, fallback: number, min: number, max: number): number {
    try {
      const raw = localStorage.getItem(key);
      if (!raw) return fallback;
      const num = Number(raw);
      if (Number.isNaN(num)) return fallback;
      return Math.min(max, Math.max(min, num));
    } catch {
      return fallback;
    }
  }
}
