"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var GoogleJwksService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.GoogleJwksService = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const jose_1 = require("jose");
let GoogleJwksService = GoogleJwksService_1 = class GoogleJwksService {
    constructor(configService) {
        this.configService = configService;
        this.logger = new common_1.Logger(GoogleJwksService_1.name);
        this.jwks = null;
    }
    getJwks() {
        if (!this.jwks) {
            const clientId = this.configService.get('googleClientId');
            if (!clientId) {
                this.logger.warn('Google Client ID not configured — token verification will fail');
            }
            this.jwks = (0, jose_1.createRemoteJWKSet)(new URL('https://www.googleapis.com/oauth2/v3/certs'), {
                cacheMaxAge: 60 * 60 * 1000,
                cooldownDuration: 60 * 1000,
            });
        }
        return this.jwks;
    }
    async verifyIdToken(token) {
        const jwks = this.getJwks();
        const clientId = this.configService.get('googleClientId');
        if (!clientId) {
            throw new Error('Google Client ID not configured');
        }
        try {
            const { payload } = await (0, jose_1.jwtVerify)(token, jwks, {
                issuer: ['https://accounts.google.com', 'accounts.google.com'],
                audience: clientId,
                clockTolerance: 30,
            });
            this.logger.debug(`Token verified for user: ${payload.sub}`);
            return payload;
        }
        catch (error) {
            this.logger.warn(`Token verification failed: ${error.message}`);
            throw new Error('Invalid or expired token');
        }
    }
    isGuestToken(token) {
        return token.startsWith('token_');
    }
    parseGuestToken(token) {
        if (!this.isGuestToken(token))
            return null;
        return token.replace('token_', '');
    }
};
exports.GoogleJwksService = GoogleJwksService;
exports.GoogleJwksService = GoogleJwksService = GoogleJwksService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [config_1.ConfigService])
], GoogleJwksService);
//# sourceMappingURL=google-jwks.service.js.map