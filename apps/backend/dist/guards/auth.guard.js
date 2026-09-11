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
var AuthGuard_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.AuthGuard = void 0;
const common_1 = require("@nestjs/common");
const google_jwks_service_1 = require("../services/google-jwks.service");
let AuthGuard = AuthGuard_1 = class AuthGuard {
    constructor(googleJwksService) {
        this.googleJwksService = googleJwksService;
        this.logger = new common_1.Logger(AuthGuard_1.name);
    }
    async canActivate(context) {
        const request = context.switchToHttp().getRequest();
        const authHeader = request.headers?.authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            this.logger.warn('Missing or invalid Authorization header');
            throw new common_1.UnauthorizedException('Authorization header required');
        }
        const token = authHeader.substring(7).trim();
        if (!token) {
            throw new common_1.UnauthorizedException('Token required');
        }
        if (this.googleJwksService.isGuestToken(token)) {
            const userId = this.googleJwksService.parseGuestToken(token);
            if (!userId) {
                throw new common_1.UnauthorizedException('Invalid guest token');
            }
            request.user = {
                userId,
                email: null,
                role: 'USER',
            };
            return true;
        }
        try {
            const payload = await this.googleJwksService.verifyIdToken(token);
            request.user = {
                userId: payload.sub,
                email: payload.email,
                role: 'USER',
            };
            return true;
        }
        catch (error) {
            this.logger.warn(`Auth failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
            throw new common_1.UnauthorizedException('Invalid or expired token');
        }
    }
};
exports.AuthGuard = AuthGuard;
exports.AuthGuard = AuthGuard = AuthGuard_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [google_jwks_service_1.GoogleJwksService])
], AuthGuard);
//# sourceMappingURL=auth.guard.js.map