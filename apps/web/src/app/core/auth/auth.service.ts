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
  readonly sessionExpired = signal<boolean>(this.computeInitialExpired());
  readonly sessionNeedsSignIn = this.sessionExpired;
  readonly sessionPromptDismissed = signal<boolean>(false);
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
  private legacyUpgradeStarted = false;
  private signedOutDuringUpgrade = false;
  private unsubExternal: (() => void) | null = null;

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
    if (user && user.id.startsWith('guest_')) {
      this.tokenStore.clearAuthSessionKeysOnly(user.id);
      this.currentUser.set(null);
      this.sessionExpired.set(false);
    } else {
      if (user?.email) {
        void this.checkIsAdmin(user.email);
      }
      if (user && !this.tokenStore.getRefreshToken() && !this.sessionExpired()) {
        void this.upgradeLegacyGoogleSession(user);
      }
    }
  }

  ngOnDestroy(): void {
    this.unsubExternal?.();
    this.unsubExternal = null;
  }

  markSessionRejected(): void {
    this.tokenStore.markSessionExpired();
    this.sessionPromptDismissed.set(false);
    this.sessionExpired.set(true);
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

  renderGoogleButton(element: HTMLElement): boolean {
    if (!this.initGoogleSignIn()) return false;
    element.innerHTML = '';
    window.google?.accounts?.id?.renderButton(element, {
      theme: 'outline',
      size: 'large',
      width: 280,
      text: 'continue_with',
    });
    return true;
  }

  promptGoogleSignIn(): void {
    if (!this.initGoogleSignIn()) {
      this.lastError.set('Google Sign-In is still loading. Please try again.');
      return;
    }
    window.google?.accounts?.id?.prompt();
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
    this.signedOutDuringUpgrade = true;
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
    this.sessionPromptDismissed.set(false);
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

      if (existing !== null && nextSub && existing.id !== nextSub) {
        const confirmed = await this.confirmAccountSwitch(existing, {
          id: nextSub,
          email: nextEmail,
          displayName: nextName,
          photoUrl: nextPhoto,
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
      this.sessionPromptDismissed.set(false);
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

  private computeInitialExpired(): boolean {
    if (this.tokenStore.readSessionExpired()) return true;
    const user = this.tokenStore.readUser();
    if (!user) return false;
    if (this.tokenStore.getRefreshToken()) return false;

    const token = this.tokenStore.getAccessToken() ?? user.idToken;
    if (!token) return true;
    if (token.startsWith('session_')) return false;

    const payload = this.decodeJwtPayload(token);
    const exp = typeof payload['exp'] === 'number' ? payload['exp'] : null;
    if (exp !== null && exp * 1000 <= Date.now()) {
      this.tokenStore.markSessionExpired();
      return true;
    }
    return false;
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

  private async upgradeLegacyGoogleSession(user: AuthUser): Promise<void> {
    if (this.legacyUpgradeStarted) return;
    this.legacyUpgradeStarted = true;
    this.signedOutDuringUpgrade = false;

    const legacyToken = this.tokenStore.getAccessToken() ?? user.idToken;
    if (
      !legacyToken ||
      legacyToken.startsWith('session_') ||
      legacyToken.split('.').length !== 3
    ) {
      return;
    }

    const payload = this.decodeJwtPayload(legacyToken);
    const exp = typeof payload['exp'] === 'number' ? payload['exp'] : null;
    if (exp === null || exp * 1000 <= Date.now()) {
      return;
    }

    try {
      const res = await firstValueFrom(
        this.rawHttp.post<BackendSessionResponse>(
          `${AppConfig.apiBaseUrl}/api/auth/google`,
          {
            idToken: legacyToken,
            deviceId: this.tokenStore.getDeviceId(),
            deviceLabel: this.tokenStore.getDeviceLabel(),
          },
        ),
      );
      if (this.signedOutDuringUpgrade) {
        void firstValueFrom(
          this.rawHttp.post(
            `${AppConfig.apiBaseUrl}/api/auth/logout`,
            {},
            { headers: { Authorization: `Bearer ${res.accessToken}` } },
          ),
        ).catch(() => {});
        return;
      }
      const upgraded: AuthUser = {
        id: res.user.id,
        email: res.user.email ?? user.email,
        displayName: res.user.displayName || user.displayName,
        photoUrl: res.user.photoUrl ?? user.photoUrl,
      };
      this.tokenStore.saveSession({
        user: upgraded,
        accessToken: res.accessToken,
        refreshToken: res.refreshToken,
        sessionId: res.sessionId,
      });
      this.currentUser.set(upgraded);
      this.sessionExpired.set(false);
    } catch {
      // Non-fatal if offline or backend unavailable
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
