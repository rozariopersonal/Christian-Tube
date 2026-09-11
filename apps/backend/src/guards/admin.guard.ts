import {
  Injectable,
  CanActivate,
  ExecutionContext,
  ForbiddenException,
} from '@nestjs/common';
import { AuthGuard } from './auth.guard';

@Injectable()
export class AdminGuard extends AuthGuard implements CanActivate {
  async canActivate(context: ExecutionContext): Promise<boolean> {
    await super.canActivate(context);

    const request = context.switchToHttp().getRequest();
    const user = request.user;

    if (user?.role !== 'ADMIN') {
      this.logger.warn(`Admin access denied for user: ${user?.userId} (role: ${user?.role})`);
      throw new ForbiddenException('Admin access required');
    }

    return true;
  }
}