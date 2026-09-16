-- Cutover migration for the split transcription / chunking / embedding pipeline.
--
-- The monolithic content-worker wrote transcripts AND chunks AND embeddings in
-- one atomic step. The new daemons (services/transcriber, services/chunker,
-- services/embedder) advance three independent statuses. This script is
-- idempotent and safe to run before starting the new services; the workers also
-- self-heal the same columns on boot, so re-runs are harmless.

-- 1. Stage columns (idempotent)
ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "chunkStatus" TEXT DEFAULT 'pending';
ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "chunkError" TEXT;
ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "chunkRetryCount" INTEGER DEFAULT 0;

ALTER TABLE "VideoChunk" ALTER COLUMN "embedding" DROP NOT NULL;
ALTER TABLE "VideoChunk" ALTER COLUMN "model" DROP NOT NULL;
ALTER TABLE "VideoChunk" ADD COLUMN IF NOT EXISTS "embeddingStatus" TEXT DEFAULT 'pending';
ALTER TABLE "VideoChunk" ADD COLUMN IF NOT EXISTS "embeddingError" TEXT;
ALTER TABLE "VideoChunk" ADD COLUMN IF NOT EXISTS "embeddingRetryCount" INTEGER DEFAULT 0;
CREATE INDEX IF NOT EXISTS "VideoChunk_embedding_status_idx"
  ON "VideoChunk"("embeddingStatus")
  WHERE "embeddingStatus" IS DISTINCT FROM 'completed';

-- 2. Legacy rows produced by the monolithic worker: transcripts AND chunks AND
--    embeddings already exist, so the chunk stage is considered complete.
UPDATE "Video" SET "chunkStatus" = 'completed'
WHERE "chunkStatus" = 'pending'
  AND "transcriptionStatus" = 'completed'
  AND "contentVersion" IS NOT NULL
  AND EXISTS (SELECT 1 FROM "VideoChunk" vc WHERE vc."videoId" = "Video"."id");

-- 3. Existing chunks that already carry vectors were embedded by the old
--    pipeline; mark them completed so the embedder does not re-embed at the
--    current model version.
UPDATE "VideoChunk" SET "embeddingStatus" = 'completed'
WHERE "embedding" IS NOT NULL
  AND ("embeddingStatus" IS NULL OR "embeddingStatus" = 'pending');