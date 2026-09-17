import pg from 'pg';
import * as dotenv from 'dotenv';
import * as fs from 'fs';
import * as path from 'path';

// Load envs if not set
if (!process.env.DATABASE_URL) {
  const neonEnvPath = path.resolve(__dirname, '../../../envs/neon.env');
  if (fs.existsSync(neonEnvPath)) {
    dotenv.config({ path: neonEnvPath });
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
    SELECT "transcriptionStatus", count(*) 
    FROM "Video" 
    GROUP BY "transcriptionStatus"
  `);
  console.log('Current transcription status breakdown:');
  for (const r of statusRes.rows) {
    console.log(`  - ${r.transcriptionStatus || 'NULL'}: ${r.count}`);
  }

  const contentRes = await pool.query('SELECT count(*) FROM "Video" WHERE content IS NOT NULL');
  console.log(`Videos with non-null content: ${contentRes.rows[0].count}`);

  const detailRes = await pool.query('SELECT count(*) FROM "Video" WHERE "transcriptionDetail" IS NOT NULL');
  console.log(`Videos with non-null transcriptionDetail: ${detailRes.rows[0].count}`);

  const chunkRes = await pool.query('SELECT count(*) FROM "VideoChunk"');
  console.log(`Total VideoChunk records: ${chunkRes.rows[0].count}`);

  const embeddingRes = await pool.query('SELECT count(*) FROM "VideoEmbedding"');
  console.log(`Total VideoEmbedding records: ${embeddingRes.rows[0].count}`);

  const audioReady = await pool.query(`
    SELECT count(*) 
    FROM "Video" 
    WHERE "audioUploadStatus" = 'completed' AND "audioUrl" IS NOT NULL
  `);
  console.log(`Videos with completed audio ready for transcription: ${audioReady.rows[0].count}`);

  const englishAudioReady = await pool.query(`
    SELECT count(*) 
    FROM "Video" v
    JOIN "Channel" c ON c.id = v."channelId"
    WHERE v."audioUploadStatus" = 'completed' 
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

  // 3. Reset Video fields for transcription, chunking, and embedding
  const resetVideos = await pool.query(`
    UPDATE "Video"
    SET 
      "transcriptionStatus" = 'pending',
      "transcriptionProgress" = NULL,
      "transcriptionRetryCount" = 0,
      "transcriptionDetail" = NULL,
      "lastTranscriptionError" = NULL,
      "content" = NULL,
      "contentVersion" = 0,
      "chunkStatus" = 'pending',
      "chunkError" = NULL,
      "chunkRetryCount" = 0,
      "embeddingStatus" = 'pending',
      "embeddingError" = NULL,
      "embeddingRetryCount" = 0,
      "embeddingVersion" = 0,
      "embeddingHash" = NULL
  `);
  console.log(`Reset ${resetVideos.rowCount} Video row(s) to transcriptionStatus='pending', embeddingStatus='pending', and cleared content.`);

  console.log('----------------------------------------');
  console.log('RESET SUCCESSFUL! Verifying post-reset state:');

  const postStatus = await pool.query(`
    SELECT "transcriptionStatus", count(*) 
    FROM "Video" 
    GROUP BY "transcriptionStatus"
  `);
  console.log('New transcription status breakdown:');
  for (const r of postStatus.rows) {
    console.log(`  - ${r.transcriptionStatus}: ${r.count}`);
  }

  const postEmbedStatus = await pool.query(`
    SELECT "embeddingStatus", count(*) 
    FROM "Video" 
    GROUP BY "embeddingStatus"
  `);
  console.log('New embedding status breakdown:');
  for (const r of postEmbedStatus.rows) {
    console.log(`  - ${r.embeddingStatus}: ${r.count}`);
  }

  const postContent = await pool.query('SELECT count(*) FROM "Video" WHERE content IS NOT NULL');
  console.log(`Videos with content: ${postContent.rows[0].count}`);

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
