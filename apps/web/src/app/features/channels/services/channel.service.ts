import { Injectable, computed, effect, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ApiService } from '../../../core/api/api.service';
import { AuthService } from '../../../core/auth/auth.service';
import { UserSyncService } from '../../../core/services/user-sync.service';
import {
  Channel,
  ChannelRequest,
  normalizeChannel,
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

  private syncedUserId: string | null = null;
  private inFlightSubscriptionsSync: Promise<void> | null = null;
  private subscriptionMutationVersion = 0;

  readonly subscribedChannels = computed(() => {
    const ids = new Set(this.subscribedIds());
    return this.channels().filter((c) => ids.has(c.id));
  });

  constructor() {
    effect(() => {
      const user = this.auth.currentUser();
      if (user && user.id !== this.syncedUserId) {
        this.syncedUserId = user.id;
        this.setLocalSubscriptions(this.readLocalSubscriptions());
        void this.loadSubscriptions();
      } else if (!user) {
        this.syncedUserId = null;
        this.setLocalSubscriptions(this.readLocalSubscriptions());
      }
    });

    effect(() => {
      const remote = this.userSync.remoteState();
      if (!remote?.subscriptions) return;
      const projected = this.projectSubscriptions(remote.subscriptions);
      if (!this.areSameIdSets(projected, this.subscribedIds())) {
        this.setLocalSubscriptions(projected);
      }
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
    if (!this.auth.isAuthenticated()) {
      return;
    }
    if (this.inFlightSubscriptionsSync) {
      return this.inFlightSubscriptionsSync;
    }

    const versionBefore = this.subscriptionMutationVersion;
    this.inFlightSubscriptionsSync = (async () => {
      try {
        const res = await firstValueFrom(
          this.api.get<unknown>('/api/channels/subscriptions'),
        );
        if (versionBefore !== this.subscriptionMutationVersion) {
          return;
        }
        const ids = this.extractSubscriptionIds(res);
        if (ids !== null) {
          const projected = this.projectSubscriptions(ids);
          if (!this.areSameIdSets(projected, this.subscribedIds())) {
            this.setLocalSubscriptions(projected);
          }
        }
      } catch {
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

  async fetchRequests(): Promise<void> {
    try {
      const res = await firstValueFrom(
        this.api.get<ChannelRequest[]>('/api/channels/requests'),
      );
      if (Array.isArray(res)) {
        this.channelRequests.set(res);
      }
    } catch {
      // ignore
    }
  }

  async submitRequest(
    channelName: string,
    channelUrl: string,
    reason?: string,
  ): Promise<boolean> {
    try {
      await firstValueFrom(
        this.api.post('/api/channels/request', {
          channelUrl,
          notes: reason ? `${channelName} — ${reason}` : channelName,
        }),
      );
      await this.fetchRequests();
      return true;
    } catch {
      return false;
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

  async approveRequest(requestId: string): Promise<boolean> {
    try {
      await firstValueFrom(
        this.api.post(`/api/channels/requests/${requestId}/approve`, {}),
      );
      await Promise.all([this.fetchRequests(), this.fetchAdminChannels()]);
      return true;
    } catch {
      return false;
    }
  }

  async rejectRequest(requestId: string): Promise<boolean> {
    try {
      await firstValueFrom(
        this.api.post(`/api/channels/requests/${requestId}/reject`, {}),
      );
      await this.fetchRequests();
      return true;
    } catch {
      return false;
    }
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
