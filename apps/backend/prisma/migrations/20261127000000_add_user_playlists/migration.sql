-- CreateTable
CREATE TABLE IF NOT EXISTS "UserPlaylist" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT,
    "isDeleted" BOOLEAN NOT NULL DEFAULT false,
    "clientUpdatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UserPlaylist_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "UserPlaylist_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "UserPlaylistItem" (
    "id" TEXT NOT NULL,
    "playlistId" TEXT NOT NULL,
    "videoId" TEXT NOT NULL,
    "position" INTEGER NOT NULL DEFAULT 0,
    "addedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UserPlaylistItem_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "UserPlaylistItem_playlistId_fkey" FOREIGN KEY ("playlistId") REFERENCES "UserPlaylist"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateIndex
CREATE INDEX IF NOT EXISTS "UserPlaylist_userId_isDeleted_updatedAt_idx"
    ON "UserPlaylist"("userId", "isDeleted", "updatedAt");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "UserPlaylistItem_playlistId_videoId_key"
    ON "UserPlaylistItem"("playlistId", "videoId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "UserPlaylistItem_playlistId_position_idx"
    ON "UserPlaylistItem"("playlistId", "position");
