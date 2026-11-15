import { Injectable, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ApiService } from '../../../core/api/api.service';
import {
  Channel,
  ChannelRequest,
  normalizeChannel,
} from '../models/channel.model';

const KEY_SUBSCRIPTIONS = 'subscribed_channel_ids';

@Injectable({ providedIn: 'root' })
export class ChannelService {
  private readonly api = inject(ApiService);

  readonly channels = signal<Channel[]>([]);
  readonly subscribedIds = signal<string[]>(this.readLocalSubscriptions());
  readonly channelRequests = signal<ChannelRequest[]>([]);
  readonly isLoading = signal<boolean>(false);

  readonly subscribedChannels = computed(() => {
    const ids = new Set(this.subscribedIds());
    return this.channels().filter((c) => ids.has(c.id));
  });

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

  async loadSubscriptions(): Promise<void> {
    try {
      const res = await firstValueFrom(
        this.api.get<unknown>('/api/channels/subscriptions'),
      );
      const list = Array.isArray(res)
        ? (res as Record<string, unknown>[])
        : ((res as Record<string, unknown>)?.['subscriptions'] as Record<
            string,
            unknown
          >[]) ?? [];
      const ids = list
        .map((c) => String(c['id'] ?? c['channelId'] ?? ''))
        .filter(Boolean);
      if (ids.length > 0) {
        this.setLocalSubscriptions(ids);
      }
    } catch {
      // fallback to local storage
    }
  }

  async toggleSubscribe(channelId: string): Promise<void> {
    const current = new Set(this.subscribedIds());
    const wasSubscribed = current.has(channelId);
    if (wasSubscribed) {
      current.delete(channelId);
    } else {
      current.add(channelId);
    }
    this.setLocalSubscriptions([...current]);

    try {
      if (wasSubscribed) {
        await firstValueFrom(
          this.api.delete(`/api/channels/${channelId}/subscribe`),
        );
      } else {
        await firstValueFrom(
          this.api.post(`/api/channels/${channelId}/subscribe`, {}),
        );
      }
    } catch {
      // keep optimistic local state for guest/offline usage
    }
  }

  async subscribeMany(channelIds: string[]): Promise<void> {
    const merged = Array.from(
      new Set([...this.subscribedIds(), ...channelIds]),
    );
    this.setLocalSubscriptions(merged);
    await Promise.allSettled(
      channelIds.map((id) =>
        firstValueFrom(this.api.post(`/api/channels/${id}/subscribe`, {})),
      ),
    );
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
        this.api.post('/api/channels/requests', {
          channelName,
          channelUrl,
          reason,
        }),
      );
      await this.fetchRequests();
      return true;
    } catch {
      return false;
    }
  }

  private setLocalSubscriptions(ids: string[]): void {
    this.subscribedIds.set(ids);
    const idSet = new Set(ids);
    this.channels.update((list) =>
      list.map((c) => ({ ...c, isSubscribed: idSet.has(c.id) })),
    );
    try {
      localStorage.setItem(KEY_SUBSCRIPTIONS, JSON.stringify(ids));
    } catch {
      // ignore
    }
  }

  private readLocalSubscriptions(): string[] {
    try {
      const raw = localStorage.getItem(KEY_SUBSCRIPTIONS);
      const parsed = raw ? (JSON.parse(raw) as unknown) : [];
      return Array.isArray(parsed) ? parsed.map(String) : [];
    } catch {
      return [];
    }
  }
}
