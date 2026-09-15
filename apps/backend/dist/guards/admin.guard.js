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
Object.defineProperty(exports, "__esModule", { value: true });
exports.AdminGuard = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const google_jwks_service_1 = require("../services/google-jwks.service");
const auth_guard_1 = require("./auth.guard");
let AdminGuard = class AdminGuard extends auth_guard_1.AuthGuard {
    constructor(googleJwksService, configService) {
        super(googleJwksService);
        this.configService = configService;
    }
    async canActivate(context) {
        await super.canActivate(context);
        const request = context.switchToHttp().getRequest();
        const user = request.user;
        const adminEmails = this.configService.get('adminEmails') || [];
        const isEmailAdmin = user?.email && adminEmails.includes(user.email.trim().toLowerCase());
        if (user?.role === 'ADMIN' || isEmailAdmin) {
            if (user)
                user.role = 'ADMIN';
            return true;
        }
        this.logger.warn(`Admin access denied for user: ${user?.userId} (email: ${user?.email})`);
        throw new common_1.ForbiddenException('Admin access required');
    }
};
exports.AdminGuard = AdminGuard;
exports.AdminGuard = AdminGuard = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [google_jwks_service_1.GoogleJwksService,
        config_1.ConfigService])
], AdminGuard);
//# sourceMappingURL=admin.guard.js.map