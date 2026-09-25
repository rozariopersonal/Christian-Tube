import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  transcriptionRowFromItem,
  batchMarkCompleted,
  batchMarkSkipped,
  hasTranscription,
} from '../src/db.js';
import type { BatchCompletedItem, BatchSkippedItem } from '../src/db.js';

function mockPool() {
  const calls: any[] = [];
  return {
    calls,
    async query(sql: string, params?: any[]) {
      calls.push({ sql, params });
      return { rowCount: params ? params.length / 3 : 0, rows: [] };
    },
  };
}

describe('transcriptionRowFromItem', () => {
  it('maps a completed item to a Transcription row', () => {
    const item: BatchCompletedItem = {
      videoId: 'vid1',
      transcript: '[00:01 00:02] Hello world.',
      detail: { source: 'parakeet', wordCount: 2, segmentCount: 1, maxSec: 2.5 },
      contentVersion: 3,
      segments: [],
    };
    assert.deepEqual(transcriptionRowFromItem(item), {
      videoId: 'vid1',
      transcript: '[00:01 00:02] Hello world.',
      source: 'parakeet',
      contentVersion: 3,
      wordCount: 2,
      segmentCount: 1,
      maxSec: 2.5,
    });
  });

  it('defaults missing fields and source', () => {
    const item: BatchCompletedItem = {
      videoId: 'vid2',
      transcript: 'x',
      detail: {},
      contentVersion: 1,
    };
    assert.deepEqual(transcriptionRowFromItem(item), {
      videoId: 'vid2',
      transcript: 'x',
      source: 'parakeet',
      contentVersion: 1,
      wordCount: null,
      segmentCount: null,
      maxSec: null,
    });
  });
});

describe('batchMarkCompleted', () => {
  it('writes transcription rows and updates Video status without touching content', async () => {
    const pool: any = mockPool();
    const items: BatchCompletedItem[] = [
      {
        videoId: 'vid1',
        transcript: 't1',
        detail: { source: 'parakeet' },
        contentVersion: 3,
      },
      {
        videoId: 'vid2',
        transcript: 't2',
        detail: { source: 'parakeet' },
        contentVersion: 3,
      },
    ];

    const n = await batchMarkCompleted(pool, items);
    assert.equal(n, 2);
    assert.equal(pool.calls.length, 2);

    // First call: multi-row Transcription upsert (writes content into the new table)
    const insert = pool.calls[0];
    assert.match(insert.sql, /INSERT INTO "Transcription"/);
    assert.match(insert.sql, /ON CONFLICT \("videoId"\)/);
    assert.deepEqual(insert.params, [
      'vid1', 't1', 'parakeet', 3, null, null, null,
      'vid2', 't2', 'parakeet', 3, null, null, null,
    ]);

    // Second call: Video status update must not write the content column
    const update = pool.calls[1];
    assert.match(update.sql, /UPDATE "Video"/);
    assert.ok(!/"content"\s*=/.test(update.sql), 'Video status update must not write content');
    assert.ok(update.sql.includes('"transcriptionStatus"'));
  });
});

describe('batchMarkSkipped', () => {
  it('marks completed without writing an empty content marker', async () => {
    const pool: any = mockPool();
    const items: BatchSkippedItem[] = [
      { videoId: 'vid9', reason: 'non-english', channelLanguage: 'Tamil', contentVersion: 3 },
    ];

    const n = await batchMarkSkipped(pool, items);
    assert.equal(n, 1);
    assert.equal(pool.calls.length, 1);
    const update = pool.calls[0];
    assert.match(update.sql, /UPDATE "Video"/);
    assert.ok(!/"content"\s*=/.test(update.sql), 'skipped update must not write content column');
    assert.equal(update.params[1], JSON.stringify({
      skipped: true,
      reason: 'non-english',
      channelLanguage: 'Tamil',
    }));
  });
});

describe('hasTranscription', () => {
  it('reads an existing transcript from the Transcription table', async () => {
    const calls: any[] = [];
    const pool: any = {
      async query(sql: string, params?: any[]) {
        calls.push({ sql, params });
        return { rows: [{ content: 'existing transcript', source: 'parakeet' }] };
      },
    };
    const result = await hasTranscription(pool, 'vid1', 3);
    assert.deepEqual(result, { transcript: 'existing transcript', source: 'parakeet' });
    assert.match(calls[0].sql, /FROM "Transcription"/);
    assert.ok(calls[0].sql.includes('length("content") > 0'));
    assert.deepEqual(calls[0].params, ['vid1', 3]);
  });

  it('returns null when no transcription exists', async () => {
    const pool: any = { async query() { return { rows: [] }; } };
    assert.deepEqual(await hasTranscription(pool, 'vid1', 3), { transcript: null, source: null });
  });
});