import { HttpClient } from '@angular/common/http';
import { Injectable, inject, signal } from '@angular/core';
import { firstValueFrom, timeout } from 'rxjs';
import { AppConfig } from '../config/app-config';
import { IndexedDbCacheService } from '../storage/indexed-db-cache.service';

const KEY_RELEASE_REVISION = 'release_revision';

interface ReleaseManifest {
  revision?: string;
}

@Injectable({ providedIn: 'root' })
export class ReleaseDataService {
  private readonly http = inject(HttpClient);
  private readonly idb = inject(IndexedDbCacheService);
  private readonly memoryCache = new Map<string, unknown>();
  private readonly inFlight = new Map<string, Promise<unknown>>();
  private readonly inFlightFonts = new Map<string, Promise<boolean>>();
  private readonly loadedFonts = new Set<string>();
  private readonly loadingFonts = new Set<string>();

  readonly loadedFontFamilies = signal<ReadonlySet<string>>(new Set());
  readonly loadingFontFamilies = signal<ReadonlySet<string>>(new Set());
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
        this.memoryCache.clear();
        void this.idb.clear();
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
    if (useCache && this.inFlight.has(clean)) {
      return this.inFlight.get(clean) as Promise<T>;
    }

    const load = async (): Promise<T> => {
      if (useCache) {
        const cached = await this.idb.get<T>(clean, this.revision());
        if (cached !== null) {
          this.memoryCache.set(clean, cached);
          return cached;
        }
      }
      const data = await this.fetchJsonFromUrls<T>(this.urlsFor(clean), 10000);
      if (useCache) {
        this.memoryCache.set(clean, data);
        void this.idb.set(clean, data, this.revision());
      }
      return data;
    };

    const req = load().finally(() => {
      this.inFlight.delete(clean);
    });
    if (useCache) {
      this.inFlight.set(clean, req);
    }
    return req;
  }

  prefetchJson(relativePath: string): void {
    const clean = relativePath.replace(/^\/+/, '');
    if (this.memoryCache.has(clean) || this.inFlight.has(clean)) return;
    void this.getJson(clean, true).catch(() => null);
  }

  /**
   * Background-prefetches a list of release JSON paths in small batches,
   * optionally stopping once estimated cached bytes exceed [maxTotalBytes]
   * or when [shouldContinue] returns false.
   */
  async prefetchBatch(
    paths: string[],
    options?: {
      concurrency?: number;
      maxTotalBytes?: number;
      initialBytes?: number;
      shouldContinue?: () => boolean;
    },
  ): Promise<void> {
    const concurrency = options?.concurrency ?? 3;
    const maxBytes = options?.maxTotalBytes;
    const shouldContinue = options?.shouldContinue ?? (() => true);
    let totalBytes = options?.initialBytes ?? 0;

    for (let i = 0; i < paths.length; i += concurrency) {
      if (!shouldContinue()) return;
      if (maxBytes !== undefined && totalBytes >= maxBytes) return;

      const slice = paths.slice(i, i + concurrency);
      const results = await Promise.all(
        slice.map(async (p) => {
          if (!shouldContinue()) return 0;
          try {
            const data = await this.getJson<unknown>(p, true);
            return maxBytes !== undefined ? JSON.stringify(data).length : 0;
          } catch {
            return 0;
          }
        }),
      );
      for (const bytes of results) {
        totalBytes += bytes;
      }
    }
  }

  getFontCatalog<T>(): Promise<T> {
    return this.getJson<T>('fonts/catalog.json', true);
  }

  isFontLoaded(family: string): boolean {
    return this.loadedFontFamilies().has(family);
  }

  isFontLoading(family: string): boolean {
    return this.loadingFontFamilies().has(family);
  }

  async loadFont(
    family: string,
    fileNameOrFiles: string | Readonly<Record<string, string>>,
  ): Promise<boolean> {
    if (this.loadedFonts.has(family)) return true;
    if (typeof FontFace === 'undefined' || typeof document === 'undefined' || !document.fonts) {
      return false;
    }
    const existing = this.inFlightFonts.get(family);
    if (existing) return existing;

    this.loadingFonts.add(family);
    this.loadingFontFamilies.set(new Set(this.loadingFonts));

    const filesMap: Readonly<Record<string, string>> =
      typeof fileNameOrFiles === 'string'
        ? { regular: fileNameOrFiles }
        : fileNameOrFiles;

    const task = (async (): Promise<boolean> => {
      let loadedAny = false;
      for (const [weightKey, fileName] of Object.entries(filesMap)) {
        const descriptors: FontFaceDescriptors = {
          weight: weightKey.toLowerCase().includes('bold') ? '700' : '400',
          style: weightKey.toLowerCase().includes('italic') ? 'italic' : 'normal',
        };
        const ok = await this.loadSingleFontFace(family, fileName, descriptors);
        if (ok) loadedAny = true;
      }
      if (loadedAny) {
        this.loadedFonts.add(family);
        this.loadedFontFamilies.set(new Set(this.loadedFonts));
      }
      return loadedAny;
    })().finally(() => {
      this.inFlightFonts.delete(family);
      this.loadingFonts.delete(family);
      this.loadingFontFamilies.set(new Set(this.loadingFonts));
    });

    this.inFlightFonts.set(family, task);
    return task;
  }

  private async loadSingleFontFace(
    family: string,
    fileName: string,
    descriptors: FontFaceDescriptors,
  ): Promise<boolean> {
    const cacheKey = `https://reader-fonts.local/${encodeURIComponent(fileName)}`;
    const cache =
      typeof caches !== 'undefined'
        ? await caches.open('reader-fonts-v1').catch(() => null)
        : null;

    if (cache) {
      try {
        const cachedResp = await cache.match(cacheKey);
        if (cachedResp) {
          const buf = await cachedResp.arrayBuffer();
          const font = new FontFace(family, buf, descriptors);
          const loaded = await font.load();
          document.fonts.add(loaded);
          return true;
        }
      } catch {
        // fall through to network
      }
    }

    for (const url of this.urlsFor(`fonts/${fileName}`)) {
      try {
        if (typeof fetch !== 'undefined') {
          const resp = await fetch(url);
          if (resp.ok) {
            const buf = await resp.arrayBuffer();
            if (cache) {
              void cache
                .put(cacheKey, new Response(buf.slice(0)))
                .catch(() => null);
            }
            const font = new FontFace(family, buf, descriptors);
            const loaded = await font.load();
            document.fonts.add(loaded);
            return true;
          }
        } else {
          const font = new FontFace(family, `url("${url}")`, descriptors);
          const loaded = await font.load();
          document.fonts.add(loaded);
          return true;
        }
      } catch {
        // try next mirror
      }
    }
    return false;
  }

  clearCache(): void {
    this.memoryCache.clear();
    void this.idb.clear();
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
