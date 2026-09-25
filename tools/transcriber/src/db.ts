import pg from 'pg';
import { VideoRow, TranscriberConfig, SentenceSegment } from './types.js';

const { Pool } = pg;

export function createDbPool(connectionString: string): pg.Pool {
  return new Pool({
    connectionString,
    max: 5,
    idleTimeoutMillis: 30000,
  });
}

export async function ensureSchema(pool: pg.Pool): Promise<void> {
  const steps: [string, string][] = [
    [
      "VideoPipelineStatus table",
      `CREATE TABLE IF NOT EXISTS "VideoPipelineStatus" (
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
       );
       CREATE INDEX IF NOT EXISTS "VideoPipelineStatus_transcription_status_idx"
         ON "VideoPipelineStatus" ((transcription->>'status'))
         WHERE transcription->>'status' IN ('pending', 'failed');`,
    ],
    [
      "Transcription table",
      `CREATE TABLE IF NOT EXISTS "Transcription" (
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
       );
       CREATE INDEX IF NOT EXISTS "Transcription_contentVersion_idx"
         ON "Transcription"("contentVersion");`,
    ],
  ];
  for (const [name, sql] of steps) {
    try {
      await pool.query(sql);
    } catch (err: any) {
      console.warn(`[Transcriber DB] ${name} warning: ${err.message}`);
    }
  }
}

export async function releaseStaleProcessing(pool: pg.Pool): Promise<number> {
  try {
    const res = await pool.query(
      `UPDATE "VideoPipelineStatus"
       SET "transcription" = COALESCE("transcription", '{}'::jsonb) || '{"status":"pending"}'::jsonb,
           "updatedAt" = CURRENT_TIMESTAMP
       WHERE "transcription"->>'status' = 'processing'`
    );
    if ((res.rowCount ?? 0) > 0) {
      console.log(`[Transcriber DB] Released ${res.rowCount} stale processing video(s)`);
    }
    return res.rowCount ?? 0;
  } catch (err: any) {
    console.warn(`[Transcriber DB] releaseStaleProcessing warning: ${err.message}`);
    return 0;
  }
}

export async function fetchEligibleVideos(
  pool: pg.Pool,
  cfg: TranscriberConfig
): Promise<VideoRow[]> {
  const query = `
    SELECT v.id, v.title, v.description, v."audioUrl", v.duration, v."channelId", c.language AS "channelLanguage"
    FROM "Video" v
    JOIN "Channel" c ON c.id = v."channelId"
    LEFT JOIN "VideoPipelineStatus" s ON s."videoId" = v.id
    LEFT JOIN (
        SELECT "channelId", COUNT(*) AS video_count
        FROM "Video"
        GROUP BY "channelId"
    ) vc ON vc."channelId" = v."channelId"
    WHERE (c."isActive" = true OR c."isActive" IS NULL)
      AND c.id != 'UC_ChristianTubeOfficial'
      AND (v."duration" IS NULL OR (v."duration" != '0:00' AND v."duration" NOT LIKE '0:0%'))
      AND COALESCE(s.ingest->>'status', 'pending') = 'completed'
      AND v."audioUrl" IS NOT NULL
      AND COALESCE(s.transcription->>'status', 'pending') IN ('pending', 'failed')
      AND (NULLIF(s.transcription->>'retryCount', '')::integer IS NULL
           OR NULLIF(s.transcription->>'retryCount', '')::integer < $1)
    ORDER BY
      CASE WHEN v."channelId" = ANY($2::text[]) THEN 0 ELSE 1 END,
      CASE c.language
        WHEN 'Tamil' THEN 0
        WHEN 'English' THEN 1
        ELSE 2
      END,
      vc.video_count DESC,
      v."publishedAt" DESC
    LIMIT $3;
  `;

  const res = await pool.query(query, [
    cfg.maxRetries,
    cfg.priorityChannelIds,
    cfg.batchLimit,
  ]);

  return res.rows.map((r) => ({
    id: r.id,
    title: r.title,
    description: r.description,
    audioUrl: r.audioUrl,
    duration: r.duration,
    channelId: r.channelId,
    channelLanguage: r.channelLanguage,
  }));
}

export async function fetchOneVideo(
  pool: pg.Pool,
  videoId: string
): Promise<VideoRow | null> {
  const res = await pool.query(
    `SELECT id, title, description, "audioUrl", duration, "channelId"
     FROM "Video" WHERE id = $1`,
    [videoId]
  );
  if (res.rows.length === 0) return null;
  const r = res.rows[0];
  return {
    id: r.id,
    title: r.title,
    description: r.description,
    audioUrl: r.audioUrl,
    duration: r.duration,
    channelId: r.channelId,
  };
}

export async function markProcessing(pool: pg.Pool, videoId: string): Promise<void> {
  await pool.query(
    `INSERT INTO "VideoPipelineStatus" ("videoId", "transcription", "updatedAt")
     VALUES ($1, $2::jsonb, CURRENT_TIMESTAMP)
     ON CONFLICT ("videoId") DO UPDATE SET
       "transcription" = COALESCE("VideoPipelineStatus"."transcription", '{}'::jsonb) || EXCLUDED."transcription",
       "updatedAt" = CURRENT_TIMESTAMP`,
    [videoId, JSON.stringify({ status: 'processing', progress: 5, lastError: null })]
  );
}

export async function updateProgress(
  pool: pg.Pool,
  videoId: string,
  progress: number
): Promise<void> {
  const safe = Math.min(99, Math.max(1, Math.round(progress)));
  await pool.query(
    `INSERT INTO "VideoPipelineStatus" ("videoId", "transcription", "updatedAt")
     VALUES ($1, jsonb_build_object('progress', $2), CURRENT_TIMESTAMP)
     ON CONFLICT ("videoId") DO UPDATE SET
       "transcription" = COALESCE("VideoPipelineStatus"."transcription", '{}'::jsonb) || jsonb_build_object('progress', $2),
       "updatedAt" = CURRENT_TIMESTAMP`,
    [videoId, safe]
  );
}

export interface TranscriptionRow {
  videoId: string;
  transcript: string;
  source: string;
  contentVersion: number;
  wordCount: number | null;
  segmentCount: number | null;
  maxSec: number | null;
}

export function transcriptionRowFromItem(item: BatchCompletedItem): TranscriptionRow {
  return {
    videoId: item.videoId,
    transcript: item.transcript,
    source: item.detail.source || 'parakeet',
    contentVersion: item.contentVersion,
    wordCount: item.detail.wordCount ?? null,
    segmentCount: item.detail.segmentCount ?? null,
    maxSec: item.detail.maxSec ?? null,
  };
}

export async function upsertTranscription(pool: pg.Pool, row: TranscriptionRow): Promise<void> {
  await pool.query(
    `INSERT INTO "Transcription" ("videoId", "content", "source", "contentVersion", "wordCount", "segmentCount", "maxSec", "createdAt", "updatedAt")
     VALUES ($1, $2, $3, $4, $5, $6, $7, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
     ON CONFLICT ("videoId") DO UPDATE SET
       "content" = EXCLUDED."content",
       "source" = EXCLUDED."source",
       "contentVersion" = EXCLUDED."contentVersion",
       "wordCount" = EXCLUDED."wordCount",
       "segmentCount" = EXCLUDED."segmentCount",
       "maxSec" = EXCLUDED."maxSec",
       "updatedAt" = CURRENT_TIMESTAMP`,
    [row.videoId, row.transcript, row.source, row.contentVersion, row.wordCount, row.segmentCount, row.maxSec]
  );
}

export async function hasTranscription(
  pool: pg.Pool,
  videoId: string,
  contentVersion: number
): Promise<{ transcript: string | null; source: string | null }> {
  const res = await pool.query(
    `SELECT "content", "source", "contentVersion"
     FROM "Transcription"
     WHERE "videoId" = $1
       AND "contentVersion" >= $2
       AND length("content") > 0
     LIMIT 1`,
    [videoId, contentVersion]
  );
  if (res.rows.length === 0) return { transcript: null, source: null };
  return {
    transcript: res.rows[0].content as string,
    source: res.rows[0].source as string | null,
  };
}

export async function markCompleted(
  pool: pg.Pool,
  videoId: string,
  transcript: string,
  detail: Record<string, any>,
  contentVersion: number
): Promise<void> {
  await upsertTranscription(pool, {
    videoId,
    transcript,
    source: detail.source || 'parakeet',
    contentVersion,
    wordCount: detail.wordCount ?? null,
    segmentCount: detail.segmentCount ?? null,
    maxSec: detail.maxSec ?? null,
  });

  await pool.query(
    `INSERT INTO "VideoPipelineStatus" ("videoId", "contentVersion", "transcription", "chunk", "updatedAt")
     VALUES ($1, $2, $3::jsonb, $4::jsonb, CURRENT_TIMESTAMP)
     ON CONFLICT ("videoId") DO UPDATE SET
       "contentVersion" = EXCLUDED."contentVersion",
       "transcription" = COALESCE("VideoPipelineStatus"."transcription", '{}'::jsonb) || EXCLUDED."transcription",
       "chunk" = COALESCE("VideoPipelineStatus"."chunk", '{}'::jsonb) || EXCLUDED."chunk",
       "updatedAt" = CURRENT_TIMESTAMP`,
    [
      videoId,
      contentVersion,
      JSON.stringify({ status: 'completed', progress: 100, retryCount: 0, detail, lastError: null }),
      JSON.stringify({ status: 'pending', error: null, retryCount: 0 }),
    ]
  );
}

export async function markFailed(
  pool: pg.Pool,
  videoId: string,
  error: string
): Promise<void> {
  await pool.query(
    `INSERT INTO "VideoPipelineStatus" ("videoId", "transcription", "updatedAt")
     VALUES ($1, jsonb_build_object('status', 'failed', 'lastError', $2, 'retryCount', 1), CURRENT_TIMESTAMP)
     ON CONFLICT ("videoId") DO UPDATE SET
       "transcription" = jsonb_build_object(
         'status', 'failed',
         'lastError', $2,
         'retryCount', COALESCE(NULLIF("VideoPipelineStatus"."transcription"->>'retryCount', '')::integer, 0) + 1),
       "updatedAt" = CURRENT_TIMESTAMP`,
    [videoId, error.slice(0, 2000)]
  );
}

export interface BatchCompletedItem {
  videoId: string;
  transcript: string;
  detail: Record<string, any>;
  contentVersion: number;
  segments?: SentenceSegment[];
}

export interface BatchSkippedItem {
  videoId: string;
  reason?: string;
  channelLanguage?: string | null;
  contentVersion: number;
}

export async function batchSaveSentences(
  pool: pg.Pool,
  items: { videoId: string; segments?: SentenceSegment[] }[]
): Promise<number> {
  const allSentences: { id: string; videoId: string; seq: number; text: string; start: number; end: number }[] = [];
  for (const item of items) {
    if (!item.segments || item.segments.length === 0) continue;
    item.segments.forEach((seg, seq) => {
      allSentences.push({
        id: `${item.videoId}_s${seq}`,
        videoId: item.videoId,
        seq,
        text: seg.text,
        start: seg.start,
        end: seg.end,
      });
    });
  }
  if (allSentences.length === 0) return 0;

  const CHUNK_SIZE = 400;
  for (let i = 0; i < allSentences.length; i += CHUNK_SIZE) {
    const chunk = allSentences.slice(i, i + CHUNK_SIZE);
    const valuePlaceholders: string[] = [];
    const params: any[] = [];
    chunk.forEach((s, idx) => {
      const base = idx * 6;
      valuePlaceholders.push(`($${base + 1}, $${base + 2}, $${base + 3}::integer, $${base + 4}, $${base + 5}::double precision, $${base + 6}::double precision, 'pending')`);
      params.push(s.id, s.videoId, s.seq, s.text, s.start, s.end);
    });

    const sql = `
      INSERT INTO "VideoSentence" ("id", "videoId", "seq", "text", "startSec", "endSec", "embeddingStatus")
      VALUES ${valuePlaceholders.join(',\n')}
      ON CONFLICT ("videoId", "seq") DO UPDATE SET
        "text" = EXCLUDED."text",
        "startSec" = EXCLUDED."startSec",
        "endSec" = EXCLUDED."endSec",
        "embeddingStatus" = 'pending';
    `;
    await pool.query(sql, params);
  }
  return allSentences.length;
}

export async function batchMarkCompleted(
  pool: pg.Pool,
  items: BatchCompletedItem[]
): Promise<number> {
  if (items.length === 0) return 0;

  const rows = items.map(transcriptionRowFromItem);

  // 1. Upsert transcripts into the Transcription table (multi-row)
  const transValuePlaceholders: string[] = [];
  const transParams: any[] = [];
  rows.forEach((row, idx) => {
    const base = idx * 7;
    transValuePlaceholders.push(
      `($${base + 1}, $${base + 2}, $${base + 3}, $${base + 4}::integer, $${base + 5}::integer, $${base + 6}::integer, $${base + 7}::double precision)`
    );
    transParams.push(
      row.videoId,
      row.transcript,
      row.source,
      row.contentVersion,
      row.wordCount,
      row.segmentCount,
      row.maxSec
    );
  });

  await pool.query(
    `INSERT INTO "Transcription" ("videoId", "content", "source", "contentVersion", "wordCount", "segmentCount", "maxSec", "createdAt", "updatedAt")
     VALUES ${transValuePlaceholders.join(', ')}
     ON CONFLICT ("videoId") DO UPDATE SET
       "content" = EXCLUDED."content",
       "source" = EXCLUDED."source",
       "contentVersion" = EXCLUDED."contentVersion",
       "wordCount" = EXCLUDED."wordCount",
       "segmentCount" = EXCLUDED."segmentCount",
       "maxSec" = EXCLUDED."maxSec",
       "updatedAt" = CURRENT_TIMESTAMP`,
    transParams
  );

  // 2. Batch upsert per-video pipeline status (transcription + chunk + contentVersion)
  const valuePlaceholders: string[] = [];
  const params: any[] = [];

  items.forEach((item, idx) => {
    const base = idx * 4;
    valuePlaceholders.push(
      `($${base + 1}, $${base + 2}::integer, $${base + 3}::jsonb, $${base + 4}::jsonb)`
    );
    params.push(
      item.videoId,
      item.contentVersion,
      JSON.stringify({
        status: 'completed',
        progress: 100,
        retryCount: 0,
        detail: item.detail,
        lastError: null,
      }),
      JSON.stringify({ status: 'pending', error: null, retryCount: 0 })
    );
  });

  await pool.query(
    `INSERT INTO "VideoPipelineStatus" ("videoId", "contentVersion", "transcription", "chunk", "updatedAt")
     VALUES ${valuePlaceholders.join(', ')}
     ON CONFLICT ("videoId") DO UPDATE SET
       "contentVersion" = EXCLUDED."contentVersion",
       "transcription" = COALESCE("VideoPipelineStatus"."transcription", '{}'::jsonb) || EXCLUDED."transcription",
       "chunk" = COALESCE("VideoPipelineStatus"."chunk", '{}'::jsonb) || EXCLUDED."chunk",
       "updatedAt" = CURRENT_TIMESTAMP`,
    params
  );

  return items.length;
}

export async function batchMarkSkipped(
  pool: pg.Pool,
  items: BatchSkippedItem[]
): Promise<number> {
  if (items.length === 0) return 0;

  const valuePlaceholders: string[] = [];
  const params: any[] = [];

  items.forEach((item, idx) => {
    const base = idx * 4;
    const detail = {
      skipped: true,
      reason: item.reason,
      channelLanguage: item.channelLanguage,
    };
    valuePlaceholders.push(
      `($${base + 1}, $${base + 2}::integer, $${base + 3}::jsonb, $${base + 4}::jsonb)`
    );
    params.push(
      item.videoId,
      item.contentVersion,
      JSON.stringify({
        status: 'completed',
        progress: 100,
        retryCount: 0,
        detail,
        lastError: null,
      }),
      JSON.stringify({ status: 'pending', error: null, retryCount: 0 })
    );
  });

  await pool.query(
    `INSERT INTO "VideoPipelineStatus" ("videoId", "contentVersion", "transcription", "chunk", "updatedAt")
     VALUES ${valuePlaceholders.join(', ')}
     ON CONFLICT ("videoId") DO UPDATE SET
       "contentVersion" = EXCLUDED."contentVersion",
       "transcription" = COALESCE("VideoPipelineStatus"."transcription", '{}'::jsonb) || EXCLUDED."transcription",
       "chunk" = COALESCE("VideoPipelineStatus"."chunk", '{}'::jsonb) || EXCLUDED."chunk",
       "updatedAt" = CURRENT_TIMESTAMP`,
    params
  );

  return items.length;
}

