import { CanActivate, ExecutionContext, Logger } from '@nestjs/common';
import { GoogleJwksService } from '../services/google-jwks.service';
export declare class AuthGuard implements CanActivate {
    private readonly googleJwksService;
    protected readonly logger: Logger;
    constructor(googleJwksService: GoogleJwksService);
    canActivate(context: ExecutionContext): Promise<boolean>;
}
