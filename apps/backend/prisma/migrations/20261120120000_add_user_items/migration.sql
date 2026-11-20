-- Idempotent migration for unified reader annotations (Bible, Book, Article)

CREATE TABLE IF NOT EXISTS "UserItem" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "itemType" TEXT NOT NULL,
  "feature" TEXT NOT NULL,
  "targetId" TEXT NOT NULL,
  "versionId" TEXT NOT NULL DEFAULT '',
  "book" TEXT NOT NULL DEFAULT '',
  "chapter" INTEGER NOT NULL DEFAULT 0,
  "verseStart" INTEGER NOT NULL DEFAULT 0,
  "verseEnd" INTEGER NOT NULL DEFAULT 0,
  "startOffset" INTEGER NOT NULL DEFAULT 0,
  "endOffset" INTEGER NOT NULL DEFAULT 0,
  "color" TEXT,
  "colorIndex" INTEGER,
  "text" TEXT NOT NULL DEFAULT '',
  "contextText" TEXT,
  "payloadJson" TEXT,
  "isDeleted" BOOLEAN NOT NULL DEFAULT false,
  "clientUpdatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "UserItem_pkey" PRIMARY KEY ("userId", "id"),
  CONSTRAINT "UserItem_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS "UserItem_userId_feature_isDeleted_clientUpdatedAt_idx"
  ON "UserItem"("userId", "feature", "isDeleted", "clientUpdatedAt");
