-- AlterTable
ALTER TABLE "AudioSeries" ADD COLUMN     "channelId" TEXT;

-- CreateIndex
CREATE INDEX "AudioSeries_channelId_idx" ON "AudioSeries"("channelId");

-- AddForeignKey
ALTER TABLE "AudioSeries" ADD CONSTRAINT "AudioSeries_channelId_fkey" FOREIGN KEY ("channelId") REFERENCES "Channel"("id") ON DELETE SET NULL ON UPDATE CASCADE;