import { Injectable, CanActivate, ExecutionContext } from '@nestjs/common';
import { AuthGuard } from './auth.guard';

/**
 * Allows unauthenticated requests (guests) through without populating
 * `request.user`, while still validating any supplied Bearer token so expired
 * tokens return 401 and trigger client token refresh + retry.
 */
@Injectable()
export class OptionalAuthGuard extends AuthGuard implements CanActivate {
  override async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const authHeader = request.headers?.authorization;
    if (!authHeader || typeof authHeader !== 'string' || !authHeader.startsWith('Bearer ')) {
      return true;
    }
    return super.canActivate(context);
  }
}
