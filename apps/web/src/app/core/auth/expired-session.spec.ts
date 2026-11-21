import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { AuthService } from './auth.service';
import { UserSyncService } from '../services/user-sync.service';
import { UserItemsSyncService } from '../services/user-items-sync.service';

describe('expired account session', () => {
  it('keeps local pending changes and does not send sync requests', async () => {
    localStorage.clear();
    const payload = btoa(JSON.stringify({ exp: Math.floor(Date.now() / 1000) - 60 }));
    localStorage.setItem('auth_token', `header.${payload}.signature`);
    localStorage.setItem('current_user', JSON.stringify({ id: 'u1', email: '', displayName: 'User' }));
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting()] });
    const auth = TestBed.inject(AuthService);
    const sync = TestBed.inject(UserSyncService);
    TestBed.inject(UserItemsSyncService);
    const http = TestBed.inject(HttpTestingController);
    TestBed.flushEffects();
    sync.enqueueWatchItem({ itemType: 'video_playhead', itemId: 'v1', positionSeconds: 5 });
    await Promise.resolve();
    expect(auth.sessionNeedsSignIn()).toBe(true);
    expect(Object.keys(sync.pendingOps())).toContain('video_playhead:v1');
    http.expectNone((request) => request.url.includes('/api/user/'));
    http.verify();
    TestBed.resetTestingModule();
    localStorage.clear();
  });
});
