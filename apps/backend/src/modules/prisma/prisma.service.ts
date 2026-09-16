import { Injectable, OnModuleInit, OnModuleDestroy, Logger } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PrismaService.name);

  async onModuleInit() {
    try {
      await this.$connect();
      this.logger.log('✅ Prisma connected successfully to PostgreSQL database.');

      // Auto-create core tables on boot if not already present
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

      await this.ensureEmbeddingSchema();
      this.logger.log('✅ PostgreSQL database tables verified and created.');
    } catch (e: any) {
      this.logger.error(`⚠️ Prisma connection or table init error: ${e.message}`);
    }
  }

  /**
   * Creates the pgvector extension, Video embedding metadata columns, the
   * VideoEmbedding table, and the HNSW index. Idempotent; safe to run every
   * boot. Each step is isolated so a single failure (e.g. CREATE EXTENSION on
   * a restricted pooled connection) cannot prevent the table from existing.
   */
  private async ensureEmbeddingSchema() {
    const steps: [string, string][] = [
      ["extension", `CREATE EXTENSION IF NOT EXISTS vector`],
      [
        "embedding columns",
        `ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "embeddingStatus" TEXT DEFAULT 'pending';
         ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "embeddingVersion" INTEGER DEFAULT 0;
         ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "embeddingHash" TEXT;
         ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "embeddingError" TEXT;
         ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "embeddingRetryCount" INTEGER DEFAULT 0;`,
      ],
      [
        "content columns",
        `ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "contentVersion" INTEGER DEFAULT 0;
         ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "chunkStatus" TEXT DEFAULT 'pending';
         ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "chunkError" TEXT;
         ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "chunkRetryCount" INTEGER DEFAULT 0;`,
      ],
      [
        "VideoEmbedding table",
        `CREATE TABLE IF NOT EXISTS "VideoEmbedding" (
           "videoId" TEXT NOT NULL PRIMARY KEY,
           "embedding" vector(384) NOT NULL,
           "model" TEXT NOT NULL,
           "version" INTEGER NOT NULL DEFAULT 0,
           "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
           "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
           CONSTRAINT "VideoEmbedding_videoId_fkey"
             FOREIGN KEY ("videoId") REFERENCES "Video"("id")
             ON DELETE CASCADE ON UPDATE CASCADE
         );`,
      ],
      [
        "VideoEmbedding indexes",
        `CREATE INDEX IF NOT EXISTS "VideoEmbedding_version_idx" ON "VideoEmbedding"("version");
         CREATE INDEX IF NOT EXISTS "VideoEmbedding_embedding_hnsw_idx"
           ON "VideoEmbedding" USING hnsw ("embedding" vector_cosine_ops)
           WITH (m = 16, ef_construction = 64);`,
      ],
      [
        "VideoChunk table",
        `CREATE TABLE IF NOT EXISTS "VideoChunk" (
           "id" SERIAL PRIMARY KEY,
           "videoId" TEXT NOT NULL,
           "seq" INTEGER NOT NULL,
           "kind" TEXT NOT NULL DEFAULT 'idea',
           "title" TEXT,
           "content" TEXT NOT NULL,
           "quoteText" TEXT,
           "scriptureRefs" JSONB,
           "startSec" DOUBLE PRECISION,
           "endSec" DOUBLE PRECISION,
           "source" TEXT NOT NULL DEFAULT 'caption',
           "embedding" vector(384),
           "model" TEXT,
           "version" INTEGER NOT NULL DEFAULT 0,
           "digest" TEXT,
           "embeddingStatus" TEXT NOT NULL DEFAULT 'pending',
           "embeddingError" TEXT,
           "embeddingRetryCount" INTEGER NOT NULL DEFAULT 0,
           "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
           "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
           CONSTRAINT "VideoChunk_videoId_fkey"
             FOREIGN KEY ("videoId") REFERENCES "Video"("id")
             ON DELETE CASCADE ON UPDATE CASCADE
         );`,
      ],
      [
        "VideoChunk split columns",
        `ALTER TABLE "VideoChunk" ALTER COLUMN "embedding" DROP NOT NULL;
         ALTER TABLE "VideoChunk" ALTER COLUMN "model" DROP NOT NULL;
         ALTER TABLE "VideoChunk" ADD COLUMN IF NOT EXISTS "embeddingStatus" TEXT DEFAULT 'pending';
         ALTER TABLE "VideoChunk" ADD COLUMN IF NOT EXISTS "embeddingError" TEXT;
         ALTER TABLE "VideoChunk" ADD COLUMN IF NOT EXISTS "embeddingRetryCount" INTEGER DEFAULT 0;`,
      ],
      [
        "VideoChunk indexes",
        `CREATE UNIQUE INDEX IF NOT EXISTS "VideoChunk_videoId_seq_key" ON "VideoChunk"("videoId", "seq");
         CREATE INDEX IF NOT EXISTS "VideoChunk_model_version_idx" ON "VideoChunk"("model", "version");
         CREATE INDEX IF NOT EXISTS "VideoChunk_embedding_status_idx"
           ON "VideoChunk"("embeddingStatus")
           WHERE "embeddingStatus" IS DISTINCT FROM 'completed';
         CREATE INDEX IF NOT EXISTS "VideoChunk_embedding_hnsw_idx"
           ON "VideoChunk" USING hnsw ("embedding" vector_cosine_ops)
           WITH (m = 16, ef_construction = 64);`,
      ],
    ];

    for (const [name, sql] of steps) {
      try {
        await this.$executeRawUnsafe(sql);
      } catch (e: any) {
        this.logger.warn(
          `Embedding schema step '${name}' failed: ${e.message}`,
        );
      }
    }
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
