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
      service: this.configService.get<string>('appName') || 'PrivateTube API',
      instanceId: this.configService.get<string>('instanceId') || 'unknown',
      timestamp: new Date().toISOString(),
    };
  }

  @Get('health')
  getHealth() {
    return {
      status: 'healthy',
      instanceId: this.configService.get<string>('instanceId') || 'unknown',
      uptime: process.uptime(),
      cache: this.cache?.getStatus() ?? { enabled: false, provider: 'none' },
      timestamp: new Date().toISOString(),
    };
  }
}
