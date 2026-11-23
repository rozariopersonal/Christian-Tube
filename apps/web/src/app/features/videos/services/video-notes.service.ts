import { Injectable, computed, inject, signal } from '@angular/core';
import { AuthService } from '../../../core/auth/auth.service';
import {
  SyncUserItem,
  UserItemsSyncService,
} from '../../../core/services/user-items-sync.service';
import { UserSyncService } from '../../../core/services/user-sync.service';

export type MediaNoteFeature = 'video' | 'short';

export interface MediaNote {
  id: string;
  feature: MediaNoteFeature;
  targetId: string;
  text: string;
  contextText?: string | null;
  updatedAt: string;
}

const KEY_GUEST_MEDIA_NOTES = 'ct_web_guest_media_notes_v1';

@Injectable({ providedIn: 'root' })
export class VideoNotesService {
  private readonly auth = inject(AuthService);
  private readonly itemsSync = inject(UserItemsSyncService);
  private readonly userSync = inject(UserSyncService);

  private readonly guestNotes = signal<Record<string, MediaNote>>(
    this.readGuestNotes(),
  );

  /** Map keyed by `${feature}:${targetId}` for active notes. */
  readonly notesByAnchor = computed<Record<string, MediaNote>>(() => {
    if (!this.auth.currentUser()) {
      return this.guestNotes();
    }
    const merged = new Map<string, SyncUserItem>();
    for (const item of this.itemsSync.remoteItems()) {
      if (
        item.itemType === 'note' &&
        (item.feature === 'video' || item.feature === 'short')
      ) {
        merged.set(item.id, item);
      }
    }
    for (const item of Object.values(this.itemsSync.pendingItems())) {
      if (
        item.itemType === 'note' &&
        (item.feature === 'video' || item.feature === 'short')
      ) {
        merged.set(item.id, item);
      }
    }

    const byAnchor: Record<string, MediaNote> = {};
    for (const item of merged.values()) {
      if (item.deleted || !(item.text ?? '').trim()) continue;
      const key = this.anchorKey(
        item.feature as MediaNoteFeature,
        item.targetId,
      );
      const existing = byAnchor[key];
      if (!existing || item.updatedAt >= existing.updatedAt) {
        byAnchor[key] = {
          id: item.id,
          feature: item.feature as MediaNoteFeature,
          targetId: item.targetId,
          text: item.text ?? '',
          contextText: item.contextText,
          updatedAt: item.updatedAt,
        };
      }
    }
    return byAnchor;
  });

  getNote(feature: MediaNoteFeature, targetId: string): MediaNote | null {
    return this.notesByAnchor()[this.anchorKey(feature, targetId)] ?? null;
  }

  hasNote(feature: MediaNoteFeature, targetId: string): boolean {
    return this.getNote(feature, targetId) !== null;
  }

  saveNote(
    feature: MediaNoteFeature,
    targetId: string,
    text: string,
    contextText?: string | null,
  ): void {
    const trimmed = text.trim();
    if (!trimmed) {
      this.deleteNote(feature, targetId);
      return;
    }

    const existing = this.getNote(feature, targetId);
    const id = existing?.id ?? this.generateId();
    const nowIso = new Date(this.userSync.nowServerAligned()).toISOString();

    if (!this.auth.currentUser()) {
      const next = { ...this.guestNotes() };
      next[this.anchorKey(feature, targetId)] = {
        id,
        feature,
        targetId,
        text: trimmed,
        contextText: contextText ?? null,
        updatedAt: nowIso,
      };
      this.guestNotes.set(next);
      this.writeGuestNotes(next);
      return;
    }

    this.itemsSync.enqueueItem({
      id,
      itemType: 'note',
      feature,
      targetId,
      text: trimmed,
      contextText: contextText ?? null,
      deleted: false,
      updatedAt: nowIso,
      createdAt: existing ? undefined : nowIso,
    });
  }

  deleteNote(feature: MediaNoteFeature, targetId: string): void {
    const existing = this.getNote(feature, targetId);
    if (!existing) return;

    if (!this.auth.currentUser()) {
      const next = { ...this.guestNotes() };
      delete next[this.anchorKey(feature, targetId)];
      this.guestNotes.set(next);
      this.writeGuestNotes(next);
      return;
    }

    this.itemsSync.enqueueItem({
      id: existing.id,
      itemType: 'note',
      feature,
      targetId,
      text: '',
      contextText: existing.contextText ?? null,
      deleted: true,
    });
  }

  private anchorKey(feature: MediaNoteFeature, targetId: string): string {
    return `${feature}:${targetId}`;
  }

  private generateId(): string {
    if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
      return crypto.randomUUID();
    }
    return `note_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
  }

  private readGuestNotes(): Record<string, MediaNote> {
    if (typeof localStorage === 'undefined') return {};
    try {
      const raw = localStorage.getItem(KEY_GUEST_MEDIA_NOTES);
      if (!raw) return {};
      const parsed = JSON.parse(raw);
      return parsed && typeof parsed === 'object' ? parsed : {};
    } catch {
      return {};
    }
  }

  private writeGuestNotes(notes: Record<string, MediaNote>): void {
    if (typeof localStorage === 'undefined') return;
    try {
      localStorage.setItem(KEY_GUEST_MEDIA_NOTES, JSON.stringify(notes));
    } catch {
      // Ignore quota errors
    }
  }
}
