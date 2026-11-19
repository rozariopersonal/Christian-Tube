import { Injectable, effect, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ApiService } from '../api/api.service';
import { AuthService } from '../auth/auth.service';
import { SUPPORTED_LANGUAGES, canonicalLanguageCode } from '../../shared/ui/language-meta';

const KEY_PREFERRED_LANGUAGES = 'preferred_languages';

@Injectable({ providedIn: 'root' })
export class ContentPreferencesService {
  private readonly api = inject(ApiService);
  private readonly auth = inject(AuthService);

  readonly preferredLanguages = signal<string[]>(this.readLocalLanguages());
  private syncedUserId: string | null = null;

  constructor() {
    effect(() => {
      const user = this.auth.currentUser();
      if (user && user.id !== this.syncedUserId) {
        this.syncedUserId = user.id;
        void this.loadRemote();
      } else if (!user) {
        this.syncedUserId = null;
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
      void firstValueFrom(
        this.api.put('/api/user/preferences', { languages: clean }),
      ).catch(() => {});
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

  private async loadRemote(): Promise<void> {
    try {
      const pref = await firstValueFrom(
        this.api.get<{ languages?: string[] }>('/api/user/preferences'),
      );
      if (Array.isArray(pref?.languages) && pref.languages.length > 0) {
        this.preferredLanguages.set(pref.languages);
        try {
          localStorage.setItem(
            KEY_PREFERRED_LANGUAGES,
            JSON.stringify(pref.languages),
          );
        } catch {
          // ignore
        }
      }
    } catch {
      // keep local fallback
    }
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
