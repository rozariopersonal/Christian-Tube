import { Controller, Get, Optional } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { CacheService } from '../cache/cache.service';

@Controller()
export class HealthController {
  constructor(
    private readonly configService: ConfigService,
    @Optional() private readonly cache?: CacheService,
  ) {}

  @Get()
  getRoot() {
    return {
      status: 'ok',
      service: this.configService.get<string>('appName') || 'ChristianApp API',
      instanceId: this.configService.get<string>('instanceId') || 'unknown',
      timestamp: new Date().toISOString(),
    };
  }

  @Get('health')
  getHealth() {
    const vectorUrl = this.configService.get<string>('upstashVector.restUrl') || process.env.UPSTASH_VECTOR_REST_URL;
    const vectorTok = this.configService.get<string>('upstashVector.restToken') || process.env.UPSTASH_VECTOR_REST_TOKEN;
    const vectorEnabled = Boolean(vectorUrl && vectorTok);
    return {
      status: 'healthy',
      instanceId: this.configService.get<string>('instanceId') || 'unknown',
      uptime: process.uptime(),
      cache: this.cache?.getStatus() ?? { enabled: false, provider: 'none' },
      bibleVector: { enabled: vectorEnabled, provider: vectorEnabled ? 'upstash-vector' : 'none' },
      timestamp: new Date().toISOString(),
    };
  }
}
