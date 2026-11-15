import { DOCUMENT } from '@angular/common';
import { Injectable, computed, effect, inject, signal } from '@angular/core';

export type ThemeMode = 'system' | 'light' | 'dark';

export interface AppColorTheme {
  id: 'blue' | 'red' | 'green' | 'purple' | 'amber' | 'pink' | 'teal';
  name: string;
  color: string;
}

export const APP_COLOR_THEMES: readonly AppColorTheme[] = [
  { id: 'blue', name: 'Sapphire Blue', color: '#3B82F6' },
  { id: 'red', name: 'Royal Crimson', color: '#DC2626' },
  { id: 'green', name: 'Emerald Green', color: '#10B981' },
  { id: 'purple', name: 'Violet Purple', color: '#8B5CF6' },
  { id: 'amber', name: 'Warm Amber', color: '#F59E0B' },
  { id: 'pink', name: 'Rose Pink', color: '#EC4899' },
  { id: 'teal', name: 'Cyan Teal', color: '#06B6D4' },
];

const KEY_THEME_MODE = 'theme_mode';
const KEY_COLOR_THEME = 'color_theme';
const KEY_AMOLED = 'is_amoled';

@Injectable({ providedIn: 'root' })
export class ThemeService {
  private readonly doc = inject(DOCUMENT);
  private readonly systemDark = signal(
    typeof window !== 'undefined' &&
      window.matchMedia?.('(prefers-color-scheme: dark)').matches,
  );

  readonly themeMode = signal<ThemeMode>(this.readThemeMode());
  readonly colorTheme = signal<AppColorTheme>(this.readColorTheme());
  readonly isAmoled = signal<boolean>(this.readAmoled());

  readonly isDark = computed(() => {
    const mode = this.themeMode();
    if (mode === 'dark') return true;
    if (mode === 'light') return false;
    return this.systemDark();
  });

  constructor() {
    if (typeof window !== 'undefined' && window.matchMedia) {
      const mql = window.matchMedia('(prefers-color-scheme: dark)');
      mql.addEventListener?.('change', (e) => this.systemDark.set(e.matches));
    }

    effect(() => {
      const root = this.doc.documentElement;
      const dark = this.isDark();
      const amoled = this.isAmoled();
      const accent = this.colorTheme();

      root.setAttribute('data-theme', dark ? 'dark' : 'light');
      root.setAttribute('data-amoled', dark && amoled ? 'true' : 'false');
      root.style.setProperty('--accent', accent.color);

      const metaTheme = this.doc.querySelector('meta[name="theme-color"]');
      if (metaTheme) {
        metaTheme.setAttribute(
          'content',
          dark ? (amoled ? '#000000' : '#0F172A') : '#F8FAFC',
        );
      }
    });
  }

  setThemeMode(mode: ThemeMode): void {
    this.themeMode.set(mode);
    this.writeStorage(KEY_THEME_MODE, mode);
  }

  setColorTheme(id: AppColorTheme['id']): void {
    const found = APP_COLOR_THEMES.find((c) => c.id === id) ?? APP_COLOR_THEMES[0];
    this.colorTheme.set(found);
    this.writeStorage(KEY_COLOR_THEME, found.id);
  }

  setAmoled(enabled: boolean): void {
    this.isAmoled.set(enabled);
    this.writeStorage(KEY_AMOLED, String(enabled));
  }

  private readThemeMode(): ThemeMode {
    const raw = this.readStorage(KEY_THEME_MODE);
    if (raw === 'light' || raw === 'dark' || raw === 'system') return raw;
    return 'system';
  }

  private readColorTheme(): AppColorTheme {
    const raw = this.readStorage(KEY_COLOR_THEME);
    return APP_COLOR_THEMES.find((c) => c.id === raw) ?? APP_COLOR_THEMES[0];
  }

  private readAmoled(): boolean {
    return this.readStorage(KEY_AMOLED) === 'true';
  }

  private readStorage(key: string): string | null {
    try {
      return typeof localStorage !== 'undefined' ? localStorage.getItem(key) : null;
    } catch {
      return null;
    }
  }

  private writeStorage(key: string, value: string): void {
    try {
      if (typeof localStorage !== 'undefined') localStorage.setItem(key, value);
    } catch {
      // Ignore storage quota / privacy mode errors
    }
  }
}
