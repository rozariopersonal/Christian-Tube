-- Purge orphaned UserPlayback rows for guest users first (no FK cascade)
DELETE FROM "UserPlayback"
WHERE "userId" IN (
  SELECT "id" FROM "User"
  WHERE "isGuest" = true
     OR "email" LIKE '%@guest.local'
     OR "email" LIKE '%@christianapp.local'
     OR "id" LIKE 'guest_%'
     OR "id" LIKE 'user_%'
)
OR "userEmail" LIKE '%@guest.local'
OR "userEmail" LIKE '%@christianapp.local';

-- Purge guest WebSession rows (no FK cascade)
DELETE FROM "WebSession"
WHERE "userId" LIKE 'guest_%'
   OR "userId" LIKE 'user_%'
   OR "email" LIKE '%@guest.local'
   OR "email" LIKE '%@christianapp.local';

-- Delete guest User rows (cascades to UserSession, UserPreference, ChannelSubscription, UserWatchItem, UserItem, ShortCreation)
DELETE FROM "User"
WHERE "isGuest" = true
   OR "email" LIKE '%@guest.local'
   OR "email" LIKE '%@christianapp.local'
   OR "id" LIKE 'guest_%'
   OR "id" LIKE 'user_%';

-- Drop removed columns from UserPreference, UserSession, and User
ALTER TABLE "UserPreference"
  DROP COLUMN IF EXISTS "videoChannelIds",
  DROP COLUMN IF EXISTS "shortsChannelIds",
  DROP COLUMN IF EXISTS "bibleVersionIds",
  DROP COLUMN IF EXISTS "dailyReminderEnabled",
  DROP COLUMN IF EXISTS "dailyReminderTime";

ALTER TABLE "UserSession"
  DROP COLUMN IF EXISTS "isGuest";

ALTER TABLE "User"
  DROP COLUMN IF EXISTS "isGuest";
