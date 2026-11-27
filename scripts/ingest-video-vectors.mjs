#!/usr/bin/env node
/**
 * Resumable Upstash Vector backfill script for Videos (30,000+ videos on Free Tier).
 *
 * Tracks synced hashes in Neon `VideoPipelineStatus.embedding->>'upstashHash'`
 * so re-runs cost 0 Upstash read ops and skip unchanged videos automatically.
 *
 * Usage:
 *   node scripts/ingest-video-vectors.mjs --max-videos 6000 --batch 100
 *   node scripts/ingest-video-vectors.mjs --dry-run --max-videos 50
 */
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { PrismaClient } = require('../apps/backend/node_modules/@prisma/client');

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return;
  const lines = fs.readFileSync(filePath, 'utf8').split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    const val = trimmed.slice(eq + 1).trim().replace(/^['"]|['"]$/g, '');
    if (!process.env[key]) {
      process.env[key] = val;
    }
  }
}

function parseArgs(argv) {
  const opts = {
    batch: 100,
    maxVideos: 6000,
    namespace: '',
    dryRun: false,
    force: false,
    checkChanged: false,
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--batch' && argv[i + 1]) {
      opts.batch = Math.max(1, Math.min(200, parseInt(argv[++i], 10)));
    } else if (a === '--max-videos' && argv[i + 1]) {
      opts.maxVideos = Math.max(1, parseInt(argv[++i], 10));
    } else if (a === '--namespace' && argv[i + 1]) {
      opts.namespace = argv[++i];
    } else if (a === '--dry-run') {
      opts.dryRun = true;
    } else if (a === '--force') {
      opts.force = true;
    } else if (a === '--check-changed') {
      opts.checkChanged = true;
    }
  }
  return opts;
}

function scrubDescription(raw, maxChars = 220) {
  if (!raw) return '';
  const cleaned = String(raw)
    .replace(/<!--[\s\S]*?-->/g, ' ')
    .replace(/https?:\/\/\S+/gi, ' ')
    .replace(/\bwww\.\S+/gi, ' ')
    .replace(/\b[\w.+-]+@[\w-]+\.[\w.-]+\b/g, ' ')
    .replace(/@[\w.-]+/g, ' ')
    .replace(/(?:#[\w-]+(?:\s+|$)){3,}/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (cleaned.length <= maxChars) return cleaned;
  return cleaned.slice(0, maxChars).replace(/\s+\S*$/, '').trim();
}

function extractMetadataHints(meta) {
  if (!meta || typeof meta !== 'object') return '';
  const parts = [];
  for (const key of ['speaker', 'preacher', 'artist', 'book', 'scripture', 'topic']) {
    const val = meta[key];
    if (typeof val === 'string' && val.trim()) {
      parts.push(val.trim());
    } else if (Array.isArray(val)) {
      const joined = val
        .filter((v) => typeof v === 'string' && v.trim().length > 0)
        .slice(0, 4)
        .join(', ');
      if (joined) parts.push(joined);
    }
  }
  return parts.join(', ');
}

function buildDocument(video) {
  const title = (video.title || '').trim();
  const channelName = (video.channelName || '').trim();
  const category = (video.category || '').trim();
  const tags = Array.isArray(video.tags)
    ? video.tags
        .map((t) => String(t || '').replace(/^#/, '').trim())
        .filter((t) => t.length > 0 && t.toLowerCase() !== 'shorts')
        .slice(0, 8)
        .join(', ')
    : '';
  const hints = extractMetadataHints(video.metadata);
  const desc = scrubDescription(video.description, 220);

  const data = [title, channelName, category, tags, hints, desc]
    .filter((p) => p.length > 0)
    .join(' | ');

  const type = video.type === 'SHORT' ? 'SHORT' : 'VIDEO';
  const publishedAtSec = video.publishedAt
    ? Math.floor(new Date(video.publishedAt).getTime() / 1000) || 0
    : 0;

  const metadata = {
    type,
    channelId: video.channelId,
    publishedAt: publishedAtSec,
  };
  if (category) {
    metadata.category = category;
  }

  const hash = createHash('sha256')
    .update(`${data}|${type}|${video.channelId}|${category}`)
    .digest('hex');

  return { id: video.id, data, hash, metadata };
}

async function main() {
  const opts = parseArgs(process.argv);
  loadEnvFile(path.resolve('apps/backend/.env'));
  loadEnvFile(path.resolve('envs/neon.env'));

  const instanceId = (process.env.INSTANCE_ID || 'christian_tube').trim();
  const namespace =
    opts.namespace ||
    (process.env.UPSTASH_VIDEO_VECTOR_NAMESPACE || '').trim() ||
    (instanceId === 'christian_tube' ? 'videos' : `videos_${instanceId}`);

  const restUrl = (
    process.env.UPSTASH_VIDEO_VECTOR_REST_URL ||
    process.env.UPSTASH_VECTOR_REST_URL ||
    ''
  )
    .trim()
    .replace(/\/+$/, '');
  const restToken = (
    process.env.UPSTASH_VIDEO_VECTOR_REST_TOKEN ||
    process.env.UPSTASH_VECTOR_REST_TOKEN ||
    ''
  ).trim();

  if (!opts.dryRun && (!restUrl || !restToken)) {
    console.error('UPSTASH_VIDEO_VECTOR_REST_URL (or UPSTASH_VECTOR_REST_URL) and token are required.');
    process.exit(1);
  }

  const prisma = new PrismaClient();
  try {
    const whereClause =
      opts.force || opts.checkChanged
        ? ''
        : `AND (s.embedding->>'upstashHash' IS NULL OR s.embedding->>'upstashHash' = '')`;

    const rows = await prisma.$queryRawUnsafe(
      `SELECT v.id, v.type, v.title, v.description, v."channelId", v."channelName",
              v.category, v.tags, v.metadata, v."publishedAt",
              s.embedding->>'upstashHash' AS "existingHash"
       FROM "Video" v
       JOIN "Channel" c ON c.id = v."channelId"
       LEFT JOIN "VideoPipelineStatus" s ON s."videoId" = v.id
       WHERE c."isActive" = true
         ${whereClause}
       ORDER BY v."publishedAt" DESC
       LIMIT $1`,
      opts.maxVideos,
    );

    const docs = [];
    for (const row of rows) {
      const doc = buildDocument(row);
      if (!opts.force && row.existingHash === doc.hash) continue;
      docs.push(doc);
    }

    console.log(
      `Found ${rows.length} active candidate video(s); ${docs.length} need Upstash upsert (namespace="${namespace}", dryRun=${opts.dryRun}).`,
    );

    if (opts.dryRun) {
      console.log('Sample document:', JSON.stringify(docs[0] || null, null, 2));
      return;
    }

    const endpoint = `${restUrl}/upsert-data/${encodeURIComponent(namespace)}`;
    let uploaded = 0;

    for (let i = 0; i < docs.length; i += opts.batch) {
      const chunk = docs.slice(i, i + opts.batch);
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${restToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(
          chunk.map((d) => ({ id: d.id, data: d.data, metadata: d.metadata })),
        ),
      });

      if (!res.ok) {
        const errText = await res.text().catch(() => '');
        console.error(`Stopped at ${uploaded} uploaded (${res.status}): ${errText}`);
        if (res.status === 429 || errText.toLowerCase().includes('limit')) {
          console.log('Daily quota reached; re-run tomorrow to resume automatically.');
          break;
        }
        process.exit(1);
      }

      const ids = chunk.map((d) => d.id);
      const hashes = chunk.map((d) => d.hash);
      await prisma.$executeRawUnsafe(
        `INSERT INTO "VideoPipelineStatus" ("videoId", "embedding", "updatedAt")
         SELECT v.id, jsonb_build_object('upstashHash', u.hash), CURRENT_TIMESTAMP
         FROM unnest($1::text[], $2::text[]) AS u(id, hash)
         JOIN "Video" v ON v.id = u.id
         ON CONFLICT ("videoId") DO UPDATE SET
           "embedding" = COALESCE("VideoPipelineStatus"."embedding", '{}'::jsonb)
                         || jsonb_build_object('upstashHash', EXCLUDED."embedding"->>'upstashHash'),
           "updatedAt" = CURRENT_TIMESTAMP`,
        ids,
        hashes,
      );

      uploaded += chunk.length;
      if (uploaded % 500 === 0 || i + opts.batch >= docs.length) {
        console.log(`Uploaded ${uploaded}/${docs.length} videos to namespace "${namespace}".`);
      }
    }

    console.log(`Done! Uploaded ${uploaded} video(s).`);
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((err) => {
  console.error('[Video Vector Ingest Fatal]', err);
  process.exit(1);
});
