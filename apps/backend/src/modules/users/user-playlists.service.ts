import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import {
  AddPlaylistItemDto,
  CreatePlaylistDto,
  ReorderPlaylistItemsDto,
  UpdatePlaylistDto,
} from './dto/playlist.dto';

export interface PlaylistVideoDto {
  id: string;
  type: string;
  title: string;
  description?: string;
  thumbnailUrl: string;
  channelId: string;
  channelTitle: string;
  channelAvatarUrl?: string;
  subscriberCount?: string;
  viewCount: number;
  publishedAt: string;
  duration: string;
  streamUrl?: string;
  sourceVideoId?: string;
  clipStartTime?: number;
  clipEndTime?: number;
  cropOffsetX?: number;
  isLive: boolean;
}

export interface PlaylistDto {
  id: string;
  title: string;
  description: string | null;
  thumbnailUrl: string | null;
  videoCount: number;
  videos: PlaylistVideoDto[];
  createdAt: string;
  updatedAt: string;
  clientUpdatedAt: number;
}

export interface PlaylistsSyncSlice {
  playlists: PlaylistDto[];
  playlistTombstones: Record<string, number>;
}

const MAX_TITLE_LENGTH = 120;
const MAX_DESCRIPTION_LENGTH = 1000;
const MAX_FUTURE_SKEW_MS = 60_000;

@Injectable()
export class UserPlaylistsService {
  constructor(private readonly prisma: PrismaService) {}

  private clampTimestampMs(raw?: number | string | Date | null): number {
    const now = Date.now();
    const maxAllowed = now + MAX_FUTURE_SKEW_MS;
    if (raw === undefined || raw === null) return now;

    let parsed: number;
    if (raw instanceof Date) {
      parsed = raw.getTime();
    } else if (typeof raw === 'number') {
      parsed = raw;
    } else {
      const str = String(raw).trim();
      parsed = /^\d+$/.test(str) ? Number(str) : Date.parse(str);
    }

    if (!Number.isFinite(parsed) || parsed <= 0) return now;
    return Math.min(parsed, maxAllowed);
  }

  private normalizeTitle(raw: unknown): string {
    if (typeof raw !== 'string') {
      throw new BadRequestException('Playlist title is required');
    }
    const trimmed = raw.trim();
    if (trimmed.length === 0) {
      throw new BadRequestException('Playlist title cannot be empty');
    }
    if (trimmed.length > MAX_TITLE_LENGTH) {
      throw new BadRequestException(
        `Playlist title must be at most ${MAX_TITLE_LENGTH} characters`,
      );
    }
    return trimmed;
  }

  private normalizeDescription(raw: unknown): string | null | undefined {
    if (raw === undefined) return undefined;
    if (raw === null) return null;
    if (typeof raw !== 'string') {
      throw new BadRequestException('Playlist description must be a string');
    }
    const trimmed = raw.trim();
    if (trimmed.length > MAX_DESCRIPTION_LENGTH) {
      throw new BadRequestException(
        `Playlist description must be at most ${MAX_DESCRIPTION_LENGTH} characters`,
      );
    }
    return trimmed.length === 0 ? null : trimmed;
  }

  private async ensureUser(data: { id: string; email?: string | null }) {
    const cleanEmail = (data.email || '').trim().toLowerCase();
    const fallbackEmail = `guest_${data.id}@christianapp.local`;

    try {
      return await this.prisma.user.upsert({
        where: { id: data.id },
        update: {
          email: cleanEmail || undefined,
          lastLoginAt: new Date(),
        },
        create: {
          id: data.id,
          email: cleanEmail || fallbackEmail,
          displayName: 'User',
          role: 'USER',
          isBlocked: false,
          lastLoginAt: new Date(),
        },
      });
    } catch (err: any) {
      if (err?.code === 'P2002') {
        return this.prisma.user.upsert({
          where: { id: data.id },
          update: {
            lastLoginAt: new Date(),
          },
          create: {
            id: data.id,
            email: fallbackEmail,
            displayName: 'User',
            role: 'USER',
            isBlocked: false,
            lastLoginAt: new Date(),
          },
        });
      }
      throw err;
    }
  }

  private serializeVideo(video: any): PlaylistVideoDto {
    const publishedAt =
      video.publishedAt instanceof Date
        ? video.publishedAt.toISOString()
        : video.publishedAt ?? new Date(0).toISOString();

    return {
      id: String(video.id ?? ''),
      type: String(video.type ?? 'VIDEO'),
      title: video.title ?? '',
      description: video.description ?? undefined,
      thumbnailUrl: video.thumbnailUrl ?? video.thumbnail ?? '',
      channelId: video.channelId ?? '',
      channelTitle:
        video.channelTitle ??
        video.channelName ??
        video.channel?.name ??
        'Channel',
      channelAvatarUrl:
        video.channelAvatarUrl ??
        video.channelThumbnail ??
        video.channel?.thumbnail ??
        undefined,
      subscriberCount:
        video.subscriberCount ?? video.channelSubscriberCount ?? undefined,
      viewCount: Number(video.viewCount ?? 0),
      publishedAt,
      duration: video.duration ?? '0:00',
      streamUrl: video.streamUrl ?? video.stream_url ?? undefined,
      sourceVideoId: video.sourceVideoId ?? undefined,
      clipStartTime: video.clipStartTime ?? undefined,
      clipEndTime: video.clipEndTime ?? undefined,
      cropOffsetX: video.cropOffsetX ?? undefined,
      isLive: Boolean(video.isLive ?? video.is_live ?? false),
    };
  }

  private async hydrateVideoMap(
    videoIds: string[],
    existingVideoMap?: Map<string, any>,
  ): Promise<Map<string, any>> {
    const videoMap = existingVideoMap ? new Map(existingVideoMap) : new Map<string, any>();
    const missingIds = Array.from(new Set(videoIds)).filter(
      (id) => id && !videoMap.has(id),
    );

    if (missingIds.length > 0 && (this.prisma as any).video?.findMany) {
      const rows = await (this.prisma as any).video.findMany({
        where: { id: { in: missingIds } },
        include: { channel: { select: { id: true, name: true, thumbnail: true } } },
      });
      for (const v of rows || []) {
        videoMap.set(v.id, v);
      }
    }

    return videoMap;
  }

  private toPlaylistDto(row: any, videoMap: Map<string, any>): PlaylistDto {
    const sortedItems = [...(row.items || [])].sort(
      (a: any, b: any) => (a.position ?? 0) - (b.position ?? 0),
    );

    const videos: PlaylistVideoDto[] = [];
    for (const item of sortedItems) {
      const rawVideo = videoMap.get(item.videoId);
      if (rawVideo) {
        videos.push(this.serializeVideo(rawVideo));
      }
    }

    const firstThumb = videos[0]?.thumbnailUrl;
    const thumbnailUrl = firstThumb ? firstThumb : null;

    return {
      id: row.id,
      title: row.title,
      description: row.description ?? null,
      thumbnailUrl,
      videoCount: videos.length,
      videos,
      createdAt:
        row.createdAt instanceof Date
          ? row.createdAt.toISOString()
          : String(row.createdAt),
      updatedAt:
        row.updatedAt instanceof Date
          ? row.updatedAt.toISOString()
          : String(row.updatedAt),
      clientUpdatedAt: new Date(row.clientUpdatedAt).getTime(),
    };
  }

  private async runInTx<T>(fn: (tx: any) => Promise<T>): Promise<T> {
    if (typeof (this.prisma as any).$transaction === 'function') {
      return (this.prisma as any).$transaction((tx: any) => fn(tx));
    }
    return fn(this.prisma);
  }

  async listPlaylists(userId: string): Promise<PlaylistDto[]> {
    const rows = await (this.prisma as any).userPlaylist.findMany({
      where: { userId, isDeleted: false },
      include: { items: { orderBy: { position: 'asc' } } },
      orderBy: { updatedAt: 'desc' },
    });

    const allVideoIds: string[] = [];
    for (const row of rows || []) {
      for (const item of row.items || []) {
        allVideoIds.push(item.videoId);
      }
    }

    const videoMap = await this.hydrateVideoMap(allVideoIds);
    return (rows || []).map((row: any) => this.toPlaylistDto(row, videoMap));
  }

  async getPlaylist(userId: string, playlistId: string): Promise<PlaylistDto> {
    const row = await (this.prisma as any).userPlaylist.findFirst({
      where: { id: playlistId, userId, isDeleted: false },
      include: { items: { orderBy: { position: 'asc' } } },
    });

    if (!row) {
      throw new NotFoundException('Playlist not found');
    }

    const videoIds = (row.items || []).map((item: any) => item.videoId);
    const videoMap = await this.hydrateVideoMap(videoIds);
    return this.toPlaylistDto(row, videoMap);
  }

  async createPlaylist(
    user: { userId: string; email?: string | null },
    dto: CreatePlaylistDto,
  ): Promise<PlaylistDto> {
    const title = this.normalizeTitle(dto.title);
    const description = this.normalizeDescription(dto.description) ?? null;
    await this.ensureUser({ id: user.userId, email: user.email });

    const clientTs = new Date(this.clampTimestampMs(dto.clientUpdatedAt));
    const clientId = dto.id?.trim() || undefined;

    if (clientId) {
      const existing = await (this.prisma as any).userPlaylist.findUnique({
        where: { id: clientId },
        include: { items: { orderBy: { position: 'asc' } } },
      });

      if (existing) {
        if (existing.userId !== user.userId) {
          throw new ForbiddenException('Playlist belongs to another user');
        }

        const existingTsMs = new Date(existing.clientUpdatedAt).getTime();
        let resolved = existing;
        if (clientTs.getTime() >= existingTsMs) {
          resolved = await (this.prisma as any).userPlaylist.update({
            where: { id: clientId },
            data: {
              title,
              description,
              isDeleted: false,
              clientUpdatedAt: clientTs,
            },
            include: { items: { orderBy: { position: 'asc' } } },
          });
        }

        const videoIds = (resolved.items || []).map((item: any) => item.videoId);
        const videoMap = await this.hydrateVideoMap(videoIds);
        return this.toPlaylistDto(resolved, videoMap);
      }
    }

    try {
      const created = await (this.prisma as any).userPlaylist.create({
        data: {
          ...(clientId ? { id: clientId } : {}),
          userId: user.userId,
          title,
          description,
          isDeleted: false,
          clientUpdatedAt: clientTs,
        },
        include: { items: { orderBy: { position: 'asc' } } },
      });

      return this.toPlaylistDto(created, new Map());
    } catch (err: any) {
      if (err?.code === 'P2002' && clientId) {
        const existing = await (this.prisma as any).userPlaylist.findUnique({
          where: { id: clientId },
          include: { items: { orderBy: { position: 'asc' } } },
        });
        if (existing) {
          if (existing.userId !== user.userId) {
            throw new ForbiddenException('Playlist belongs to another user');
          }
          const videoIds = (existing.items || []).map((item: any) => item.videoId);
          const videoMap = await this.hydrateVideoMap(videoIds);
          return this.toPlaylistDto(existing, videoMap);
        }
      }
      throw err;
    }
  }

  async updatePlaylist(
    userId: string,
    playlistId: string,
    dto: UpdatePlaylistDto,
  ): Promise<PlaylistDto> {
    const existing = await (this.prisma as any).userPlaylist.findFirst({
      where: { id: playlistId, userId, isDeleted: false },
      include: { items: { orderBy: { position: 'asc' } } },
    });

    if (!existing) {
      throw new NotFoundException('Playlist not found');
    }

    const nextTitle =
      dto.title !== undefined ? this.normalizeTitle(dto.title) : undefined;
    const nextDescription =
      dto.description !== undefined
        ? this.normalizeDescription(dto.description)
        : undefined;

    const incomingTsMs = this.clampTimestampMs(dto.clientUpdatedAt);
    const existingTsMs = new Date(existing.clientUpdatedAt).getTime();

    let resolved = existing;
    if (incomingTsMs >= existingTsMs) {
      resolved = await (this.prisma as any).userPlaylist.update({
        where: { id: playlistId },
        data: {
          ...(nextTitle !== undefined ? { title: nextTitle } : {}),
          ...(nextDescription !== undefined ? { description: nextDescription } : {}),
          clientUpdatedAt: new Date(incomingTsMs),
        },
        include: { items: { orderBy: { position: 'asc' } } },
      });
    }

    const videoIds = (resolved.items || []).map((item: any) => item.videoId);
    const videoMap = await this.hydrateVideoMap(videoIds);
    return this.toPlaylistDto(resolved, videoMap);
  }

  async deletePlaylist(
    userId: string,
    playlistId: string,
    clientUpdatedAt?: number | string,
  ): Promise<{ status: 'deleted'; id: string }> {
    const existing = await (this.prisma as any).userPlaylist.findUnique({
      where: { id: playlistId },
    });

    if (!existing || existing.userId !== userId) {
      throw new NotFoundException('Playlist not found');
    }

    const incomingTsMs = this.clampTimestampMs(clientUpdatedAt);
    const existingTsMs = new Date(existing.clientUpdatedAt).getTime();

    if (!existing.isDeleted && incomingTsMs >= existingTsMs) {
      await (this.prisma as any).userPlaylist.update({
        where: { id: playlistId },
        data: {
          isDeleted: true,
          clientUpdatedAt: new Date(incomingTsMs),
        },
      });
    }

    return { status: 'deleted', id: playlistId };
  }

  async addItem(
    userId: string,
    playlistId: string,
    dto: AddPlaylistItemDto,
  ): Promise<PlaylistDto> {
    const videoId = (dto.videoId || '').trim();
    if (!videoId) {
      throw new BadRequestException('videoId is required');
    }

    const existing = await (this.prisma as any).userPlaylist.findFirst({
      where: { id: playlistId, userId, isDeleted: false },
      include: { items: { orderBy: { position: 'asc' } } },
    });

    if (!existing) {
      throw new NotFoundException('Playlist not found');
    }

    const currentItems: any[] = existing.items || [];
    if (currentItems.some((item) => item.videoId === videoId)) {
      const videoMap = await this.hydrateVideoMap(
        currentItems.map((item) => item.videoId),
      );
      return this.toPlaylistDto(existing, videoMap);
    }

    const insertPos =
      dto.position !== undefined
        ? Math.min(Math.max(0, dto.position), currentItems.length)
        : currentItems.length;
    const nowTs = new Date(this.clampTimestampMs(dto.clientUpdatedAt));

    let updated: any;
    try {
      updated = await this.runInTx(async (tx) => {
        if (insertPos < currentItems.length) {
          await tx.userPlaylistItem.updateMany({
            where: { playlistId, position: { gte: insertPos } },
            data: { position: { increment: 1 } },
          });
        }

        await tx.userPlaylistItem.create({
          data: {
            playlistId,
            videoId,
            position: insertPos,
          },
        });

        return tx.userPlaylist.update({
          where: { id: playlistId },
          data: {
            clientUpdatedAt: nowTs,
            updatedAt: new Date(),
          },
          include: { items: { orderBy: { position: 'asc' } } },
        });
      });
    } catch (err: any) {
      if (err?.code === 'P2002') {
        return this.getPlaylist(userId, playlistId);
      }
      throw err;
    }

    const videoMap = await this.hydrateVideoMap(
      (updated.items || []).map((item: any) => item.videoId),
    );
    return this.toPlaylistDto(updated, videoMap);
  }

  async removeItem(
    userId: string,
    playlistId: string,
    videoId: string,
  ): Promise<PlaylistDto> {
    const existing = await (this.prisma as any).userPlaylist.findFirst({
      where: { id: playlistId, userId, isDeleted: false },
      include: { items: { orderBy: { position: 'asc' } } },
    });

    if (!existing) {
      throw new NotFoundException('Playlist not found');
    }

    const currentItems: any[] = existing.items || [];
    if (!currentItems.some((item) => item.videoId === videoId)) {
      const videoMap = await this.hydrateVideoMap(
        currentItems.map((item) => item.videoId),
      );
      return this.toPlaylistDto(existing, videoMap);
    }

    const remaining = currentItems.filter((item) => item.videoId !== videoId);
    const now = new Date();

    const updated = await this.runInTx(async (tx) => {
      await tx.userPlaylistItem.deleteMany({
        where: { playlistId, videoId },
      });

      for (let i = 0; i < remaining.length; i++) {
        if (remaining[i].position !== i) {
          await tx.userPlaylistItem.update({
            where: { id: remaining[i].id },
            data: { position: i },
          });
        }
      }

      return tx.userPlaylist.update({
        where: { id: playlistId },
        data: {
          clientUpdatedAt: now,
          updatedAt: now,
        },
        include: { items: { orderBy: { position: 'asc' } } },
      });
    });

    const videoMap = await this.hydrateVideoMap(
      (updated.items || []).map((item: any) => item.videoId),
    );
    return this.toPlaylistDto(updated, videoMap);
  }

  async reorderItems(
    userId: string,
    playlistId: string,
    dto: ReorderPlaylistItemsDto,
  ): Promise<PlaylistDto> {
    const existing = await (this.prisma as any).userPlaylist.findFirst({
      where: { id: playlistId, userId, isDeleted: false },
      include: { items: { orderBy: { position: 'asc' } } },
    });

    if (!existing) {
      throw new NotFoundException('Playlist not found');
    }

    const currentItems: any[] = existing.items || [];
    const byVideoId = new Map<string, any>(
      currentItems.map((item) => [item.videoId, item]),
    );
    const seen = new Set<string>();
    const ordered: any[] = [];

    for (const vid of dto.videoIds || []) {
      if (!seen.has(vid) && byVideoId.has(vid)) {
        seen.add(vid);
        ordered.push(byVideoId.get(vid));
      }
    }

    for (const item of currentItems) {
      if (!seen.has(item.videoId)) {
        seen.add(item.videoId);
        ordered.push(item);
      }
    }

    const nowTs = new Date(this.clampTimestampMs(dto.clientUpdatedAt));

    const updated = await this.runInTx(async (tx) => {
      for (let i = 0; i < ordered.length; i++) {
        if (ordered[i].position !== i) {
          await tx.userPlaylistItem.update({
            where: { id: ordered[i].id },
            data: { position: i },
          });
        }
      }

      return tx.userPlaylist.update({
        where: { id: playlistId },
        data: {
          clientUpdatedAt: nowTs,
          updatedAt: new Date(),
        },
        include: { items: { orderBy: { position: 'asc' } } },
      });
    });

    const videoMap = await this.hydrateVideoMap(
      (updated.items || []).map((item: any) => item.videoId),
    );
    return this.toPlaylistDto(updated, videoMap);
  }

  async getPlaylistsSyncSlice(
    userId: string,
    existingVideoMap?: Map<string, any>,
  ): Promise<PlaylistsSyncSlice> {
    const playlistModel = (this.prisma as any).userPlaylist;
    if (!playlistModel?.findMany) {
      return { playlists: [], playlistTombstones: {} };
    }

    const rows = await playlistModel.findMany({
      where: { userId },
      include: { items: { orderBy: { position: 'asc' } } },
      orderBy: { updatedAt: 'desc' },
    });

    const activeRows: any[] = [];
    const playlistTombstones: Record<string, number> = {};
    const allVideoIds: string[] = [];

    for (const row of rows || []) {
      if (row.isDeleted) {
        playlistTombstones[row.id] = new Date(row.clientUpdatedAt).getTime();
        continue;
      }
      activeRows.push(row);
      for (const item of row.items || []) {
        allVideoIds.push(item.videoId);
      }
    }

    const videoMap = await this.hydrateVideoMap(allVideoIds, existingVideoMap);
    const playlists = activeRows.map((row) => this.toPlaylistDto(row, videoMap));

    return { playlists, playlistTombstones };
  }
}
