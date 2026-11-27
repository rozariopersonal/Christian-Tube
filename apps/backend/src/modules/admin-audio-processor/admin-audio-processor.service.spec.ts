import { ConflictException, NotFoundException } from '@nestjs/common';
import { AdminAudioProcessorService } from './admin-audio-processor.service';

describe('AdminAudioProcessorService', () => {
  let service: AdminAudioProcessorService;
  let prisma: any;
  let cache: any;
  let audioCom: any;
  let push: any;

  beforeEach(() => {
    prisma = {
      video: {
        findMany: jest.fn().mockResolvedValue([]),
        findUnique: jest.fn().mockResolvedValue(null),
        update: jest.fn().mockResolvedValue({}),
      },
      $executeRawUnsafe: jest.fn().mockResolvedValue(1),
    };
    cache = {
      getPrefix: jest.fn().mockReturnValue('ct:christian_tube'),
      getString: jest.fn().mockResolvedValue(null),
      mgetStrings: jest.fn().mockResolvedValue([]),
      setString: jest.fn().mockResolvedValue(undefined),
      setNxEx: jest.fn().mockResolvedValue(true),
      delKey: jest.fn().mockResolvedValue(undefined),
      zadd: jest.fn().mockResolvedValue(undefined),
      zrange: jest.fn().mockResolvedValue([]),
      zrem: jest.fn().mockResolvedValue(undefined),
      zremrangebyscore: jest.fn().mockResolvedValue(undefined),
      lpushTrim: jest.fn().mockResolvedValue(undefined),
      lrange: jest.fn().mockResolvedValue([]),
      invalidate: jest.fn().mockResolvedValue(undefined),
    };
    audioCom = {
      createAudio: jest.fn(),
      triggerSuccessHook: jest.fn().mockResolvedValue(undefined),
      getOrCreateCollection: jest.fn().mockResolvedValue('col_1'),
      addToCollection: jest.fn().mockResolvedValue('ok'),
      addToChannelCollection: jest.fn().mockResolvedValue('col_1'),
      resolveStreamUrl: jest.fn().mockResolvedValue('https://cdn.audio.com/stream.mp3'),
    };
    push = {
      notifyNewVideo: jest.fn().mockResolvedValue(undefined),
      isConfigured: jest.fn().mockReturnValue(false),
      getRegisteredTokenCount: jest.fn().mockResolvedValue(0),
      registerToken: jest.fn().mockResolvedValue(undefined),
      unregisterToken: jest.fn().mockResolvedValue(undefined),
    };
    service = new AdminAudioProcessorService(prisma, cache, audioCom, push);
  });

  it('serves warm pending list from Redis with 0 Neon queries using MGET', async () => {
    cache.getString.mockResolvedValueOnce('1'); // pending_72h_seeded
    cache.zrange.mockResolvedValueOnce(['vid1']);
    cache.mgetStrings.mockResolvedValueOnce([
      JSON.stringify({
        id: 'vid1',
        title: 'Sunday Sermon',
        channelName: 'CFC India',
        channelId: 'UC_1',
        publishedAt: new Date().toISOString(),
        duration: '45:00',
        thumbnail: 'https://img/1.jpg',
        isSongChannel: false,
      }),
    ]);

    const items = await service.getPendingVideos(72);
    expect(items).toHaveLength(1);
    expect(items[0].id).toBe('vid1');
    expect(prisma.video.findMany).not.toHaveBeenCalled();
    expect(cache.zremrangebyscore).toHaveBeenCalled();
    expect(cache.mgetStrings).toHaveBeenCalledTimes(1);
  });

  it('rejects duplicate claim with 409 Conflict', async () => {
    cache.setNxEx.mockResolvedValueOnce(false);
    await expect(service.claimVideo('vid1', 'admin2@test.com')).rejects.toThrow(ConflictException);
  });

  it('never leaks successHook from upload-session to mobile client', async () => {
    prisma.video.findUnique.mockResolvedValueOnce({
      id: 'vid1',
      title: 'Grace and Truth - Zac Poonen',
      description: 'Sunday message',
      thumbnail: 'https://img/1.jpg',
      channelId: 'UC_1',
      channelName: 'CFC India',
      publishedAt: new Date('2026-11-26T10:00:00Z'),
      tags: ['sermon'],
      channel: { name: 'CFC India', language: 'English' },
    });
    audioCom.createAudio.mockResolvedValueOnce({
      audioId: '9999',
      uploadUrl: 'https://storage.audio.com/presigned-put',
      successHook: 'https://api.audio.com/internal-hook-secret',
    });

    const res = await service.createUploadSession(
      { videoId: 'vid1', mime: 'audio/mp4', size: 123456 },
      'admin@test.com',
    );
    expect(res.uploadUrl).toBe('https://storage.audio.com/presigned-put');
    expect(res.uploadSessionId).toBeTruthy();
    expect((res as any).successHook).toBeUndefined();
    expect((res as any).audioId).toBeUndefined();
  });

  it('throws NotFoundException when completing an expired upload session', async () => {
    cache.getString.mockResolvedValueOnce(null);
    await expect(
      service.completeUpload({ uploadSessionId: 'expired' }),
    ).rejects.toThrow(NotFoundException);
  });
});
