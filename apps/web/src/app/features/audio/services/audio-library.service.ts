import { Injectable, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ApiService } from '../../../core/api/api.service';
import { AudioSeries } from '../models/audio.model';

@Injectable({ providedIn: 'root' })
export class AudioLibraryService {
  private readonly api = inject(ApiService);

  readonly seriesList = signal<AudioSeries[]>([]);
  readonly loading = signal<boolean>(false);
  readonly error = signal<string | null>(null);

  async loadCatalog(force = false): Promise<void> {
    if (!force && this.seriesList().length > 0) return;
    this.loading.set(true);
    this.error.set(null);
    try {
      const res = await firstValueFrom(
        this.api.get<{ data?: AudioSeries[]; series?: AudioSeries[] } | AudioSeries[]>(
          '/api/audio/catalog',
        ),
      );
      const list = Array.isArray(res)
        ? res
        : (res?.data ?? res?.series ?? []);
      this.seriesList.set(list);
    } catch (err) {
      this.error.set(
        err instanceof Error ? err.message : 'Unable to load audio library',
      );
    } finally {
      this.loading.set(false);
    }
  }

  async fetchSeries(id: string): Promise<AudioSeries | null> {
    try {
      const res = await firstValueFrom(
        this.api.get<{ data?: AudioSeries } | AudioSeries>(
          `/api/audio/series/${id}`,
        ),
      );
      return (res as { data?: AudioSeries })?.data ?? (res as AudioSeries);
    } catch {
      return this.seriesList().find((s) => s.id === id) ?? null;
    }
  }

  resolveStreamUrl(trackId: string, directUrl?: string): string {
    if (directUrl && directUrl.startsWith('http')) {
      if (
        typeof window !== 'undefined' &&
        window.location.protocol === 'https:' &&
        directUrl.startsWith('http://')
      ) {
        return `https://${directUrl.slice('http://'.length)}`;
      }
      return directUrl;
    }
    return this.api.streamUrl(`/api/audio/stream/${trackId}`);
  }
}
