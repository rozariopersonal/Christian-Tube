import { HttpClient } from '@angular/common/http';
import { Injectable, inject, signal } from '@angular/core';
import { firstValueFrom, timeout } from 'rxjs';
import { AppConfig } from '../config/app-config';

const KEY_RELEASE_REVISION = 'release_revision';

interface ReleaseManifest {
  revision?: string;
}

@Injectable({ providedIn: 'root' })
export class ReleaseDataService {
  private readonly http = inject(HttpClient);
  private readonly memoryCache = new Map<string, unknown>();
  private readonly loadedFonts = new Set<string>();

  readonly revision = signal<string>(this.readCachedRevision());

  constructor() {
    void this.refreshRevision();
  }

  /**
   * Resolves candidate CDN URLs matching apps/mobile/lib/core/api/release_assets.dart:
   * 1) jsDelivr edge CDN
   * 2) raw.githubusercontent.com fallback
   * Appends ?rv=<revision> unless skipRevision is true (used for manifest.json itself).
   */
  urlsFor(relativePath: string, skipRevision = false): string[] {
    const clean = relativePath.replace(/^\/+/, '');
    const rev = !skipRevision ? this.revision() : '';
    const query = rev ? `?rv=${encodeURIComponent(rev)}` : '';
    const repo = AppConfig.releasesRepo;
    return [
      `https://cdn.jsdelivr.net/gh/${repo}@main/${clean}${query}`,
      `https://raw.githubusercontent.com/${repo}/main/${clean}${query}`,
    ];
  }

  assetUrl(relativePath: string): string {
    return this.urlsFor(relativePath)[0];
  }

  async refreshRevision(): Promise<void> {
    try {
      const manifest = await this.fetchJsonFromUrls<ReleaseManifest>(
        this.urlsFor('manifest.json', true),
        4000,
      );
      if (manifest?.revision && manifest.revision !== this.revision()) {
        this.revision.set(manifest.revision);
        try {
          localStorage.setItem(KEY_RELEASE_REVISION, manifest.revision);
        } catch {
          // ignore
        }
      }
    } catch {
      // Non-fatal: keep last-known revision
    }
  }

  async getJson<T>(relativePath: string, useCache = true): Promise<T> {
    const clean = relativePath.replace(/^\/+/, '');
    if (useCache && this.memoryCache.has(clean)) {
      return this.memoryCache.get(clean) as T;
    }
    const data = await this.fetchJsonFromUrls<T>(this.urlsFor(clean), 10000);
    if (useCache) {
      this.memoryCache.set(clean, data);
    }
    return data;
  }

  async loadFont(family: string, fileName: string): Promise<void> {
    if (typeof FontFace === 'undefined' || this.loadedFonts.has(family)) return;
    for (const url of this.urlsFor(`fonts/${fileName}`)) {
      try {
        const font = new FontFace(family, `url("${url}")`);
        const loaded = await font.load();
        document.fonts.add(loaded);
        this.loadedFonts.add(family);
        return;
      } catch {
        // try next mirror
      }
    }
  }

  clearCache(): void {
    this.memoryCache.clear();
  }

  private async fetchJsonFromUrls<T>(urls: string[], timeoutMs: number): Promise<T> {
    let lastError: unknown;
    for (const url of urls) {
      try {
        return await firstValueFrom(
          this.http.get<T>(url).pipe(timeout(timeoutMs)),
        );
      } catch (err) {
        lastError = err;
      }
    }
    throw lastError ?? new Error('Failed to fetch release asset');
  }

  private readCachedRevision(): string {
    try {
      return localStorage.getItem(KEY_RELEASE_REVISION) ?? '';
    } catch {
      return '';
    }
  }
}
