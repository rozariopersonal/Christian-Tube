import {
  HttpBackend,
  HttpClient,
  HttpErrorResponse,
} from '@angular/common/http';
import {
  Injectable,
  OnDestroy,
  computed,
  inject,
  signal,
} from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ApiService } from '../api/api.service';
import { AppConfig } from '../config/app-config';
import { IndexedDbCacheService } from '../storage/indexed-db-cache.service';
import { AuthTokenStore, StoredAuthUser } from './auth-token.store';

export type AuthUser = StoredAuthUser;

export interface AccountSwitchPrompt {
  currentUser: AuthUser;
  nextUser: AuthUser;
  resolve: (confirmed: boolean) => void;
}

interface GoogleCredentialResponse {
  credential?: string;
}

interface BackendSessionResponse {
  accessToken: string;
  refreshToken: string;
  sessionId: string;
  expiresIn: number;
  user: {
    id: string;
    email: string | null;
    displayName: string | null;
    photoUrl: string | null;
    isGuest: boolean;
  };
}

interface BackendRefreshResponse {
  accessToken: string;
  refreshToken: string;
  sessionId: string;
  expiresIn: number;
}

declare global {
  interface Window {
    google?: {
      accounts?: {
        id?: {
          initialize: (cfg: {
            client_id: string;
            auto_select?: boolean;
            use_fedcm_for_prompt?: boolean;
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

const REFRESH_FAILURE_BACKOFF_MS = 30_000;

@Injectable({ providedIn: 'root' })
export class AuthService implements OnDestroy {
  private readonly api = inject(ApiService);
  private readonly httpBackend = inject(HttpBackend);
  private readonly rawHttp = new HttpClient(this.httpBackend);
  private readonly idbCache = inject(IndexedDbCacheService);
  private readonly tokenStore = inject(AuthTokenStore);

  readonly currentUser = signal<AuthUser | null>(this.tokenStore.readUser());
  readonly sessionExpired = signal<boolean>(
    this.tokenStore.readSessionExpired(),
  );
  readonly isAdmin = signal<boolean>(false);
  readonly isLoading = signal<boolean>(false);
  readonly lastError = signal<string | null>(null);
  readonly pendingAccountSwitch = signal<AccountSwitchPrompt | null>(null);

  readonly isAuthenticated = computed(() => this.currentUser() !== null);
  readonly canSync = computed(
    () => this.currentUser() !== null && !this.sessionExpired(),
  );

  private googleInitialized = false;
  private inFlightRefresh: Promise<string | null> | null = null;
  private lastRefreshFailureAt = 0;
  private unsubExternal: (() => void) | null = null;
  private bootstrapStarted = false;

  constructor() {
    this.unsubExternal = this.tokenStore.subscribeExternalChanges((msg) => {
      if (msg.type === 'signed_out') {
        this.currentUser.set(null);
        this.sessionExpired.set(false);
        this.isAdmin.set(false);
      } else if (msg.type === 'session_expired') {
        this.sessionExpired.set(true);
      } else if (msg.type === 'session_updated') {
        const stored = this.tokenStore.readUser();
        if (stored) {
          this.currentUser.set(stored);
        }
        this.sessionExpired.set(this.tokenStore.readSessionExpired());
      }
    });

    const user = this.currentUser();
    if (user?.email) {
      void this.checkIsAdmin(user.email);
    }
    if (user && !this.tokenStore.getRefreshToken()) {
      void this.bootstrapLegacySession(user);
    }
  }

  ngOnDestroy(): void {
    this.unsubExternal?.();
    this.unsubExternal = null;
  }

  initGoogleSignIn(): boolean {
    const gsi = window.google?.accounts?.id;
    if (!gsi) return false;
    if (!this.googleInitialized) {
      gsi.initialize({
        client_id: AppConfig.googleClientId,
        auto_select: true,
        use_fedcm_for_prompt: true,
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
    element.innerHTML = '';
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

  async signInAsGuest(displayName?: string): Promise<void> {
    this.isLoading.set(true);
    this.lastError.set(null);
    try {
      const res = await firstValueFrom(
        this.rawHttp.post<BackendSessionResponse>(
          `${AppConfig.apiBaseUrl}/api/auth/guest`,
          {
            deviceId: this.tokenStore.getDeviceId(),
            deviceLabel: this.tokenStore.getDeviceLabel(),
            displayName: displayName?.trim() || undefined,
          },
        ),
      );
      const user: AuthUser = {
        id: res.user.id,
        email: res.user.email ?? '',
        displayName: res.user.displayName || 'Guest User',
        photoUrl: res.user.photoUrl ?? undefined,
        isGuest: true,
      };
      this.tokenStore.saveSession({
        user,
        accessToken: res.accessToken,
        refreshToken: res.refreshToken,
        sessionId: res.sessionId,
      });
      this.currentUser.set(user);
      this.sessionExpired.set(false);
      this.isAdmin.set(false);
    } catch (err) {
      this.lastError.set(
        err instanceof Error ? err.message : 'Guest sign-in failed',
      );
    } finally {
      this.isLoading.set(false);
    }
  }

  async refreshSession(): Promise<string | null> {
    if (this.inFlightRefresh) {
      return this.inFlightRefresh;
    }
    if (Date.now() - this.lastRefreshFailureAt < REFRESH_FAILURE_BACKOFF_MS) {
      return null;
    }

    const tokenBeforeWait = this.tokenStore.getAccessToken();
    const run = async (): Promise<string | null> => {
      // Re-read inside lock: another tab may have already rotated tokens
      const latestAccess = this.tokenStore.getAccessToken();
      if (
        latestAccess &&
        latestAccess !== tokenBeforeWait &&
        !this.tokenStore.readSessionExpired()
      ) {
        this.sessionExpired.set(false);
        return latestAccess;
      }

      const refreshToken = this.tokenStore.getRefreshToken();
      const sessionId = this.tokenStore.getSessionId();
      if (!refreshToken || !sessionId) {
        this.tokenStore.markSessionExpired();
        this.sessionExpired.set(true);
        return null;
      }

      try {
        const res = await firstValueFrom(
          this.rawHttp.post<BackendRefreshResponse>(
            `${AppConfig.apiBaseUrl}/api/auth/refresh`,
            { sessionId, refreshToken },
          ),
        );
        this.lastRefreshFailureAt = 0;
        this.tokenStore.saveSession({
          accessToken: res.accessToken,
          refreshToken: res.refreshToken,
          sessionId: res.sessionId,
        });
        this.sessionExpired.set(false);
        return res.accessToken;
      } catch (err) {
        if (
          err instanceof HttpErrorResponse &&
          (err.status === 401 || err.status === 403)
        ) {
          this.tokenStore.markSessionExpired();
          this.sessionExpired.set(true);
          return null;
        }
        // Network error / 5xx / timeout: keep session intact, back off 30s
        this.lastRefreshFailureAt = Date.now();
        return null;
      }
    };

    const withCrossTabLock = async (): Promise<string | null> => {
      if (
        typeof navigator !== 'undefined' &&
        navigator.locks &&
        typeof navigator.locks.request === 'function'
      ) {
        return navigator.locks.request('auth_refresh', run);
      }
      return run();
    };

    this.inFlightRefresh = withCrossTabLock().finally(() => {
      this.inFlightRefresh = null;
    });

    return this.inFlightRefresh;
  }

  signOut(): void {
    const accessToken = this.tokenStore.getAccessToken();
    const sessionId = this.tokenStore.getSessionId();
    if (accessToken && sessionId) {
      void firstValueFrom(
        this.rawHttp.post(
          `${AppConfig.apiBaseUrl}/api/auth/logout`,
          {},
          { headers: { Authorization: `Bearer ${accessToken}` } },
        ),
      ).catch(() => {});
    }

    try {
      window.google?.accounts?.id?.disableAutoSelect();
    } catch {
      // ignore
    }
    this.tokenStore.wipeAllKeepingDeviceId();
    void this.idbCache.clear();
    this.currentUser.set(null);
    this.sessionExpired.set(false);
    this.isAdmin.set(false);
    this.lastError.set(null);
    this.lastRefreshFailureAt = 0;
    queueMicrotask(() => this.tokenStore.wipeAllKeepingDeviceId());
  }

  resolveAccountSwitch(confirmed: boolean): void {
    const pending = this.pendingAccountSwitch();
    if (!pending) return;
    this.pendingAccountSwitch.set(null);
    pending.resolve(confirmed);
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

  async handleGoogleCredential(idToken: string): Promise<void> {
    this.isLoading.set(true);
    this.lastError.set(null);
    try {
      const payload = this.decodeJwtPayload(idToken);
      const nextSub = String(payload['sub'] ?? '');
      const nextEmail = String(payload['email'] ?? '');
      const nextName = String(
        payload['name'] ?? (nextEmail ? nextEmail.split('@')[0] : 'User'),
      );
      const nextPhoto = payload['picture']
        ? String(payload['picture'])
        : undefined;

      const existing = this.currentUser();
      const existingIsGoogle =
        existing !== null &&
        !existing.isGuest &&
        !existing.id.startsWith('guest_');

      if (existingIsGoogle && nextSub && existing.id !== nextSub) {
        const confirmed = await this.confirmAccountSwitch(existing, {
          id: nextSub,
          email: nextEmail,
          displayName: nextName,
          photoUrl: nextPhoto,
          isGuest: false,
        });
        if (!confirmed) {
          return;
        }
        this.signOut();
      }

      const res = await firstValueFrom(
        this.rawHttp.post<BackendSessionResponse>(
          `${AppConfig.apiBaseUrl}/api/auth/google`,
          {
            idToken,
            deviceId: this.tokenStore.getDeviceId(),
            deviceLabel: this.tokenStore.getDeviceLabel(),
          },
        ),
      );

      const user: AuthUser = {
        id: res.user.id,
        email: res.user.email ?? nextEmail,
        displayName: res.user.displayName || nextName,
        photoUrl: res.user.photoUrl ?? nextPhoto,
        isGuest: false,
      };
      this.lastRefreshFailureAt = 0;
      this.tokenStore.saveSession({
        user,
        accessToken: res.accessToken,
        refreshToken: res.refreshToken,
        sessionId: res.sessionId,
      });
      this.currentUser.set(user);
      this.sessionExpired.set(false);
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

  private async confirmAccountSwitch(
    currentUser: AuthUser,
    nextUser: AuthUser,
  ): Promise<boolean> {
    if (typeof window === 'undefined') return true;
    return new Promise<boolean>((resolve) => {
      this.pendingAccountSwitch.set({
        currentUser,
        nextUser,
        resolve,
      });
    });
  }

  private async bootstrapLegacySession(user: AuthUser): Promise<void> {
    if (this.bootstrapStarted) return;
    this.bootstrapStarted = true;

    const isLegacyGuest = Boolean(user.isGuest) || user.id.startsWith('guest_');
    if (isLegacyGuest) {
      try {
        const res = await firstValueFrom(
          this.rawHttp.post<BackendSessionResponse>(
            `${AppConfig.apiBaseUrl}/api/auth/guest`,
            {
              deviceId: this.tokenStore.getDeviceId(),
              deviceLabel: this.tokenStore.getDeviceLabel(),
              displayName: user.displayName,
            },
          ),
        );
        const migratedUser: AuthUser = {
          id: res.user.id,
          email: '',
          displayName: res.user.displayName || user.displayName,
          isGuest: true,
        };
        this.rekeyGuestStorage(user.id, migratedUser.id);
        this.tokenStore.saveSession({
          user: migratedUser,
          accessToken: res.accessToken,
          refreshToken: res.refreshToken,
          sessionId: res.sessionId,
        });
        this.currentUser.set(migratedUser);
        this.sessionExpired.set(false);
      } catch {
        // Offline or server unavailable; legacy token or local cache remains
      }
      return;
    }

    if (this.initGoogleSignIn()) {
      try {
        window.google?.accounts?.id?.prompt();
      } catch {
        // ignore
      }
    }
  }

  private rekeyGuestStorage(oldId: string, newId: string): void {
    if (oldId === newId) return;
    try {
      const syncKeyOld = `ct_web_sync_pending_v2_${oldId}`;
      const syncKeyNew = `ct_web_sync_pending_v2_${newId}`;
      const itemsKeyOld = `ct_web_user_items_pending_v1_${oldId}`;
      const itemsKeyNew = `ct_web_user_items_pending_v1_${newId}`;
      const syncVal = localStorage.getItem(syncKeyOld);
      if (syncVal && !localStorage.getItem(syncKeyNew)) {
        localStorage.setItem(syncKeyNew, syncVal.replaceAll(oldId, newId));
        localStorage.removeItem(syncKeyOld);
      }
      const itemsVal = localStorage.getItem(itemsKeyOld);
      if (itemsVal && !localStorage.getItem(itemsKeyNew)) {
        localStorage.setItem(itemsKeyNew, itemsVal.replaceAll(oldId, newId));
        localStorage.removeItem(itemsKeyOld);
      }
    } catch {
      // ignore
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
