import { ConfigService } from '@nestjs/config';
import { JWTPayload } from 'jose';
export declare class GoogleJwksService {
    private readonly configService;
    private readonly logger;
    private jwks;
    constructor(configService: ConfigService);
    private getJwks;
    verifyIdToken(token: string): Promise<JWTPayload>;
    isGuestToken(token: string): boolean;
    parseGuestToken(token: string): string | null;
}
