import axios from 'axios';
import { YoutubeService, classifyVideoVisibility } from './youtube.service';

jest.mock('axios');
const mockedAxios = axios as jest.Mocked<typeof axios>;

function makeYoutubeService(config: Record<string, any> = {}) {
  const configService = {
    get: jest.fn((key: string) => config[key]),
  };
  return new YoutubeService(configService as any);
}

describe('YoutubeService visibility & batching', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('classifyVideoVisibility allows public and unlisted, rejects private, and fails closed on missing status', () => {
    expect(classifyVideoVisibility({ status: { privacyStatus: 'public' } })).toBe('eligible');
    expect(classifyVideoVisibility({ status: { privacyStatus: 'unlisted' } })).toBe('eligible');
    expect(classifyVideoVisibility({ status: { privacyStatus: 'private' } })).toBe('private');
    expect(classifyVideoVisibility({ status: {} })).toBe('unavailable');
    expect(classifyVideoVisibility({})).toBe('unavailable');
    expect(classifyVideoVisibility(undefined)).toBe('unavailable');
  });

  it('requests part=snippet,contentDetails,statistics,status in batched videos.list calls', async () => {
    const service = makeYoutubeService({ youtubeApiKey: 'test-key' });
    mockedAxios.get.mockResolvedValueOnce({
      data: {
        items: [
          { id: 'v1', status: { privacyStatus: 'public' }, snippet: { title: 'Pub' } },
          { id: 'v2', status: { privacyStatus: 'unlisted' }, snippet: { title: 'Unl' } },
        ],
      },
    } as any);

    const res = await service.verifyVideosVisibility(['v1', 'v2', 'v3']);

    expect(mockedAxios.get).toHaveBeenCalledTimes(1);
    expect(mockedAxios.get).toHaveBeenCalledWith(
      expect.stringContaining('part=snippet,contentDetails,statistics,status'),
      expect.any(Object),
    );
    expect(res.get('v1')?.status).toBe('eligible');
    expect(res.get('v2')?.status).toBe('eligible');
    expect(res.get('v3')?.status).toBe('unavailable');
  });

  it('returns error status on network/quota failure without treating videos as private', async () => {
    const service = makeYoutubeService({ youtubeApiKey: 'test-key' });
    mockedAxios.get.mockRejectedValueOnce(new Error('Request failed with status code 403'));

    const res = await service.verifyVideosVisibility(['v1', 'v2']);

    expect(res.get('v1')?.status).toBe('error');
    expect(res.get('v2')?.status).toBe('error');
  });

  it('reuses Shorts OAuth only for videos owned by shorts.customChannelId', async () => {
    const service = makeYoutubeService({
      youtubeApiKey: 'test-key',
      youtubeClientId: 'cid',
      youtubeClientSecret: 'csec',
      youtubeRefreshToken: 'rtok',
      'shorts.customChannelId': 'UC_SHORTS_OWNER',
    });

    // Public API-key lookup omits v_priv and v_other
    mockedAxios.get.mockResolvedValueOnce({ data: { items: [] } } as any);
    // OAuth token exchange
    mockedAxios.post.mockResolvedValueOnce({ data: { access_token: 'oauth-tok' } } as any);
    // OAuth videos.list returns v_priv (owned by UC_SHORTS_OWNER) and v_other (different channel)
    mockedAxios.get.mockResolvedValueOnce({
      data: {
        items: [
          {
            id: 'v_priv',
            snippet: { channelId: 'UC_SHORTS_OWNER', title: 'Secret' },
            status: { privacyStatus: 'private' },
          },
          {
            id: 'v_other',
            snippet: { channelId: 'UC_OTHER_CHANNEL', title: 'Other' },
            status: { privacyStatus: 'private' },
          },
        ],
      },
    } as any);

    const res = await service.verifyVideosVisibility(['v_priv', 'v_other'], {
      allowShortsOAuth: true,
      expectedChannelId: 'UC_SHORTS_OWNER',
    });

    expect(res.get('v_priv')?.status).toBe('private');
    // v_other is not owned by UC_SHORTS_OWNER, so OAuth result is ignored -> unavailable
    expect(res.get('v_other')?.status).toBe('unavailable');
  });

  it('does not use Shorts OAuth when expectedChannelId is a different channel', async () => {
    const service = makeYoutubeService({
      youtubeApiKey: 'test-key',
      youtubeClientId: 'cid',
      youtubeClientSecret: 'csec',
      youtubeRefreshToken: 'rtok',
      'shorts.customChannelId': 'UC_SHORTS_OWNER',
    });

    mockedAxios.get.mockResolvedValueOnce({ data: { items: [] } } as any);

    const res = await service.verifyVideosVisibility(['v1'], {
      allowShortsOAuth: true,
      expectedChannelId: 'UC_THIRD_PARTY',
    });

    expect(mockedAxios.post).not.toHaveBeenCalled();
    expect(res.get('v1')?.status).toBe('unavailable');
  });
});


function makeInitialHtml(tabTitle: string, videoIds: string[], continuationToken?: string) {
  const contents: any[] = videoIds.map((id) => ({
    richItemRenderer: {
      content: {
        videoRenderer: {
          videoId: id,
          title: { runs: [{ text: `Title ${id}` }] },
          publishedTimeText: { simpleText: '10 years ago' },
          lengthText: { simpleText: '12:34' },
          viewCountText: { simpleText: '100 views' },
        },
      },
    },
  }));
  if (continuationToken) {
    contents.push({
      continuationItemRenderer: {
        continuationEndpoint: {
          continuationCommand: { token: continuationToken },
        },
      },
    });
  }
  const ytInitialData = {
    contents: {
      twoColumnBrowseResultsRenderer: {
        tabs: [
          {
            tabRenderer: {
              title: tabTitle,
              content: { richGridRenderer: { contents } },
            },
          },
        ],
      },
    },
  };
  return `<html><script>var ytInitialData = ${JSON.stringify(ytInitialData)};</script></html>`;
}

function makeContinuationResponse(videoIds: string[], nextToken?: string) {
  const continuationItems: any[] = videoIds.map((id) => ({
    richItemRenderer: {
      content: {
        videoRenderer: {
          videoId: id,
          title: { runs: [{ text: `Title ${id}` }] },
          publishedTimeText: { simpleText: '11 years ago' },
          lengthText: { simpleText: '10:00' },
          viewCountText: { simpleText: '50 views' },
        },
      },
    },
  }));
  if (nextToken) {
    continuationItems.push({
      continuationItemRenderer: {
        continuationEndpoint: {
          continuationCommand: { token: nextToken },
        },
      },
    });
  }
  return {
    data: {
      onResponseReceivedActions: [{ appendContinuationItemsAction: { continuationItems } }],
    },
  };
}

describe('YoutubeService fault-tolerant scraping', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('retries transient 429/5xx errors and exhausts all continuation pages', async () => {
    const service = makeYoutubeService({});
    mockedAxios.get
      .mockRejectedValueOnce({ response: { status: 429 }, message: 'Too Many Requests' })
      .mockResolvedValueOnce({ data: makeInitialHtml('Videos', ['v1', 'v2'], 'tok_2') });

    mockedAxios.post
      .mockRejectedValueOnce({ response: { status: 503 }, message: 'Service Unavailable' })
      .mockResolvedValueOnce(makeContinuationResponse(['v3', 'v4']));

    const pages: string[][] = [];
    const result = await service.scrapeChannelVideosTab('UC123', {
      maxBatches: 10,
      delayMs: 0,
      retryDelayMs: 1,
      onPage: async (videos) => {
        pages.push(videos.map((v) => v.videoId));
      },
    });

    expect(result.exhausted).toBe(true);
    expect(result.stoppedEarly).toBe(false);
    expect(result.error).toBeUndefined();
    expect(result.batchesProcessed).toBe(2);
    expect(pages).toEqual([
      ['v1', 'v2'],
      ['v3', 'v4'],
    ]);
  });

  it('does not retry non-retryable 404 errors', async () => {
    const service = makeYoutubeService({});
    mockedAxios.get.mockRejectedValue({ response: { status: 404 }, message: 'Not Found' });

    const result = await service.scrapeChannelVideosTab('UC404', {
      maxBatches: 10,
      delayMs: 0,
      retryDelayMs: 1,
    });

    expect(mockedAxios.get).toHaveBeenCalledTimes(1);
    expect(result.exhausted).toBe(false);
    expect(result.error).toBe('Not Found');
  });

  it('stops early without error when onPage returns false', async () => {
    const service = makeYoutubeService({});
    mockedAxios.get.mockResolvedValueOnce({
      data: makeInitialHtml('Videos', ['v1', 'v2'], 'tok_2'),
    });

    const result = await service.scrapeChannelVideosTab('UC123', {
      maxBatches: 10,
      delayMs: 0,
      retryDelayMs: 1,
      onPage: async () => false,
    });

    expect(mockedAxios.post).not.toHaveBeenCalled();
    expect(result.stoppedEarly).toBe(true);
    expect(result.exhausted).toBe(false);
    expect(result.error).toBeUndefined();
    expect(result.videos.map((v) => v.videoId)).toEqual(['v1', 'v2']);
  });

  it('preserves earlier pages and marks exhausted=false when continuation fails after retries', async () => {
    const service = makeYoutubeService({});
    mockedAxios.get.mockResolvedValueOnce({
      data: makeInitialHtml('Videos', ['v1', 'v2'], 'tok_2'),
    });
    mockedAxios.post.mockRejectedValue(new Error('ETIMEDOUT'));

    const streamed: string[] = [];
    const result = await service.scrapeChannelVideosTab('UC123', {
      maxBatches: 10,
      delayMs: 0,
      retryDelayMs: 1,
      onPage: async (videos) => {
        streamed.push(...videos.map((v) => v.videoId));
      },
    });

    expect(mockedAxios.post).toHaveBeenCalledTimes(3);
    expect(result.exhausted).toBe(false);
    expect(result.stoppedEarly).toBe(false);
    expect(result.error).toBe('ETIMEDOUT');
    expect(streamed).toEqual(['v1', 'v2']);
  });
});
