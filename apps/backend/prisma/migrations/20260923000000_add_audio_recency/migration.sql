-- AlterTable
ALTER TABLE "AudioSeries" ADD COLUMN "latestPublishedAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "AudioTrack" ADD COLUMN "publishedAt" TIMESTAMP(3);

-- CreateIndex
CREATE INDEX "AudioSeries_latestPublishedAt_idx" ON "AudioSeries"("latestPublishedAt");

-- CreateIndex
CREATE INDEX "AudioTrack_publishedAt_idx" ON "AudioTrack"("publishedAt");