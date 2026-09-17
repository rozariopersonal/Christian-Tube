import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildReport } from '../src/reporter.js';

test('buildReport computes correct speed multiplier and density', () => {
  const report = buildReport({
    videoId: 'test_123',
    title: 'Test Sermon on Faith',
    audioDurationSec: 600, // 10 minutes
    downloadTimeMs: 2000,
    inferenceTimeMs: 30000, // 30s
    totalTimeMs: 35000,
    silenceCount: 15,
    chunkCount: 4,
    wordCount: 1200,
    segments: [
      { start: 0.0, end: 5.0, text: 'Hello everyone.' },
      { start: 5.0, end: 12.0, text: 'Let us pray.' },
    ],
  });

  const s = report.summary;
  assert.equal(s.videoId, 'test_123');
  assert.equal(s.durationSec, 600);
  assert.equal(s.duration, '10:00');
  assert.equal(s.downloadTimeSec, 2);
  assert.equal(s.inferenceTimeSec, 30);
  assert.equal(s.speedFactor, '20.0x'); // 600s / 30s = 20.0x
  assert.equal(s.sentenceCount, 2);
  assert.equal(s.wordCount, 1200);
  assert.equal(s.avgWordsPerSentence, 600);
  assert.equal(s.wpm, 120); // 1200 words / 10 mins = 120 WPM
  assert.equal(report.sampleSentences.length, 2);
});
