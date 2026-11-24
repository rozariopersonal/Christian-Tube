import { provideHttpClient } from '@angular/common/http';
import {
  HttpTestingController,
  provideHttpClientTesting,
} from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { AuthService } from '../auth/auth.service';
import {
  ContentPreferencesService,
  normalizeDefaultPage,
  resolveDefaultWebRoute,
} from './content-preferences.service';
import { UserSyncService } from './user-sync.service';

describe('ContentPreferencesService defaultPage', () => {
  let httpMock: HttpTestingController;
  let authService: AuthService;
  let userSync: UserSyncService;
  let prefs: ContentPreferencesService;

  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    httpMock = TestBed.inject(HttpTestingController);
    authService = TestBed.inject(AuthService);
    userSync = TestBed.inject(UserSyncService);
    prefs = TestBed.inject(ContentPreferencesService);
  });

  afterEach(() => {
    httpMock.match((r) => r.url.includes('manifest.json')).forEach((r) => r.flush({}));
    httpMock.verify();
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('normalizes and resolves default page routes across platforms', () => {
    expect(normalizeDefaultPage(undefined)).toBe('feed');
    expect(normalizeDefaultPage('books')).toBe('library');
    expect(normalizeDefaultPage('Bible')).toBe('bible');
    expect(normalizeDefaultPage('unknown')).toBe('feed');

    expect(resolveDefaultWebRoute('feed')).toBe('feed');
    expect(resolveDefaultWebRoute('shorts')).toBe('shorts');
    expect(resolveDefaultWebRoute('bible')).toBe('bible');
    expect(resolveDefaultWebRoute('words')).toBe('words');
    expect(resolveDefaultWebRoute('library')).toBe('books');
    expect(resolveDefaultWebRoute('books')).toBe('books');
    expect(resolveDefaultWebRoute('articles')).toBe('articles');
    expect(resolveDefaultWebRoute('audio')).toBe('audio');
  });

  it('isolates defaultPage per user and syncs with UserSyncService', async () => {
    expect(prefs.defaultPage()).toBe('feed');
    expect(prefs.defaultRoute()).toBe('feed');

    authService.currentUser.set({
      id: 'user-a',
      email: 'a@example.com',
      displayName: 'User A',
    });
    TestBed.flushEffects();
    await Promise.resolve();

    const stateReqA = httpMock.expectOne((r) => r.url.endsWith('/api/user/state'));
    stateReqA.flush({
      serverTime: Date.now(),
      preferences: { defaultPage: 'bible' },
    });
    await Promise.resolve();
    TestBed.flushEffects();

    expect(prefs.defaultPage()).toBe('bible');
    expect(prefs.defaultRoute()).toBe('bible');

    prefs.setDefaultPage('library');
    expect(prefs.defaultPage()).toBe('library');
    expect(prefs.defaultRoute()).toBe('books');
    expect(userSync.pendingOps()['pref:defaultPage']?.prefValue).toBe('library');

    const patchReq = httpMock.expectOne((r) =>
      r.url.endsWith('/api/user/preferences') && r.method === 'PATCH',
    );
    expect(patchReq.request.body.defaultPage).toBe('library');
    patchReq.flush({ defaultPage: 'library' });
    await Promise.resolve();

    // Switching to another user loads that user's own defaultPage.
    authService.currentUser.set({
      id: 'user-b',
      email: 'b@example.com',
      displayName: 'User B',
    });
    TestBed.flushEffects();
    await Promise.resolve();

    expect(prefs.defaultPage()).toBe('feed');
    const stateReqB = httpMock.expectOne((r) => r.url.endsWith('/api/user/state'));
    stateReqB.flush({
      serverTime: Date.now(),
      preferences: { defaultPage: 'shorts' },
    });
    await Promise.resolve();
    TestBed.flushEffects();

    expect(prefs.defaultPage()).toBe('shorts');
    expect(prefs.defaultRoute()).toBe('shorts');
  });
});
