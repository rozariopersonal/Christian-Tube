CREATE TABLE IF NOT EXISTS "WebSession" (
  "tokenHash" TEXT NOT NULL PRIMARY KEY,
  "userId" TEXT NOT NULL,
  "email" TEXT NOT NULL,
  "expiresAt" TIMESTAMP(3) NOT NULL
);
CREATE INDEX IF NOT EXISTS "WebSession_expiresAt_idx" ON "WebSession"("expiresAt");
