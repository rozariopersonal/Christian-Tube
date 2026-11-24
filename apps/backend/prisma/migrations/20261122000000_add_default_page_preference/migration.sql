-- Idempotent migration for per-user default page preference

ALTER TABLE "UserPreference"
  ADD COLUMN IF NOT EXISTS "defaultPage" TEXT DEFAULT 'feed';
