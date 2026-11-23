import { DOCUMENT } from '@angular/common';
import { Injectable, computed, inject, signal } from '@angular/core';
import { BibleVersionSelectionService } from '../../../core/services/bible-version-selection.service';
import { ThemeService } from '../../../core/theme/theme.service';
import {
  TextAlignOption,
  WordFeedItem,
  WordsAppearanceState,
} from '../models/words-feed.model';
import {
  findFontOption,
  getDefaultFontForLanguage,
  getLanguageForVersion,
  resolvePresetDefaultText,
  getPreset,
} from '../models/words-theme.catalog';

const KEY_SAVED_CARDS = 'words_saved_cards';
const KEY_LANG_PREF_PREFIX = 'words_lang_pref_';
const WORDS_CONTEXT_KEY = 'words';
export const MAX_SELECTED_VERSIONS = 3;
export const MAX_COMPARISON_VERSIONS = MAX_SELECTED_VERSIONS - 1;

interface LangAppearancePref {
  fontSizeScale: number;
  activeFontFamily: string;
  textColorHex: string | null; // null = auto from preset
  isBold: boolean;
  isItalic: boolean;
  textAlign: TextAlignOption;
  backgroundPreset: string;
}

@Injectable({ providedIn: 'root' })
export class WordsPreferencesService {
  private readonly doc = inject(DOCUMENT);
  private readonly versionSelection = inject(BibleVersionSelectionService);
  private readonly theme = inject(ThemeService);
  private readonly loadedFonts = new Set<string>();

  readonly selectedVersions = this.versionSelection.selectedVersionsSignal(
    WORDS_CONTEXT_KEY,
    MAX_SELECTED_VERSIONS,
  );
  readonly activeVersionId = computed<string>(
    () => this.selectedVersions()[0] ?? 'nasb',
  );
  readonly comparisonVersionIds = computed<string[]>(() =>
    this.selectedVersions().slice(1),
  );
  readonly savedCards = signal<WordFeedItem[]>(this.readSavedCards());

  private readonly langPrefs = signal<LangAppearancePref>(
    this.readLangPref(getLanguageForVersion(this.activeVersionId())),
  );

  readonly appearance = computed<WordsAppearanceState>(() => {
    const pref = this.langPrefs();
    const preset = getPreset(pref.backgroundPreset);
    const defaultText = resolvePresetDefaultText(preset, this.theme.isDark());
    return {
      activeVersionId: this.activeVersionId(),
      comparisonVersionIds: this.comparisonVersionIds(),
      fontSizeScale: pref.fontSizeScale,
      activeFontFamily: pref.activeFontFamily,
      textColorHex: pref.textColorHex ?? defaultText,
      isBold: pref.isBold,
      isItalic: pref.isItalic,
      textAlign: pref.textAlign,
      backgroundPreset: pref.backgroundPreset,
    };
  });

  readonly savedIds = computed(
    () => new Set(this.savedCards().map((c) => c.id)),
  );

  constructor() {
    const a = this.appearance();
    this.ensureFontLoaded(
      a.activeFontFamily,
      getLanguageForVersion(a.activeVersionId),
    );
  }

  isSaved(id: string): boolean {
    return this.savedIds().has(id);
  }

  toggleSave(item: WordFeedItem): boolean {
    const current = this.savedCards();
    const exists = current.some((c) => c.id === item.id);
    const next = exists
      ? current.filter((c) => c.id !== item.id)
      : [{ ...item, isSaved: true }, ...current];
    this.savedCards.set(next);
    this.writeJson(KEY_SAVED_CARDS, next);
    return !exists;
  }

  setVersion(versionId: string): void {
    const clean = versionId.toLowerCase();
    this.versionSelection.setSelection(
      WORDS_CONTEXT_KEY,
      clean,
      this.comparisonVersionIds(),
      MAX_SELECTED_VERSIONS,
    );
    const lang = getLanguageForVersion(clean);
    const pref = this.readLangPref(lang);
    this.langPrefs.set(pref);
    this.ensureFontLoaded(pref.activeFontFamily, lang);
  }

  toggleVersionSelection(versionId: string): 'primary-changed' | 'comparison-changed' | 'noop' {
    const res = this.versionSelection.toggleVersion(
      WORDS_CONTEXT_KEY,
      versionId,
      MAX_SELECTED_VERSIONS,
    );
    if (res === 'primary-changed') {
      const lang = getLanguageForVersion(this.activeVersionId());
      const pref = this.readLangPref(lang);
      this.langPrefs.set(pref);
      this.ensureFontLoaded(pref.activeFontFamily, lang);
    }
    return res;
  }

  promoteVersionToPrimary(versionId: string): boolean {
    const changed = this.versionSelection.promoteToPrimary(
      WORDS_CONTEXT_KEY,
      versionId,
      MAX_SELECTED_VERSIONS,
    );
    if (changed) {
      const lang = getLanguageForVersion(this.activeVersionId());
      const pref = this.readLangPref(lang);
      this.langPrefs.set(pref);
      this.ensureFontLoaded(pref.activeFontFamily, lang);
    }
    return changed;
  }

  addComparisonVersion(versionId: string): void {
    const clean = versionId.toLowerCase();
    if (clean === this.activeVersionId() || this.comparisonVersionIds().includes(clean)) {
      return;
    }
    this.versionSelection.toggleVersion(
      WORDS_CONTEXT_KEY,
      clean,
      MAX_SELECTED_VERSIONS,
    );
  }

  removeComparisonVersion(versionId: string): void {
    const clean = versionId.toLowerCase();
    if (!this.comparisonVersionIds().includes(clean)) return;
    this.versionSelection.toggleVersion(
      WORDS_CONTEXT_KEY,
      clean,
      MAX_SELECTED_VERSIONS,
    );
  }

  clearComparisonVersions(): void {
    this.versionSelection.setSelection(
      WORDS_CONTEXT_KEY,
      this.activeVersionId(),
      [],
      MAX_SELECTED_VERSIONS,
    );
  }

  updateLangPref(patch: Partial<LangAppearancePref>): void {
    const lang = getLanguageForVersion(this.activeVersionId());
    const next: LangAppearancePref = { ...this.langPrefs(), ...patch };
    this.langPrefs.set(next);
    this.writeJson(`${KEY_LANG_PREF_PREFIX}${lang}`, next);
    if (patch.activeFontFamily) {
      this.ensureFontLoaded(patch.activeFontFamily, lang);
    }
  }

  setFontScale(scale: number): void {
    const clamped = Number(Math.min(1.5, Math.max(0.8, scale)).toFixed(1));
    this.updateLangPref({ fontSizeScale: clamped });
  }

  ensureFontLoaded(fontId: string, lang?: string): void {
    const opt = findFontOption(fontId, lang);
    if (!opt.googleFontQuery || this.loadedFonts.has(opt.googleFontQuery)) {
      return;
    }
    this.loadedFonts.add(opt.googleFontQuery);
    if (!this.doc?.head) return;
    const link = this.doc.createElement('link');
    link.rel = 'stylesheet';
    link.href = `https://fonts.googleapis.com/css2?family=${opt.googleFontQuery}&display=swap`;
    this.doc.head.appendChild(link);
  }

  private readLangPref(lang: string): LangAppearancePref {
    const raw = this.readJson<Partial<LangAppearancePref>>(
      `${KEY_LANG_PREF_PREFIX}${lang}`,
      {},
    );
    return {
      fontSizeScale:
        typeof raw.fontSizeScale === 'number'
          ? Math.min(1.5, Math.max(0.8, raw.fontSizeScale))
          : 1.0,
      activeFontFamily:
        raw.activeFontFamily || getDefaultFontForLanguage(lang),
      textColorHex: raw.textColorHex ?? null,
      isBold: Boolean(raw.isBold),
      isItalic: Boolean(raw.isItalic),
      textAlign:
        raw.textAlign === 'left' || raw.textAlign === 'right'
          ? raw.textAlign
          : 'center',
      backgroundPreset: raw.backgroundPreset || 'gradient_celestial_dawn',
    };
  }

  private readSavedCards(): WordFeedItem[] {
    return this.readJson<WordFeedItem[]>(KEY_SAVED_CARDS, []);
  }

  private readStr(key: string): string | null {
    try {
      return localStorage.getItem(key);
    } catch {
      return null;
    }
  }

  private writeStr(key: string, value: string): void {
    try {
      localStorage.setItem(key, value);
    } catch {
      // ignore storage quota errors
    }
  }

  private removeKey(key: string): void {
    try {
      localStorage.removeItem(key);
    } catch {
      // ignore
    }
  }

  private readJson<T>(key: string, fallback: T): T {
    try {
      const raw = localStorage.getItem(key);
      return raw ? (JSON.parse(raw) as T) : fallback;
    } catch {
      return fallback;
    }
  }

  private writeJson(key: string, value: unknown): void {
    try {
      localStorage.setItem(key, JSON.stringify(value));
    } catch {
      // ignore
    }
  }
}
