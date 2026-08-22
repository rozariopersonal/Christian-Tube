import { Controller, Get } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

@Controller()
export class HealthController {
  constructor(private readonly configService: ConfigService) {}

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
      timestamp: new Date().toISOString(),
    };
  }
}
