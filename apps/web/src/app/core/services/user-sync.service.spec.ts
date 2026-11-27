import { provideHttpClient } from '@angular/common/http';
import {
  HttpTestingController,
  provideHttpClientTesting,
} from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { AuthService } from '../auth/auth.service';
import { AudioPlayerService } from '../../features/audio/services/audio-player.service';
import { BibleService } from '../../features/bible/services/bible.service';
import { BookHighlightsService } from '../../features/books/services/book-highlights.service';
import { ChannelService } from '../../features/channels/services/channel.service';
import { VideoLibraryService } from '../../features/videos/services/video-library.service';
import { ContentPreferencesService } from './content-preferences.service';
import { UserItemsSyncService } from './user-items-sync.service';
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

  it('keeps a followed channel when an older state pull completes after the write', async () => {
    authService.currentUser.set({
      id: 'user-1',
      email: 'u1@example.com',
      displayName: 'U1',
    });
    TestBed.flushEffects();
    await Promise.resolve();
    httpMock.expectOne((r) => r.url.endsWith('/api/user/state'))
      .flush({ serverTime: Date.now(), subscriptions: [] });
    await Promise.resolve();

    const pull = userSync.pullAndFlush(true);
    await Promise.resolve();
    const stale = httpMock.expectOne((r) => r.url.endsWith('/api/user/state'));

    userSync.enqueueSubscription('ch-new', true);
    httpMock.expectOne((r) => r.url.endsWith('/api/channels/ch-new/subscribe'))
      .flush({ status: 'subscribed', channelId: 'ch-new' });
    await Promise.resolve();
    expect(userSync.pendingOps()['sub:ch-new']).toBeUndefined();

    stale.flush({ serverTime: Date.now(), subscriptions: [] });
    await pull;
    expect(userSync.remoteState()?.subscriptions).toEqual(['ch-new']);
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

  it('isolates pending ops per userId without cross-user handoff', async () => {
    authService.currentUser.set({
      id: 'user-a',
      email: 'a@example.com',
      displayName: 'User A',
    });
    TestBed.flushEffects();
    await Promise.resolve();

    const stateReqA = httpMock.expectOne((r) => r.url.endsWith('/api/user/state'));
    stateReqA.flush({ serverTime: Date.now() });
    await Promise.resolve();

    userSync.enqueueSubscription('ch-a', true);
    const subReqA = httpMock.expectOne((r) =>
      r.url.endsWith('/api/channels/ch-a/subscribe'),
    );
    subReqA.flush(null, { status: 503, statusText: 'Unavailable' });
    await Promise.resolve();
    expect(userSync.pendingOps()['sub:ch-a']).toBeDefined();

    // Switch to another authenticated user
    authService.currentUser.set({
      id: 'user-b',
      email: 'b@example.com',
      displayName: 'User B',
    });
    TestBed.flushEffects();
    await Promise.resolve();

    httpMock.expectNone((r) =>
      r.url.endsWith('/api/channels/ch-a/subscribe'),
    );
    const stateReqB = httpMock.expectOne((r) => r.url.endsWith('/api/user/state'));
    stateReqB.flush({ serverTime: Date.now(), subscriptions: [] });
    await Promise.resolve();

    expect(userSync.pendingOps()).toEqual({});
  });

  it('clears all on-device user data from localStorage on signOut', async () => {
    const channels = TestBed.inject(ChannelService);
    const videoLibrary = TestBed.inject(VideoLibraryService);

    localStorage.setItem('current_user', JSON.stringify({ id: 'u1' }));
    localStorage.setItem('auth_token', 'tok');
    localStorage.setItem('subscribed_channel_ids_u1', JSON.stringify(['ch-1']));
    localStorage.setItem('ct_web_watch_history_v1_u1', JSON.stringify([{ id: 'v1' }]));
    localStorage.setItem('ct_web_sync_pending_v2_u1', JSON.stringify({ x: 1 }));
    localStorage.setItem('audio_last_track', JSON.stringify({ id: 't1' }));
    localStorage.setItem('theme_mode', 'dark');

    authService.signOut();
    TestBed.flushEffects();
    await Promise.resolve();

    expect(localStorage.length).toBe(0);
    expect(channels.subscribedIds()).toEqual([]);
    expect(videoLibrary.history()).toEqual([]);
  });

  it('hydrates all feature services from remoteState without re-triggering infinite effect loops', async () => {
    const videoLibrary = TestBed.inject(VideoLibraryService);
    const channels = TestBed.inject(ChannelService);
    const prefs = TestBed.inject(ContentPreferencesService);
    const bookHighlights = TestBed.inject(BookHighlightsService);
    const bible = TestBed.inject(BibleService);
    const audio = TestBed.inject(AudioPlayerService);
    TestBed.inject(UserItemsSyncService);

    authService.currentUser.set({
      id: 'u-full',
      email: 'full@example.com',
      displayName: 'Full User',
    });
    TestBed.flushEffects();
    await Promise.resolve();

    const subsReq = httpMock.expectOne((r) => r.url.endsWith('/api/channels/subscriptions'));
    subsReq.flush({ channelIds: ['ch-1'], channels: [] });

    const stateReq = httpMock.expectOne((r) => r.url.endsWith('/api/user/state'));
    stateReq.flush({
      serverTime: Date.now(),
      preferences: { languages: ['en', 'ta'], themeMode: 'dark' },
      subscriptions: ['ch-1'],
      watchLater: [{ video: { id: 'v1', title: 'Video 1' }, updatedAt: 1000 }],
      videoHistory: [
        {
          video: { id: 'v2', title: 'Video 2' },
          progressSeconds: 30,
          durationSeconds: 120,
          watchedAt: 2000,
        },
      ],
      videoPlayheads: { v2: { positionSeconds: 30, updatedAt: 2000 } },
      audioPlayback: {
        trackId: 't1',
        positionSeconds: 15,
        durationSeconds: 300,
        updatedAt: 3000,
      },
    });

    const itemsReq = httpMock.expectOne((r) => r.url.endsWith('/api/user/items'));
    itemsReq.flush({
      serverTime: Date.now(),
      items: [
        {
          id: 'range:book:b1:0:1:0-5',
          itemType: 'text_range',
          feature: 'book',
          targetId: 'book:b1:0',
          verseStart: 1,
          startOffset: 0,
          endOffset: 5,
          text: 'Grace',
          color: '#FEF08A',
          deleted: false,
          updatedAt: new Date().toISOString(),
        },
        {
          id: 'bible_hl:1:1:1',
          itemType: 'highlight',
          feature: 'bible',
          targetId: '1:1:1',
          color: '#FEF08A',
          deleted: false,
          updatedAt: new Date().toISOString(),
        },
      ],
    });

    await Promise.resolve();
    TestBed.flushEffects();

    expect(videoLibrary.watchLater().map((v) => v.id)).toEqual(['v1']);
    expect(videoLibrary.history().map((h) => h.video.id)).toEqual(['v2']);
    expect(videoLibrary.getVideoPosition('v2')).toBe(30);
    expect(channels.subscribedIds()).toEqual(['ch-1']);
    expect(prefs.preferredLanguages()).toEqual(['en', 'ta']);
    expect(bookHighlights.rangesForLine('book:b1:0', 1)).toHaveLength(1);
    expect(bible.highlights()['1:1:1']).toBe('#FCE0B1');
    expect(audio.currentTrack()?.id).toBe('t1');

    httpMock.match((r) => r.url.includes('manifest.json')).forEach((r) => r.flush({}));
  });
});
