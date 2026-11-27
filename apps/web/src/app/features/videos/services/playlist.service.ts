import { Injectable, effect, inject, signal, untracked } from '@angular/core';
import { AuthService } from '../../../core/auth/auth.service';
import { UserSyncService } from '../../../core/services/user-sync.service';
import { UserPlaylist, normalizePlaylist } from '../models/playlist.model';
import { Video } from '../models/video.model';

const PLAYLISTS_STORAGE_KEY = 'ct_web_playlists_v1';
const MAX_TITLE_LENGTH = 120;

function generatePlaylistId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `pl_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;
}

@Injectable({ providedIn: 'root' })
export class PlaylistService {
  private readonly auth = inject(AuthService);
  private readonly userSync = inject(UserSyncService);

  readonly playlists = signal<UserPlaylist[]>([]);
  readonly loading = signal<boolean>(false);

  private syncedForUserId: string | null | undefined = undefined;

  constructor() {
    this.reloadFromUserCache();

    effect(() => {
      const user = this.auth.currentUser();
      const nextUid = user?.id ?? null;
      if (nextUid !== this.syncedForUserId) {
        this.syncedForUserId = nextUid;
        untracked(() => this.reloadFromUserCache());
      }
    });

    effect(() => {
      const remote = this.userSync.remoteState();
      if (!remote) return;
      untracked(() => this.applyRemoteState(remote));
    });
  }

  playlistById(id: string): UserPlaylist | null {
    if (!id) return null;
    return this.playlists().find((p) => p.id === id) ?? null;
  }

  playlistsContaining(videoId: string): UserPlaylist[] {
    if (!videoId) return [];
    return this.playlists().filter((p) =>
      p.videos.some((v) => v.id === videoId),
    );
  }

  isInAnyPlaylist(videoId: string): boolean {
    return this.playlistsContaining(videoId).length > 0;
  }

  createPlaylist(
    title: string,
    description?: string | null,
    initialVideo?: Video,
  ): UserPlaylist | null {
    const cleanTitle = title.trim();
    if (!cleanTitle || cleanTitle.length > MAX_TITLE_LENGTH) {
      return null;
    }
    const cleanDesc =
      typeof description === 'string' && description.trim().length > 0
        ? description.trim()
        : null;
    const now = this.userSync.nowServerAligned();
    const nowIso = new Date(now).toISOString();
    const id = generatePlaylistId();
    const videos = initialVideo ? [initialVideo] : [];

    const created: UserPlaylist = {
      id,
      title: cleanTitle,
      description: cleanDesc,
      thumbnailUrl: initialVideo?.thumbnailUrl ?? null,
      videoCount: videos.length,
      videos,
      createdAt: nowIso,
      updatedAt: nowIso,
      clientUpdatedAt: now,
    };

    const next = [created, ...this.playlists()];
    this.playlists.set(next);
    this.writeUserJson(PLAYLISTS_STORAGE_KEY, next);

    this.userSync.enqueuePlaylistOp({
      playlistId: id,
      action: 'create',
      payload: {
        id,
        title: cleanTitle,
        description: cleanDesc,
      },
      clientUpdatedAt: now,
    });

    if (initialVideo) {
      this.userSync.enqueuePlaylistOp({
        playlistId: id,
        action: 'add_item',
        payload: {
          videoId: initialVideo.id,
        },
        clientUpdatedAt: now + 1,
      });
    }

    return created;
  }

  updatePlaylist(
    id: string,
    patch: { title?: string; description?: string | null },
  ): boolean {
    const existing = this.playlistById(id);
    if (!existing) return false;

    let nextTitle = existing.title;
    if (patch.title !== undefined) {
      const trimmed = patch.title.trim();
      if (!trimmed || trimmed.length > MAX_TITLE_LENGTH) {
        return false;
      }
      nextTitle = trimmed;
    }

    const nextDescription =
      patch.description !== undefined
        ? typeof patch.description === 'string' &&
          patch.description.trim().length > 0
          ? patch.description.trim()
          : null
        : existing.description;

    const now = this.userSync.nowServerAligned();
    const updated: UserPlaylist = {
      ...existing,
      title: nextTitle,
      description: nextDescription,
      updatedAt: new Date(now).toISOString(),
      clientUpdatedAt: now,
    };

    const next = this.playlists().map((p) => (p.id === id ? updated : p));
    this.playlists.set(next);
    this.writeUserJson(PLAYLISTS_STORAGE_KEY, next);

    this.userSync.enqueuePlaylistOp({
      playlistId: id,
      action: 'update',
      payload: {
        title: nextTitle,
        description: nextDescription,
      },
      clientUpdatedAt: now,
    });
    return true;
  }

  deletePlaylist(id: string): boolean {
    const existing = this.playlistById(id);
    if (!existing) return false;

    const now = this.userSync.nowServerAligned();
    const next = this.playlists().filter((p) => p.id !== id);
    this.playlists.set(next);
    this.writeUserJson(PLAYLISTS_STORAGE_KEY, next);

    this.userSync.enqueuePlaylistOp({
      playlistId: id,
      action: 'delete',
      clientUpdatedAt: now,
    });
    return true;
  }

  addVideoToPlaylist(playlistId: string, video: Video): boolean {
    const existing = this.playlistById(playlistId);
    if (!existing || !video.id) return false;
    if (existing.videos.some((v) => v.id === video.id)) return false;

    const now = this.userSync.nowServerAligned();
    const videos = [...existing.videos, video];
    const updated: UserPlaylist = {
      ...existing,
      videos,
      videoCount: videos.length,
      thumbnailUrl: videos[0]?.thumbnailUrl ?? null,
      updatedAt: new Date(now).toISOString(),
      clientUpdatedAt: now,
    };

    const next = this.playlists().map((p) =>
      p.id === playlistId ? updated : p,
    );
    this.playlists.set(next);
    this.writeUserJson(PLAYLISTS_STORAGE_KEY, next);

    this.userSync.enqueuePlaylistOp({
      playlistId,
      action: 'add_item',
      payload: { videoId: video.id },
      clientUpdatedAt: now,
    });
    return true;
  }

  removeVideoFromPlaylist(playlistId: string, videoId: string): boolean {
    const existing = this.playlistById(playlistId);
    if (!existing || !videoId) return false;
    if (!existing.videos.some((v) => v.id === videoId)) return false;

    const now = this.userSync.nowServerAligned();
    const videos = existing.videos.filter((v) => v.id !== videoId);
    const updated: UserPlaylist = {
      ...existing,
      videos,
      videoCount: videos.length,
      thumbnailUrl: videos[0]?.thumbnailUrl ?? null,
      updatedAt: new Date(now).toISOString(),
      clientUpdatedAt: now,
    };

    const next = this.playlists().map((p) =>
      p.id === playlistId ? updated : p,
    );
    this.playlists.set(next);
    this.writeUserJson(PLAYLISTS_STORAGE_KEY, next);

    this.userSync.enqueuePlaylistOp({
      playlistId,
      action: 'remove_item',
      payload: { videoId },
      clientUpdatedAt: now,
    });
    return true;
  }

  reorderVideos(
    playlistId: string,
    fromIndex: number,
    toIndex: number,
  ): boolean {
    const existing = this.playlistById(playlistId);
    if (!existing) return false;
    const len = existing.videos.length;
    if (
      fromIndex < 0 ||
      toIndex < 0 ||
      fromIndex >= len ||
      toIndex >= len ||
      fromIndex === toIndex
    ) {
      return false;
    }

    const now = this.userSync.nowServerAligned();
    const videos = [...existing.videos];
    const [moved] = videos.splice(fromIndex, 1);
    videos.splice(toIndex, 0, moved);

    const updated: UserPlaylist = {
      ...existing,
      videos,
      videoCount: videos.length,
      thumbnailUrl: videos[0]?.thumbnailUrl ?? null,
      updatedAt: new Date(now).toISOString(),
      clientUpdatedAt: now,
    };

    const next = this.playlists().map((p) =>
      p.id === playlistId ? updated : p,
    );
    this.playlists.set(next);
    this.writeUserJson(PLAYLISTS_STORAGE_KEY, next);

    this.userSync.enqueuePlaylistOp({
      playlistId,
      action: 'reorder',
      payload: { videoIds: videos.map((v) => v.id) },
      clientUpdatedAt: now,
    });
    return true;
  }

  private reloadFromUserCache(): void {
    const stored = this.readUserJson<unknown[]>(PLAYLISTS_STORAGE_KEY, []);
    const normalized = Array.isArray(stored)
      ? stored
          .map((item) => normalizePlaylist(item))
          .filter((item): item is UserPlaylist => item !== null)
      : [];
    this.playlists.set(normalized);
  }

  private applyRemoteState(
    remote: NonNullable<ReturnType<UserSyncService['remoteState']>>,
  ): void {
    if (!Array.isArray(remote.playlists) && !remote.playlistTombstones) {
      return;
    }

    const tombstones = remote.playlistTombstones ?? {};
    const localById = new Map(this.playlists().map((p) => [p.id, p]));
    const mergedById = new Map<string, UserPlaylist>();

    // Start with remote playlists (skip if tombstoned on server)
    for (const raw of remote.playlists ?? []) {
      const playlist = normalizePlaylist(raw);
      if (!playlist) continue;
      const tombTs = tombstones[playlist.id] ?? 0;
      if (tombTs > 0 && tombTs >= playlist.clientUpdatedAt) {
        continue;
      }
      mergedById.set(playlist.id, playlist);
    }

    // Preserve local playlists that have pending ops or were not yet pushed/tombstoned
    for (const [id, local] of localById.entries()) {
      if (this.userSync.hasPendingPlaylistOps(id)) {
        mergedById.set(id, local);
        continue;
      }
      const tombTs = tombstones[id] ?? 0;
      if (tombTs > 0 && tombTs >= local.clientUpdatedAt) {
        mergedById.delete(id);
        continue;
      }
      if (!mergedById.has(id) && tombTs === 0 && !this.auth.canSync()) {
        mergedById.set(id, local);
      }
    }

    // If a playlist has a pending delete op, ensure it stays removed locally
    for (const op of Object.values(this.userSync.pendingOps())) {
      if (
        op.kind === 'playlist_op' &&
        op.playlistAction === 'delete' &&
        op.playlistId &&
        !localById.has(op.playlistId)
      ) {
        mergedById.delete(op.playlistId);
      }
    }

    const sorted = Array.from(mergedById.values()).sort(
      (a, b) =>
        b.clientUpdatedAt - a.clientUpdatedAt ||
        b.updatedAt.localeCompare(a.updatedAt),
    );
    this.playlists.set(sorted);
    this.writeUserJson(PLAYLISTS_STORAGE_KEY, sorted);
  }

  private readUserJson<T>(baseKey: string, fallback: T): T {
    const key = this.auth.isAuthenticated()
      ? this.userSync.userCacheKey(baseKey)
      : baseKey;
    try {
      const raw = localStorage.getItem(key);
      return raw ? (JSON.parse(raw) as T) : fallback;
    } catch {
      return fallback;
    }
  }

  private writeUserJson(baseKey: string, value: unknown): void {
    const key = this.auth.isAuthenticated()
      ? this.userSync.userCacheKey(baseKey)
      : baseKey;
    try {
      localStorage.setItem(key, JSON.stringify(value));
    } catch {
      // ignore storage quota errors
    }
  }
}
