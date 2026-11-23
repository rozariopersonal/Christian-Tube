import {
  HttpClient,
  provideHttpClient,
  withInterceptors,
} from '@angular/common/http';
import {
  HttpTestingController,
  provideHttpClientTesting,
} from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { firstValueFrom } from 'rxjs';
import { authInterceptor } from '../api/auth.interceptor';
import { AppConfig } from '../config/app-config';
import { UserSyncService } from '../services/user-sync.service';
import {
  AuthTokenStore,
  KEY_ACCESS_TOKEN,
  KEY_DEVICE_ID,
  KEY_REFRESH_TOKEN,
  KEY_SESSION_EXPIRED,
  KEY_SESSION_ID,
  KEY_USER,
} from './auth-token.store';
import { AuthService } from './auth.service';

function makeFakeJwt(payload: Record<string, unknown>): string {
  const header = btoa(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const body = btoa(JSON.stringify(payload));
  return `${header}.${body}.sig`;
}

const tick = () => new Promise<void>((resolve) => setTimeout(resolve, 0));

describe('Web Auth, Interceptor & Sync Gating', () => {
  let http: HttpClient;
  let httpMock: HttpTestingController;
  let auth: AuthService;
  let tokenStore: AuthTokenStore;

  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(withInterceptors([authInterceptor])),
        provideHttpClientTesting(),
      ],
    });
    http = TestBed.inject(HttpClient);
    httpMock = TestBed.inject(HttpTestingController);
    auth = TestBed.inject(AuthService);
    tokenStore = TestBed.inject(AuthTokenStore);
  });

  afterEach(() => {
    try {
      httpMock.verify();
    } finally {
      localStorage.clear();
      TestBed.resetTestingModule();
    }
  });

  it('refreshes once on 401 and replays concurrent requests with the new token', async () => {
    tokenStore.saveSession({
      user: {
        id: 'u_1',
        email: 'u1@example.com',
        displayName: 'User One',
        isGuest: false,
      },
      accessToken: 'expired-access',
      refreshToken: 'refresh-1',
      sessionId: 'sess-1',
    });

    const p1 = firstValueFrom(
      http.get<{ ok: boolean }>(`${AppConfig.apiBaseUrl}/api/videos`),
    );
    const p2 = firstValueFrom(
      http.get<{ ok: boolean }>(`${AppConfig.apiBaseUrl}/api/channels`),
    );

    const r1 = httpMock.expectOne(`${AppConfig.apiBaseUrl}/api/videos`);
    const r2 = httpMock.expectOne(`${AppConfig.apiBaseUrl}/api/channels`);
    expect(r1.request.headers.get('Authorization')).toBe('Bearer expired-access');
    expect(r2.request.headers.get('Authorization')).toBe('Bearer expired-access');

    r1.flush({ message: 'expired' }, { status: 401, statusText: 'Unauthorized' });
    r2.flush({ message: 'expired' }, { status: 401, statusText: 'Unauthorized' });
    await tick();

    const refreshReq = httpMock.expectOne(
      `${AppConfig.apiBaseUrl}/api/auth/refresh`,
    );
    refreshReq.flush({
      accessToken: 'fresh-access',
      refreshToken: 'refresh-2',
      sessionId: 'sess-1',
      expiresIn: 900,
    });
    await tick();

    const retry1 = httpMock.expectOne(`${AppConfig.apiBaseUrl}/api/videos`);
    const retry2 = httpMock.expectOne(`${AppConfig.apiBaseUrl}/api/channels`);
    expect(retry1.request.headers.get('Authorization')).toBe('Bearer fresh-access');
    expect(retry2.request.headers.get('Authorization')).toBe('Bearer fresh-access');
    retry1.flush({ ok: true });
    retry2.flush({ ok: true });

    await expect(p1).resolves.toEqual({ ok: true });
    await expect(p2).resolves.toEqual({ ok: true });
    expect(auth.sessionExpired()).toBe(false);
  });

  it('sets sessionExpired=true when /api/auth/refresh returns 401 and keeps currentUser', async () => {
    tokenStore.saveSession({
      user: {
        id: 'u_1',
        email: 'u1@example.com',
        displayName: 'User One',
        isGuest: false,
      },
      accessToken: 'expired-access',
      refreshToken: 'revoked-refresh',
      sessionId: 'sess-1',
    });
    auth.currentUser.set(tokenStore.readUser());

    const refreshPromise = auth.refreshSession();
    await tick();

    const refreshReq = httpMock.expectOne(
      `${AppConfig.apiBaseUrl}/api/auth/refresh`,
    );
    refreshReq.flush(
      { message: 'Session revoked' },
      { status: 401, statusText: 'Unauthorized' },
    );

    const nextToken = await refreshPromise;
    expect(nextToken).toBeNull();
    expect(auth.sessionExpired()).toBe(true);
    expect(auth.canSync()).toBe(false);
    expect(auth.currentUser()?.id).toBe('u_1');
    expect(localStorage.getItem(KEY_USER)).toBeTruthy();
    expect(localStorage.getItem(KEY_ACCESS_TOKEN)).toBeNull();
    expect(localStorage.getItem(KEY_REFRESH_TOKEN)).toBeNull();
  });

  it('does NOT mark sessionExpired on network/5xx error during refresh', async () => {
    tokenStore.saveSession({
      user: {
        id: 'u_1',
        email: 'u1@example.com',
        displayName: 'User One',
        isGuest: false,
      },
      accessToken: 'expired-access',
      refreshToken: 'refresh-1',
      sessionId: 'sess-1',
    });
    auth.currentUser.set(tokenStore.readUser());

    const refreshPromise = auth.refreshSession();
    await tick();

    const refreshReq = httpMock.expectOne(
      `${AppConfig.apiBaseUrl}/api/auth/refresh`,
    );
    refreshReq.flush(
      { message: 'Bad Gateway' },
      { status: 502, statusText: 'Bad Gateway' },
    );

    const nextToken = await refreshPromise;
    expect(nextToken).toBeNull();
    expect(auth.sessionExpired()).toBe(false);
    expect(auth.canSync()).toBe(true);
  });

  it('syncs sessionExpired and access token from cross-tab storage events', () => {
    localStorage.setItem(KEY_SESSION_EXPIRED, 'true');
    window.dispatchEvent(
      new StorageEvent('storage', { key: KEY_SESSION_EXPIRED, newValue: 'true' }),
    );
    expect(auth.sessionExpired()).toBe(true);

    localStorage.setItem(
      KEY_USER,
      JSON.stringify({ id: 'u2', email: 'u2@x.com', displayName: 'U2' }),
    );
    localStorage.setItem(KEY_SESSION_EXPIRED, 'false');
    localStorage.setItem(KEY_ACCESS_TOKEN, 'tab2-token');
    window.dispatchEvent(
      new StorageEvent('storage', { key: KEY_ACCESS_TOKEN, newValue: 'tab2-token' }),
    );
    expect(auth.sessionExpired()).toBe(false);
    expect(auth.currentUser()?.id).toBe('u2');
  });

  it('preserves auth_device_id across signOut', () => {
    const devId = tokenStore.getDeviceId();
    tokenStore.saveSession({
      user: {
        id: 'u_1',
        email: 'u1@example.com',
        displayName: 'U1',
        isGuest: false,
      },
      accessToken: 'tok',
      refreshToken: 'ref',
      sessionId: 'sid-1',
    });
    auth.signOut();
    httpMock.match(`${AppConfig.apiBaseUrl}/api/auth/logout`).forEach((r) => r.flush({ ok: true }));
    expect(localStorage.getItem(KEY_DEVICE_ID)).toBe(devId);
    expect(auth.currentUser()).toBeNull();
  });

  it('guards account switch with confirmation and wipes previous local data on confirm', async () => {
    tokenStore.saveSession({
      user: {
        id: 'sub_old',
        email: 'old@example.com',
        displayName: 'Old User',
        isGuest: false,
      },
      accessToken: 'tok-old',
      refreshToken: 'ref-old',
      sessionId: 'sid-old',
    });
    auth.currentUser.set(tokenStore.readUser());
    localStorage.setItem('ct_web_sync_pending_v2_sub_old', '{"k":"v"}');

    const newJwt = makeFakeJwt({
      sub: 'sub_new',
      email: 'new@example.com',
      name: 'New User',
    });

    const credPromise = auth.handleGoogleCredential(newJwt);
    await tick();

    expect(auth.pendingAccountSwitch()).not.toBeNull();
    auth.resolveAccountSwitch(true);
    await tick();

    httpMock
      .match(`${AppConfig.apiBaseUrl}/api/auth/logout`)
      .forEach((r) => r.flush({ ok: true }));

    const googleReq = httpMock.expectOne(`${AppConfig.apiBaseUrl}/api/auth/google`);
    googleReq.flush({
      accessToken: 'tok-new',
      refreshToken: 'ref-new',
      sessionId: 'sid-new',
      expiresIn: 900,
      user: {
        id: 'sub_new',
        email: 'new@example.com',
        displayName: 'New User',
        photoUrl: null,
        isGuest: false,
      },
    });
    await tick();

    httpMock.match(`${AppConfig.apiBaseUrl}/api/users/sync`).forEach((r) => r.flush({}));
    await tick();
    httpMock
      .match((r) => r.url.includes('/channels/check-admin'))
      .forEach((r) => r.flush({ isAdmin: false }));

    await credPromise;
    expect(localStorage.getItem('ct_web_sync_pending_v2_sub_old')).toBeNull();
    expect(auth.currentUser()?.id).toBe('sub_new');
    expect(localStorage.getItem(KEY_SESSION_ID)).toBe('sid-new');
  });

  it('gates UserSyncService on canSync and flushes when sessionExpired recovers', async () => {
    const userSync = TestBed.inject(UserSyncService);

    auth.sessionExpired.set(true);
    auth.currentUser.set({
      id: 'u_1',
      email: 'u1@example.com',
      displayName: 'U1',
      isGuest: false,
    });
    TestBed.flushEffects();
    await tick();

    userSync.enqueuePreference('themeMode', 'dark');
    httpMock.expectNone(`${AppConfig.apiBaseUrl}/api/user/state`);
    httpMock.expectNone(`${AppConfig.apiBaseUrl}/api/user/preferences`);

    auth.sessionExpired.set(false);
    TestBed.flushEffects();
    await tick();

    const prefReq = httpMock.expectOne(
      (r) => r.url.endsWith('/api/user/preferences') && r.method === 'PATCH',
    );
    prefReq.flush({});
    await tick();

    const stateReq = httpMock.expectOne((r) => r.url.endsWith('/api/user/state'));
    stateReq.flush({ serverTime: Date.now() });
  });
});
