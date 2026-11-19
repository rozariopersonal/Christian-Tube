import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

export type CacheProvider = 'upstash-rest' | 'ioredis' | 'none';

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
   * error), invokes loader() and populates the cache with ttlSec.
   */
  async getOrSet<T>(
    namespace: string,
    key: string,
    ttlSec: number | undefined,
    loader: () => Promise<T>,
  ): Promise<T> {
    if (!this.isEnabled()) {
      return loader();
    }

    const effectiveTtl = ttlSec && ttlSec > 0 ? ttlSec : this.defaultTtlSec;
    const version = await this.getNamespaceVersion(namespace);
    const fullKey = `${this.prefix}:${namespace}:v${version}:${key}`;

    try {
      const cached = await this.getRaw(fullKey);
      if (cached !== null) {
        return JSON.parse(cached) as T;
      }
    } catch (err: any) {
      this.logger.warn(`Cache read error (${fullKey}): ${err?.message || err}`);
    }

    const value = await loader();

    if (value !== undefined && value !== null) {
      try {
        await this.setRaw(fullKey, JSON.stringify(value), effectiveTtl);
      } catch (err: any) {
        this.logger.warn(`Cache write error (${fullKey}): ${err?.message || err}`);
      }
    }

    return value;
  }

  /**
   * Bumps the version counter for one or more namespaces so subsequent reads
   * bypass stale cached entries without needing expensive SCAN/KEYS calls.
   */
  async invalidate(...namespaces: string[]): Promise<void> {
    if (!this.isEnabled() || namespaces.length === 0) return;

    await Promise.all(
      namespaces.map(async (ns) => {
        const verKey = `${this.prefix}:ver:${ns}`;
        try {
          await this.incrRaw(verKey);
        } catch (err: any) {
          this.logger.warn(`Cache invalidation error (${verKey}): ${err?.message || err}`);
        }
      }),
    );
  }

  private async getNamespaceVersion(namespace: string): Promise<string> {
    const verKey = `${this.prefix}:ver:${namespace}`;
    try {
      const val = await this.getRaw(verKey);
      return val || '0';
    } catch {
      return '0';
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
