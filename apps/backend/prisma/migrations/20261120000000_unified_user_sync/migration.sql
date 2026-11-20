-- Idempotent migration for unified multi-device user sync

ALTER TABLE "UserPreference"
  ADD COLUMN IF NOT EXISTS "fieldTimestamps" JSONB;

ALTER TABLE "ChannelSubscription"
  ADD COLUMN IF NOT EXISTS "isActive" BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS "clientUpdatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

CREATE INDEX IF NOT EXISTS "ChannelSubscription_userId_isActive_idx"
  ON "ChannelSubscription"("userId", "isActive");

CREATE TABLE IF NOT EXISTS "UserWatchItem" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "itemType" TEXT NOT NULL,
  "itemId" TEXT NOT NULL,
  "positionSeconds" INTEGER NOT NULL DEFAULT 0,
  "durationSeconds" INTEGER NOT NULL DEFAULT 0,
  "payloadJson" TEXT,
  "isDeleted" BOOLEAN NOT NULL DEFAULT false,
  "clientUpdatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "UserWatchItem_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "UserWatchItem_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS "UserWatchItem_userId_itemType_itemId_key"
  ON "UserWatchItem"("userId", "itemType", "itemId");

CREATE INDEX IF NOT EXISTS "UserWatchItem_userId_itemType_isDeleted_clientUpdatedAt_idx"
  ON "UserWatchItem"("userId", "itemType", "isDeleted", "clientUpdatedAt");
