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
var UsersService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.UsersService = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const prisma_service_1 = require("../prisma/prisma.service");
let UsersService = UsersService_1 = class UsersService {
    constructor(prisma, configService) {
        this.prisma = prisma;
        this.configService = configService;
        this.logger = new common_1.Logger(UsersService_1.name);
    }
    isAdmin(email) {
        if (!email)
            return false;
        const adminEmails = this.configService.get('adminEmails') || [];
        return adminEmails.includes(email.trim().toLowerCase());
    }
    async syncUser(data) {
        const role = this.isAdmin(data.email) ? 'ADMIN' : 'USER';
        const user = await this.prisma.user.upsert({
            where: { id: data.id },
            update: {
                email: data.email,
                displayName: data.displayName || undefined,
                photoUrl: data.photoUrl || undefined,
                role,
                lastLoginAt: new Date(),
            },
            create: {
                id: data.id,
                email: data.email,
                displayName: data.displayName || 'User',
                photoUrl: data.photoUrl || null,
                role,
                isBlocked: false,
                lastLoginAt: new Date(),
            },
        });
        return user;
    }
    async findAll(query) {
        const where = {};
        if (query?.search) {
            where.OR = [
                { email: { contains: query.search, mode: 'insensitive' } },
                { displayName: { contains: query.search, mode: 'insensitive' } },
            ];
        }
        return this.prisma.user.findMany({
            where,
            orderBy: { lastLoginAt: 'desc' },
        });
    }
    async findOne(id) {
        const user = await this.prisma.user.findUnique({
            where: { id },
        });
        if (!user) {
            throw new common_1.NotFoundException(`User with ID ${id} not found`);
        }
        return user;
    }
    async toggleBlock(id) {
        const user = await this.findOne(id);
        return this.prisma.user.update({
            where: { id },
            data: { isBlocked: !user.isBlocked },
        });
    }
    async blockUser(id) {
        return this.prisma.user.update({
            where: { id },
            data: { isBlocked: true },
        });
    }
    async unblockUser(id) {
        return this.prisma.user.update({
            where: { id },
            data: { isBlocked: false },
        });
    }
    async savePlayback(data) {
        const userId = (data.userId || '').trim();
        const email = (data.userEmail || '').trim().toLowerCase();
        const mediaType = (data.mediaType || 'audio').toLowerCase();
        if (!userId || !data.trackId) {
            return { success: false, message: 'userId and trackId are required' };
        }
        const updatedAtDate = data.updatedAt ? new Date(data.updatedAt) : new Date();
        const record = {
            userId,
            userEmail: email || null,
            deviceId: data.deviceId || null,
            mediaType,
            trackId: data.trackId,
            seriesId: data.seriesId || null,
            title: data.title || null,
            speaker: data.speaker || null,
            coverUrl: data.coverUrl || null,
            audioUrl: data.audioUrl || null,
            positionSeconds: Math.max(0, Math.round(data.positionSeconds || 0)),
            durationSeconds: Math.max(0, Math.round(data.durationSeconds || 0)),
            payloadJson: data.payloadJson || null,
            updatedAt: updatedAtDate,
        };
        const cacheKey = `${userId}:${mediaType}`;
        UsersService_1.playbackCache.set(cacheKey, record);
        try {
            if (this.prisma.userPlayback) {
                await this.prisma.userPlayback.upsert({
                    where: {
                        userEmail_mediaType: {
                            userEmail: email || userId,
                            mediaType,
                        },
                    },
                    update: {
                        ...record,
                        updatedAt: updatedAtDate,
                    },
                    create: {
                        ...record,
                        updatedAt: updatedAtDate,
                    },
                });
            }
        }
        catch (e) {
            this.logger.warn(`Database playback upsert non-critical fallback: ${e}`);
        }
        return { success: true, playback: record };
    }
    async getPlayback(query) {
        const userId = (query.userId || '').trim();
        const email = (query.userEmail || '').trim().toLowerCase();
        const mediaType = (query.mediaType || 'audio').toLowerCase();
        if (!userId && !email) {
            return null;
        }
        const cacheKey = userId ? `${userId}:${mediaType}` : `${email}:${mediaType}`;
        try {
            if (this.prisma.userPlayback) {
                const where = userId
                    ? { userEmail_mediaType: { userEmail: userId, mediaType } }
                    : { userEmail_mediaType: { userEmail: email, mediaType } };
                const row = await this.prisma.userPlayback.findUnique({ where });
                if (row)
                    return row;
            }
        }
        catch (e) {
            this.logger.warn(`Database playback query non-critical fallback: ${e}`);
        }
        return UsersService_1.playbackCache.get(cacheKey) || null;
    }
};
exports.UsersService = UsersService;
UsersService.playbackCache = new Map();
exports.UsersService = UsersService = UsersService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        config_1.ConfigService])
], UsersService);
//# sourceMappingURL=users.service.js.map