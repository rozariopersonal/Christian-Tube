"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var PrismaService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.PrismaService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
let PrismaService = PrismaService_1 = class PrismaService extends client_1.PrismaClient {
    constructor() {
        super(...arguments);
        this.logger = new common_1.Logger(PrismaService_1.name);
    }
    async onModuleInit() {
        try {
            await this.$connect();
            this.logger.log('✅ Prisma connected successfully to PostgreSQL database.');
            await this.$executeRawUnsafe(`
        CREATE TABLE IF NOT EXISTS "Channel" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "name" TEXT NOT NULL,
          "description" TEXT,
          "thumbnail" TEXT,
          "subscriberCount" TEXT,
          "category" TEXT,
          "language" TEXT,
          "isActive" BOOLEAN NOT NULL DEFAULT true,
          "syncCursor" TEXT,
          "syncStatus" TEXT DEFAULT 'IDLE',
          "lastSyncedAt" TIMESTAMP(3),
          "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
          "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        ALTER TABLE "Channel" ADD COLUMN IF NOT EXISTS "syncCursor" TEXT;
        ALTER TABLE "Channel" ADD COLUMN IF NOT EXISTS "syncStatus" TEXT DEFAULT 'IDLE';

        CREATE TABLE IF NOT EXISTS "Video" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "type" TEXT NOT NULL DEFAULT 'VIDEO',
          "title" TEXT NOT NULL,
          "description" TEXT NOT NULL,
          "thumbnail" TEXT NOT NULL,
          "channelId" TEXT NOT NULL,
          "channelName" TEXT NOT NULL,
          "channelThumbnail" TEXT,
          "channelSubscriberCount" TEXT,
          "publishedAt" TIMESTAMP(3) NOT NULL,
          "duration" TEXT NOT NULL,
          "viewCount" INTEGER NOT NULL DEFAULT 0,
          "tags" TEXT[] DEFAULT ARRAY[]::TEXT[],
          "category" TEXT,
          "transcriptionStatus" TEXT NOT NULL DEFAULT 'pending',
          "transcriptionProgress" INTEGER,
          "transcriptionRetryCount" INTEGER NOT NULL DEFAULT 0,
          "transcriptionDetail" JSONB,
          "lastTranscriptionError" TEXT,
          "content" TEXT,
          "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
          "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS "ChannelRequest" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "channelUrl" TEXT NOT NULL,
          "notes" TEXT,
          "status" TEXT NOT NULL DEFAULT 'PENDING',
          "submittedBy" TEXT,
          "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
          "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS "User" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "email" TEXT NOT NULL UNIQUE,
          "displayName" TEXT,
          "photoUrl" TEXT,
          "isBlocked" BOOLEAN NOT NULL DEFAULT false,
          "role" TEXT NOT NULL DEFAULT 'USER',
          "lastLoginAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
          "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
          "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS "MicroFeedItem" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "engine" TEXT NOT NULL DEFAULT 'scripture',
          "bookNumber" INTEGER,
          "bookName" TEXT,
          "chapter" INTEGER,
          "startVerse" INTEGER,
          "endVerse" INTEGER,
          "referenceLabel" TEXT NOT NULL,
          "text" TEXT NOT NULL,
          "translation" TEXT NOT NULL DEFAULT 'WEB',
          "category" TEXT NOT NULL DEFAULT 'General',
          "backgroundPreset" TEXT NOT NULL DEFAULT 'mountain_dawn',
          "tags" TEXT[] DEFAULT ARRAY[]::TEXT[],
          "likesCount" INTEGER NOT NULL DEFAULT 0,
          "sharesCount" INTEGER NOT NULL DEFAULT 0,
          "isFeatured" BOOLEAN NOT NULL DEFAULT false,
          "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
          "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE INDEX IF NOT EXISTS "Video_channelId_idx" ON "Video"("channelId");
        CREATE INDEX IF NOT EXISTS "Video_publishedAt_idx" ON "Video"("publishedAt");
        CREATE INDEX IF NOT EXISTS "Video_type_idx" ON "Video"("type");
        CREATE INDEX IF NOT EXISTS "Video_category_idx" ON "Video"("category");
        CREATE INDEX IF NOT EXISTS "Channel_isActive_idx" ON "Channel"("isActive");
        CREATE INDEX IF NOT EXISTS "Channel_category_idx" ON "Channel"("category");
        CREATE INDEX IF NOT EXISTS "User_isBlocked_idx" ON "User"("isBlocked");
        CREATE INDEX IF NOT EXISTS "User_email_idx" ON "User"("email");
        CREATE INDEX IF NOT EXISTS "MicroFeedItem_engine_idx" ON "MicroFeedItem"("engine");
        CREATE INDEX IF NOT EXISTS "MicroFeedItem_category_idx" ON "MicroFeedItem"("category");
        CREATE INDEX IF NOT EXISTS "MicroFeedItem_isFeatured_idx" ON "MicroFeedItem"("isFeatured");
      `);
            this.logger.log('✅ PostgreSQL database tables verified and created.');
        }
        catch (e) {
            this.logger.error(`⚠️ Prisma connection or table init error: ${e.message}`);
        }
    }
    async onModuleDestroy() {
        await this.$disconnect();
    }
};
exports.PrismaService = PrismaService;
exports.PrismaService = PrismaService = PrismaService_1 = __decorate([
    (0, common_1.Injectable)()
], PrismaService);
//# sourceMappingURL=prisma.service.js.map