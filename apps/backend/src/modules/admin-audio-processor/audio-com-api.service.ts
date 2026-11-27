import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { CacheService } from '../cache/cache.service';
import { PrismaService } from '../prisma/prisma.service';

export interface AudioComCreateResult {
  audioId: string;
  uploadUrl: string;
  successHook: string | null;
}

interface StoredAudioComTokens {
  accessToken: string;
  refreshToken?: string;
  expiresAt?: number;
}

@Injectable()
export class AudioComApiService {
  private readonly logger = new Logger(AudioComApiService.name);
  private readonly apiBase = 'https://api.audio.com/v1';
  private readonly tokenEndpoint = 'https://api.audio.com/auth/token';
  private readonly collectionCache = new Map<string, string>();

  constructor(
    private readonly configService: ConfigService,
    private readonly cache: CacheService,
    private readonly prisma: PrismaService,
  ) {}

  private tokenRedisKey(): string {
    return `${this.cache.getPrefix()}:audio_proc:audiocom_tokens`;
  }

  private authErrorRedisKey(): string {
    return `${this.cache.getPrefix()}:audio_proc:auth_error`;
  }

  private refreshLockKey(): string {
    return `${this.cache.getPrefix()}:audio_proc:audiocom_refresh_lock`;
  }

  private cleanBearer(token: string): string {
    const t = token.trim();
    return t.toLowerCase().startsWith('bearer ') ? t.slice(7).trim() : t;
  }

  /**
   * Resolves the current Audio.com access token from Redis (0 Neon queries),
   * falling back to Neon SystemSecret backup, then env AUDIO_COM_TOKEN.
   */
  async getAccessToken(): Promise<string> {
    const raw = await this.cache.getString(this.tokenRedisKey());
    if (raw) {
      try {
        const parsed = JSON.parse(raw) as StoredAudioComTokens;
        if (parsed.accessToken) {
          if (parsed.expiresAt && parsed.expiresAt - Date.now() < 5 * 60 * 1000 && parsed.refreshToken) {
            const refreshed = await this.tryRefreshToken(parsed.refreshToken);
            if (refreshed) return refreshed;
          }
          return this.cleanBearer(parsed.accessToken);
        }
      } catch {
        // Ignore malformed cache entry
      }
    }

    const envToken = this.configService.get<string>('AUDIO_COM_TOKEN') || process.env.AUDIO_COM_TOKEN || '';
    const envRefresh = this.configService.get<string>('AUDIO_COM_REFRESH_TOKEN') || process.env.AUDIO_COM_REFRESH_TOKEN || '';
    if (envToken) {
      const cleaned = this.cleanBearer(envToken);
      await this.cache.setString(
        this.tokenRedisKey(),
        JSON.stringify({ accessToken: cleaned, refreshToken: envRefresh || undefined }),
      );
      return cleaned;
    }

    throw new Error('AUDIO_COM_TOKEN is not configured on backend');
  }

  private async loadRefreshToken(): Promise<string | null> {
    const raw = await this.cache.getString(this.tokenRedisKey());
    if (raw) {
      try {
        const parsed = JSON.parse(raw) as StoredAudioComTokens;
        if (parsed.refreshToken) return parsed.refreshToken;
      } catch {
        // ignore
      }
    }
    try {
      const rows = await this.prisma.$queryRawUnsafe<Array<{ value: string }>>(
        `SELECT "value" FROM "SystemSecret" WHERE "key" = 'audiocom_tokens' LIMIT 1`,
      );
      if (rows?.[0]?.value) {
        const parsed = JSON.parse(rows[0].value) as StoredAudioComTokens;
        if (parsed.refreshToken) return parsed.refreshToken;
      }
    } catch {
      // Table may not exist yet; fall back to env
    }
    return (
      this.configService.get<string>('AUDIO_COM_REFRESH_TOKEN') ||
      process.env.AUDIO_COM_REFRESH_TOKEN ||
      null
    );
  }

  private async persistTokens(tokens: StoredAudioComTokens): Promise<void> {
    const serialized = JSON.stringify(tokens);
    await this.cache.setString(this.tokenRedisKey(), serialized);
    await this.cache.delKey(this.authErrorRedisKey());
    try {
      await this.prisma.$executeRawUnsafe(`
        CREATE TABLE IF NOT EXISTS "SystemSecret" (
          "key" TEXT PRIMARY KEY,
          "value" TEXT NOT NULL,
          "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
      `);
      await this.prisma.$executeRawUnsafe(
        `INSERT INTO "SystemSecret" ("key", "value", "updatedAt")
         VALUES ('audiocom_tokens', $1, NOW())
         ON CONFLICT ("key") DO UPDATE SET "value" = EXCLUDED."value", "updatedAt" = NOW()`,
        serialized,
      );
    } catch (err: any) {
      this.logger.warn(`Failed to back up rotated Audio.com token to Neon: ${err?.message || err}`);
    }
  }

  async tryRefreshToken(explicitRefreshToken?: string): Promise<string | null> {
    const clientId =
      this.configService.get<string>('AUDIO_COM_CLIENT_ID') ||
      process.env.AUDIO_COM_CLIENT_ID ||
      '';
    const refreshToken = explicitRefreshToken || (await this.loadRefreshToken());
    if (!clientId || !refreshToken) {
      return null;
    }

    const locked = await this.cache.setNxEx(this.refreshLockKey(), '1', 30);
    if (!locked) {
      await new Promise((r) => setTimeout(r, 1500));
      const raw = await this.cache.getString(this.tokenRedisKey());
      if (raw) {
        try {
          const parsed = JSON.parse(raw) as StoredAudioComTokens;
          if (parsed.accessToken) return this.cleanBearer(parsed.accessToken);
        } catch {
          // ignore
        }
      }
      return null;
    }

    try {
      const body = new URLSearchParams({
        grant_type: 'refresh_token',
        client_id: clientId,
        refresh_token: refreshToken,
      });
      const resp = await fetch(this.tokenEndpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString(),
      });
      if (!resp.ok) {
        const text = await resp.text().catch(() => '');
        this.logger.error(`Audio.com token refresh failed (${resp.status}): ${text.slice(0, 200)}`);
        await this.recordAuthError(`Audio.com token refresh failed (${resp.status})`);
        return null;
      }
      const data = (await resp.json()) as {
        access_token?: string;
        refresh_token?: string;
        expires_in?: number;
      };
      if (!data.access_token) {
        await this.recordAuthError('Audio.com refresh response missing access_token');
        return null;
      }
      const nextTokens: StoredAudioComTokens = {
        accessToken: this.cleanBearer(data.access_token),
        refreshToken: data.refresh_token || refreshToken,
        expiresAt: data.expires_in ? Date.now() + data.expires_in * 1000 : undefined,
      };
      await this.persistTokens(nextTokens);
      this.logger.log('Successfully refreshed and persisted Audio.com access token');
      return nextTokens.accessToken;
    } catch (err: any) {
      this.logger.error(`Audio.com token refresh error: ${err?.message || err}`);
      await this.recordAuthError(`Audio.com token refresh error: ${err?.message || err}`);
      return null;
    } finally {
      await this.cache.delKey(this.refreshLockKey());
    }
  }

  async recordAuthError(message: string): Promise<void> {
    await this.cache.setString(
      this.authErrorRedisKey(),
      JSON.stringify({
        error: message.slice(0, 300),
        source: 'backend',
        at: new Date().toISOString(),
      }),
      86400,
    );
  }

  private async authedFetch(url: string, init: RequestInit): Promise<Response> {
    let token = await this.getAccessToken();
    const buildHeaders = (t: string) => ({
      ...(init.headers as Record<string, string>),
      Authorization: `Bearer ${t}`,
      Accept: 'application/json',
    });

    let resp = await fetch(url, { ...init, headers: buildHeaders(token) });
    if (resp.status === 401) {
      const refreshed = await this.tryRefreshToken();
      if (refreshed && refreshed !== token) {
        token = refreshed;
        resp = await fetch(url, { ...init, headers: buildHeaders(token) });
      }
      if (resp.status === 401) {
        await this.recordAuthError(`Audio.com returned 401 Unauthorized on ${url}`);
      }
    }
    return resp;
  }

  cleanTags(tags: string[], limit = 5, maxLen = 40): string[] {
    const cleaned: string[] = [];
    for (const raw of tags || []) {
      let s = String(raw || '').trim();
      if (!s) continue;
      if (s.length > maxLen) s = s.slice(0, maxLen).trimEnd();
      if (s && !cleaned.includes(s)) cleaned.push(s);
      if (cleaned.length >= limit) break;
    }
    return cleaned;
  }

  async createAudio(params: {
    title: string;
    description: string;
    mime: string;
    size: number;
    tags: string[];
  }): Promise<AudioComCreateResult> {
    const resp = await this.authedFetch(`${this.apiBase}/audio/create`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        title: (params.title || 'Untitled Sermon').slice(0, 100),
        category: 'podcast',
        mime: params.mime,
        size: params.size,
        description: (params.description || '').slice(0, 500),
        tags: this.cleanTags(params.tags),
        is_listed: true,
      }),
    });

    if (!resp.ok) {
      const text = await resp.text().catch(() => '');
      throw new Error(`Audio.com create failed (${resp.status}): ${text.slice(0, 300)}`);
    }

    const data = (await resp.json()) as {
      url?: string;
      success?: string;
      audio?: { id?: string | number };
    };
    const audioId = data?.audio?.id ? String(data.audio.id) : '';
    const uploadUrl = data?.url || '';
    if (!audioId || !uploadUrl) {
      throw new Error('Audio.com create response missing audio id or upload URL');
    }

    return {
      audioId,
      uploadUrl,
      successHook: data.success || null,
    };
  }

  async triggerSuccessHook(successHook: string | null): Promise<void> {
    if (!successHook) return;
    try {
      await fetch(successHook, { method: 'POST' });
    } catch (err: any) {
      this.logger.warn(`Audio.com successHook warning: ${err?.message || err}`);
    }
  }

  async getOrCreateCollection(title: string): Promise<string | null> {
    const cleanTitle = (title || '').trim().slice(0, 100);
    if (!cleanTitle) return null;
    const key = cleanTitle.toLowerCase();
    if (this.collectionCache.has(key)) return this.collectionCache.get(key)!;

    const redisKey = `${this.cache.getPrefix()}:audio_proc:col:${key}`;
    const cached = await this.cache.getString(redisKey);
    if (cached) {
      this.collectionCache.set(key, cached);
      return cached;
    }

    try {
      const listResp = await this.authedFetch(`${this.apiBase}/collection/list`, { method: 'GET' });
      if (listResp.ok) {
        const cols = (await listResp.json()) as Array<{ id?: string | number; title?: string }>;
        for (const col of cols || []) {
          const cTitle = (col.title || '').trim().toLowerCase();
          const cId = col.id ? String(col.id) : '';
          if (cTitle && cId) {
            this.collectionCache.set(cTitle, cId);
            if (cTitle === key) {
              await this.cache.setString(redisKey, cId, 86400);
              return cId;
            }
          }
        }
      }

      const createResp = await this.authedFetch(`${this.apiBase}/collection/create`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title: cleanTitle }),
      });
      if (createResp.ok) {
        const created = (await createResp.json()) as { id?: string | number };
        const cId = created?.id ? String(created.id) : '';
        if (cId) {
          this.collectionCache.set(key, cId);
          await this.cache.setString(redisKey, cId, 86400);
          return cId;
        }
      }
    } catch (err: any) {
      this.logger.warn(`getOrCreateCollection(${cleanTitle}) warning: ${err?.message || err}`);
    }
    return null;
  }

  async addToCollection(collectionId: string, audioId: string): Promise<void> {
    try {
      await this.authedFetch(`${this.apiBase}/collection/item/add?id=${collectionId}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ audio: String(audioId) }),
      });
    } catch (err: any) {
      this.logger.warn(`addToCollection warning: ${err?.message || err}`);
    }
  }

  async resolveStreamUrl(audioId: string, maxAttempts = 2, delayMs = 2000): Promise<string | null> {
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        const resp = await this.authedFetch(`${this.apiBase}/audio/view?id=${audioId}`, {
          method: 'GET',
        });
        if (resp.ok) {
          const data = (await resp.json()) as {
            transcodings?: Array<{ format?: string; url?: string }>;
            sources?: Array<{ format?: string; url?: string }>;
            play?: { url?: string; stream_url?: string; streamUrl?: string };
          };
          const transcodings = data.transcodings || data.sources || [];
          const mp3 = transcodings.find((t) => (t.format || '').toLowerCase() === 'mp3' && t.url);
          if (mp3?.url) return mp3.url;
          const playUrl = data.play?.url || data.play?.stream_url || data.play?.streamUrl;
          if (playUrl) return playUrl;
        }
      } catch (err: any) {
        this.logger.warn(`resolveStreamUrl(${audioId}) attempt ${attempt} failed: ${err?.message || err}`);
      }
      if (attempt < maxAttempts) {
        await new Promise((r) => setTimeout(r, delayMs));
      }
    }
    return null;
  }
}
