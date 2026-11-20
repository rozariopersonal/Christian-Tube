import { provideHttpClient } from '@angular/common/http';
import {
  HttpTestingController,
  provideHttpClientTesting,
} from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { AuthService } from '../auth/auth.service';
import { UserSyncService } from './user-sync.service';

describe('UserSyncService', () => {
  let httpMock: HttpTestingController;
  let authService: AuthService;
  let userSync: UserSyncService;

  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    httpMock = TestBed.inject(HttpTestingController);
    authService = TestBed.inject(AuthService);
    userSync = TestBed.inject(UserSyncService);
  });

  afterEach(() => {
    httpMock.verify();
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('coalesces multiple updates to the same (itemType, itemId) in pendingOps', async () => {
    authService.currentUser.set({
      id: 'user-1',
      email: 'u1@example.com',
      displayName: 'U1',
    });
    TestBed.flushEffects();
    await Promise.resolve();

    const stateReq = httpMock.expectOne((r) => r.url.endsWith('/api/user/state'));
    stateReq.flush({ serverTime: Date.now() + 5000 });
    await Promise.resolve();

    userSync.enqueueWatchItem({
      itemType: 'video_playhead',
      itemId: 'vid-1',
      positionSeconds: 10,
    });
    userSync.enqueueWatchItem({
      itemType: 'video_playhead',
      itemId: 'vid-1',
      positionSeconds: 45,
    });

    const pending = userSync.pendingOps();
    expect(Object.keys(pending)).toEqual(['video_playhead:vid-1']);
    expect(pending['video_playhead:vid-1'].positionSeconds).toBe(45);

    const batchReqs = httpMock.match((r) =>
      r.url.endsWith('/api/user/watch-items/batch'),
    );
    expect(batchReqs.length).toBeGreaterThanOrEqual(1);
    batchReqs.forEach((req) =>
      req.flush({
        results: (req.request.body.items as Array<{ opId: string }>).map(
          (i) => ({ opId: i.opId, status: 'ok' }),
        ),
      }),
    );
    await Promise.resolve();
  });

  it('preserves pending ops on 401 and drops rejected ops on 404', async () => {
    authService.currentUser.set({
      id: 'user-1',
      email: 'u1@example.com',
      displayName: 'U1',
    });
    TestBed.flushEffects();
    await Promise.resolve();

    const stateReq = httpMock.expectOne((r) => r.url.endsWith('/api/user/state'));
    stateReq.flush({ serverTime: Date.now() });
    await Promise.resolve();

    userSync.enqueueSubscription('ch-deleted', true);
    const subReq = httpMock.expectOne((r) =>
      r.url.endsWith('/api/channels/ch-deleted/subscribe'),
    );
    subReq.flush({ message: 'Not found' }, { status: 404, statusText: 'Not Found' });
    await Promise.resolve();
    expect(userSync.pendingOps()['sub:ch-deleted']).toBeUndefined();

    userSync.enqueueSubscription('ch-valid', true);
    const subReq2 = httpMock.expectOne((r) =>
      r.url.endsWith('/api/channels/ch-valid/subscribe'),
    );
    subReq2.flush({ message: 'Unauthorized' }, { status: 401, statusText: 'Unauthorized' });
    await Promise.resolve();
    expect(userSync.pendingOps()['sub:ch-valid']).toBeDefined();
  });

  it('hands off guest pending ops to authenticated user on Google sign-in', async () => {
    authService.currentUser.set({
      id: 'guest_123',
      email: 'guest_123@christianapp.local',
      displayName: 'Guest',
    });
    TestBed.flushEffects();
    await Promise.resolve();

    const guestStateReq = httpMock.expectOne((r) => r.url.endsWith('/api/user/state'));
    guestStateReq.flush({ serverTime: Date.now() });
    await Promise.resolve();

    userSync.enqueueSubscription('ch-guest', true);
    const guestSubReq = httpMock.expectOne((r) =>
      r.url.endsWith('/api/channels/ch-guest/subscribe'),
    );
    guestSubReq.flush(null, { status: 503, statusText: 'Unavailable' });
    await Promise.resolve();
    expect(userSync.pendingOps()['sub:ch-guest']).toBeDefined();

    // Sign in as Google user
    authService.currentUser.set({
      id: 'google-sub-999',
      email: 'user@gmail.com',
      displayName: 'Real User',
    });
    TestBed.flushEffects();
    await Promise.resolve();

    const handoffSubReq = httpMock.expectOne((r) =>
      r.url.endsWith('/api/channels/ch-guest/subscribe'),
    );
    handoffSubReq.flush({ status: 'subscribed', channelId: 'ch-guest' });
    await new Promise((r) => setTimeout(r, 0));

    const userStateReq = httpMock.expectOne((r) => r.url.endsWith('/api/user/state'));
    userStateReq.flush({ serverTime: Date.now(), subscriptions: ['ch-guest'] });
    await Promise.resolve();
  });

  it('clears all on-device user data from localStorage on signOut', () => {
    localStorage.setItem('current_user', JSON.stringify({ id: 'u1' }));
    localStorage.setItem('auth_token', 'tok');
    localStorage.setItem('subscribed_channel_ids_u1', JSON.stringify(['ch-1']));
    localStorage.setItem('ct_web_watch_history_v1_u1', JSON.stringify([{ id: 'v1' }]));
    localStorage.setItem('ct_web_sync_pending_v2_u1', JSON.stringify({ x: 1 }));
    localStorage.setItem('audio_last_track', JSON.stringify({ id: 't1' }));

    authService.signOut();

    expect(localStorage.getItem('current_user')).toBeNull();
    expect(localStorage.getItem('auth_token')).toBeNull();
    expect(localStorage.getItem('subscribed_channel_ids_u1')).toBeNull();
    expect(localStorage.getItem('ct_web_watch_history_v1_u1')).toBeNull();
    expect(localStorage.getItem('ct_web_sync_pending_v2_u1')).toBeNull();
    expect(localStorage.getItem('audio_last_track')).toBeNull();
  });
});
