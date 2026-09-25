import pg from 'pg';
import * as dotenv from 'dotenv';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'node:url';

// envs/ is gitignored and not copied into worktrees, so walk up from the
// current directory toward the monorepo root looking for envs/neon.env.
const currentDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = process.cwd();

if (!process.env.DATABASE_URL) {
  let dir = repoRoot;
  for (let i = 0; i < 6 && dir !== path.parse(dir).root; i++) {
    const candidate = path.resolve(dir, 'envs/neon.env');
    if (fs.existsSync(candidate)) {
      dotenv.config({ path: candidate });
      break;
    }
    dir = path.dirname(dir);
  }
}

const dbUrl = process.env.DATABASE_URL;
if (!dbUrl) {
  console.error('DATABASE_URL is not set!');
  process.exit(1);
}
const validDbUrl: string = dbUrl;

const pool = new pg.Pool({
  connectionString: validDbUrl,
  ssl: { rejectUnauthorized: false },
});

// The 17 status columns moving off Video into per-worker JSONB in
// VideoPipelineStatus. Order matters for the DROP phase.
const STATUS_COLUMNS = [
  'transcriptionStatus',
  'transcriptionProgress',
  'transcriptionRetryCount',
  'transcriptionDetail',
  'lastTranscriptionError',
  'contentVersion',
  'embeddingStatus',
  'embeddingVersion',
  'embeddingHash',
  'embeddingError',
  'embeddingRetryCount',
  'audioUploadStatus',
  'audioRetryCount',
  'audioLastError',
  'chunkStatus',
  'chunkError',
  'chunkRetryCount',
];

async function main() {
  const isApply = process.argv.includes('--apply');

  console.log('=== MIGRATE Video pipeline-status columns -> VideoPipelineStatus JSONB ===');
  console.log(`Connecting to: ${validDbUrl.replace(/:[^:@]+@/, ':****@')}`);
  console.log(`Mode: ${isApply ? 'APPLY (MUTATING DATABASE)' : 'DRY RUN (Pass --apply to execute)'}`);
  console.log('----------------------------------------');

  const cols = await pool.query(
    `SELECT column_name FROM information_schema.columns WHERE table_name = 'Video' AND column_name = ANY($1::text[])`,
    [STATUS_COLUMNS]
  );
  const legacy = cols.rows.map((r) => r.column_name as string);
  console.log(`Status columns still present on Video: ${legacy.length}`);
  if (legacy.length > 0) {
    console.log(`  ${legacy.join(', ')}`);
  } else {
    console.log('  (none) — migration already complete');
  }

  const tableExists = await pool.query(`SELECT to_regclass('"VideoPipelineStatus"') AS t`);
  const hasTable = tableExists.rows[0].t !== null;
  console.log(`VideoPipelineStatus table exists: ${hasTable}`);

  if (legacy.length === 0) {
    const count = hasTable
      ? (await pool.query(`SELECT count(*) FROM "VideoPipelineStatus"`)).rows[0].count
      : 0;
    console.log(`Nothing to migrate. VideoPipelineStatus rows: ${count}`);
    await pool.end();
    return;
  }

  if (!isApply) {
    console.log('----------------------------------------');
    console.log('DRY RUN COMPLETE. No data was modified.');
    console.log('Run with --apply to backfill and DROP the Video status columns.');
    await pool.end();
    return;
  }

  console.log('----------------------------------------');
  console.log('EXECUTING MIGRATION...');

  // 1. Ensure VideoPipelineStatus table exists
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "VideoPipelineStatus" (
      "videoId" TEXT NOT NULL PRIMARY KEY,
      "contentVersion" INTEGER NOT NULL DEFAULT 0,
      "ingest" JSONB NOT NULL DEFAULT '{}'::jsonb,
      "transcription" JSONB NOT NULL DEFAULT '{}'::jsonb,
      "chunk" JSONB NOT NULL DEFAULT '{}'::jsonb,
      "embedding" JSONB NOT NULL DEFAULT '{}'::jsonb,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "VideoPipelineStatus_videoId_fkey"
        FOREIGN KEY ("videoId") REFERENCES "Video"("id")
        ON DELETE CASCADE ON UPDATE CASCADE
    )
  `);
  console.log('Ensured VideoPipelineStatus table.');

  // 2. Backfill statuses from whatever legacy columns remain. A backend boot
  //    (`prisma db push`) may have already dropped the data-free columns, so
  //    build the expression from the live column set. jsonb_build_object()
  //    omits keys whose value is NULL, so absent keys read back as
  //    "pending"/0 via COALESCE in workers.
  const present = await pool.query(
    `SELECT column_name FROM information_schema.columns WHERE table_name = 'Video' AND column_name = ANY($1::text[])`,
    [STATUS_COLUMNS]
  );
  const have = new Set(present.rows.map((r) => r.column_name as string));
  const obj = (kvs: string[]) => (kvs.length ? `jsonb_build_object(${kvs.join(', ')})` : `'{}'::jsonb`);
  console.log(`Legacy columns present and being backfilled: ${have.size ? [...have].join(', ') : '(none)'}`);

  const ingestKvs = [
    have.has('audioUploadStatus') ? `'status', v."audioUploadStatus"` : null,
    have.has('audioRetryCount') ? `'retryCount', v."audioRetryCount"` : null,
    have.has('audioLastError') ? `'lastError', v."audioLastError"` : null,
  ].filter(Boolean) as string[];
  const transcriptionKvs = [
    have.has('transcriptionStatus') ? `'status', v."transcriptionStatus"` : null,
    have.has('transcriptionProgress') ? `'progress', v."transcriptionProgress"` : null,
    have.has('transcriptionRetryCount') ? `'retryCount', v."transcriptionRetryCount"` : null,
    have.has('transcriptionDetail') ? `'detail', v."transcriptionDetail"` : null,
    have.has('lastTranscriptionError') ? `'lastError', v."lastTranscriptionError"` : null,
  ].filter(Boolean) as string[];
  const chunkKvs = [
    have.has('chunkStatus') ? `'status', v."chunkStatus"` : null,
    have.has('chunkError') ? `'error', v."chunkError"` : null,
    have.has('chunkRetryCount') ? `'retryCount', v."chunkRetryCount"` : null,
  ].filter(Boolean) as string[];
  const embeddingKvs = [
    have.has('embeddingStatus') ? `'status', v."embeddingStatus"` : null,
    have.has('embeddingVersion') ? `'version', v."embeddingVersion"` : null,
    have.has('embeddingHash') ? `'hash', v."embeddingHash"` : null,
    have.has('embeddingError') ? `'error', v."embeddingError"` : null,
    have.has('embeddingRetryCount') ? `'retryCount', v."embeddingRetryCount"` : null,
  ].filter(Boolean) as string[];
  const contentVersionExpr = have.has('contentVersion') ? `COALESCE(v."contentVersion", 0)` : '0';

  const backfill = await pool.query(`
    INSERT INTO "VideoPipelineStatus" ("videoId", "contentVersion", "ingest", "transcription", "chunk", "embedding", "createdAt", "updatedAt")
    SELECT
      v.id,
      ${contentVersionExpr},
      ${obj(ingestKvs)},
      ${obj(transcriptionKvs)},
      ${obj(chunkKvs)},
      ${obj(embeddingKvs)},
      CURRENT_TIMESTAMP,
      CURRENT_TIMESTAMP
    FROM "Video" v
    WHERE NOT EXISTS (SELECT 1 FROM "VideoPipelineStatus" s WHERE s."videoId" = v.id)
  `);
  console.log(`Backfilled ${backfill.rowCount} row(s) into VideoPipelineStatus.`);

  // 3. Reset-empties policy: transcripts marked completed but holding no
  //    content (Video.content NULL or empty) are re-queued as 'pending' so the
  //    transcriber reprocesses them.
  const resetEmpties = await pool.query(`
    UPDATE "VideoPipelineStatus" s
    SET
      "transcription" = COALESCE(s."transcription", '{}'::jsonb)
        || '{"status": "pending", "retryCount": 0, "lastError": null}'::jsonb,
      "updatedAt" = CURRENT_TIMESTAMP
    FROM "Video" v
    WHERE s."videoId" = v.id
      AND s."transcription"->>'status' = 'completed'
      AND (v."content" IS NULL OR length(v."content") = 0)
  `);
  console.log(`Reset ${resetEmpties.rowCount} completed-without-content transcript(s) to pending.`);

  // 4. Full re-embed policy: reset every chunk/sentence to 'pending' so the
  //    embedder re-embeds the entire corpus on the current contract version.
  //    embeddingError only exists where the embedder wrote it, so include it
  //    per-table only if the column is present.
  const resetChildEmbedding = async (table: 'VideoChunk' | 'VideoSentence') => {
    const errCol = await pool.query(
      `SELECT 1 FROM information_schema.columns WHERE table_name = $1 AND column_name = 'embeddingError'`,
      [table]
    );
    const setClause = errCol.rows.length
      ? `"embeddingStatus"='pending', "embeddingError"=NULL`
      : `"embeddingStatus"='pending'`;
    const r = await pool.query(`UPDATE "${table}" SET ${setClause} WHERE "embeddingStatus" IS DISTINCT FROM 'pending'`);
    return r.rowCount;
  };
  const reEmbedChunks = await resetChildEmbedding('VideoChunk');
  const reEmbedSentences = await resetChildEmbedding('VideoSentence');
  console.log(`Full re-embed: reset ${reEmbedChunks} VideoChunk + ${reEmbedSentences} VideoSentence row(s).`);

  // 5. Drop the status columns from Video (audioUrl stays — it is data, not status)
  for (const col of STATUS_COLUMNS) {
    await pool.query(`ALTER TABLE "Video" DROP COLUMN IF EXISTS "${col}"`);
  }
  console.log(`Dropped ${STATUS_COLUMNS.length} status columns from Video.`);

  const verify = await pool.query(`SELECT count(*) FROM "VideoPipelineStatus"`);
  console.log(`Verification: VideoPipelineStatus rows = ${verify.rows[0].count}`);

  console.log('----------------------------------------');
  console.log('MIGRATION COMPLETE.');

  await pool.end();
}

main().catch((err) => {
  console.error('Migration error:', err);
  process.exit(1);
});