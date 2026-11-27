import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
  Optional,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma } from '@prisma/client';
import { randomUUID } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { CacheService } from '../cache/cache.service';
import { UserPlaylistsService } from './user-playlists.service';

export type WatchItemType =
  | 'watch_later'
  | 'video_history'
  | 'video_playhead'
  | 'audio_playback'
  | 'liked_video'
  | 'liked_short';

export interface WatchItemInput {
  opId?: string;
  itemType: WatchItemType;
  itemId: string;
  positionSeconds?: number;
  durationSeconds?: number;
  payloadJson?: string | null;
  isDeleted?: boolean;
  clientUpdatedAt?: number | string | Date;
}

const VALID_WATCH_ITEM_TYPES = new Set<string>([
  'watch_later',
  'video_history',
  'video_playhead',
  'audio_playback',
  'liked_video',
  'liked_short',
]);

const PREF_FIELDS = [
  'languages',
  'primaryBibleVersionId',
  'themeMode',
  'accentColor',
  'defaultPage',
  'lockScreenWordFeedEnabled',
  'lockScreenRefreshIntervalMinutes',
  'hasCompletedOnboarding',
] as const;

@Injectable()
export class UsersService {
  private readonly logger = new Logger(UsersService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
    @Optional() private readonly cache?: CacheService,
    @Optional() private readonly userPlaylistsService?: UserPlaylistsService,
  ) {}

  isAdmin(email?: string): boolean {
    if (!email) return false;
    const adminEmails = this.configService.get<string[]>('adminEmails') || [];
    return adminEmails.includes(email.trim().toLowerCase());
  }

  private clampTimestampMs(raw?: number | string | Date | null): number {
    const now = Date.now();
    const maxAllowed = now + 60_000;
    if (raw === undefined || raw === null) return now;
    const parsed =
      raw instanceof Date
        ? raw.getTime()
        : typeof raw === 'number'
          ? raw
          : Date.parse(String(raw));
    if (!Number.isFinite(parsed) || parsed <= 0) return now;
    return Math.min(parsed, maxAllowed);
  }

  private async ensureUser(data: {
    id: string;
    email?: string | null;
    displayName?: string;
    photoUrl?: string;
  }) {
    const cleanEmail = (data.email || '').trim().toLowerCase();
    if (!cleanEmail) {
      if (typeof this.prisma.user?.findUnique === 'function') {
        const existing = await this.prisma.user.findUnique({
          where: { id: data.id },
          include: { preference: true },
        });
        if (existing) {
          return existing;
        }
      }
      throw new BadRequestException('Valid email is required to create user');
    }

    const role = this.isAdmin(cleanEmail) ? 'ADMIN' : 'USER';

    try {
      return await this.prisma.user.upsert({
        where: { id: data.id },
        update: {
          email: cleanEmail,
          displayName: data.displayName || undefined,
          photoUrl: data.photoUrl || undefined,
          role,
          lastLoginAt: new Date(),
        },
        create: {
          id: data.id,
          email: cleanEmail,
          displayName: data.displayName || 'User',
          photoUrl: data.photoUrl || null,
          role,
          isBlocked: false,
          lastLoginAt: new Date(),
        },
        include: {
          preference: true,
        },
      });
    } catch (err: any) {
      if (err?.code === 'P2002' && typeof this.prisma.user?.findUnique === 'function') {
        const existing = await this.prisma.user.findUnique({
          where: { id: data.id },
          include: { preference: true },
        });
        if (existing) {
          return existing;
        }
      }
      throw err;
    }
  }

  async syncUser(data: {
    id: string;
    email: string;
    displayName?: string;
    photoUrl?: string;
  }) {
    return this.ensureUser(data);
  }

  async getPreferences(userId: string, userEmail?: string | null) {
    return this.getPreferencesUncached(userId, userEmail);
  }

  private async getPreferencesUncached(userId: string, userEmail?: string | null) {
    let pref = await this.prisma.userPreference.findUnique({
      where: { userId },
    });
    if (!pref) {
      const cleanEmail = (userEmail || '').trim().toLowerCase();
      if (cleanEmail) {
        await this.ensureUser({ id: userId, email: cleanEmail });
      } else if (typeof this.prisma.user?.findUnique === 'function') {
        const existingUser = await this.prisma.user.findUnique({
          where: { id: userId },
        });
        if (!existingUser) {
          return {
            userId,
            languages: ['en'],
            primaryBibleVersionId: 'NASB',
            themeMode: 'system',
            accentColor: 'blue',
            defaultPage: 'feed',
            lockScreenWordFeedEnabled: false,
            lockScreenRefreshIntervalMinutes: 60,
            hasCompletedOnboarding: false,
          };
        }
      }

      pref = await this.prisma.userPreference.create({
        data: {
          userId,
          languages: ['en'],
          primaryBibleVersionId: 'NASB',
          defaultPage: 'feed',
          hasCompletedOnboarding: false,
        },
      });
    }

    return pref;
  }

  async savePreferences(
    userId: string,
    data: {
      languages?: string[];
      primaryBibleVersionId?: string;
      themeMode?: string;
      accentColor?: string;
      defaultPage?: string;
      lockScreenWordFeedEnabled?: boolean;
      lockScreenRefreshIntervalMinutes?: number;
      hasCompletedOnboarding?: boolean;
      clientUpdatedAt?: number | string;
      fieldTimestamps?: Record<string, number | string>;
    },
    userEmail?: string | null,
  ) {
    await this.ensureUser({ id: userId, email: userEmail });

    const defaultTs = this.clampTimestampMs(data.clientUpdatedAt);
    const incomingFieldTs = data.fieldTimestamps || {};

    const applySave = async (tx: any) => {
      if (typeof tx.$queryRaw === 'function') {
        await tx.$queryRaw(
          Prisma.sql`SELECT "id" FROM "UserPreference" WHERE "userId" = ${userId} FOR UPDATE`,
        );
      }

      const existing = await tx.userPreference.findUnique({
        where: { userId },
      });

      const storedTs: Record<string, number> =
        existing?.fieldTimestamps && typeof existing.fieldTimestamps === 'object'
          ? { ...(existing.fieldTimestamps as Record<string, number>) }
          : {};

      const updateData: Record<string, any> = {};
      const nextTs: Record<string, number> = { ...storedTs };

      for (const field of PREF_FIELDS) {
        if ((data as any)[field] === undefined) continue;
        const fieldTs = this.clampTimestampMs(
          incomingFieldTs[field] ?? defaultTs,
        );
        const prevTs = typeof storedTs[field] === 'number' ? storedTs[field] : 0;
        if (fieldTs >= prevTs) {
          updateData[field] = (data as any)[field];
          nextTs[field] = fieldTs;
        }
      }

      if (Object.keys(updateData).length > 0) {
        updateData['fieldTimestamps'] = nextTs;
      }

      return tx.userPreference.upsert({
        where: { userId },
        update: updateData,
        create: {
          userId,
          languages: data.languages || ['en'],
          primaryBibleVersionId: data.primaryBibleVersionId || 'NASB',
          themeMode: data.themeMode || 'system',
          accentColor: data.accentColor || 'blue',
          defaultPage: data.defaultPage || 'feed',
          lockScreenWordFeedEnabled: data.lockScreenWordFeedEnabled ?? false,
          lockScreenRefreshIntervalMinutes: data.lockScreenRefreshIntervalMinutes || 60,
          hasCompletedOnboarding: data.hasCompletedOnboarding ?? true,
          fieldTimestamps: nextTs,
        },
      });
    };

    const pref =
      typeof (this.prisma as any).$transaction === 'function'
        ? await (this.prisma as any).$transaction((tx: any) => applySave(tx))
        : await applySave(this.prisma);

    await this.cache?.invalidate(`user:${userId}`);

    return pref;
  }

  async findAll(query?: { search?: string }) {
    const where: any = {};
    if (query?.search) {
      where.OR = [
        { email: { contains: query.search, mode: 'insensitive' } },
        { displayName: { contains: query.search, mode: 'insensitive' } },
      ];
    }

    return this.prisma.user.findMany({
      where,
      orderBy: { lastLoginAt: 'desc' },
    });
  }

  async findOne(id: string) {
    const user = await this.prisma.user.findUnique({
      where: { id },
    });
    if (!user) {
      throw new NotFoundException(`User with ID ${id} not found`);
    }
    return user;
  }

  async toggleBlock(id: string) {
    const user = await this.findOne(id);
    return this.prisma.user.update({
      where: { id },
      data: { isBlocked: !user.isBlocked },
    });
  }

  async blockUser(id: string) {
    return this.prisma.user.update({
      where: { id },
      data: { isBlocked: true },
    });
  }

  async unblockUser(id: string) {
    return this.prisma.user.update({
      where: { id },
      data: { isBlocked: false },
    });
  }

  async removeUser(id: string, currentAdminId?: string) {
    if (currentAdminId && id === currentAdminId) {
      throw new BadRequestException('Cannot remove your own admin account');
    }
    const user = await this.findOne(id);
    if ((this.prisma as any).userPlayback) {
      await (this.prisma as any).userPlayback.deleteMany({
        where: {
          OR: [{ userId: id }, { userEmail: user.email }],
        },
      });
    }
    await this.prisma.user.delete({ where: { id } });
    return { status: 'success', id };
  }

  async upsertWatchItemsBatch(
    userId: string,
    userEmail: string | null | undefined,
    items: WatchItemInput[],
  ) {
    if (!userId) {
      throw new BadRequestException('userId is required');
    }
    await this.ensureUser({ id: userId, email: userEmail });

    const results: Array<{ opId: string; status: 'ok' | 'rejected' | 'retry' }> = [];
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      const opId = item?.opId || String(i);
      const itemId = (item?.itemId || '').trim();
      if (!item || !VALID_WATCH_ITEM_TYPES.has(item.itemType) || !itemId) {
        results.push({ opId, status: 'rejected' });
        continue;
      }

      try {
        await this.upsertWatchItemAtomic(userId, {
          ...item,
          itemId,
        });
        results.push({ opId, status: 'ok' });
      } catch (err: any) {
        if (err?.code === 'P2003' || err?.status === 400 || err?.status === 404) {
          results.push({ opId, status: 'rejected' });
        } else {
          this.logger.warn(`Watch item upsert retry (${item.itemType}:${itemId}): ${err?.message || err}`);
          results.push({ opId, status: 'retry' });
        }
      }
    }

    return { serverTime: Date.now(), results };
  }

  private async upsertWatchItemAtomic(userId: string, item: WatchItemInput) {
    const ts = new Date(this.clampTimestampMs(item.clientUpdatedAt));
    const positionSeconds = Math.max(0, Math.round(item.positionSeconds || 0));
    const durationSeconds = Math.max(0, Math.round(item.durationSeconds || 0));
    const isDeleted = Boolean(item.isDeleted);
    const payloadJson = item.payloadJson ?? null;

    if (typeof (this.prisma as any).$executeRaw === 'function') {
      await (this.prisma as any).$executeRaw(
        Prisma.sql`
          INSERT INTO "UserWatchItem" (
            "id", "userId", "itemType", "itemId",
            "positionSeconds", "durationSeconds", "payloadJson",
            "isDeleted", "clientUpdatedAt", "createdAt"
          )
          VALUES (
            ${randomUUID()}, ${userId}, ${item.itemType}, ${item.itemId},
            ${positionSeconds}, ${durationSeconds}, ${payloadJson},
            ${isDeleted}, ${ts}, NOW()
          )
          ON CONFLICT ("userId", "itemType", "itemId") DO UPDATE
          SET "positionSeconds" = EXCLUDED."positionSeconds",
              "durationSeconds" = EXCLUDED."durationSeconds",
              "payloadJson" = COALESCE(EXCLUDED."payloadJson", "UserWatchItem"."payloadJson"),
              "isDeleted" = EXCLUDED."isDeleted",
              "clientUpdatedAt" = EXCLUDED."clientUpdatedAt"
          WHERE "UserWatchItem"."clientUpdatedAt" <= EXCLUDED."clientUpdatedAt"
        `,
      );
      return;
    }

    const watchItemModel = (this.prisma as any).userWatchItem;
    if (!watchItemModel) return;

    if (typeof watchItemModel.createMany === 'function') {
      await watchItemModel.createMany({
        data: [
          {
            userId,
            itemType: item.itemType,
            itemId: item.itemId,
            positionSeconds,
            durationSeconds,
            payloadJson,
            isDeleted,
            clientUpdatedAt: ts,
          },
        ],
        skipDuplicates: true,
      });
    }

    if (typeof watchItemModel.updateMany === 'function') {
      await watchItemModel.updateMany({
        where: {
          userId,
          itemType: item.itemType,
          itemId: item.itemId,
          clientUpdatedAt: { lte: ts },
        },
        data: {
          positionSeconds,
          durationSeconds,
          ...(payloadJson !== null ? { payloadJson } : {}),
          isDeleted,
          clientUpdatedAt: ts,
        },
      });
    }
  }

  async getSyncState(userId: string, userEmail?: string | null) {
    const serverTime = Date.now();
    const watchItemModel = (this.prisma as any).userWatchItem;
    const subModel = (this.prisma as any).channelSubscription;

    const [
      preferences,
      subRows,
      watchLaterRows,
      historyRows,
      likedVideoRows,
      likedShortRows,
      playheadRows,
      audioRow,
    ] = await Promise.all([
      this.getPreferencesUncached(userId, userEmail),
      subModel?.findMany
        ? subModel.findMany({
            where: { userId },
            select: { channelId: true, isActive: true, clientUpdatedAt: true },
          })
        : Promise.resolve([]),
      watchItemModel?.findMany
        ? watchItemModel.findMany({
            where: { userId, itemType: 'watch_later' },
            orderBy: { clientUpdatedAt: 'desc' },
            take: 500,
          })
        : Promise.resolve([]),
      watchItemModel?.findMany
        ? watchItemModel.findMany({
            where: { userId, itemType: 'video_history' },
            orderBy: { clientUpdatedAt: 'desc' },
            take: 100,
          })
        : Promise.resolve([]),
      watchItemModel?.findMany
        ? watchItemModel.findMany({
            where: { userId, itemType: 'liked_video' },
            orderBy: { clientUpdatedAt: 'desc' },
            take: 1000,
          })
        : Promise.resolve([]),
      watchItemModel?.findMany
        ? watchItemModel.findMany({
            where: { userId, itemType: 'liked_short' },
            orderBy: { clientUpdatedAt: 'desc' },
            take: 1000,
          })
        : Promise.resolve([]),
      watchItemModel?.findMany
        ? watchItemModel.findMany({
            where: { userId, itemType: 'video_playhead', isDeleted: false },
            orderBy: { clientUpdatedAt: 'desc' },
            take: 200,
          })
        : Promise.resolve([]),
      watchItemModel?.findFirst
        ? watchItemModel.findFirst({
            where: { userId, itemType: 'audio_playback', isDeleted: false },
            orderBy: { clientUpdatedAt: 'desc' },
          })
        : Promise.resolve(null),
    ]);

    const subscriptions: string[] = [];
    const subscriptionTombstones: Record<string, number> = {};
    for (const row of subRows || []) {
      const ts = row.clientUpdatedAt ? new Date(row.clientUpdatedAt).getTime() : 0;
      if (row.isActive !== false) {
        subscriptions.push(row.channelId);
      } else {
        subscriptionTombstones[row.channelId] = ts;
      }
    }

    // Hydrate video metadata from Video table for active watch_later & video_history
    const activeVideoIds = Array.from(
      new Set<string>([
        ...(watchLaterRows || [])
          .filter((r: any) => !r.isDeleted)
          .map((r: any) => String(r.itemId)),
        ...(historyRows || [])
          .filter((r: any) => !r.isDeleted)
          .map((r: any) => String(r.itemId)),
        ...(likedVideoRows || [])
          .filter((r: any) => !r.isDeleted)
          .map((r: any) => String(r.itemId)),
        ...(likedShortRows || [])
          .filter((r: any) => !r.isDeleted)
          .map((r: any) => String(r.itemId)),
      ]),
    );

    const videoMap = new Map<string, any>();
    if (activeVideoIds.length > 0 && (this.prisma as any).video?.findMany) {
      const videos = await (this.prisma as any).video.findMany({
        where: { id: { in: activeVideoIds } },
        include: { channel: { select: { id: true, name: true, thumbnail: true } } },
      });
      for (const v of videos || []) {
        videoMap.set(v.id, v);
      }
    }

    const watchLater: any[] = [];
    const watchLaterTombstones: Record<string, number> = {};
    for (const row of watchLaterRows || []) {
      const ts = new Date(row.clientUpdatedAt).getTime();
      if (row.isDeleted) {
        watchLaterTombstones[row.itemId] = ts;
        continue;
      }
      const video = videoMap.get(row.itemId);
      if (video) {
        watchLater.push({ video, updatedAt: ts });
      }
    }

    const videoHistory: any[] = [];
    const videoHistoryTombstones: Record<string, number> = {};
    for (const row of historyRows || []) {
      const ts = new Date(row.clientUpdatedAt).getTime();
      if (row.isDeleted) {
        videoHistoryTombstones[row.itemId] = ts;
        continue;
      }
      const video = videoMap.get(row.itemId);
      if (video) {
        videoHistory.push({
          video,
          progressSeconds: row.positionSeconds || 0,
          durationSeconds: row.durationSeconds || 0,
          watchedAt: ts,
        });
      }
    }

    const likedVideos: any[] = [];
    const likedVideoTombstones: Record<string, number> = {};
    for (const row of likedVideoRows || []) {
      const ts = new Date(row.clientUpdatedAt).getTime();
      if (row.isDeleted) {
        likedVideoTombstones[row.itemId] = ts;
        continue;
      }
      const rawVideo = videoMap.get(row.itemId) ?? this.parseVideoSnapshot(row.payloadJson);
      const video = rawVideo ? this.serializeLikedVideo(rawVideo) : null;
      if (video) likedVideos.push({ video, likedAt: ts });
    }

    const likedShorts: any[] = [];
    const likedShortTombstones: Record<string, number> = {};
    for (const row of likedShortRows || []) {
      const ts = new Date(row.clientUpdatedAt).getTime();
      if (row.isDeleted) {
        likedShortTombstones[row.itemId] = ts;
        continue;
      }
      const rawVideo = videoMap.get(row.itemId) ?? this.parseVideoSnapshot(row.payloadJson);
      const video = rawVideo ? this.serializeLikedVideo(rawVideo) : null;
      if (video) likedShorts.push({ video, likedAt: ts });
    }

    const videoPlayheads: Record<string, { positionSeconds: number; updatedAt: number }> = {};
    for (const row of playheadRows || []) {
      videoPlayheads[row.itemId] = {
        positionSeconds: row.positionSeconds || 0,
        updatedAt: new Date(row.clientUpdatedAt).getTime(),
      };
    }

    // Legacy fallback if UserWatchItem has no rows yet
    let audioPlayback = audioRow
      ? {
          trackId: audioRow.itemId === 'audio' ? undefined : audioRow.itemId,
          positionSeconds: audioRow.positionSeconds || 0,
          durationSeconds: audioRow.durationSeconds || 0,
          payloadJson: audioRow.payloadJson,
          updatedAt: new Date(audioRow.clientUpdatedAt).getTime(),
        }
      : null;

    if (!audioPlayback && (this.prisma as any).userPlayback?.findFirst) {
      const legacyAudio = await this.getLegacyPlaybackRow(userId, userEmail, 'audio');
      if (legacyAudio) {
        audioPlayback = {
          trackId: legacyAudio.trackId,
          positionSeconds: legacyAudio.positionSeconds || 0,
          durationSeconds: legacyAudio.durationSeconds || 0,
          payloadJson: legacyAudio.payloadJson,
          updatedAt: new Date(legacyAudio.updatedAt).getTime(),
        };
      }
    }

    const playlistSlice = this.userPlaylistsService
      ? await this.userPlaylistsService.getPlaylistsSyncSlice(userId, videoMap)
      : { playlists: [], playlistTombstones: {} };

    return {
      serverTime,
      preferences,
      subscriptions,
      subscriptionTombstones,
      watchLater,
      watchLaterTombstones,
      playlists: playlistSlice.playlists,
      playlistTombstones: playlistSlice.playlistTombstones,
      videoHistory,
      videoHistoryTombstones,
      likedVideos,
      likedVideoTombstones,
      likedShorts,
      likedShortTombstones,
      videoPlayheads,
      audioPlayback,
    };
  }

  private parseVideoSnapshot(payloadJson?: string | null): any | null {
    if (!payloadJson) return null;
    try {
      const parsed = JSON.parse(payloadJson);
      return parsed && typeof parsed === 'object' ? parsed : null;
    } catch {
      return null;
    }
  }

  private serializeLikedVideo(video: any) {
    return {
      id: String(video.id ?? ''),
      type: String(video.type ?? 'VIDEO'),
      title: video.title ?? '',
      description: video.description ?? undefined,
      thumbnailUrl: video.thumbnailUrl ?? video.thumbnail ?? '',
      channelId: video.channelId ?? '',
      channelTitle: video.channelTitle ?? video.channelName ?? video.channel?.name ?? 'Channel',
      channelAvatarUrl: video.channelAvatarUrl ?? video.channelThumbnail ?? video.channel?.thumbnail ?? undefined,
      subscriberCount: video.subscriberCount ?? video.channelSubscriberCount ?? undefined,
      viewCount: Number(video.viewCount ?? 0),
      publishedAt: video.publishedAt ?? new Date(0).toISOString(),
      duration: video.duration ?? '0:00',
      streamUrl: video.streamUrl ?? video.stream_url ?? undefined,
      sourceVideoId: video.sourceVideoId ?? undefined,
      clipStartTime: video.clipStartTime ?? undefined,
      clipEndTime: video.clipEndTime ?? undefined,
      cropOffsetX: video.cropOffsetX ?? undefined,
      isLive: Boolean(video.isLive ?? video.is_live ?? false),
    };
  }

  private async getLegacyPlaybackRow(
    userId?: string | null,
    userEmail?: string | null,
    mediaType = 'audio',
  ) {
    const userPlayback = (this.prisma as any).userPlayback;
    if (!userPlayback) return null;
    const lookupOr: any[] = [];
    if (userId) lookupOr.push({ userId }, { userEmail: userId });
    if (userEmail) lookupOr.push({ userEmail: userEmail.trim().toLowerCase() });
    if (lookupOr.length === 0) return null;

    return userPlayback.findFirst
      ? userPlayback.findFirst({
          where: { mediaType, OR: lookupOr },
          orderBy: { updatedAt: 'desc' },
        })
      : userPlayback.findUnique({
          where: {
            userEmail_mediaType: {
              userEmail: (userEmail || userId || '').trim().toLowerCase(),
              mediaType,
            },
          },
        });
  }

  async savePlayback(data: {
    userId: string;
    userEmail?: string;
    deviceId?: string;
    mediaType?: string;
    trackId: string;
    seriesId?: string;
    title?: string;
    speaker?: string;
    coverUrl?: string;
    audioUrl?: string;
    positionSeconds: number;
    durationSeconds: number;
    payloadJson?: string;
    updatedAt?: string;
  }) {
    const userId = (data.userId || '').trim();
    const email = (data.userEmail || '').trim().toLowerCase();
    const mediaType = (data.mediaType || 'audio').toLowerCase();

    if (!userId || !data.trackId) {
      return { success: false, message: 'userId and trackId are required' };
    }

    await this.ensureUser({ id: userId, email });
    const tsMs = this.clampTimestampMs(data.updatedAt);

    // Delegate to UserWatchItem for unified cross-version sync
    if (mediaType === 'audio') {
      await this.upsertWatchItemAtomic(userId, {
        itemType: 'audio_playback',
        itemId: 'audio',
        positionSeconds: data.positionSeconds,
        durationSeconds: data.durationSeconds,
        payloadJson: data.payloadJson ?? null,
        isDeleted: false,
        clientUpdatedAt: tsMs,
      });
    } else if (mediaType === 'video') {
      await this.upsertWatchItemAtomic(userId, {
        itemType: 'video_playhead',
        itemId: data.trackId,
        positionSeconds: data.positionSeconds,
        durationSeconds: data.durationSeconds,
        isDeleted: false,
        clientUpdatedAt: tsMs,
      });
    } else if (mediaType === 'video_playheads' && data.payloadJson) {
      try {
        const parsed = JSON.parse(data.payloadJson) as Record<string, any>;
        for (const [vid, entry] of Object.entries(parsed || {})) {
          await this.upsertWatchItemAtomic(userId, {
            itemType: 'video_playhead',
            itemId: vid,
            positionSeconds: entry?.positionSeconds || 0,
            durationSeconds: 0,
            isDeleted: false,
            clientUpdatedAt: entry?.updatedAt || tsMs,
          });
        }
      } catch {
        // ignore malformed legacy payload
      }
    }

    const updatedAtDate = new Date(tsMs);
    const record = {
      userId,
      userEmail: email || null,
      deviceId: data.deviceId || null,
      mediaType,
      trackId: data.trackId,
      seriesId: data.seriesId || null,
      title: data.title || null,
      speaker: data.speaker || null,
      coverUrl: data.coverUrl || null,
      audioUrl: data.audioUrl || null,
      positionSeconds: Math.max(0, Math.round(data.positionSeconds || 0)),
      durationSeconds: Math.max(0, Math.round(data.durationSeconds || 0)),
      payloadJson: data.payloadJson || null,
      updatedAt: updatedAtDate,
    };

    try {
      const userPlayback = (this.prisma as any).userPlayback;
      if (userPlayback) {
        const existing = await this.getLegacyPlaybackRow(userId, email, mediaType);
        if (existing) {
          if (new Date(existing.updatedAt).getTime() <= tsMs) {
            await userPlayback.update({
              where: { id: existing.id },
              data: {
                ...record,
                userEmail: email || existing.userEmail || userId,
                updatedAt: updatedAtDate,
              },
            });
          }
        } else {
          await userPlayback.upsert({
            where: {
              userEmail_mediaType: {
                userEmail: email || userId,
                mediaType,
              },
            },
            update: {
              ...record,
              userEmail: email || userId,
              updatedAt: updatedAtDate,
            },
            create: {
              ...record,
              userEmail: email || userId,
              updatedAt: updatedAtDate,
            },
          });
        }
      }
    } catch (e) {
      this.logger.warn(`Database playback upsert non-critical fallback: ${e}`);
    }

    return { success: true, playback: record };
  }

  async getPlayback(query: { userId?: string; userEmail?: string; mediaType?: string }) {
    const userId = (query.userId || '').trim();
    const email = (query.userEmail || '').trim().toLowerCase();
    const mediaType = (query.mediaType || 'audio').toLowerCase();

    if (!userId && !email) {
      return null;
    }

    if (userId && mediaType === 'audio' && (this.prisma as any).userWatchItem?.findFirst) {
      const row = await (this.prisma as any).userWatchItem.findFirst({
        where: { userId, itemType: 'audio_playback', isDeleted: false },
        orderBy: { clientUpdatedAt: 'desc' },
      });
      if (row) {
        let parsedTrackId = row.itemId === 'audio' ? '' : row.itemId;
        if (!parsedTrackId && row.payloadJson) {
          try {
            parsedTrackId = JSON.parse(row.payloadJson)?.id || '';
          } catch {}
        }
        return {
          userId,
          userEmail: email || null,
          mediaType: 'audio',
          trackId: parsedTrackId,
          positionSeconds: row.positionSeconds,
          durationSeconds: row.durationSeconds,
          payloadJson: row.payloadJson,
          updatedAt: row.clientUpdatedAt,
        };
      }
    }

    try {
      const row = await this.getLegacyPlaybackRow(userId, email, mediaType);
      if (row) return row;
    } catch (e) {
      this.logger.warn(`Database playback query non-critical fallback: ${e}`);
    }

    return null;
  }
}
