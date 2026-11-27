import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import * as crypto from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { CacheService } from '../cache/cache.service';
import { extractVideoMetadata, isSongChannel } from '../sync/metadata-extractor';
import { AudioComApiService } from './audio-com-api.service';
import { AdminPushService } from './admin-push.service';

export interface PendingAudioVideo {
  id: string;
  title: string;
  channelName: string;
  channelId: string;
  publishedAt: string;
  duration: string;
  thumbnail: string;
  isSongChannel: boolean;
}

export interface ActivityEvent {
  videoId: string;
  title: string;
  channelName: string;
  status: 'completed' | 'failed' | 'dead' | 'short' | 'ignored';
  source: 'mobile' | 'desktop';
  adminEmail?: string;
  bytesUploaded?: number;
  durationSeconds?: number;
  error?: string;
  at: string;
}

interface UploadSessionPayload {
  audioId: string;
  successHook: string | null;
  videoId: string;
  adminEmail: string;
  title: string;
  channelName: string;
  channelId: string;
  thumbnail: string;
  publishedAt: string;
  speaker: string;
  language: string;
  category: string;
}

function slugify(text: string): string {
  const cleaned = (text || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  return cleaned || 'misc';
}

@Injectable()
export class AdminAudioProcessorService {
  private readonly logger = new Logger(AdminAudioProcessorService.name);
  private readonly defaultWindowHours = 72;

  constructor(
    private readonly prisma: PrismaService,
    private readonly cache: CacheService,
    private readonly audioCom: AudioComApiService,
    private readonly push: AdminPushService,
  ) {}

  private key(suffix: string): string {
    return `${this.cache.getPrefix()}:audio_proc:${suffix}`;
  }

  private pendingSetKey(): string {
    return this.key('pending_72h');
  }

  private pendingSeededKey(): string {
    return this.key('pending_72h_seeded');
  }

  private pendingMetaKey(videoId: string): string {
    return this.key(`pending_meta:${videoId}`);
  }

  private claimLockKey(videoId: string): string {
    return this.key(`lock:${videoId}`);
  }

  private uploadSessionKey(sessionId: string): string {
    return this.key(`session:${sessionId}`);
  }

  private activityLogKey(): string {
    return this.key('activity_log');
  }

  private desktopSyncKey(): string {
    return this.key('desktop_sync');
  }

  private authErrorKey(): string {
    return this.key('auth_error');
  }

  /**
   * Called by SyncService whenever a new non-Short video (<= 72h old) is ingested.
   */
  async enqueuePendingVideo(video: {
    id: string;
    title: string;
    channelName: string;
    channelId: string;
    publishedAt: Date | string;
    duration?: string;
    thumbnail?: string;
    audioUrl?: string | null;
    type?: string;
  }): Promise<void> {
    if (!video?.id || video.audioUrl || video.type === 'SHORT') return;
    const pubDate = video.publishedAt instanceof Date ? video.publishedAt : new Date(video.publishedAt);
    if (Number.isNaN(pubDate.getTime())) return;

    const cutoffMs = Date.now() - this.defaultWindowHours * 3600 * 1000;
    if (pubDate.getTime() < cutoffMs) return;

    const item: PendingAudioVideo = {
      id: video.id,
      title: video.title || 'Untitled',
      channelName: video.channelName || 'Unknown',
      channelId: video.channelId || '',
      publishedAt: pubDate.toISOString(),
      duration: video.duration || '',
      thumbnail: video.thumbnail || `https://img.youtube.com/vi/${video.id}/hqdefault.jpg`,
      isSongChannel: isSongChannel(video.channelName || ''),
    };

    const ttlSec = this.defaultWindowHours * 3600;
    await this.cache.zadd(this.pendingSetKey(), pubDate.getTime(), video.id);
    await this.cache.setString(this.pendingMetaKey(video.id), JSON.stringify(item), ttlSec);
    await this.cache.setString(this.pendingSeededKey(), '1', ttlSec);

    // Fire-and-forget FCM wakeup (non-blocking)
    this.push
      .notifyNewVideo({ id: item.id, title: item.title, channelName: item.channelName })
      .catch((err) => this.logger.warn(`Admin push warning: ${err?.message || err}`));
  }

  /**
   * Rehydrates Redis pending_72h from Neon once if Redis was cold/flushed.
   */
  private async ensurePendingSeeded(hours: number): Promise<void> {
    const seeded = await this.cache.getString(this.pendingSeededKey());
    if (seeded) return;

    const cutoff = new Date(Date.now() - hours * 3600 * 1000);
    const rows = await this.prisma.video.findMany({
      where: {
        type: 'VIDEO',
        audioUrl: null,
        publishedAt: { gte: cutoff },
        channel: { isActive: true },
      },
      include: { pipelineStatus: true },
      orderBy: { publishedAt: 'desc' },
      take: 100,
    });

    const ttlSec = hours * 3600;
    for (const v of rows) {
      const ingest = (v.pipelineStatus?.ingest as Record<string, any>) || {};
      const status = String(ingest.status || 'pending');
      if (status === 'completed' || status === 'ignored' || status === 'dead') continue;
      const item: PendingAudioVideo = {
        id: v.id,
        title: v.title,
        channelName: v.channelName,
        channelId: v.channelId,
        publishedAt: v.publishedAt.toISOString(),
        duration: v.duration,
        thumbnail: v.thumbnail,
        isSongChannel: isSongChannel(v.channelName),
      };
      await this.cache.zadd(this.pendingSetKey(), v.publishedAt.getTime(), v.id);
      await this.cache.setString(this.pendingMetaKey(v.id), JSON.stringify(item), ttlSec);
    }
    await this.cache.setString(this.pendingSeededKey(), '1', ttlSec);
  }

  async getPendingVideos(hours = this.defaultWindowHours): Promise<PendingAudioVideo[]> {
    const effectiveHours = Math.max(1, Math.min(168, Number(hours) || this.defaultWindowHours));
    await this.ensurePendingSeeded(effectiveHours);

    const cutoffMs = Date.now() - effectiveHours * 3600 * 1000;
    await this.cache.zremrangebyscore(this.pendingSetKey(), '-inf', cutoffMs);

    const ids = await this.cache.zrange(this.pendingSetKey(), 0, -1);
    if (ids.length === 0) return [];

    // Single-batch MGET (2 Redis round-trips total, 0 Neon queries)
    const rawItems = await this.cache.mgetStrings(ids.map((id) => this.pendingMetaKey(id)));
    const result: PendingAudioVideo[] = [];
    for (let i = 0; i < ids.length; i++) {
      const raw = rawItems[i];
      if (!raw) continue;
      try {
        result.push(JSON.parse(raw) as PendingAudioVideo);
      } catch {
        // ignore malformed entry
      }
    }
    // Newest first for mobile processing
    result.sort((a, b) => new Date(b.publishedAt).getTime() - new Date(a.publishedAt).getTime());
    return result;
  }

  async claimVideo(videoId: string, adminEmail: string): Promise<{ claimed: true; videoId: string }> {
    if (!videoId) throw new BadRequestException('videoId is required');

    const acquired = await this.cache.setNxEx(this.claimLockKey(videoId), adminEmail || 'admin', 900);
    if (!acquired) {
      throw new ConflictException(`Video ${videoId} is already claimed by another admin`);
    }

    // Double-check if already completed in Neon
    const existing = await this.prisma.video.findUnique({
      where: { id: videoId },
      select: { audioUrl: true, type: true },
    });
    if (existing?.audioUrl) {
      await this.removeFromPending(videoId);
      await this.cache.delKey(this.claimLockKey(videoId));
      throw new ConflictException(`Video ${videoId} already has audio`);
    }

    return { claimed: true, videoId };
  }

  async createUploadSession(
    params: { videoId: string; mime: string; size: number },
    adminEmail: string,
  ): Promise<{ uploadSessionId: string; uploadUrl: string }> {
    const { videoId, mime, size } = params;
    if (!videoId || !mime || !size || size <= 0) {
      throw new BadRequestException('videoId, mime, and positive size are required');
    }

    const video = await this.prisma.video.findUnique({
      where: { id: videoId },
      include: { channel: true },
    });
    if (!video) {
      throw new NotFoundException(`Video ${videoId} not found`);
    }

    const channelName = video.channelName || video.channel?.name || 'General Sermons';
    const meta = extractVideoMetadata({
      title: video.title,
      description: video.description,
      channelTitle: channelName,
      tags: video.tags,
    });
    const speaker = meta.speaker || channelName;
    const language = meta.language || video.channel?.language || 'English';
    const category = isSongChannel(channelName) ? 'Songs' : 'YouTube';
    const tags = [
      ...(video.tags || []),
      speaker,
      language,
      meta.secondaryLanguage || '',
      channelName,
    ].filter(Boolean);

    const created = await this.audioCom.createAudio({
      title: video.title,
      description: video.id,
      mime,
      size,
      tags,
    });

    const uploadSessionId = crypto.randomBytes(16).toString('hex');
    const session: UploadSessionPayload = {
      audioId: created.audioId,
      successHook: created.successHook,
      videoId: video.id,
      adminEmail,
      title: video.title,
      channelName,
      channelId: video.channelId,
      thumbnail: video.thumbnail || `https://img.youtube.com/vi/${video.id}/hqdefault.jpg`,
      publishedAt: video.publishedAt.toISOString(),
      speaker,
      language,
      category,
    };

    // Store opaque session in Redis (TTL 30m) — successHook is never exposed to mobile
    await this.cache.setString(this.uploadSessionKey(uploadSessionId), JSON.stringify(session), 1800);

    return {
      uploadSessionId,
      uploadUrl: created.uploadUrl,
    };
  }

  async completeUpload(params: {
    uploadSessionId: string;
    durationSeconds?: number;
    bytesUploaded?: number;
  }): Promise<{ audioUrl: string; streamUrl: string | null }> {
    const raw = await this.cache.getString(this.uploadSessionKey(params.uploadSessionId));
    if (!raw) {
      throw new NotFoundException('Upload session expired or not found');
    }
    const session = JSON.parse(raw) as UploadSessionPayload;

    // 1. Trigger Audio.com success hook & add to collection (auto-rollover at 1000-item cap)
    await this.audioCom.triggerSuccessHook(session.successHook);
    await this.audioCom.addToChannelCollection(session.channelName, session.audioId);

    // 2. Quick 3-4s stream URL check (avoids HTTP gateway timeouts)
    const streamUrl = await this.audioCom.resolveStreamUrl(session.audioId, 2, 1800);
    const audioUrl = `https://audio.com/${session.audioId}`;
    const seriesId = slugify(session.channelName);
    const durationSec = Math.max(0, Math.floor(params.durationSeconds || 0));
    const pubDate = new Date(session.publishedAt);

    // 3. Upsert AudioSeries, AudioTrack, Video.audioUrl, and VideoPipelineStatus in Neon
    await this.prisma.$executeRawUnsafe(
      `INSERT INTO "AudioSeries"
         ("id","title","description","speaker","category","language",
          "coverUrl","channelId","trackCount","latestPublishedAt","updatedAt","createdAt")
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,0,$9,NOW(),NOW())
       ON CONFLICT ("id") DO UPDATE SET
         "title"=EXCLUDED."title",
         "description"=EXCLUDED."description",
         "speaker"=COALESCE("AudioSeries"."speaker", EXCLUDED."speaker"),
         "category"=EXCLUDED."category",
         "language"=EXCLUDED."language",
         "coverUrl"=COALESCE("AudioSeries"."coverUrl", EXCLUDED."coverUrl"),
         "channelId"=EXCLUDED."channelId",
         "updatedAt"=NOW()`,
      seriesId,
      session.channelName,
      `Audio sermons and messages from ${session.channelName}`,
      session.speaker,
      session.category,
      session.language,
      session.thumbnail,
      session.channelId || null,
      pubDate,
    );

    await this.prisma.$executeRawUnsafe(
      `INSERT INTO "AudioTrack"
         ("id","seriesId","title","speaker","durationSeconds",
          "audioUrl","streamUrl","thumbnailUrl","youtubeVideoId","publishedAt","updatedAt","createdAt")
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,NOW(),NOW())
       ON CONFLICT ("id") DO UPDATE SET
         "seriesId"=EXCLUDED."seriesId",
         "title"=EXCLUDED."title",
         "speaker"=EXCLUDED."speaker",
         "durationSeconds"=EXCLUDED."durationSeconds",
         "audioUrl"=EXCLUDED."audioUrl",
         "streamUrl"=COALESCE(EXCLUDED."streamUrl", "AudioTrack"."streamUrl"),
         "thumbnailUrl"=EXCLUDED."thumbnailUrl",
         "youtubeVideoId"=EXCLUDED."youtubeVideoId",
         "publishedAt"=EXCLUDED."publishedAt",
         "updatedAt"=NOW()`,
      session.videoId,
      seriesId,
      session.title,
      session.speaker,
      durationSec,
      audioUrl,
      streamUrl,
      session.thumbnail,
      session.videoId,
      pubDate,
    );

    await this.prisma.$executeRawUnsafe(
      `UPDATE "AudioSeries" SET
         "trackCount"=(SELECT COUNT(*) FROM "AudioTrack" WHERE "seriesId"=$1),
         "latestPublishedAt"=(SELECT MAX("publishedAt") FROM "AudioTrack" WHERE "seriesId"=$1),
         "updatedAt"=NOW()
       WHERE "id"=$1`,
      seriesId,
    );

    await this.prisma.video.update({
      where: { id: session.videoId },
      data: { audioUrl },
    });

    const ingestPayload = {
      status: 'completed',
      retryCount: 0,
      lastRetryAt: null,
      lastError: null,
      processedBy: 'mobile',
      processedAt: new Date().toISOString(),
    };
    await this.prisma.$executeRawUnsafe(
      `INSERT INTO "VideoPipelineStatus" ("videoId", "ingest", "updatedAt")
       VALUES ($1, $2::jsonb, CURRENT_TIMESTAMP)
       ON CONFLICT ("videoId") DO UPDATE SET
         "ingest" = COALESCE("VideoPipelineStatus"."ingest", '{}'::jsonb) || EXCLUDED."ingest",
         "updatedAt" = CURRENT_TIMESTAMP`,
      session.videoId,
      JSON.stringify(ingestPayload),
    );

    // 4. Cleanup Redis queue/session/lock + record activity + invalidate caches
    await this.removeFromPending(session.videoId);
    await this.cache.delKey(
      this.claimLockKey(session.videoId),
      this.uploadSessionKey(params.uploadSessionId),
    );
    await this.appendActivity({
      videoId: session.videoId,
      title: session.title,
      channelName: session.channelName,
      status: 'completed',
      source: 'mobile',
      adminEmail: session.adminEmail,
      bytesUploaded: params.bytesUploaded,
      durationSeconds: durationSec,
      at: new Date().toISOString(),
    });
    await this.cache.invalidate('videos', 'channels', 'audio');

    // 5. If Audio.com is still transcoding, backfill streamUrl asynchronously
    if (!streamUrl) {
      this.backfillStreamUrlAsync(session.videoId, session.audioId).catch(() => {});
    }

    return { audioUrl, streamUrl };
  }

  private async backfillStreamUrlAsync(videoId: string, audioId: string): Promise<void> {
    await new Promise((r) => setTimeout(r, 10000));
    const resolved = await this.audioCom.resolveStreamUrl(audioId, 3, 5000);
    if (resolved) {
      await this.prisma.$executeRawUnsafe(
        `UPDATE "AudioTrack" SET "streamUrl" = $1, "updatedAt" = NOW() WHERE "id" = $2`,
        resolved,
        videoId,
      );
      await this.cache.invalidate('audio');
    }
  }

  async markShort(videoId: string, adminEmail: string): Promise<{ ok: true }> {
    const video = await this.prisma.video.findUnique({
      where: { id: videoId },
      select: { id: true, title: true, channelName: true },
    });
    if (video) {
      await this.prisma.video.update({ where: { id: videoId }, data: { type: 'SHORT' } });
      await this.prisma.$executeRawUnsafe(
        `INSERT INTO "VideoPipelineStatus" ("videoId", "ingest", "updatedAt")
         VALUES ($1, $2::jsonb, CURRENT_TIMESTAMP)
         ON CONFLICT ("videoId") DO UPDATE SET
           "ingest" = COALESCE("VideoPipelineStatus"."ingest", '{}'::jsonb) || EXCLUDED."ingest",
           "updatedAt" = CURRENT_TIMESTAMP`,
        videoId,
        JSON.stringify({
          status: 'ignored',
          lastError: 'Ignored: YouTube Short detected (mobile)',
          processedBy: 'mobile',
          processedAt: new Date().toISOString(),
        }),
      );
      await this.appendActivity({
        videoId,
        title: video.title,
        channelName: video.channelName,
        status: 'short',
        source: 'mobile',
        adminEmail,
        at: new Date().toISOString(),
      });
    }
    await this.removeFromPending(videoId);
    await this.cache.delKey(this.claimLockKey(videoId));
    await this.cache.invalidate('videos', 'shorts');
    return { ok: true };
  }

  async markIgnored(videoId: string, adminEmail: string, reason?: string): Promise<{ ok: true }> {
    const video = await this.prisma.video.findUnique({
      where: { id: videoId },
      select: { id: true, title: true, channelName: true },
    });
    if (video) {
      await this.prisma.$executeRawUnsafe(
        `INSERT INTO "VideoPipelineStatus" ("videoId", "ingest", "updatedAt")
         VALUES ($1, $2::jsonb, CURRENT_TIMESTAMP)
         ON CONFLICT ("videoId") DO UPDATE SET
           "ingest" = COALESCE("VideoPipelineStatus"."ingest", '{}'::jsonb) || EXCLUDED."ingest",
           "updatedAt" = CURRENT_TIMESTAMP`,
        videoId,
        JSON.stringify({
          status: 'ignored',
          lastError: reason || 'Ignored manually by admin',
          processedBy: 'mobile',
          processedAt: new Date().toISOString(),
        }),
      );
      await this.appendActivity({
        videoId,
        title: video.title,
        channelName: video.channelName,
        status: 'ignored',
        source: 'mobile',
        adminEmail,
        error: reason || 'Ignored manually by admin',
        at: new Date().toISOString(),
      });
    }
    await this.removeFromPending(videoId);
    await this.cache.delKey(this.claimLockKey(videoId));
    return { ok: true };
  }

  async reportFailure(
    params: { videoId: string; error: string; permanent?: boolean },
    adminEmail: string,
  ): Promise<{ ok: true }> {
    const { videoId, error, permanent } = params;
    await this.cache.delKey(this.claimLockKey(videoId));

    const status = permanent ? 'dead' : 'failed';
    const video = await this.prisma.video.findUnique({
      where: { id: videoId },
      select: { id: true, title: true, channelName: true },
    });

    if (video) {
      await this.prisma.$executeRawUnsafe(
        `INSERT INTO "VideoPipelineStatus" ("videoId", "ingest", "updatedAt")
         VALUES ($1, $2::jsonb, CURRENT_TIMESTAMP)
         ON CONFLICT ("videoId") DO UPDATE SET
           "ingest" = COALESCE("VideoPipelineStatus"."ingest", '{}'::jsonb) || EXCLUDED."ingest",
           "updatedAt" = CURRENT_TIMESTAMP`,
        videoId,
        JSON.stringify({
          status,
          lastError: (error || 'Unknown error').slice(0, 1000),
          lastRetryAt: new Date().toISOString(),
          processedBy: 'mobile',
        }),
      );
      if (permanent) {
        await this.removeFromPending(videoId);
      }
      await this.appendActivity({
        videoId,
        title: video.title,
        channelName: video.channelName,
        status,
        source: 'mobile',
        adminEmail,
        error: (error || 'Unknown error').slice(0, 300),
        at: new Date().toISOString(),
      });
    }
    return { ok: true };
  }

  async getReport(): Promise<Record<string, any>> {
    const [pendingIds, rawEvents, rawDesktop, rawAuthErr, fcmDeviceCount] = await Promise.all([
      this.cache.zrange(this.pendingSetKey(), 0, -1),
      this.cache.lrange(this.activityLogKey(), 0, 99),
      this.cache.getString(this.desktopSyncKey()),
      this.cache.getString(this.authErrorKey()),
      this.push.getRegisteredTokenCount(),
    ]);

    const events: ActivityEvent[] = [];
    for (const raw of rawEvents) {
      try {
        events.push(JSON.parse(raw) as ActivityEvent);
      } catch {
        // ignore
      }
    }

    const now = Date.now();
    const h24 = now - 24 * 3600 * 1000;
    const d7 = now - 7 * 24 * 3600 * 1000;

    const countStats = (sinceMs: number) => {
      const subset = events.filter((e) => new Date(e.at).getTime() >= sinceMs);
      return {
        completed: subset.filter((e) => e.status === 'completed').length,
        failed: subset.filter((e) => e.status === 'failed' || e.status === 'dead').length,
        skipped: subset.filter((e) => e.status === 'short' || e.status === 'ignored').length,
        mobileCompleted: subset.filter((e) => e.status === 'completed' && e.source === 'mobile').length,
        desktopCompleted: subset.filter((e) => e.status === 'completed' && e.source === 'desktop').length,
      };
    };

    let desktopSync: Record<string, any> | null = null;
    if (rawDesktop) {
      try {
        desktopSync = JSON.parse(rawDesktop);
      } catch {
        // ignore
      }
    }

    let authError: Record<string, any> | null = null;
    if (rawAuthErr) {
      try {
        authError = JSON.parse(rawAuthErr);
      } catch {
        // ignore
      }
    }

    return {
      pendingCount: pendingIds.length,
      last24h: countStats(h24),
      last7d: countStats(d7),
      desktopSync,
      audioComAuthError: authError,
      fcmConfigured: this.push.isConfigured(),
      fcmDeviceCount,
      recentActivity: events.slice(0, 50),
    };
  }

  async registerDeviceToken(token: string): Promise<{ ok: true }> {
    if (!token) throw new BadRequestException('token is required');
    await this.push.registerToken(token);
    return { ok: true };
  }

  async unregisterDeviceToken(token: string): Promise<{ ok: true }> {
    if (token) await this.push.unregisterToken(token);
    return { ok: true };
  }

  private async removeFromPending(videoId: string): Promise<void> {
    await this.cache.zrem(this.pendingSetKey(), videoId);
    await this.cache.delKey(this.pendingMetaKey(videoId));
  }

  private async appendActivity(event: ActivityEvent): Promise<void> {
    await this.cache.lpushTrim(this.activityLogKey(), JSON.stringify(event), 100);
  }
}
