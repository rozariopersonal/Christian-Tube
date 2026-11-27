import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

export type CacheProvider = 'upstash-rest' | 'ioredis' | 'none';

export interface CacheGetOrSetOptions<T> {
  shouldCache?: (value: T) => boolean;
}

@Injectable()
export class CacheService implements OnModuleDestroy {
  private readonly logger = new Logger(CacheService.name);
  private readonly provider: CacheProvider;
  private readonly prefix: string;
  private readonly timeoutMs: number;
  private readonly defaultTtlSec: number;
  private readonly upstashRestUrl?: string;
  private readonly upstashRestToken?: string;
  private readonly redisClient?: Redis;

  private readonly versionCache = new Map<string, { value: string; expiresAt: number }>();
  private readonly versionCacheTtlMs = 10_000;
  private readonly inflight = new Map<string, Promise<unknown>>();
  private circuitOpenUntil = 0;
  private readonly circuitCooldownMs = 30_000;

  constructor(private readonly configService: ConfigService) {
    const instanceId = this.configService.get<string>('instanceId') || 'christian_tube';
    this.prefix = `ct:${instanceId}`;

    const upstashRestUrl = (
      this.configService.get<string>('redis.upstashRestUrl') ||
      process.env.UPSTASH_REDIS_REST_URL ||
      ''
    )
      .trim()
      .replace(/\/+$/, '');
    const upstashRestToken = (
      this.configService.get<string>('redis.upstashRestToken') ||
      process.env.UPSTASH_REDIS_REST_TOKEN ||
      ''
    ).trim();
    const redisUrl = (
      this.configService.get<string>('redis.url') ||
      process.env.REDIS_URL ||
      process.env.UPSTASH_REDIS_URL ||
      ''
    ).trim();

    this.timeoutMs =
      this.configService.get<number>('redis.timeoutMs') || 1500;
    this.defaultTtlSec =
      this.configService.get<number>('redis.defaultTtlSec') || 300;

    if (upstashRestUrl && upstashRestToken) {
      this.provider = 'upstash-rest';
      this.upstashRestUrl = upstashRestUrl;
      this.upstashRestToken = upstashRestToken;
      this.logger.log(`Upstash Redis REST cache enabled (prefix=${this.prefix})`);
    } else if (redisUrl) {
      this.provider = 'ioredis';
      this.redisClient = new Redis(redisUrl, {
        lazyConnect: true,
        connectTimeout: 2000,
        commandTimeout: this.timeoutMs,
        maxRetriesPerRequest: 1,
        enableOfflineQueue: false,
        ...(redisUrl.startsWith('rediss://') ? { tls: {} } : {}),
      });
      this.redisClient.on('error', (err) => {
        this.logger.warn(`Redis client error: ${err.message}`);
      });
      this.logger.log(`Redis TCP/TLS cache enabled via ioredis (prefix=${this.prefix})`);
    } else {
      this.provider = 'none';
      this.logger.log('Upstash/Redis not configured; running without distributed cache.');
    }
  }

  async onModuleDestroy() {
    if (this.redisClient) {
      try {
        await this.redisClient.quit();
      } catch {
        this.redisClient.disconnect();
      }
    }
  }

  isEnabled(): boolean {
    return this.provider !== 'none';
  }

  getStatus(): { enabled: boolean; provider: CacheProvider; prefix: string } {
    return {
      enabled: this.isEnabled(),
      provider: this.provider,
      prefix: this.prefix,
    };
  }

  /**
   * Reads from Upstash/Redis by versioned namespace key; on miss (or Redis
   * error), invokes loader() with single-flight dedup and populates the cache
   * with ttlSec unless options.shouldCache returns false.
   */
  async getOrSet<T>(
    namespace: string,
    key: string,
    ttlSec: number | undefined,
    loader: () => Promise<T>,
    options?: CacheGetOrSetOptions<T>,
  ): Promise<T> {
    if (!this.isEnabled()) {
      return loader();
    }

    const effectiveTtl = ttlSec && ttlSec > 0 ? ttlSec : this.defaultTtlSec;
    const version = await this.getNamespaceVersion(namespace);
    const fullKey = `${this.prefix}:${namespace}:v${version}:${key}`;

    if (!this.isCircuitOpen()) {
      let raw: string | null = null;
      try {
        raw = await this.getRaw(fullKey);
      } catch (err: any) {
        this.tripCircuit(`Cache read error (${fullKey}): ${err?.message || err}`);
      }
      if (raw !== null) {
        try {
          return JSON.parse(raw) as T;
        } catch (parseErr: any) {
          this.logger.warn(`Corrupted cache entry (${fullKey}), bypassing: ${parseErr?.message || parseErr}`);
        }
      }
    }

    const existing = this.inflight.get(fullKey) as Promise<T> | undefined;
    if (existing) {
      return existing;
    }

    const promise = (async () => {
      const value = await loader();
      const allowCache =
        value !== undefined &&
        value !== null &&
        (!options?.shouldCache || options.shouldCache(value));

      if (allowCache && !this.isCircuitOpen()) {
        try {
          await this.setRaw(fullKey, JSON.stringify(value), effectiveTtl);
        } catch (err: any) {
          this.tripCircuit(`Cache write error (${fullKey}): ${err?.message || err}`);
        }
      }

      return value;
    })();

    this.inflight.set(fullKey, promise);
    try {
      return await promise;
    } finally {
      this.inflight.delete(fullKey);
    }
  }

  /**
   * Bumps the version counter for one or more namespaces so subsequent reads
   * bypass stale cached entries without needing expensive SCAN/KEYS calls.
   */
  async invalidate(...namespaces: string[]): Promise<void> {
    if (!this.isEnabled() || namespaces.length === 0) return;

    await Promise.all(
      namespaces.map(async (ns) => {
        this.versionCache.delete(ns);
        const verKey = `${this.prefix}:ver:${ns}`;
        try {
          const next = await this.incrRaw(verKey);
          this.versionCache.set(ns, {
            value: String(next),
            expiresAt: Date.now() + this.versionCacheTtlMs,
          });
        } catch (err: any) {
          this.logger.warn(`Cache invalidation error (${verKey}): ${err?.message || err}`);
        }
      }),
    );
  }

  private isCircuitOpen(): boolean {
    return Date.now() < this.circuitOpenUntil;
  }

  private tripCircuit(reason: string): void {
    this.circuitOpenUntil = Date.now() + this.circuitCooldownMs;
    this.logger.warn(`${reason} — opening Redis circuit for ${this.circuitCooldownMs / 1000}s`);
  }

  getPrefix(): string {
    return this.prefix;
  }

  async getString(key: string): Promise<string | null> {
    if (!this.isEnabled()) return null;
    try {
      return await this.getRaw(key);
    } catch (err: any) {
      this.logger.warn(`Redis GET error (${key}): ${err?.message || err}`);
      return null;
    }
  }

  async mgetStrings(keys: string[]): Promise<(string | null)[]> {
    if (!this.isEnabled() || keys.length === 0) return keys.map(() => null);
    try {
      if (this.provider === 'upstash-rest') {
        const res = await this.upstashCommand<(string | null)[]>(['MGET', ...keys]);
        return Array.isArray(res) ? res : keys.map(() => null);
      }
      if (this.provider === 'ioredis' && this.redisClient) {
        if (this.redisClient.status === 'wait') await this.redisClient.connect();
        return await this.redisClient.mget(...keys);
      }
    } catch (err: any) {
      this.logger.warn(`Redis MGET error: ${err?.message || err}`);
    }
    return keys.map(() => null);
  }

  async setString(key: string, value: string, ttlSec?: number): Promise<void> {
    if (!this.isEnabled()) return;
    try {
      if (ttlSec && ttlSec > 0) {
        await this.setRaw(key, value, ttlSec);
        return;
      }
      if (this.provider === 'upstash-rest') {
        await this.upstashCommand(['SET', key, value]);
      } else if (this.provider === 'ioredis' && this.redisClient) {
        if (this.redisClient.status === 'wait') await this.redisClient.connect();
        await this.redisClient.set(key, value);
      }
    } catch (err: any) {
      this.logger.warn(`Redis SET error (${key}): ${err?.message || err}`);
    }
  }

  async setNxEx(key: string, value: string, ttlSec: number): Promise<boolean> {
    if (!this.isEnabled()) return true;
    const ttl = Math.max(1, Math.floor(ttlSec));
    try {
      if (this.provider === 'upstash-rest') {
        const res = await this.upstashCommand<string | null>(['SET', key, value, 'EX', ttl, 'NX']);
        return res === 'OK';
      }
      if (this.provider === 'ioredis' && this.redisClient) {
        if (this.redisClient.status === 'wait') await this.redisClient.connect();
        const res = await this.redisClient.set(key, value, 'EX', ttl, 'NX');
        return res === 'OK';
      }
    } catch (err: any) {
      this.logger.warn(`Redis SET NX error (${key}): ${err?.message || err}`);
    }
    return false;
  }

  async delKey(...keys: string[]): Promise<void> {
    if (!this.isEnabled() || keys.length === 0) return;
    try {
      if (this.provider === 'upstash-rest') {
        await this.upstashCommand(['DEL', ...keys]);
      } else if (this.provider === 'ioredis' && this.redisClient) {
        if (this.redisClient.status === 'wait') await this.redisClient.connect();
        await this.redisClient.del(...keys);
      }
    } catch (err: any) {
      this.logger.warn(`Redis DEL error: ${err?.message || err}`);
    }
  }

  async zadd(key: string, score: number, member: string): Promise<void> {
    if (!this.isEnabled()) return;
    try {
      if (this.provider === 'upstash-rest') {
        await this.upstashCommand(['ZADD', key, score, member]);
      } else if (this.provider === 'ioredis' && this.redisClient) {
        if (this.redisClient.status === 'wait') await this.redisClient.connect();
        await this.redisClient.zadd(key, score, member);
      }
    } catch (err: any) {
      this.logger.warn(`Redis ZADD error (${key}): ${err?.message || err}`);
    }
  }

  async zrange(key: string, start: number, stop: number): Promise<string[]> {
    if (!this.isEnabled()) return [];
    try {
      if (this.provider === 'upstash-rest') {
        const res = await this.upstashCommand<string[]>(['ZRANGE', key, start, stop]);
        return Array.isArray(res) ? res : [];
      }
      if (this.provider === 'ioredis' && this.redisClient) {
        if (this.redisClient.status === 'wait') await this.redisClient.connect();
        return await this.redisClient.zrange(key, start, stop);
      }
    } catch (err: any) {
      this.logger.warn(`Redis ZRANGE error (${key}): ${err?.message || err}`);
    }
    return [];
  }

  async zrem(key: string, ...members: string[]): Promise<void> {
    if (!this.isEnabled() || members.length === 0) return;
    try {
      if (this.provider === 'upstash-rest') {
        await this.upstashCommand(['ZREM', key, ...members]);
      } else if (this.provider === 'ioredis' && this.redisClient) {
        if (this.redisClient.status === 'wait') await this.redisClient.connect();
        await this.redisClient.zrem(key, ...members);
      }
    } catch (err: any) {
      this.logger.warn(`Redis ZREM error (${key}): ${err?.message || err}`);
    }
  }

  async zremrangebyscore(key: string, min: number | string, max: number | string): Promise<void> {
    if (!this.isEnabled()) return;
    try {
      if (this.provider === 'upstash-rest') {
        await this.upstashCommand(['ZREMRANGEBYSCORE', key, min, max]);
      } else if (this.provider === 'ioredis' && this.redisClient) {
        if (this.redisClient.status === 'wait') await this.redisClient.connect();
        await this.redisClient.zremrangebyscore(key, min, max);
      }
    } catch (err: any) {
      this.logger.warn(`Redis ZREMRANGEBYSCORE error (${key}): ${err?.message || err}`);
    }
  }

  async lpushTrim(key: string, value: string, maxLen: number): Promise<void> {
    if (!this.isEnabled()) return;
    try {
      if (this.provider === 'upstash-rest') {
        await this.upstashCommand(['LPUSH', key, value]);
        await this.upstashCommand(['LTRIM', key, 0, Math.max(0, maxLen - 1)]);
      } else if (this.provider === 'ioredis' && this.redisClient) {
        if (this.redisClient.status === 'wait') await this.redisClient.connect();
        await this.redisClient.lpush(key, value);
        await this.redisClient.ltrim(key, 0, Math.max(0, maxLen - 1));
      }
    } catch (err: any) {
      this.logger.warn(`Redis LPUSH/LTRIM error (${key}): ${err?.message || err}`);
    }
  }

  async lrange(key: string, start: number, stop: number): Promise<string[]> {
    if (!this.isEnabled()) return [];
    try {
      if (this.provider === 'upstash-rest') {
        const res = await this.upstashCommand<string[]>(['LRANGE', key, start, stop]);
        return Array.isArray(res) ? res : [];
      }
      if (this.provider === 'ioredis' && this.redisClient) {
        if (this.redisClient.status === 'wait') await this.redisClient.connect();
        return await this.redisClient.lrange(key, start, stop);
      }
    } catch (err: any) {
      this.logger.warn(`Redis LRANGE error (${key}): ${err?.message || err}`);
    }
    return [];
  }

  async sadd(key: string, member: string): Promise<void> {
    if (!this.isEnabled()) return;
    try {
      if (this.provider === 'upstash-rest') {
        await this.upstashCommand(['SADD', key, member]);
      } else if (this.provider === 'ioredis' && this.redisClient) {
        if (this.redisClient.status === 'wait') await this.redisClient.connect();
        await this.redisClient.sadd(key, member);
      }
    } catch (err: any) {
      this.logger.warn(`Redis SADD error (${key}): ${err?.message || err}`);
    }
  }

  async srem(key: string, member: string): Promise<void> {
    if (!this.isEnabled()) return;
    try {
      if (this.provider === 'upstash-rest') {
        await this.upstashCommand(['SREM', key, member]);
      } else if (this.provider === 'ioredis' && this.redisClient) {
        if (this.redisClient.status === 'wait') await this.redisClient.connect();
        await this.redisClient.srem(key, member);
      }
    } catch (err: any) {
      this.logger.warn(`Redis SREM error (${key}): ${err?.message || err}`);
    }
  }

  async smembers(key: string): Promise<string[]> {
    if (!this.isEnabled()) return [];
    try {
      if (this.provider === 'upstash-rest') {
        const res = await this.upstashCommand<string[]>(['SMEMBERS', key]);
        return Array.isArray(res) ? res : [];
      }
      if (this.provider === 'ioredis' && this.redisClient) {
        if (this.redisClient.status === 'wait') await this.redisClient.connect();
        return await this.redisClient.smembers(key);
      }
    } catch (err: any) {
      this.logger.warn(`Redis SMEMBERS error (${key}): ${err?.message || err}`);
    }
    return [];
  }

  private async getNamespaceVersion(namespace: string): Promise<string> {
    const cached = this.versionCache.get(namespace);
    if (cached && Date.now() < cached.expiresAt) {
      return cached.value;
    }
    if (this.isCircuitOpen()) {
      return cached?.value ?? '0';
    }
    const verKey = `${this.prefix}:ver:${namespace}`;
    try {
      const val = (await this.getRaw(verKey)) || '0';
      this.versionCache.set(namespace, {
        value: val,
        expiresAt: Date.now() + this.versionCacheTtlMs,
      });
      return val;
    } catch (err: any) {
      this.tripCircuit(`Cache version read error (${verKey}): ${err?.message || err}`);
      return cached?.value ?? '0';
    }
  }

  private async getRaw(key: string): Promise<string | null> {
    if (this.provider === 'upstash-rest') {
      const res = await this.upstashCommand<string | null>(['GET', key]);
      return res ?? null;
    }
    if (this.provider === 'ioredis' && this.redisClient) {
      if (this.redisClient.status === 'wait') {
        await this.redisClient.connect();
      }
      return this.redisClient.get(key);
    }
    return null;
  }

  private async setRaw(key: string, value: string, ttlSec: number): Promise<void> {
    if (this.provider === 'upstash-rest') {
      await this.upstashCommand(['SET', key, value, 'EX', Math.max(1, Math.floor(ttlSec))]);
      return;
    }
    if (this.provider === 'ioredis' && this.redisClient) {
      if (this.redisClient.status === 'wait') {
        await this.redisClient.connect();
      }
      await this.redisClient.set(key, value, 'EX', Math.max(1, Math.floor(ttlSec)));
    }
  }

  private async incrRaw(key: string): Promise<number> {
    if (this.provider === 'upstash-rest') {
      const res = await this.upstashCommand<number>(['INCR', key]);
      return Number(res ?? 1);
    }
    if (this.provider === 'ioredis' && this.redisClient) {
      if (this.redisClient.status === 'wait') {
        await this.redisClient.connect();
      }
      return this.redisClient.incr(key);
    }
    return 1;
  }

  private async upstashCommand<T = unknown>(args: (string | number)[]): Promise<T | null> {
    if (!this.upstashRestUrl || !this.upstashRestToken) return null;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const res = await fetch(this.upstashRestUrl, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.upstashRestToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(args),
        signal: controller.signal,
      });

      if (!res.ok) {
        const text = await res.text().catch(() => '');
        throw new Error(`HTTP ${res.status} ${text.slice(0, 200)}`);
      }

      const data = (await res.json()) as { result?: T; error?: string };
      if (data.error) {
        throw new Error(data.error);
      }

      return data.result ?? null;
    } finally {
      clearTimeout(timer);
    }
  }
}
