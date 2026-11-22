import {
  Injectable,
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Optional,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { GoogleJwksService } from '../services/google-jwks.service';
import { AppJwtService } from '../modules/auth/app-jwt.service';
import { PrismaService } from '../modules/prisma/prisma.service';
import { AuthGuard } from './auth.guard';

@Injectable()
export class AdminGuard extends AuthGuard implements CanActivate {
  constructor(
    googleJwksService: GoogleJwksService,
    private readonly adminConfigService: ConfigService,
    @Optional() appJwtService?: AppJwtService,
    @Optional() prisma?: PrismaService,
  ) {
    super(googleJwksService, appJwtService, prisma, adminConfigService);
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    await super.canActivate(context);

    const request = context.switchToHttp().getRequest();
    const user = request.user;

    if (!user || user.isGuest === true) {
      this.logger.warn(`Admin access denied for guest user: ${user?.userId}`);
      throw new ForbiddenException('Admin access required');
    }

    const adminEmails = (
      this.adminConfigService.get<string[]>('adminEmails') || []
    ).map((e) => e.trim().toLowerCase());

    const verifiedEmail =
      typeof user.email === 'string' ? user.email.trim().toLowerCase() : '';
    const isEmailAdmin =
      verifiedEmail.length > 0 && adminEmails.includes(verifiedEmail);

    if (user.role === 'ADMIN' || isEmailAdmin) {
      user.role = 'ADMIN';
      return true;
    }

    this.logger.warn(
      `Admin access denied for user: ${user?.userId} (email: ${user?.email})`,
    );
    throw new ForbiddenException('Admin access required');
  }
}