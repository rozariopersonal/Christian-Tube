import { HttpErrorResponse } from '@angular/common/http';
import { Injectable, computed, effect, inject, signal, untracked } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ApiService } from '../../../core/api/api.service';
import { AuthService } from '../../../core/auth/auth.service';
import { UserSyncService } from '../../../core/services/user-sync.service';
import {
  Channel,
  ChannelActionResult,
  ChannelRequest,
  YouTubeChannelResult,
  normalizeChannel,
  normalizeChannelRequest,
  normalizeYouTubeChannelResult,
} from '../models/channel.model';

const KEY_SUBSCRIPTIONS = 'subscribed_channel_ids';

@Injectable({ providedIn: 'root' })
export class ChannelService {
  private readonly api = inject(ApiService);
  private readonly auth = inject(AuthService);
  private readonly userSync = inject(UserSyncService);

  readonly channels = signal<Channel[]>([]);
  readonly subscribedIds = signal<string[]>(this.readLocalSubscriptions());
  readonly channelRequests = signal<ChannelRequest[]>([]);
  readonly isLoading = signal<boolean>(false);
  readonly isLoadingRequests = signal<boolean>(false);

  private syncedUserId: string | null | undefined = undefined;
  private inFlightSubscriptionsSync: Promise<void> | null = null;
  private subscriptionMutationVersion = 0;

  readonly subscribedChannels = computed(() => {
    const ids = new Set(this.subscribedIds());
    return this.channels().filter((c) => ids.has(c.id));
  });

  constructor() {
    effect(() => {
      const user = this.auth.currentUser();
      const needsSignIn = this.auth.sessionNeedsSignIn();
      const nextUid = user?.id ?? null;
      if (nextUid !== this.syncedUserId) {
        this.syncedUserId = nextUid;
        untracked(() => {
          if (user) {
            const localIds = this.readLocalSubscriptions();
            if (!this.areSameIdSets(localIds, this.subscribedIds())) {
              this.setLocalSubscriptions(localIds);
            }
            if (!needsSignIn) void this.loadSubscriptions();
          } else {
            this.channelRequests.set([]);
            const ids = this.readLocalSubscriptions();
            const followed = new Set(ids);
            this.subscribedIds.set(ids);
            this.channels.update((list) =>
              list.map((channel) => ({ ...channel, isSubscribed: followed.has(channel.id) })),
            );
          }
        });
      }
    });

    effect(() => {
      const remote = this.userSync.remoteState();
      if (!remote?.subscriptions) return;
      untracked(() => {
        const projected = this.projectSubscriptions(remote.subscriptions!);
        if (!this.areSameIdSets(projected, this.subscribedIds())) {
          this.setLocalSubscriptions(projected);
        }
      });
    });
  }

  async fetchChannels(): Promise<void> {
    this.isLoading.set(true);
    try {
      const res = await firstValueFrom(
        this.api.get<unknown>('/api/channels'),
      );
      const rawList = Array.isArray(res)
        ? (res as Record<string, unknown>[])
        : ((res as Record<string, unknown>)?.['channels'] as Record<
            string,
            unknown
          >[]) ?? [];
      const subSet = new Set(this.subscribedIds());
      this.channels.set(
        rawList.map((c) => {
          const ch = normalizeChannel(c);
          return { ...ch, isSubscribed: subSet.has(ch.id) || ch.isSubscribed };
        }),
      );
    } catch {
      // keep existing channels if request fails
    } finally {
      this.isLoading.set(false);
    }
  }

  async fetchAdminChannels(): Promise<void> {
    this.isLoading.set(true);
    try {
      const res = await firstValueFrom(
        this.api.get<unknown>('/api/channels/admin/all'),
      );
      const rawList = Array.isArray(res) ? (res as Record<string, unknown>[]) : [];
      const subSet = new Set(this.subscribedIds());
      this.channels.set(
        rawList.map((c) => {
          const ch = normalizeChannel(c);
          return { ...ch, isSubscribed: subSet.has(ch.id) || ch.isSubscribed };
        }),
      );
    } catch {
      await this.fetchChannels();
    } finally {
      this.isLoading.set(false);
    }
  }

  async loadSubscriptions(): Promise<void> {
    if (!this.auth.isAuthenticated() || !this.auth.canSync()) {
      return;
    }
    if (this.inFlightSubscriptionsSync) {
      return this.inFlightSubscriptionsSync;
    }

    const versionBefore = this.subscriptionMutationVersion;
    const acknowledgementVersion = this.userSync.acknowledgementVersion;
    const userId = this.auth.currentUser()?.id;
    this.inFlightSubscriptionsSync = (async () => {
      try {
        const res = await firstValueFrom(
          this.api.get<unknown>('/api/channels/subscriptions'),
        );
        if (versionBefore !== this.subscriptionMutationVersion ||
            acknowledgementVersion !== this.userSync.acknowledgementVersion ||
            userId !== this.auth.currentUser()?.id) {
          return;
        }
        const ids = this.extractSubscriptionIds(res);
        if (ids !== null) {
          const projected = this.projectSubscriptions(ids);
          if (!this.areSameIdSets(projected, this.subscribedIds())) {
            this.setLocalSubscriptions(projected);
          }
        }
      } catch (error) {
        if (error instanceof HttpErrorResponse && error.status === 401) this.auth.markSessionRejected();
        // fallback to local storage
      } finally {
        this.inFlightSubscriptionsSync = null;
      }
    })();

    return this.inFlightSubscriptionsSync;
  }

  async toggleSubscribe(channelId: string): Promise<void> {
    this.subscriptionMutationVersion++;
    const current = new Set(this.subscribedIds());
    const wasSubscribed = current.has(channelId);
    const willSubscribe = !wasSubscribed;
    if (wasSubscribed) {
      current.delete(channelId);
    } else {
      current.add(channelId);
    }
    this.setLocalSubscriptions([...current]);

    if (!this.auth.isAuthenticated()) {
      return;
    }

    this.userSync.enqueueSubscription(channelId, willSubscribe);
  }

  saveChannelSelections(selected: ReadonlySet<string>): void {
    this.subscriptionMutationVersion++;
    const previous = new Set(this.subscribedIds());
    this.setLocalSubscriptions([...selected]);
    if (!this.auth.isAuthenticated()) return;
    for (const id of previous) {
      if (!selected.has(id)) this.userSync.enqueueSubscription(id, false);
    }
    for (const id of selected) {
      if (!previous.has(id)) this.userSync.enqueueSubscription(id, true);
    }
  }

  async subscribeMany(channelIds: string[]): Promise<void> {
    this.subscriptionMutationVersion++;
    const merged = Array.from(
      new Set([...this.subscribedIds(), ...channelIds]),
    );
    this.setLocalSubscriptions(merged);
    if (!this.auth.isAuthenticated()) {
      return;
    }
    for (const id of channelIds) {
      this.userSync.enqueueSubscription(id, true);
    }
  }

  async fetchChannelDetails(channelId: string): Promise<Channel | null> {
    const existing = this.channels().find((c) => c.id === channelId);
    try {
      const res = await firstValueFrom(
        this.api.get<Record<string, unknown>>(`/api/channels/${channelId}`),
      );
      const ch = normalizeChannel(res);
      return {
        ...ch,
        isSubscribed:
          this.subscribedIds().includes(ch.id) || ch.isSubscribed,
      };
    } catch {
      return existing ?? null;
    }
  }

  async searchYouTubeChannels(query: string): Promise<YouTubeChannelResult[]> {
    const q = query.trim();
    if (q.length < 2) return [];
    const res = await firstValueFrom(
      this.api.get<unknown>('/api/channels/search-youtube', { q }),
    );
    if (!Array.isArray(res)) return [];
    return res
      .filter((item): item is Record<string, unknown> => !!item && typeof item === 'object')
      .map((item) => normalizeYouTubeChannelResult(item));
  }

  async addChannel(payload: {
    channelUrl: string;
    name?: string;
    category?: string;
    language?: string;
  }): Promise<ChannelActionResult> {
    try {
      await firstValueFrom(this.api.post('/api/channels', payload));
      await this.fetchAdminChannels();
      return { ok: true };
    } catch (error) {
      return { ok: false, error: this.extractErrorMessage(error, 'Failed to add channel') };
    }
  }

  async fetchRequests(): Promise<void> {
    if (!this.auth.isAdmin()) {
      this.channelRequests.set([]);
      return;
    }
    this.isLoadingRequests.set(true);
    try {
      const res = await firstValueFrom(
        this.api.get<unknown>('/api/channels/requests'),
      );
      if (Array.isArray(res)) {
        this.channelRequests.set(
          res
            .filter((item): item is Record<string, unknown> => !!item && typeof item === 'object')
            .map((item) => normalizeChannelRequest(item)),
        );
      }
    } catch {
      // keep existing requests on transient failure
    } finally {
      this.isLoadingRequests.set(false);
    }
  }

  async submitRequest(
    channelName: string,
    channelUrl: string,
    notes?: string,
  ): Promise<ChannelActionResult> {
    try {
      await firstValueFrom(
        this.api.post('/api/channels/request', {
          channelUrl: channelUrl.trim(),
          channelName: channelName.trim() || undefined,
          notes: notes?.trim() || undefined,
        }),
      );
      if (this.auth.isAdmin()) {
        await this.fetchRequests();
      }
      return { ok: true };
    } catch (error) {
      return {
        ok: false,
        error: this.extractErrorMessage(error, 'Failed to submit channel request'),
      };
    }
  }

  async toggleChannelActive(channel: Channel): Promise<boolean> {
    const endpoint = channel.isActive
      ? `/api/channels/${channel.id}/suspend`
      : `/api/channels/${channel.id}/activate`;
    try {
      await firstValueFrom(this.api.post(endpoint, {}));
      this.channels.update((list) =>
        list.map((c) =>
          c.id === channel.id ? { ...c, isActive: !channel.isActive } : c,
        ),
      );
      return true;
    } catch {
      return false;
    }
  }

  async removeChannel(channelId: string): Promise<boolean> {
    try {
      await firstValueFrom(this.api.delete(`/api/channels/${channelId}`));
      this.channels.update((list) => list.filter((c) => c.id !== channelId));
      return true;
    } catch {
      return false;
    }
  }

  async approveRequest(requestId: string): Promise<ChannelActionResult> {
    try {
      await firstValueFrom(
        this.api.post(`/api/channels/requests/${requestId}/approve`, {}),
      );
      await Promise.all([this.fetchRequests(), this.fetchAdminChannels()]);
      return { ok: true };
    } catch (error) {
      return {
        ok: false,
        error: this.extractErrorMessage(error, 'Failed to approve request'),
      };
    }
  }

  async rejectRequest(
    requestId: string,
    reason?: string,
  ): Promise<ChannelActionResult> {
    try {
      await firstValueFrom(
        this.api.post(`/api/channels/requests/${requestId}/reject`, {
          reason: reason?.trim() || undefined,
        }),
      );
      await this.fetchRequests();
      return { ok: true };
    } catch (error) {
      return {
        ok: false,
        error: this.extractErrorMessage(error, 'Failed to reject request'),
      };
    }
  }

  private extractErrorMessage(error: unknown, fallback: string): string {
    if (error instanceof HttpErrorResponse) {
      const body = error.error;
      if (typeof body === 'string' && body.trim()) return body.trim();
      if (body && typeof body === 'object') {
        const msg = (body as Record<string, unknown>)['message'];
        if (typeof msg === 'string' && msg.trim()) return msg.trim();
        if (Array.isArray(msg) && msg.length > 0) return String(msg[0]);
      }
    }
    return fallback;
  }

  private extractSubscriptionIds(res: unknown): string[] | null {
    if (Array.isArray(res)) {
      return res
        .map((c) =>
          typeof c === 'string'
            ? c
            : String(
                (c as Record<string, unknown>)?.['id'] ??
                  (c as Record<string, unknown>)?.['channelId'] ??
                  '',
              ),
        )
        .filter(Boolean);
    }
    if (res && typeof res === 'object') {
      const obj = res as Record<string, unknown>;
      if (Array.isArray(obj['channelIds'])) {
        return obj['channelIds'].map(String).filter(Boolean);
      }
      const list = Array.isArray(obj['channels'])
        ? (obj['channels'] as Record<string, unknown>[])
        : Array.isArray(obj['subscriptions'])
          ? (obj['subscriptions'] as Record<string, unknown>[])
          : null;
      if (list) {
        return list
          .map((c) => String(c['id'] ?? c['channelId'] ?? ''))
          .filter(Boolean);
      }
    }
    return null;
  }

  private areSameIdSets(a: string[], b: string[]): boolean {
    if (a.length !== b.length) return false;
    const setB = new Set(b);
    return a.every((id) => setB.has(id));
  }

  private projectSubscriptions(serverIds: string[]): string[] {
    const result = new Set(serverIds);
    const pending = this.userSync.pendingOps();
    for (const op of Object.values(pending)) {
      if (op.kind !== 'subscription') continue;
      if (op.isActive) {
        result.add(op.itemId);
      } else {
        result.delete(op.itemId);
      }
    }
    return [...result];
  }

  private setLocalSubscriptions(ids: string[]): void {
    this.subscribedIds.set(ids);
    const idSet = new Set(ids);
    this.channels.update((list) =>
      list.map((c) => ({ ...c, isSubscribed: idSet.has(c.id) })),
    );
    try {
      const storageKey = this.auth.isAuthenticated()
        ? this.userSync.userCacheKey(KEY_SUBSCRIPTIONS)
        : KEY_SUBSCRIPTIONS;
      localStorage.setItem(storageKey, JSON.stringify(ids));
    } catch {
      // ignore
    }
  }

  private readLocalSubscriptions(): string[] {
    try {
      const storageKey = this.auth.isAuthenticated()
        ? this.userSync.userCacheKey(KEY_SUBSCRIPTIONS)
        : KEY_SUBSCRIPTIONS;
      const raw =
        localStorage.getItem(storageKey) ??
        localStorage.getItem(KEY_SUBSCRIPTIONS);
      const parsed = raw ? (JSON.parse(raw) as unknown) : [];
      return Array.isArray(parsed) ? parsed.map(String) : [];
    } catch {
      return [];
    }
  }
}
