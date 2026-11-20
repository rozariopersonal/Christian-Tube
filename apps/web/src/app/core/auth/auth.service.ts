import { Injectable, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ApiService } from '../api/api.service';
import { AppConfig } from '../config/app-config';

export interface AuthUser {
  id: string;
  email: string;
  displayName: string;
  photoUrl?: string;
  idToken?: string;
}

interface GoogleCredentialResponse {
  credential?: string;
}

declare global {
  interface Window {
    google?: {
      accounts?: {
        id?: {
          initialize: (cfg: {
            client_id: string;
            callback: (res: GoogleCredentialResponse) => void;
          }) => void;
          prompt: () => void;
          renderButton: (
            el: HTMLElement,
            options: Record<string, unknown>,
          ) => void;
          disableAutoSelect: () => void;
        };
      };
    };
  }
}

const KEY_USER = 'current_user';
const KEY_TOKEN = 'auth_token';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly api = inject(ApiService);

  readonly currentUser = signal<AuthUser | null>(this.readStoredUser());
  readonly isAdmin = signal<boolean>(false);
  readonly isLoading = signal<boolean>(false);
  readonly lastError = signal<string | null>(null);

  readonly isAuthenticated = computed(() => this.currentUser() !== null);

  private googleInitialized = false;

  constructor() {
    const user = this.currentUser();
    if (user?.email) {
      void this.checkIsAdmin(user.email);
    }
  }

  initGoogleSignIn(): boolean {
    const gsi = window.google?.accounts?.id;
    if (!gsi) return false;
    if (!this.googleInitialized) {
      gsi.initialize({
        client_id: AppConfig.googleClientId,
        callback: (res) => {
          if (res.credential) {
            void this.handleGoogleCredential(res.credential);
          }
        },
      });
      this.googleInitialized = true;
    }
    return true;
  }

  renderGoogleButton(element: HTMLElement): void {
    if (!this.initGoogleSignIn()) return;
    window.google?.accounts?.id?.renderButton(element, {
      theme: 'outline',
      size: 'large',
      width: 280,
      text: 'continue_with',
    });
  }

  promptGoogleSignIn(): void {
    if (!this.initGoogleSignIn()) {
      this.lastError.set('Google Sign-In is still loading. Please try again.');
      return;
    }
    window.google?.accounts?.id?.prompt();
  }

  async signInAsGuest(email?: string): Promise<void> {
    const id = `guest_${Date.now()}`;
    const cleanEmail = email?.trim() ?? '';
    const token = cleanEmail ? `token_${id}::${cleanEmail}` : `token_${id}`;
    const user: AuthUser = {
      id,
      email: cleanEmail || `guest_${id}@christianapp.local`,
      displayName: cleanEmail ? cleanEmail.split('@')[0] : 'Guest User',
      idToken: token,
    };
    this.saveSession(user, token);
    await this.syncUser(user);
    if (cleanEmail) {
      await this.checkIsAdmin(cleanEmail);
    }
  }

  signOut(): void {
    try {
      window.google?.accounts?.id?.disableAutoSelect();
    } catch {
      // ignore
    }
    try {
      localStorage.removeItem(KEY_USER);
      localStorage.removeItem(KEY_TOKEN);
      const prefixes = [
        'subscribed_channel_ids',
        'ct_web_watch_history_',
        'ct_web_watch_later_',
        'ct_web_video_playheads_',
        'ct_web_recent_searches_',
        'ct_web_autoplay_',
        'ct_web_sync_pending_',
        'ct_web_user_items_pending_',
        'ct_web_clock_offset_',
        'ct_web_last_guest_id_',
        'bible_highlights',
        'bible_bookmarks',
        'bible_notes',
        'bible_reader_state',
        'book_highlights',
        'book_bookmarks',
        'reader_text_highlights',
      ];
      const exactKeys = [
        'audio_last_track',
        'preferred_languages',
        'primary_bible_version',
      ];
      for (const k of exactKeys) {
        localStorage.removeItem(k);
      }
      const allKeys: string[] = [];
      for (let i = 0; i < localStorage.length; i++) {
        const k = localStorage.key(i);
        if (k) allKeys.push(k);
      }
      for (const k of allKeys) {
        if (prefixes.some((p) => k.startsWith(p))) {
          localStorage.removeItem(k);
        }
      }
    } catch {
      // ignore
    }
    this.currentUser.set(null);
    this.isAdmin.set(false);
    this.lastError.set(null);
  }

  async checkIsAdmin(email?: string): Promise<boolean> {
    const target = email ?? this.currentUser()?.email;
    if (!target) {
      this.isAdmin.set(false);
      return false;
    }
    try {
      const res = await firstValueFrom(
        this.api.get<{ isAdmin?: boolean }>('/channels/check-admin', {
          email: target,
        }),
      );
      const admin = res?.isAdmin === true;
      this.isAdmin.set(admin);
      return admin;
    } catch {
      return this.isAdmin();
    }
  }

  private async handleGoogleCredential(idToken: string): Promise<void> {
    this.isLoading.set(true);
    this.lastError.set(null);
    try {
      const payload = this.decodeJwtPayload(idToken);
      const user: AuthUser = {
        id: String(payload['sub'] ?? `user_${Date.now()}`),
        email: String(payload['email'] ?? ''),
        displayName: String(
          payload['name'] ??
            String(payload['email'] ?? 'User').split('@')[0],
        ),
        photoUrl: payload['picture'] ? String(payload['picture']) : undefined,
        idToken,
      };
      this.saveSession(user, idToken);
      await this.syncUser(user);
      await this.checkIsAdmin(user.email);
    } catch (err) {
      this.lastError.set(
        err instanceof Error ? err.message : 'Sign-in failed',
      );
    } finally {
      this.isLoading.set(false);
    }
  }

  private async syncUser(user: AuthUser): Promise<void> {
    try {
      await firstValueFrom(
        this.api.post('/api/users/sync', {
          email: user.email,
          displayName: user.displayName,
          photoUrl: user.photoUrl,
        }),
      );
    } catch {
      // Non-fatal if offline or backend unavailable
    }
  }

  private saveSession(user: AuthUser, token: string): void {
    this.currentUser.set(user);
    try {
      localStorage.setItem(KEY_USER, JSON.stringify(user));
      localStorage.setItem(KEY_TOKEN, token);
    } catch {
      // ignore
    }
  }

  private readStoredUser(): AuthUser | null {
    try {
      const raw = localStorage.getItem(KEY_USER);
      return raw ? (JSON.parse(raw) as AuthUser) : null;
    } catch {
      return null;
    }
  }

  private decodeJwtPayload(token: string): Record<string, unknown> {
    const parts = token.split('.');
    if (parts.length < 2) return {};
    const base64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const json = decodeURIComponent(
      atob(base64)
        .split('')
        .map((c) => `%${('00' + c.charCodeAt(0).toString(16)).slice(-2)}`)
        .join(''),
    );
    return JSON.parse(json) as Record<string, unknown>;
  }
}
