import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeFeedVerdicts, makeSentenceUnits } from '../src/feed_analyzer.js';
import { ChapterSpekOutputSchema, FeedBatchResponse } from '../src/types.js';
import { OllamaStudyClient } from '../src/ollama_client.js';

// ---------------------------------------------------------------------------
// Sentence-unit partitioning
// ---------------------------------------------------------------------------

test('partitions a chapter into sentence-complete units', () => {
  const verses = [1, 2, 3, 4, 5].map((v) => ({
    verse: v,
    text: v === 3 ? 'And God said. ' : v === 5 ? 'So it was.' : `verse-${v} continued `,
  }));
  const units = makeSentenceUnits({ version_id: 'web', book: 1, book_name: 'Genesis', chapter: 1, verses });
  // units partition 1..5 exactly once
  const covered = units.flatMap((u) => {
    const arr: number[] = [];
    for (let i = u.start; i <= u.end; i++) arr.push(i);
    return arr;
  });
  assert.deepEqual(covered, [1, 2, 3, 4, 5]);
});

test('caps overlong sentences at a clause boundary', () => {
  const verses = Array.from({ length: 10 }, (_, i) => ({
    verse: i + 1,
    text: i === 9 ? 'End.' : 'More words; ',
  }));
  const units = makeSentenceUnits({ version_id: 'web', book: 1, book_name: 'Genesis', chapter: 1, verses }, 3);
  for (const u of units) assert.ok(u.end - u.start + 1 <= 3);
});

// ---------------------------------------------------------------------------
// Feed verdict normalization
// ---------------------------------------------------------------------------

test('normalizes verdicts and drops invalid categories', () => {
  const units = [
    { start: 1, end: 1 },
    { start: 2, end: 3 },
    { start: 4, end: 5 },
  ];
  const raw: FeedBatchResponse = {
    verdicts: [
      { id: 1, include: true, category: 'promise', theme: 'God will bless', speck: ['P', 'K'] },
      { id: 2, include: false, category: 'prophecy', theme: '', speck: [] },
      { id: 3, include: true, category: 'Not_A_Real_Cat', theme: 'x', speck: ['S'] },
    ],
  };
  const out = normalizeFeedVerdicts(raw, units);
  assert.equal(out.length, 1);
  assert.equal(out[0].start, 1);
  assert.equal(out[0].end, 1);
  assert.ok(out[0].speck.includes('P'));
});

test('throws on missing/duplicated ids (coverage guard)', () => {
  const units = [
    { start: 1, end: 1 },
    { start: 2, end: 3 },
  ];
  assert.throws(() => normalizeFeedVerdicts({ verdicts: [{ id: 1, include: true }] }, units), /Coverage/);
  assert.throws(() => normalizeFeedVerdicts({ verdicts: [{ id: 1, include: true }, { id: 1, include: false }] }, units), /Coverage/);
});

// ---------------------------------------------------------------------------
// JSON parsing (Ollama output tolerant parse)
// ---------------------------------------------------------------------------

test('parseJson strips markdown fences', () => {
  const parsed = OllamaStudyClient.parseJson('```json\n{"a": 1}\n```');
  assert.deepEqual(parsed, { a: 1 });
});

test('parseJson salvages object embedded in prose', () => {
  const parsed = OllamaStudyClient.parseJson('Ok here is the result {"terms": []} hope that helps');
  assert.deepEqual(parsed, { terms: [] });
});

// ---------------------------------------------------------------------------
// Schema validation (Zod)
// ---------------------------------------------------------------------------

test('Spek output accepts bilingual glossary', () => {
  const out = {
    chapter_summary: 'Test',
    certainty: 'probable',
    verses: [
      {
        v: 1,
        speck: { S: '', P: 'I will be with you', E: '', C: '', K: 'God is faithful' },
        glossary: [{ term: 'Enmity', en: 'Enmity', ta: 'பகை', strongs: 'H342' }],
      },
    ],
  };
  const parsed = ChapterSpekOutputSchema.parse(out);
  assert.equal(parsed.verses.length, 1);
  assert.equal(parsed.verses[0].glossary[0].ta, 'பகை');
});