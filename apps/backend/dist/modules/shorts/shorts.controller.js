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
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.ShortsController = void 0;
const common_1 = require("@nestjs/common");
const auth_guard_1 = require("../../guards/auth.guard");
const current_user_decorator_1 = require("../../guards/current-user.decorator");
const shorts_service_1 = require("./shorts.service");
let ShortsController = class ShortsController {
    constructor(shortsService) {
        this.shortsService = shortsService;
    }
    async getQuotaStatus() {
        return this.shortsService.getQuotaStatus();
    }
    async initiateUpload(user, dto) {
        return this.shortsService.initiateUploadSession({ ...dto, userId: user.userId, userEmail: user.email });
    }
    async getMyCreations(user) {
        return this.shortsService.getMyCreations(user.userId, user.email);
    }
    async recordCreation(user, data) {
        return this.shortsService.recordCreation({ ...data, userId: user.userId, userEmail: user.email });
    }
    async cleanupLegacyShorts() {
        return this.shortsService.cleanupLegacyShorts();
    }
};
exports.ShortsController = ShortsController;
__decorate([
    (0, common_1.Get)('quota-status'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], ShortsController.prototype, "getQuotaStatus", null);
__decorate([
    (0, common_1.UseGuards)(auth_guard_1.AuthGuard),
    (0, common_1.Post)('initiate-upload'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object]),
    __metadata("design:returntype", Promise)
], ShortsController.prototype, "initiateUpload", null);
__decorate([
    (0, common_1.UseGuards)(auth_guard_1.AuthGuard),
    (0, common_1.Get)('my-creations'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], ShortsController.prototype, "getMyCreations", null);
__decorate([
    (0, common_1.UseGuards)(auth_guard_1.AuthGuard),
    (0, common_1.Post)('record-creation'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object]),
    __metadata("design:returntype", Promise)
], ShortsController.prototype, "recordCreation", null);
__decorate([
    (0, common_1.Post)('cleanup-legacy-shorts'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], ShortsController.prototype, "cleanupLegacyShorts", null);
exports.ShortsController = ShortsController = __decorate([
    (0, common_1.Controller)(['shorts', 'api/shorts']),
    __metadata("design:paramtypes", [shorts_service_1.ShortsService])
], ShortsController);
//# sourceMappingURL=shorts.controller.js.map