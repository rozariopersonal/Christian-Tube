-- Idempotent migration for per-device UserSession and User.isGuest

ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "isGuest" BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS "UserSession" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "refreshTokenHash" TEXT NOT NULL,
  "prevTokenHash" TEXT,
  "prevTokenGraceUntil" TIMESTAMP(3),
  "deviceId" TEXT,
  "deviceLabel" TEXT,
  "isGuest" BOOLEAN NOT NULL DEFAULT false,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "revokedAt" TIMESTAMP(3),
  "revokeReason" TEXT,
  "lastUsedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "UserSession_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "UserSession_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS "UserSession_userId_idx" ON "UserSession"("userId");
CREATE INDEX IF NOT EXISTS "UserSession_expiresAt_idx" ON "UserSession"("expiresAt");
