import { CanActivate, ExecutionContext } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { GoogleJwksService } from '../services/google-jwks.service';
import { AuthGuard } from './auth.guard';
export declare class AdminGuard extends AuthGuard implements CanActivate {
    private readonly configService;
    constructor(googleJwksService: GoogleJwksService, configService: ConfigService);
    canActivate(context: ExecutionContext): Promise<boolean>;
}
