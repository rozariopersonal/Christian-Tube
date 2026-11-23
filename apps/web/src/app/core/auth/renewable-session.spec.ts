import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { authInterceptor } from '../api/auth.interceptor';
import { AuthService } from './auth.service';
import {
  KEY_ACCESS_TOKEN,
  KEY_REFRESH_TOKEN,
  KEY_SESSION_ID,
} from './auth-token.store';

const googleToken = `header.${btoa(JSON.stringify({ sub: 'u1', email: 'u@example.com', exp: 4102444800 }))}.signature`;

describe('renewable web session', () => {
  afterEach(() => {
    TestBed.resetTestingModule();
    localStorage.clear();
  });

  function setup() {
    localStorage.setItem(
      'current_user',
      JSON.stringify({
        id: 'u1',
        email: 'u@example.com',
        displayName: 'User',
        idToken: googleToken,
      }),
    );
    localStorage.setItem('auth_token', googleToken);
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(withInterceptors([authInterceptor])),
        provideHttpClientTesting(),
      ],
    });
    const auth = TestBed.inject(AuthService);
    return { auth, http: TestBed.inject(HttpTestingController) };
  }

  it('upgrades a valid existing Google credential and keeps the session across reloads', async () => {
    const { auth, http } = setup();
    const exchange = http.expectOne(
      (r) => r.url.endsWith('/api/auth/google') && r.method === 'POST',
    );
    exchange.flush({
      accessToken: 'jwt-access-1',
      refreshToken: 'refresh-token-1',
      sessionId: 'sess-1',
      expiresIn: 900,
      user: {
        id: 'u1',
        email: 'u@example.com',
        displayName: 'User',
        photoUrl: null,
        isGuest: false,
      },
    });
    await Promise.resolve();
    expect(localStorage.getItem(KEY_ACCESS_TOKEN)).toBe('jwt-access-1');
    expect(localStorage.getItem(KEY_REFRESH_TOKEN)).toBe('refresh-token-1');
    expect(localStorage.getItem(KEY_SESSION_ID)).toBe('sess-1');
    expect(JSON.parse(localStorage.getItem('current_user')!).idToken).toBeUndefined();
    expect(auth.canSync()).toBe(true);
    http
      .match((r) => r.url.includes('/channels/check-admin'))
      .forEach((r) => r.flush({ isAdmin: false }));
    http.verify();
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    const reloaded = TestBed.inject(AuthService);
    expect(reloaded.canSync()).toBe(true);
    const reloadHttp = TestBed.inject(HttpTestingController);
    reloadHttp.expectNone((r) => r.url.endsWith('/api/auth/google'));
    reloadHttp
      .match((r) => r.url.includes('/channels/check-admin'))
      .forEach((r) => r.flush({ isAdmin: false }));
  });

  it('does not restore a session after sign-out during exchange', async () => {
    const { auth, http } = setup();
    const exchange = http.expectOne(
      (r) => r.url.endsWith('/api/auth/google') && r.method === 'POST',
    );
    auth.signOut();
    exchange.flush({
      accessToken: 'jwt-access-1',
      refreshToken: 'refresh-token-1',
      sessionId: 'sess-1',
      expiresIn: 900,
      user: {
        id: 'u1',
        email: 'u@example.com',
        displayName: 'User',
        photoUrl: null,
        isGuest: false,
      },
    });
    await Promise.resolve();
    const revoke = http.expectOne(
      (r) => r.url.endsWith('/api/auth/logout') && r.method === 'POST',
    );
    expect(revoke.request.headers.get('Authorization')).toBe('Bearer jwt-access-1');
    revoke.flush({ ok: true });
    expect(auth.currentUser()).toBeNull();
    expect(localStorage.getItem(KEY_ACCESS_TOKEN)).toBeNull();
    http
      .match((r) => r.url.includes('/channels/check-admin'))
      .forEach((r) => r.flush({ isAdmin: false }));
  });
});
