import pg from 'pg';
import * as dotenv from 'dotenv';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'node:url';

// Load envs if not set — walk up to the monorepo root looking for envs/neon.env
if (!process.env.DATABASE_URL) {
  let dir = path.dirname(fileURLToPath(import.meta.url));
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

  console.log('=== NEON DB TRANSCRIPTION RESET TOOL ===');
  console.log(`Connecting to: ${validDbUrl.replace(/:[^:@]+@/, ':****@')}`);
  console.log(`Mode: ${isApply ? 'APPLY (MUTATING DATABASE)' : 'DRY RUN (Preview only - pass --apply to execute)'}`);
  console.log('----------------------------------------');

  // 1. Inspect current status
  const totalRes = await pool.query('SELECT count(*) FROM "Video"');
  console.log(`Total videos in database: ${totalRes.rows[0].count}`);

  const statusRes = await pool.query(`
    SELECT transcription->>'status' AS status, count(*)
    FROM "VideoPipelineStatus"
    GROUP BY transcription->>'status'
  `);
  console.log('Current transcription status breakdown:');
  for (const r of statusRes.rows) {
    console.log(`  - ${r.status || 'NULL(effective pending)'}: ${r.count}`);
  }

  const detailRes = await pool.query(`SELECT count(*) FROM "VideoPipelineStatus" WHERE transcription ? 'detail'`);
  console.log(`Videos with transcription detail: ${detailRes.rows[0].count}`);

  const transcriptionRes = await pool.query('SELECT count(*) FROM "Transcription"');
  console.log(`Total Transcription rows: ${transcriptionRes.rows[0].count}`);

  const chunkRes = await pool.query('SELECT count(*) FROM "VideoChunk"');
  console.log(`Total VideoChunk records: ${chunkRes.rows[0].count}`);

  const embeddingRes = await pool.query('SELECT count(*) FROM "VideoEmbedding"');
  console.log(`Total VideoEmbedding records: ${embeddingRes.rows[0].count}`);

  const audioReady = await pool.query(`
    SELECT count(*)
    FROM "Video" v
    LEFT JOIN "VideoPipelineStatus" s ON s."videoId" = v.id
    WHERE COALESCE(s.ingest->>'status', 'pending') = 'completed' AND v."audioUrl" IS NOT NULL
  `);
  console.log(`Videos with completed audio ready for transcription: ${audioReady.rows[0].count}`);

  const englishAudioReady = await pool.query(`
    SELECT count(*)
    FROM "Video" v
    JOIN "Channel" c ON c.id = v."channelId"
    LEFT JOIN "VideoPipelineStatus" s ON s."videoId" = v.id
    WHERE COALESCE(s.ingest->>'status', 'pending') = 'completed'
      AND v."audioUrl" IS NOT NULL
      AND c.language = 'English'
  `);
  console.log(`English videos with completed audio ready for transcription: ${englishAudioReady.rows[0].count}`);

  if (!isApply) {
    console.log('----------------------------------------');
    console.log('DRY RUN COMPLETE. No data was modified.');
    console.log('Run with --apply to perform the reset.');
    await pool.end();
    return;
  }

  console.log('----------------------------------------');
  console.log('EXECUTING RESET...');

  // 1. Delete derived VideoChunk entries
  const delChunks = await pool.query('DELETE FROM "VideoChunk"');
  console.log(`Deleted ${delChunks.rowCount} VideoChunk row(s)`);

  // 2. Delete all VideoEmbedding entries
  const delEmbeddings = await pool.query('DELETE FROM "VideoEmbedding"');
  console.log(`Deleted ${delEmbeddings.rowCount} VideoEmbedding row(s)`);

  // 3. Delete all Transcription + VideoSentence rows
  const delSentences = await pool.query('DELETE FROM "VideoSentence"');
  console.log(`Deleted ${delSentences.rowCount} VideoSentence row(s)`);
  const delTranscriptions = await pool.query('DELETE FROM "Transcription"');
  console.log(`Deleted ${delTranscriptions.rowCount} Transcription row(s)`);

  // 4. Reset pipeline status JSONB columns (transcription, chunk, embedding) + contentVersion
  const resetVideos = await pool.query(`
    INSERT INTO "VideoPipelineStatus" ("videoId", "contentVersion", "transcription", "chunk", "embedding", "updatedAt")
    SELECT v.id, 0, '{"status":"pending"}'::jsonb, '{"status":"pending"}'::jsonb, '{"status":"pending"}'::jsonb, CURRENT_TIMESTAMP
    FROM "Video" v
    ON CONFLICT ("videoId") DO UPDATE SET
      "contentVersion" = 0,
      "transcription" = '{"status":"pending"}'::jsonb,
      "chunk" = '{"status":"pending"}'::jsonb,
      "embedding" = '{"status":"pending"}'::jsonb,
      "updatedAt" = CURRENT_TIMESTAMP
  `);
  console.log(`Reset ${resetVideos.rowCount} Video row(s) to transcription status='pending', embedding status='pending'.`);

  console.log('----------------------------------------');
  console.log('RESET SUCCESSFUL! Verifying post-reset state:');

  const postStatus = await pool.query(`
    SELECT transcription->>'status' AS status, count(*)
    FROM "VideoPipelineStatus"
    GROUP BY transcription->>'status'
  `);
  console.log('New transcription status breakdown:');
  for (const r of postStatus.rows) {
    console.log(`  - ${r.status || 'NULL'}: ${r.count}`);
  }

  const postEmbedStatus = await pool.query(`
    SELECT embedding->>'status' AS status, count(*)
    FROM "VideoPipelineStatus"
    GROUP BY embedding->>'status'
  `);
  console.log('New embedding status breakdown:');
  for (const r of postEmbedStatus.rows) {
    console.log(`  - ${r.status || 'NULL'}: ${r.count}`);
  }

  const postContent = await pool.query('SELECT count(*) FROM "Transcription"');
  console.log(`Transcription rows: ${postContent.rows[0].count}`);

  const postChunks = await pool.query('SELECT count(*) FROM "VideoChunk"');
  console.log(`VideoChunk count: ${postChunks.rows[0].count}`);

  const postEmbeddings = await pool.query('SELECT count(*) FROM "VideoEmbedding"');
  console.log(`VideoEmbedding count: ${postEmbeddings.rows[0].count}`);

  await pool.end();
}

main().catch((err) => {
  console.error('Reset error:', err);
  process.exit(1);
});
