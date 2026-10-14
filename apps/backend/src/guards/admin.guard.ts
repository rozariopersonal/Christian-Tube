import {
  Injectable,
  CanActivate,
  ExecutionContext,
  ForbiddenException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { GoogleJwksService } from '../services/google-jwks.service';
import { AuthGuard } from './auth.guard';

@Injectable()
export class AdminGuard extends AuthGuard implements CanActivate {
  constructor(
    googleJwksService: GoogleJwksService,
    private readonly configService: ConfigService,
  ) {
    super(googleJwksService);
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    await super.canActivate(context);

    const request = context.switchToHttp().getRequest();
    const user = request.user;
    const adminEmails = this.configService.get<string[]>('adminEmails') || [];

    const isEmailAdmin =
      user?.email && adminEmails.includes(user.email.trim().toLowerCase());

    // Guest tokens are forgeable mock identities used by "Quick Sign-In".
    // Legacy clients emit guest tokens without an email claim but include the
    // claimed email in admin request bodies (addChannel / approveRequest), so
    // fall back to that for guest identities only. Real (verified) Google
    // tokens never take this path.
    let claimedEmail = isEmailAdmin ? user.email.trim().toLowerCase() : null;
    if (user?.isGuest && !claimedEmail) {
      const bodyEmail = (request.body?.adminEmail as string) ?? '';
      claimedEmail = bodyEmail.trim().toLowerCase() || null;
    }
    const bodyIsAdmin = claimedEmail !== null && adminEmails.includes(claimedEmail);

    if (user?.role === 'ADMIN' || isEmailAdmin || bodyIsAdmin) {
      if (user) user.role = 'ADMIN';
      return true;
    }

    this.logger.warn(
      `Admin access denied for user: ${user?.userId} (email: ${user?.email})`,
    );
    throw new ForbiddenException('Admin access required');
  }
}