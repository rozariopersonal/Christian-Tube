import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { authInterceptor } from '../api/auth.interceptor';
import { AuthService } from './auth.service';

const googleToken = `header.${btoa(JSON.stringify({ sub: 'u1', email: 'u@example.com', exp: 4102444800 }))}.signature`;
const sessionToken = `session_${'a'.repeat(43)}`;

describe('renewable web session', () => {
  afterEach(() => { TestBed.resetTestingModule(); localStorage.clear(); });

  function setup() {
    localStorage.setItem('current_user', JSON.stringify({ id: 'u1', email: 'u@example.com', displayName: 'User', idToken: googleToken }));
    localStorage.setItem('auth_token', googleToken);
    TestBed.configureTestingModule({ providers: [provideHttpClient(withInterceptors([authInterceptor])), provideHttpClientTesting()] });
    const auth = TestBed.inject(AuthService);
    return { auth, http: TestBed.inject(HttpTestingController) };
  }

  it('upgrades a valid existing Google credential and keeps the session across reloads', async () => {
    const { auth, http } = setup();
    const exchange = http.expectOne((r) => r.url.endsWith('/api/auth/session') && r.method === 'POST');
    expect(exchange.request.headers.get('Authorization')).toBe(`Bearer ${googleToken}`);
    exchange.flush({ token: sessionToken });
    await Promise.resolve();
    expect(localStorage.getItem('auth_token')).toBe(sessionToken);
    expect(JSON.parse(localStorage.getItem('current_user')!).idToken).toBeUndefined();
    expect(auth.canSync()).toBe(true);
    http.match((r) => r.url.includes('/channels/check-admin')).forEach((r) => r.flush({ isAdmin: false }));
    http.verify();
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting()] });
    const reloaded = TestBed.inject(AuthService);
    expect(reloaded.canSync()).toBe(true);
    const reloadHttp = TestBed.inject(HttpTestingController);
    reloadHttp.expectNone((r) => r.url.endsWith('/api/auth/session'));
    reloadHttp.match((r) => r.url.includes('/channels/check-admin')).forEach((r) => r.flush({ isAdmin: false }));
  });

  it('does not restore a session after sign-out during exchange', async () => {
    const { auth, http } = setup();
    const exchange = http.expectOne((r) => r.url.endsWith('/api/auth/session') && r.method === 'POST');
    auth.signOut();
    exchange.flush({ token: sessionToken });
    await Promise.resolve();
    const revoke = http.expectOne((r) => r.url.endsWith('/api/auth/session') && r.method === 'DELETE');
    expect(revoke.request.headers.get('Authorization')).toBe(`Bearer ${sessionToken}`);
    revoke.flush(null);
    expect(auth.currentUser()).toBeNull();
    expect(localStorage.getItem('auth_token')).toBeNull();
    http.match((r) => r.url.includes('/channels/check-admin')).forEach((r) => r.flush({ isAdmin: false }));
  });
});
