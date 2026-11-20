import { Injectable, inject, signal } from '@angular/core';
import { ReleaseDataService } from '../api/release-data.service';
import { AuthService } from '../auth/auth.service';
import { UserSyncService } from './user-sync.service';
import { AppConfig } from '../config/app-config';
import { ScreenClass } from '../layout/screen-class.service';

export interface ReaderFontOption {
  id: string;
  label: string;
  shortLabel?: string;
  cssFamily: string;
  releaseFile?: string;
}

export const READER_FONTS: readonly ReaderFontOption[] = [
  { id: 'system', label: 'System Sans', shortLabel: 'System', cssFamily: "'Inter', system-ui, sans-serif" },
  {
    id: 'literata',
    label: 'Literata (Serif)',
    shortLabel: 'Literata',
    cssFamily: "'Literata', Georgia, serif",
    releaseFile: 'Literata_Regular.ttf',
  },
  {
    id: 'merriweather',
    label: 'Merriweather (Serif)',
    shortLabel: 'Merriweather',
    cssFamily: "'Merriweather', Georgia, serif",
    releaseFile: 'Merriweather_Regular.ttf',
  },
  {
    id: 'noto-tamil',
    label: 'Noto Sans Tamil',
    shortLabel: 'Noto Tamil',
    cssFamily: "'Noto Sans Tamil', 'Inter', sans-serif",
    releaseFile: 'NotoSansTamil_Regular.ttf',
  },
];

export type ReaderPaperTheme = 'auto' | 'paper' | 'sepia' | 'night';
export type BibleReadingLayout = 'verses' | 'paragraph';
export type BookTextAlign = 'left' | 'justify';
export type BookMarginSize = 'narrow' | 'medium' | 'wide';

export interface PaperThemeOption {
  id: ReaderPaperTheme;
  label: string;
  swatchBg: string;
  swatchFg: string;
}

export const READER_PAPER_THEMES: readonly PaperThemeOption[] = [
  { id: 'auto', label: 'App Theme', swatchBg: 'var(--bg)', swatchFg: 'var(--on-surface)' },
  { id: 'paper', label: 'Paper', swatchBg: '#FAF8F5', swatchFg: '#1F2937' },
  { id: 'sepia', label: 'Sepia', swatchBg: '#F4ECD8', swatchFg: '#433422' },
  { id: 'night', label: 'Night', swatchBg: '#121620', swatchFg: '#E2E8F0' },
];

export interface SpacingPreset {
  id: string;
  label: string;
  value: number;
}

export const LINE_HEIGHT_PRESETS: readonly SpacingPreset[] = [
  { id: 'tight', label: 'Tight', value: 1.4 },
  { id: 'normal', label: 'Normal', value: 1.65 },
  { id: 'relaxed', label: 'Relaxed', value: 1.95 },
];

export const LETTER_SPACING_PRESETS: readonly SpacingPreset[] = [
  { id: 'tight', label: 'Tight', value: -0.02 },
  { id: 'normal', label: 'Normal', value: 0 },
  { id: 'wide', label: 'Wide', value: 0.04 },
];

const KEY_FONT_ID = 'reader_font_id';
const KEY_FONT_SIZE = 'reader_font_size';
const KEY_LINE_HEIGHT = 'reader_line_height';
const KEY_LETTER_SPACING = 'reader_letter_spacing';
const KEY_PRIMARY_BIBLE = 'primary_bible_version';
const KEY_PAPER_THEME = 'reader_paper_theme';
const KEY_BIBLE_LAYOUT = 'bible_reading_layout';
const KEY_BOOK_ALIGN = 'book_text_align';
const KEY_BOOK_MARGIN = 'book_margin_size';
const KEY_BOOK_COLUMNS = 'book_columns';
const KEY_SINGLE_COL_PAGINATED = 'reader_single_col_paginated';

@Injectable({ providedIn: 'root' })
export class ReaderAppearanceService {
  private readonly releases = inject(ReleaseDataService);
  private readonly auth = inject(AuthService);
  private readonly userSync = inject(UserSyncService);

  readonly fontId = signal<string>(this.readStr(KEY_FONT_ID, 'system'));
  readonly fontSize = signal<number>(this.readNum(KEY_FONT_SIZE, 17, 13, 28));
  readonly lineHeight = signal<number>(this.readNum(KEY_LINE_HEIGHT, 1.65, 1.3, 2.2));
  readonly letterSpacing = signal<number>(
    this.readNum(KEY_LETTER_SPACING, 0, -0.04, 0.12),
  );
  readonly primaryBibleVersion = signal<string>(
    this.readStr(KEY_PRIMARY_BIBLE, AppConfig.defaultBibleVersion),
  );
  readonly paperTheme = signal<ReaderPaperTheme>(
    this.readPaperTheme(),
  );
  readonly bibleLayout = signal<BibleReadingLayout>(
    this.readStr(KEY_BIBLE_LAYOUT, 'verses') === 'paragraph' ? 'paragraph' : 'verses',
  );
  readonly bookAlign = signal<BookTextAlign>(
    this.readStr(KEY_BOOK_ALIGN, 'left') === 'justify' ? 'justify' : 'left',
  );
  readonly bookMargin = signal<BookMarginSize>(this.readBookMargin());
  readonly bookColumns = signal<1 | 2 | 3>(this.readBookColumns());
  readonly singleColPaginated = signal<boolean>(
    this.readStr(KEY_SINGLE_COL_PAGINATED, '0') === '1',
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

  stepFontSize(delta: number): void {
    this.setFontSize(this.fontSize() + delta);
  }

  setLineHeight(lh: number): void {
    const raw = Number(lh);
    if (Number.isNaN(raw)) return;
    const clamped = Math.min(2.2, Math.max(1.3, Number(raw.toFixed(2))));
    this.lineHeight.set(clamped);
    this.writeStr(KEY_LINE_HEIGHT, String(clamped));
  }

  stepLineHeight(delta: number): void {
    this.setLineHeight(this.lineHeight() + delta);
  }

  setLetterSpacing(ls: number): void {
    const raw = Number(ls);
    if (Number.isNaN(raw)) return;
    const clamped = Math.min(0.12, Math.max(-0.04, Number(raw.toFixed(2))));
    const normalized = Object.is(clamped, -0) ? 0 : clamped;
    this.letterSpacing.set(normalized);
    this.writeStr(KEY_LETTER_SPACING, String(normalized));
  }

  stepLetterSpacing(delta: number): void {
    this.setLetterSpacing(this.letterSpacing() + delta);
  }

  formatLetterSpacing(val = this.letterSpacing()): string {
    if (Math.abs(val) < 0.005) return 'Normal (0em)';
    return `${val > 0 ? '+' : ''}${val.toFixed(2)}em`;
  }

  setPrimaryBibleVersion(version: string, sync = true): void {
    this.primaryBibleVersion.set(version);
    this.writeStr(KEY_PRIMARY_BIBLE, version);
    if (sync && this.auth.isAuthenticated()) {
      this.userSync.enqueuePreference('primaryBibleVersionId', version.toUpperCase());
    }
  }

  setPaperTheme(theme: ReaderPaperTheme): void {
    this.paperTheme.set(theme);
    this.writeStr(KEY_PAPER_THEME, theme);
  }

  setBibleLayout(layout: BibleReadingLayout): void {
    this.bibleLayout.set(layout);
    this.writeStr(KEY_BIBLE_LAYOUT, layout);
  }

  setBookAlign(align: BookTextAlign): void {
    this.bookAlign.set(align);
    this.writeStr(KEY_BOOK_ALIGN, align);
  }

  setBookMargin(margin: BookMarginSize): void {
    this.bookMargin.set(margin);
    this.writeStr(KEY_BOOK_MARGIN, margin);
  }

  setSingleColPaginated(enabled: boolean): void {
    this.singleColPaginated.set(enabled);
    this.writeStr(KEY_SINGLE_COL_PAGINATED, enabled ? '1' : '0');
  }

  toggleSingleColPaginated(): void {
    this.setSingleColPaginated(!this.singleColPaginated());
  }

  setBookColumns(cols: 1 | 2 | 3): void {
    this.bookColumns.set(cols);
    this.writeStr(KEY_BOOK_COLUMNS, String(cols));
  }

  effectiveColumns(screenClass: ScreenClass): 1 | 2 | 3 {
    if (screenClass === 'compact') return 1;
    const cols = this.bookColumns();
    if (screenClass === 'medium') return cols >= 2 ? 2 : 1;
    return cols;
  }

  private readBookColumns(): 1 | 2 | 3 {
    const raw = this.readStr(KEY_BOOK_COLUMNS, '2');
    if (raw === '1') return 1;
    if (raw === '3') return 3;
    return 2;
  }

  private readBookMargin(): BookMarginSize {
    const val = this.readStr(KEY_BOOK_MARGIN, 'medium');
    if (val === 'narrow' || val === 'wide') return val;
    return 'medium';
  }

  private readPaperTheme(): ReaderPaperTheme {
    const val = this.readStr(KEY_PAPER_THEME, 'auto');
    if (val === 'paper' || val === 'sepia' || val === 'night') return val;
    return 'auto';
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
