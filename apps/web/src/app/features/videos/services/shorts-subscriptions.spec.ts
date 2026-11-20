import { provideHttpClient } from '@angular/common/http';
import {
  HttpTestingController,
  provideHttpClientTesting,
} from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { AuthService } from '../../../core/auth/auth.service';
import { ChannelService } from '../../channels/services/channel.service';
import { VideoService } from './video.service';

describe('ChannelService & VideoService Shorts Following Sync', () => {
  let httpMock: HttpTestingController;
  let channelService: ChannelService;
  let videoService: VideoService;
  let authService: AuthService;

  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    httpMock = TestBed.inject(HttpTestingController);
    authService = TestBed.inject(AuthService);
    channelService = TestBed.inject(ChannelService);
    videoService = TestBed.inject(VideoService);
  });

  afterEach(() => {
    httpMock.verify();
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('returns empty shorts without hitting /api/videos when no channels are followed', async () => {
    await videoService.fetchShorts();
    expect(videoService.shorts()).toEqual([]);
    expect(videoService.shortsHasMore()).toBe(false);
    httpMock.expectNone((req) => req.url.includes('/api/videos'));
  });

  it('fetches shorts filtered by followed channelIds', async () => {
    localStorage.setItem(
      'subscribed_channel_ids',
      JSON.stringify(['ch-1', 'ch-2']),
    );
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    httpMock = TestBed.inject(HttpTestingController);
    channelService = TestBed.inject(ChannelService);
    videoService = TestBed.inject(VideoService);

    const fetchPromise = videoService.fetchShorts();
    const req = httpMock.expectOne((r) => r.url.endsWith('/api/videos'));
    expect(req.request.params.get('type')).toBe('SHORT');
    expect(req.request.params.get('channelIds')).toBe('ch-1,ch-2');

    req.flush({
      videos: [
        { id: 's1', title: 'Short 1', channelId: 'ch-1', type: 'SHORT' },
        { id: 's2', title: 'Short 2', channelId: 'ch-2', type: 'SHORT' },
      ],
    });

    await fetchPromise;
    expect(videoService.shorts().map((s) => s.id)).toEqual(['s1', 's2']);
  });

  it('parses { channelIds, channels } from /api/channels/subscriptions and updates local state', async () => {
    authService.currentUser.set({
      id: 'user-1',
      email: 'test@example.com',
      displayName: 'Test User',
    });

    const loadPromise = channelService.loadSubscriptions();
    const req = httpMock.expectOne((r) =>
      r.url.endsWith('/api/channels/subscriptions'),
    );
    req.flush({
      channelIds: ['ch-db-1', 'ch-db-2'],
      channels: [{ id: 'ch-db-1' }, { id: 'ch-db-2' }],
    });

    await loadPromise;
    expect(channelService.subscribedIds()).toEqual(['ch-db-1', 'ch-db-2']);
    expect(
      JSON.parse(localStorage.getItem('subscribed_channel_ids_user-1') ?? '[]'),
    ).toEqual(['ch-db-1', 'ch-db-2']);
  });

  it('optimistically updates followed state and persists follow/unfollow to DB when authenticated', async () => {
    authService.currentUser.set({
      id: 'user-1',
      email: 'test@example.com',
      displayName: 'Test User',
    });

    const followPromise = channelService.toggleSubscribe('ch-99');
    // Optimistic update happens synchronously before HTTP resolves
    expect(channelService.subscribedIds()).toContain('ch-99');

    const postReq = httpMock.expectOne((r) =>
      r.url.endsWith('/api/channels/ch-99/subscribe'),
    );
    expect(postReq.request.method).toBe('POST');
    postReq.flush({ status: 'subscribed', channelId: 'ch-99' });
    await followPromise;

    const unfollowPromise = channelService.toggleSubscribe('ch-99');
    expect(channelService.subscribedIds()).not.toContain('ch-99');

    const delReq = httpMock.expectOne((r) =>
      r.url.includes('/api/channels/ch-99/subscribe') && r.method === 'DELETE',
    );
    expect(delReq.request.method).toBe('DELETE');
    delReq.flush({ status: 'unsubscribed', channelId: 'ch-99' });
    await unfollowPromise;
  });

  it('does not overwrite newer optimistic follow with stale in-flight loadSubscriptions response', async () => {
    authService.currentUser.set({
      id: 'user-1',
      email: 'test@example.com',
      displayName: 'Test User',
    });

    const loadPromise = channelService.loadSubscriptions();
    const getReq = httpMock.expectOne((r) =>
      r.url.endsWith('/api/channels/subscriptions'),
    );

    // User follows ch-new while loadSubscriptions is still in flight
    const followPromise = channelService.toggleSubscribe('ch-new');
    const postReq = httpMock.expectOne((r) =>
      r.url.endsWith('/api/channels/ch-new/subscribe'),
    );
    postReq.flush({ status: 'subscribed', channelId: 'ch-new' });
    await followPromise;

    // Now stale GET resolves without ch-new
    getReq.flush({ channelIds: ['ch-old'], channels: [] });
    await loadPromise;

    expect(channelService.subscribedIds()).toEqual(['ch-new']);
  });
});
