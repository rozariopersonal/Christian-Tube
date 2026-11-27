import { provideHttpClient } from '@angular/common/http';
import {
  HttpTestingController,
  provideHttpClientTesting,
} from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { AuthService } from '../../../core/auth/auth.service';
import { UserSyncService } from '../../../core/services/user-sync.service';
import { normalizePlaylist } from '../models/playlist.model';
import { Video } from '../models/video.model';
import { PlaylistService } from './playlist.service';

function makeVideo(id: string, title = `Video ${id}`): Video {
  return {
    id,
    title,
    thumbnailUrl: `https://example.com/${id}.jpg`,
    channelId: 'ch-1',
    channelTitle: 'Grace Church',
    viewCount: 100,
    publishedAt: '2026-01-01T00:00:00.000Z',
    duration: '12:30',
    isLive: false,
  };
}

describe('normalizePlaylist', () => {
  it('returns null for invalid inputs', () => {
    expect(normalizePlaylist(null)).toBeNull();
    expect(normalizePlaylist([])).toBeNull();
    expect(normalizePlaylist({ id: '', title: 'A' })).toBeNull();
    expect(normalizePlaylist({ id: 'p1', title: '   ' })).toBeNull();
  });

  it('normalizes videos, videoCount, thumbnailUrl fallback, and snake_case fields', () => {
    const result = normalizePlaylist({
      id: 'pl-1',
      title: '  My List  ',
      description: '  Desc  ',
      items: [
        { video: { id: 'v1', title: 'One', thumbnail_url: 'https://t/1.jpg' } },
        { video: { id: 'v1', title: 'Duplicate' } },
        { id: 'v2', title: 'Two' },
      ],
      created_at: '2026-02-01T00:00:00.000Z',
      updated_at: '2026-02-02T00:00:00.000Z',
      client_updated_at: 5000,
    });

    expect(result).not.toBeNull();
    expect(result!.title).toBe('My List');
    expect(result!.description).toBe('Desc');
    expect(result!.videoCount).toBe(2);
    expect(result!.videos.map((v) => v.id)).toEqual(['v1', 'v2']);
    expect(result!.thumbnailUrl).toBe('https://t/1.jpg');
    expect(result!.clientUpdatedAt).toBe(5000);
  });
});

describe('PlaylistService', () => {
  let service: PlaylistService;
  let userSync: UserSyncService;
  let auth: AuthService;
  let httpMock: HttpTestingController;

  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    httpMock = TestBed.inject(HttpTestingController);
    auth = TestBed.inject(AuthService);
    userSync = TestBed.inject(UserSyncService);
    service = TestBed.inject(PlaylistService);
  });

  afterEach(() => {
    httpMock.match(() => true).forEach((r) => r.flush({}));
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('supports optimistic CRUD, item add/remove/reorder, and query helpers', () => {
    expect(service.createPlaylist('   ')).toBeNull();

    const v1 = makeVideo('v1');
    const v2 = makeVideo('v2');
    const created = service.createPlaylist('Sunday Sermons', 'Weekly', v1);
    expect(created).not.toBeNull();
    expect(service.playlists()).toHaveLength(1);
    expect(service.playlistById(created!.id)?.title).toBe('Sunday Sermons');
    expect(service.playlistById('')).toBeNull();
    expect(service.isInAnyPlaylist('v1')).toBe(true);
    expect(service.playlistsContaining('v1')).toHaveLength(1);
    expect(service.playlistsContaining('')).toEqual([]);

    // Dedupe add
    expect(service.addVideoToPlaylist(created!.id, v1)).toBe(false);
    expect(service.addVideoToPlaylist(created!.id, v2)).toBe(true);
    expect(service.playlistById(created!.id)?.videos.map((v) => v.id)).toEqual([
      'v1',
      'v2',
    ]);

    // Reorder valid and invalid
    expect(service.reorderVideos(created!.id, 0, 0)).toBe(false);
    expect(service.reorderVideos(created!.id, -1, 1)).toBe(false);
    expect(service.reorderVideos('missing', 0, 1)).toBe(false);
    expect(service.reorderVideos(created!.id, 0, 1)).toBe(true);
    expect(service.playlistById(created!.id)?.videos.map((v) => v.id)).toEqual([
      'v2',
      'v1',
    ]);
    expect(service.playlistById(created!.id)?.thumbnailUrl).toBe(v2.thumbnailUrl);

    // Update valid and invalid
    expect(service.updatePlaylist('missing', { title: 'X' })).toBe(false);
    expect(service.updatePlaylist(created!.id, { title: '   ' })).toBe(false);
    expect(
      service.updatePlaylist(created!.id, {
        title: 'Updated Sermons',
        description: '',
      }),
    ).toBe(true);
    expect(service.playlistById(created!.id)?.title).toBe('Updated Sermons');
    expect(service.playlistById(created!.id)?.description).toBeNull();

    // Remove item
    expect(service.removeVideoFromPlaylist(created!.id, 'nope')).toBe(false);
    expect(service.removeVideoFromPlaylist(created!.id, 'v2')).toBe(true);
    expect(service.playlistById(created!.id)?.videoCount).toBe(1);

    // Delete playlist
    expect(service.deletePlaylist('missing')).toBe(false);
    expect(service.deletePlaylist(created!.id)).toBe(true);
    expect(service.playlists()).toEqual([]);
  });

  it('persists per user in localStorage and reloads on account switch', () => {
    auth.currentUser.set({
      id: 'u-1',
      email: 'u1@example.com',
      displayName: 'U1',
    });
    TestBed.flushEffects();

    const p1 = service.createPlaylist('User 1 List');
    expect(p1).not.toBeNull();
    expect(localStorage.getItem('ct_web_playlists_v1_u-1')).toContain(
      'User 1 List',
    );

    // Switch to user 2
    auth.currentUser.set({
      id: 'u-2',
      email: 'u2@example.com',
      displayName: 'U2',
    });
    TestBed.flushEffects();
    expect(service.playlists()).toEqual([]);

    // Switch back to user 1
    auth.currentUser.set({
      id: 'u-1',
      email: 'u1@example.com',
      displayName: 'U1',
    });
    TestBed.flushEffects();
    expect(service.playlists().map((p) => p.title)).toEqual(['User 1 List']);
  });

  it('merges remote playlists + tombstones while preserving local optimistic copies with pending ops', () => {
    auth.currentUser.set({
      id: 'u-sync',
      email: 'sync@example.com',
      displayName: 'Sync',
    });
    TestBed.flushEffects();

    const localOptimistic = service.createPlaylist('Optimistic Local');
    const toDelete = service.createPlaylist('Will Delete');
    service.deletePlaylist(toDelete!.id);

    // Simulate remote state arriving while ops are still pending
    userSync.remoteState.set({
      serverTime: Date.now(),
      playlists: [
        {
          id: 'remote-1',
          title: 'Remote Playlist',
          videos: [makeVideo('rv1')],
          clientUpdatedAt: 1000,
        },
        {
          id: 'tombstoned-1',
          title: 'Deleted Elsewhere',
          videos: [],
          clientUpdatedAt: 900,
        },
        {
          id: localOptimistic!.id,
          title: 'Stale Remote Version',
          videos: [],
          clientUpdatedAt: 100,
        },
        {
          id: toDelete!.id,
          title: 'Still On Server',
          videos: [],
          clientUpdatedAt: 100,
        },
      ],
      playlistTombstones: {
        'tombstoned-1': 1200,
      },
    });
    TestBed.flushEffects();

    const titles = service.playlists().map((p) => p.title);
    expect(titles).toContain('Remote Playlist');
    expect(titles).toContain('Optimistic Local');
    expect(titles).not.toContain('Stale Remote Version');
    expect(titles).not.toContain('Deleted Elsewhere');
    expect(titles).not.toContain('Still On Server');
  });
});
