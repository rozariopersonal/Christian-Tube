import { HttpErrorResponse } from '@angular/common/http';
import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { of, throwError } from 'rxjs';
import { vi } from 'vitest';
import { ApiService } from '../../../core/api/api.service';
import { AuthService } from '../../../core/auth/auth.service';
import { UserSyncService } from '../../../core/services/user-sync.service';
import { normalizeChannelRequest } from '../models/channel.model';
import { ChannelService } from './channel.service';

describe('ChannelService (requests & YouTube search)', () => {
  let service: ChannelService;
  let apiMock: {
    get: ReturnType<typeof vi.fn>;
    post: ReturnType<typeof vi.fn>;
    delete: ReturnType<typeof vi.fn>;
  };
  let isAdminSig: ReturnType<typeof signal<boolean>>;

  beforeEach(() => {
    apiMock = {
      get: vi.fn().mockReturnValue(of([])),
      post: vi.fn().mockReturnValue(of({})),
      delete: vi.fn().mockReturnValue(of({})),
    };
    isAdminSig = signal(false);

    TestBed.configureTestingModule({
      providers: [
        ChannelService,
        { provide: ApiService, useValue: apiMock },
        {
          provide: AuthService,
          useValue: {
            currentUser: signal(null),
            sessionNeedsSignIn: signal(false),
            isAuthenticated: signal(false),
            canSync: signal(false),
            isAdmin: isAdminSig,
            markSessionRejected: vi.fn(),
          },
        },
        {
          provide: UserSyncService,
          useValue: {
            remoteState: signal(null),
            pendingOps: signal({}),
            acknowledgementVersion: 0,
            enqueueSubscription: vi.fn(),
            userCacheKey: (k: string) => k,
          },
        },
      ],
    });
    service = TestBed.inject(ChannelService);
  });

  it('normalizes legacy channel requests without channelName', () => {
    const normalized = normalizeChannelRequest({
      id: 'req-1',
      channelUrl: '@grace',
      notes: 'Grace Fellowship',
      submittedBy: 'user@example.com',
      status: 'pending',
    });
    expect(normalized.channelName).toBe('Grace Fellowship');
    expect(normalized.status).toBe('PENDING');
    expect(normalized.submittedBy).toBe('user@example.com');
  });

  it('skips YouTube search for queries shorter than 2 characters', async () => {
    const results = await service.searchYouTubeChannels('a');
    expect(results).toEqual([]);
    expect(apiMock.get).not.toHaveBeenCalled();
  });

  it('normalizes YouTube channel search results with isExisting flag', async () => {
    apiMock.get.mockReturnValue(
      of([
        {
          id: 'UC_existing',
          name: 'Existing Church',
          handle: '@existing',
          subscriberCount: 1200,
          isExisting: true,
        },
      ]),
    );
    const results = await service.searchYouTubeChannels('Existing');
    expect(apiMock.get).toHaveBeenCalledWith('/api/channels/search-youtube', {
      q: 'Existing',
    });
    expect(results).toHaveLength(1);
    expect(results[0].isExisting).toBe(true);
    expect(results[0].subscriberCount).toBe(1200);
  });

  it('does not call fetchRequests for non-admins after submitRequest', async () => {
    apiMock.post.mockReturnValue(of({ id: 'req-1' }));
    const res = await service.submitRequest('Grace TV', '@gracetv', 'Great sermons');
    expect(res).toEqual({ ok: true });
    expect(apiMock.post).toHaveBeenCalledWith('/api/channels/request', {
      channelUrl: '@gracetv',
      channelName: 'Grace TV',
      notes: 'Great sermons',
    });
    expect(apiMock.get).not.toHaveBeenCalledWith('/api/channels/requests');
  });

  it('surfaces backend conflict message on submitRequest error', async () => {
    apiMock.post.mockReturnValue(
      throwError(
        () =>
          new HttpErrorResponse({
            status: 409,
            error: { message: 'A pending request for this channel already exists.' },
          }),
      ),
    );
    const res = await service.submitRequest('Grace TV', '@gracetv');
    expect(res).toEqual({
      ok: false,
      error: 'A pending request for this channel already exists.',
    });
  });

  it('fetches requests only when user is admin', async () => {
    await service.fetchRequests();
    expect(apiMock.get).not.toHaveBeenCalled();

    isAdminSig.set(true);
    apiMock.get.mockReturnValue(
      of([
        {
          id: 'r1',
          channelUrl: '@new',
          channelName: 'New Channel',
          submittedBy: 'a@b.com',
          status: 'PENDING',
        },
      ]),
    );
    await service.fetchRequests();
    expect(apiMock.get).toHaveBeenCalledWith('/api/channels/requests');
    expect(service.channelRequests()).toHaveLength(1);
    expect(service.channelRequests()[0].channelName).toBe('New Channel');
  });
});
