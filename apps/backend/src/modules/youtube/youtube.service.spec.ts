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
