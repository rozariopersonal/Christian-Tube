import { Injectable, effect, inject, signal, untracked } from '@angular/core';
import { AuthService } from '../auth/auth.service';
import { APP_COLOR_THEMES, AppColorTheme, ThemeMode, ThemeService } from '../theme/theme.service';
import { ReaderAppearanceService } from './reader-appearance.service';
import { UserSyncService } from './user-sync.service';
import { SUPPORTED_LANGUAGES, canonicalLanguageCode } from '../../shared/ui/language-meta';

const KEY_PREFERRED_LANGUAGES = 'preferred_languages';
const KEY_DEFAULT_PAGE = 'ct_default_page';

export function normalizeDefaultPage(page: string | null | undefined): string {
  const clean = (page ?? 'feed').trim().toLowerCase();
  switch (clean) {
    case 'shorts':
    case 'bible':
    case 'words':
    case 'library':
    case 'books':
    case 'articles':
    case 'audio':
    case 'feed':
      return clean === 'books' ? 'library' : clean;
    default:
      return 'feed';
  }
}

export function resolveDefaultWebRoute(page: string | null | undefined): string {
  switch (normalizeDefaultPage(page)) {
    case 'shorts':
      return 'shorts';
    case 'bible':
      return 'bible';
    case 'words':
      return 'words';
    case 'library':
      return 'books';
    case 'articles':
      return 'articles';
    case 'audio':
      return 'audio';
    case 'feed':
    default:
      return 'feed';
  }
}

@Injectable({ providedIn: 'root' })
export class ContentPreferencesService {
  private readonly auth = inject(AuthService);
  private readonly theme = inject(ThemeService);
  private readonly appearance = inject(ReaderAppearanceService);
  private readonly userSync = inject(UserSyncService);

  readonly preferredLanguages = signal<string[]>(this.readLocalLanguages());
  readonly defaultPage = signal<string>(this.readLocalDefaultPage());

  constructor() {
    effect(() => {
      // Re-read per-user local default page when the active user changes.
      this.auth.currentUser();
      untracked(() => {
        this.defaultPage.set(this.readLocalDefaultPage());
      });
    });

    effect(() => {
      const remote = this.userSync.remoteState()?.preferences;
      if (!remote) return;
      untracked(() => {
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
        if (!pending['pref:defaultPage'] && remote.defaultPage) {
          this.setDefaultPage(remote.defaultPage, false);
        }
      });
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

  defaultRoute(): string {
    return resolveDefaultWebRoute(this.defaultPage());
  }

  setDefaultPage(page: string, sync = true): void {
    const clean = normalizeDefaultPage(page);
    this.defaultPage.set(clean);
    try {
      localStorage.setItem(this.userSync.userCacheKey(KEY_DEFAULT_PAGE), clean);
    } catch {
      // ignore
    }
    if (sync && this.auth.isAuthenticated()) {
      this.userSync.enqueuePreference('defaultPage', clean);
    }
  }

  private readLocalDefaultPage(): string {
    try {
      const raw = localStorage.getItem(
        this.userSync.userCacheKey(KEY_DEFAULT_PAGE),
      );
      return normalizeDefaultPage(raw);
    } catch {
      return 'feed';
    }
  }

  private readLocalLanguages(): string[] {
    try {
      const raw = localStorage.getItem(KEY_PREFERRED_LANGUAGES) ??
        localStorage.getItem('selected_languages');
      const parsed = raw ? (JSON.parse(raw) as unknown) : null;
      return Array.isArray(parsed) && parsed.length > 0
        ? parsed.map(String)
        : ['en'];
    } catch {
      return ['en'];
    }
  }
}
