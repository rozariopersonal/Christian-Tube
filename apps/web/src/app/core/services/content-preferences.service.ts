import { Injectable, effect, inject, signal } from '@angular/core';
import { AuthService } from '../auth/auth.service';
import { APP_COLOR_THEMES, AppColorTheme, ThemeMode, ThemeService } from '../theme/theme.service';
import { ReaderAppearanceService } from './reader-appearance.service';
import { UserSyncService } from './user-sync.service';
import { SUPPORTED_LANGUAGES, canonicalLanguageCode } from '../../shared/ui/language-meta';

const KEY_PREFERRED_LANGUAGES = 'preferred_languages';

@Injectable({ providedIn: 'root' })
export class ContentPreferencesService {
  private readonly auth = inject(AuthService);
  private readonly theme = inject(ThemeService);
  private readonly appearance = inject(ReaderAppearanceService);
  private readonly userSync = inject(UserSyncService);

  readonly preferredLanguages = signal<string[]>(this.readLocalLanguages());

  constructor() {
    effect(() => {
      const remote = this.userSync.remoteState()?.preferences;
      if (!remote) return;
      const pending = this.userSync.pendingOps();

      if (
        !pending['pref:languages'] &&
        Array.isArray(remote.languages) &&
        remote.languages.length > 0
      ) {
        this.preferredLanguages.set(remote.languages);
        try {
          localStorage.setItem(
            KEY_PREFERRED_LANGUAGES,
            JSON.stringify(remote.languages),
          );
        } catch {
          // ignore
        }
      }
      if (!pending['pref:primaryBibleVersionId'] && remote.primaryBibleVersionId) {
        this.appearance.setPrimaryBibleVersion(remote.primaryBibleVersionId, false);
      }
      if (
        !pending['pref:themeMode'] &&
        (remote.themeMode === 'system' ||
          remote.themeMode === 'light' ||
          remote.themeMode === 'dark')
      ) {
        this.theme.setThemeMode(remote.themeMode as ThemeMode, false);
      }
      if (
        !pending['pref:accentColor'] &&
        remote.accentColor &&
        APP_COLOR_THEMES.some((c) => c.id === remote.accentColor)
      ) {
        this.theme.setColorTheme(remote.accentColor as AppColorTheme['id'], false);
      }
    });
  }

  toggleLanguage(code: string): void {
    const cur = this.preferredLanguages();
    const next = cur.includes(code)
      ? cur.filter((c) => c !== code)
      : [...cur, code];
    this.setLanguages(next.length > 0 ? next : ['en']);
  }

  setLanguages(codes: string[]): void {
    const clean = codes.length > 0 ? codes : ['en'];
    this.preferredLanguages.set(clean);
    try {
      localStorage.setItem(KEY_PREFERRED_LANGUAGES, JSON.stringify(clean));
    } catch {
      // ignore
    }
    if (this.auth.isAuthenticated()) {
      this.userSync.enqueuePreference('languages', clean);
    }
  }

  matchesLanguageName(englishLanguageName: string): boolean {
    const langs = this.preferredLanguages();
    if (langs.length === 0 || langs.includes('All')) return true;
    const target = englishLanguageName.trim().toLowerCase();
    return langs.some((code) => {
      const meta = SUPPORTED_LANGUAGES[code.toLowerCase()];
      return (
        code.toLowerCase() === target ||
        meta?.englishName.toLowerCase() === target ||
        canonicalLanguageCode(englishLanguageName).toLowerCase() === code.toLowerCase()
      );
    });
  }

  private readLocalLanguages(): string[] {
    try {
      const raw = localStorage.getItem(KEY_PREFERRED_LANGUAGES);
      const parsed = raw ? (JSON.parse(raw) as unknown) : null;
      return Array.isArray(parsed) && parsed.length > 0
        ? parsed.map(String)
        : ['en'];
    } catch {
      return ['en'];
    }
  }
}
