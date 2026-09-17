import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseSilenceDetectOutput, calculateSplitPoints } from '../src/silence.js';

test('parseSilenceDetectOutput extracts starts, ends, and midpoints', () => {
  const sampleStderr = `
[silencedetect @ 000001] silence_start: 62.35
[silencedetect @ 000001] silence_end: 63.15 | silence_duration: 0.8
[silencedetect @ 000001] silence_start: 125.10
[silencedetect @ 000001] silence_end: 126.30 | silence_duration: 1.2
  `;

  const intervals = parseSilenceDetectOutput(sampleStderr);
  assert.equal(intervals.length, 2);
  assert.equal(intervals[0].start, 62.35);
  assert.equal(intervals[0].end, 63.15);
  assert.equal(intervals[0].mid, 62.75);

  assert.equal(intervals[1].start, 125.1);
  assert.equal(intervals[1].end, 126.3);
  assert.equal(intervals[1].mid, 125.7);
});

test('calculateSplitPoints does not split if audio is shorter than maxChunkSec', () => {
  const splits = calculateSplitPoints(120, [], 60, 180);
  assert.deepEqual(splits, [0, 120]);
});

test('calculateSplitPoints cuts at silence within window', () => {
  const silences = [
    { start: 30, end: 31, mid: 30.5 },
    { start: 100, end: 101, mid: 100.5 }, // inside window [60, 180]
    { start: 220, end: 221, mid: 220.5 }, // inside second window [160.5, 280.5]
  ];

  const splits = calculateSplitPoints(300, silences, 60, 180);
  assert.equal(splits[0], 0);
  assert.equal(splits[1], 100.5);
  assert.equal(splits[2], 220.5);
  assert.equal(splits[splits.length - 1], 300);
});
