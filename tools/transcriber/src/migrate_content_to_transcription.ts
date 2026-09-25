import pg from 'pg';
import * as dotenv from 'dotenv';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'node:url';

// ./dist or ./src — walk up to the monorepo root to locate envs/neon.env
const currentDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = process.cwd();

if (!process.env.DATABASE_URL) {
  // envs/ is gitignored and not copied into worktrees, so walk up from the
  // current directory toward the monorepo root looking for envs/neon.env.
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

async function main() {
  const isApply = process.argv.includes('--apply');

  console.log('=== MIGRATE Video.content -> Transcription TABLE ===');
  console.log(`Connecting to: ${validDbUrl.replace(/:[^:@]+@/, ':****@')}`);
  console.log(`Mode: ${isApply ? 'APPLY (MUTATING DATABASE)' : 'DRY RUN (Pass --apply to execute)'}`);
  console.log('----------------------------------------');

  const cols = await pool.query(
    `SELECT column_name FROM information_schema.columns WHERE table_name = 'Video' AND column_name = 'content'`
  );
  const hasContentCol = cols.rows.length > 0;
  console.log(`Video.content column exists: ${hasContentCol}`);

  const transExists = await pool.query(
    `SELECT to_regclass('"Transcription"') AS t`
  );
  const transTableExists = transExists.rows[0].t !== null;
  console.log(`Transcription table exists: ${transTableExists}`);

  if (!hasContentCol) {
    const alreadyInTrans = transTableExists
      ? `(SELECT count(*) FROM "Transcription")`
      : `0`;
    const count = await pool.query(`SELECT ${alreadyInTrans} AS c`);
    console.log(`No content column; nothing to migrate. Transcription rows: ${count.rows[0].c}`);
    await pool.end();
    return;
  }

  const alreadyInTrans =
    transTableExists
      ? `(SELECT count(*) FROM "Transcription")`
      : '0';
  const counts = await pool.query(
    `SELECT
       (SELECT count(*) FROM "Video" WHERE "content" IS NOT NULL AND length("content") > 0) AS non_empty,
       (SELECT count(*) FROM "Video" WHERE "content" IS NOT NULL AND length("content") = 0) AS empty,
       ${alreadyInTrans} AS already_in_table`
  );
  console.log(`Videos with non-empty content: ${counts.rows[0].non_empty}`);
  console.log(`Videos with empty-string content (skipped): ${counts.rows[0].empty}`);
  console.log(`Rows already in Transcription: ${counts.rows[0].already_in_table}`);

  if (!isApply) {
    console.log('----------------------------------------');
    console.log('DRY RUN COMPLETE. No data was modified.');
    console.log('Run with --apply to backfill and DROP the Video.content column.');
    await pool.end();
    return;
  }

  console.log('----------------------------------------');
  console.log('EXECUTING MIGRATION...');

  // 1. Ensure Transcription table exists
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "Transcription" (
      "videoId" TEXT NOT NULL PRIMARY KEY,
      "content" TEXT NOT NULL,
      "source" TEXT NOT NULL DEFAULT 'parakeet',
      "contentVersion" INTEGER NOT NULL DEFAULT 0,
      "wordCount" INTEGER,
      "segmentCount" INTEGER,
      "maxSec" DOUBLE PRECISION,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "Transcription_videoId_fkey"
        FOREIGN KEY ("videoId") REFERENCES "Video"("id")
        ON DELETE CASCADE ON UPDATE CASCADE
    )
  `);

  // 2. Backfill non-empty content (millions of rows in one statement)
  const backfill = await pool.query(`
    INSERT INTO "Transcription" ("videoId", "content", "source", "contentVersion", "wordCount", "segmentCount", "maxSec", "createdAt", "updatedAt")
    SELECT
      v.id,
      v."content",
      CASE WHEN v."transcriptionDetail"->>'source' IS NOT NULL THEN v."transcriptionDetail"->>'source'
           ELSE 'parakeet' END,
      COALESCE(v."contentVersion", 0),
      NULLIF(v."transcriptionDetail"->>'wordCount', '')::int,
      NULLIF(v."transcriptionDetail"->>'segmentCount', '')::int,
      NULLIF(v."transcriptionDetail"->>'maxSec', '')::float,
      CURRENT_TIMESTAMP,
      CURRENT_TIMESTAMP
    FROM "Video" v
    WHERE v."content" IS NOT NULL AND length(v."content") > 0
    ON CONFLICT ("videoId") DO UPDATE SET
      "content" = EXCLUDED."content",
      "source" = EXCLUDED."source",
      "contentVersion" = EXCLUDED."contentVersion",
      "wordCount" = EXCLUDED."wordCount",
      "segmentCount" = EXCLUDED."segmentCount",
      "maxSec" = EXCLUDED."maxSec",
      "updatedAt" = CURRENT_TIMESTAMP
  `);
  console.log(`Backfilled ${backfill.rowCount} row(s) into Transcription.`);

  // 3. Drop the content column
  const drop = await pool.query(`ALTER TABLE "Video" DROP COLUMN IF EXISTS "content"`);
  console.log(`Dropped Video.content column (${drop.command === 'ALTER TABLE' ? 'done' : 'noop'}).`);

  const verify = await pool.query(`SELECT count(*) FROM "Transcription"`);
  console.log(`Verification: Transcription rows = ${verify.rows[0].count}`);

  console.log('----------------------------------------');
  console.log('MIGRATION COMPLETE.');

  await pool.end();
}

main().catch((err) => {
  console.error('Migration error:', err);
  process.exit(1);
});