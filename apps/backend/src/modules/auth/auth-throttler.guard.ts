import { ExecutionContext, Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';

@Injectable()
export class AuthThrottlerGuard extends ThrottlerGuard {
  protected async getTracker(req: Record<string, any>): Promise<string> {
    const ip =
      (Array.isArray(req.ips) && req.ips.length > 0 ? req.ips[0] : req.ip) ||
      req.socket?.remoteAddress ||
      'unknown';
    const sessionId =
      typeof req.body?.sessionId === 'string' ? req.body.sessionId.trim() : '';
    return sessionId ? `${ip}:${sessionId}` : String(ip);
  }

  protected async shouldSkip(_context: ExecutionContext): Promise<boolean> {
    return false;
  }
}
