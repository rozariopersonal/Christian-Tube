import { Injectable } from '@angular/core';

export const KEY_USER = 'current_user';
export const KEY_ACCESS_TOKEN = 'auth_access_token';
export const KEY_REFRESH_TOKEN = 'auth_refresh_token';
export const KEY_SESSION_ID = 'auth_session_id';
export const KEY_DEVICE_ID = 'auth_device_id';
export const KEY_SESSION_EXPIRED = 'auth_session_expired';
const LEGACY_KEY_TOKEN = 'auth_token';

export interface StoredAuthUser {
  id: string;
  email: string;
  displayName: string;
  photoUrl?: string;
  idToken?: string;
}

export interface AuthBroadcastMessage {
  type: 'session_updated' | 'session_expired' | 'signed_out';
  userId?: string;
}

@Injectable({ providedIn: 'root' })
export class AuthTokenStore {
  private channel: BroadcastChannel | null = null;

  constructor() {
    if (typeof BroadcastChannel !== 'undefined') {
      try {
        this.channel = new BroadcastChannel('auth');
      } catch {
        this.channel = null;
      }
    }
  }

  getDeviceId(): string {
    try {
      const existing = localStorage.getItem(KEY_DEVICE_ID);
      if (existing && existing.trim().length > 0) {
        return existing;
      }
      const generated =
        typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
          ? crypto.randomUUID()
          : `web_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
      localStorage.setItem(KEY_DEVICE_ID, generated);
      return generated;
    } catch {
      return `web_ephemeral_${Date.now()}`;
    }
  }

  getDeviceLabel(): string {
    if (typeof navigator === 'undefined') return 'Web Browser';
    const ua = navigator.userAgent || '';
    if (ua.includes('Edg/')) return 'Edge Web';
    if (ua.includes('Chrome/')) return 'Chrome Web';
    if (ua.includes('Firefox/')) return 'Firefox Web';
    if (ua.includes('Safari/')) return 'Safari Web';
    return 'Web Browser';
  }

  getAccessToken(): string | null {
    try {
      const current = localStorage.getItem(KEY_ACCESS_TOKEN);
      if (current && current.trim().length > 0) return current;

      const legacy = localStorage.getItem(LEGACY_KEY_TOKEN);
      if (legacy && legacy.trim().length > 0) {
        localStorage.setItem(KEY_ACCESS_TOKEN, legacy);
        localStorage.removeItem(LEGACY_KEY_TOKEN);
        return legacy;
      }
      return null;
    } catch {
      return null;
    }
  }

  getRefreshToken(): string | null {
    try {
      const val = localStorage.getItem(KEY_REFRESH_TOKEN);
      return val && val.trim().length > 0 ? val : null;
    } catch {
      return null;
    }
  }

  getSessionId(): string | null {
    try {
      const val = localStorage.getItem(KEY_SESSION_ID);
      return val && val.trim().length > 0 ? val : null;
    } catch {
      return null;
    }
  }

  readUser(): StoredAuthUser | null {
    try {
      const raw = localStorage.getItem(KEY_USER);
      return raw ? (JSON.parse(raw) as StoredAuthUser) : null;
    } catch {
      return null;
    }
  }

  readSessionExpired(): boolean {
    try {
      return localStorage.getItem(KEY_SESSION_EXPIRED) === 'true';
    } catch {
      return false;
    }
  }

  saveSession(params: {
    user?: StoredAuthUser;
    accessToken: string;
    refreshToken?: string | null;
    sessionId?: string | null;
  }): void {
    try {
      if (params.user) {
        localStorage.setItem(KEY_USER, JSON.stringify(params.user));
      }
      localStorage.setItem(KEY_ACCESS_TOKEN, params.accessToken);
      localStorage.removeItem(LEGACY_KEY_TOKEN);
      if (params.refreshToken) {
        localStorage.setItem(KEY_REFRESH_TOKEN, params.refreshToken);
      }
      if (params.sessionId) {
        localStorage.setItem(KEY_SESSION_ID, params.sessionId);
      }
      localStorage.setItem(KEY_SESSION_EXPIRED, 'false');
    } catch {
      // ignore storage quota errors
    }
    this.broadcast({ type: 'session_updated', userId: params.user?.id });
  }

  saveUserOnly(user: StoredAuthUser): void {
    try {
      localStorage.setItem(KEY_USER, JSON.stringify(user));
    } catch {
      // ignore
    }
  }

  markSessionExpired(): void {
    try {
      localStorage.removeItem(KEY_ACCESS_TOKEN);
      localStorage.removeItem(KEY_REFRESH_TOKEN);
      localStorage.removeItem(KEY_SESSION_ID);
      localStorage.removeItem(LEGACY_KEY_TOKEN);
      localStorage.setItem(KEY_SESSION_EXPIRED, 'true');
    } catch {
      // ignore
    }
    this.broadcast({ type: 'session_expired' });
  }

  clearAuthSessionKeysOnly(legacyGuestUserId?: string): void {
    try {
      localStorage.removeItem(KEY_USER);
      localStorage.removeItem(KEY_ACCESS_TOKEN);
      localStorage.removeItem(KEY_REFRESH_TOKEN);
      localStorage.removeItem(KEY_SESSION_ID);
      localStorage.removeItem(KEY_SESSION_EXPIRED);
      localStorage.removeItem(LEGACY_KEY_TOKEN);
      localStorage.removeItem('ct_web_last_guest_id_v1');
      if (legacyGuestUserId) {
        localStorage.removeItem(`ct_web_sync_pending_v2_${legacyGuestUserId}`);
        localStorage.removeItem(`ct_web_user_items_pending_v1_${legacyGuestUserId}`);
      }
    } catch {
      // ignore
    }
  }

  wipeAllKeepingDeviceId(): void {
    let existingDeviceId: string | null = null;
    try {
      existingDeviceId = localStorage.getItem(KEY_DEVICE_ID);
      localStorage.clear();
      if (existingDeviceId && existingDeviceId.trim().length > 0) {
        localStorage.setItem(KEY_DEVICE_ID, existingDeviceId);
      }
    } catch {
      // ignore
    }
    try {
      if (typeof sessionStorage !== 'undefined') {
        sessionStorage.clear();
      }
    } catch {
      // ignore
    }
    this.broadcast({ type: 'signed_out' });
  }

  subscribeExternalChanges(
    onChange: (msg: AuthBroadcastMessage) => void,
  ): () => void {
    const cleanups: Array<() => void> = [];

    if (this.channel) {
      const onMsg = (ev: MessageEvent<AuthBroadcastMessage>) => {
        if (ev.data && typeof ev.data.type === 'string') {
          onChange(ev.data);
        }
      };
      this.channel.addEventListener('message', onMsg);
      cleanups.push(() => this.channel?.removeEventListener('message', onMsg));
    }

    if (typeof window !== 'undefined') {
      const onStorage = (ev: StorageEvent) => {
        if (
          ev.key === KEY_ACCESS_TOKEN ||
          ev.key === KEY_SESSION_EXPIRED ||
          ev.key === KEY_USER ||
          ev.key === null
        ) {
          if (this.readSessionExpired()) {
            onChange({ type: 'session_expired' });
          } else if (!this.readUser()) {
            onChange({ type: 'signed_out' });
          } else {
            onChange({ type: 'session_updated' });
          }
        }
      };
      window.addEventListener('storage', onStorage);
      cleanups.push(() => window.removeEventListener('storage', onStorage));
    }

    return () => {
      for (const fn of cleanups) fn();
    };
  }

  private broadcast(msg: AuthBroadcastMessage): void {
    try {
      this.channel?.postMessage(msg);
    } catch {
      // ignore
    }
  }
}
