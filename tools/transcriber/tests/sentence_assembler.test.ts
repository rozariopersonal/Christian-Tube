import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  wordsToSentences,
  buildTranscript,
  parseTranscriptSegments,
  fmtTs,
  hasTerminalPunctuation,
} from '../src/sentence_assembler.js';
import { WordTimestamp } from '../src/types.js';

test('fmtTs formats seconds to standard timestamps', () => {
  assert.equal(fmtTs(0), '00:00');
  assert.equal(fmtTs(5.4), '00:05');
  assert.equal(fmtTs(65), '01:05');
  assert.equal(fmtTs(3661), '1:01:01');
});

test('hasTerminalPunctuation identifies sentence endpoints', () => {
  assert.equal(hasTerminalPunctuation('Romans.'), true);
  assert.equal(hasTerminalPunctuation('Amen!'), true);
  assert.equal(hasTerminalPunctuation('Why?'), true);
  assert.equal(hasTerminalPunctuation('Lord."'), true);
  assert.equal(hasTerminalPunctuation('faith)'), false);
  assert.equal(hasTerminalPunctuation('chapter,'), false);
  assert.equal(hasTerminalPunctuation('Jesus'), false);
});

test('wordsToSentences groups by punctuation', () => {
  const words: WordTimestamp[] = [
    { word: 'Grace', start: 0.0, end: 0.5 },
    { word: 'and', start: 0.5, end: 0.8 },
    { word: 'peace', start: 0.8, end: 1.2 },
    { word: 'to', start: 1.2, end: 1.4 },
    { word: 'you.', start: 1.4, end: 1.9 },
    { word: 'The', start: 2.1, end: 2.3 },
    { word: 'Lord', start: 2.3, end: 2.7 },
    { word: 'is', start: 2.7, end: 2.9 },
    { word: 'risen!', start: 2.9, end: 3.5 },
  ];

  const sentences = wordsToSentences(words);
  assert.equal(sentences.length, 2);

  assert.equal(sentences[0].text, 'Grace and peace to you.');
  assert.equal(sentences[0].start, 0.0);
  assert.equal(sentences[0].end, 1.9);

  assert.equal(sentences[1].text, 'The Lord is risen!');
  assert.equal(sentences[1].start, 2.1);
  assert.equal(sentences[1].end, 3.5);
});

test('wordsToSentences splits on long conversational pause even without terminal period', () => {
  const words: WordTimestamp[] = [
    { word: 'We', start: 1.0, end: 1.3 },
    { word: 'must', start: 1.3, end: 1.6 },
    { word: 'listen', start: 1.6, end: 2.0 },
    // 2.5s pause
    { word: 'and', start: 4.5, end: 4.8 },
    { word: 'take', start: 4.8, end: 5.1 },
    { word: 'heed.', start: 5.1, end: 5.5 },
  ];

  const sentences = wordsToSentences(words, 1.8);
  assert.equal(sentences.length, 2);
  assert.equal(sentences[0].text, 'We must listen');
  assert.equal(sentences[0].start, 1.0);
  assert.equal(sentences[0].end, 2.0);

  assert.equal(sentences[1].text, 'and take heed.');
  assert.equal(sentences[1].start, 4.5);
  assert.equal(sentences[1].end, 5.5);
});

test('buildTranscript outputs standard format', () => {
  const sentences = [
    { start: 0.0, end: 5.0, text: 'First sentence.' },
    { start: 5.5, end: 12.3, text: 'Second sentence.' },
  ];

  const transcript = buildTranscript(sentences);
  const lines = transcript.split('\n');
  assert.equal(lines.length, 2);
  assert.equal(lines[0], '[00:00 00:05] First sentence.');
  assert.equal(lines[1], '[00:05 00:12] Second sentence.');
});

test('parseTranscriptSegments extracts start, end, and text accurately', () => {
  const raw = `
# Title
---
[00:00 00:05] First sentence.
[00:05 -> 00:12] Second sentence with arrow.
[01:15 01:20] Third sentence after a minute.
`;
  const parsed = parseTranscriptSegments(raw);
  assert.equal(parsed.length, 3);
  assert.equal(parsed[0].start, 0);
  assert.equal(parsed[0].end, 5);
  assert.equal(parsed[0].text, 'First sentence.');
  assert.equal(parsed[1].start, 5);
  assert.equal(parsed[1].end, 12);
  assert.equal(parsed[1].text, 'Second sentence with arrow.');
  assert.equal(parsed[2].start, 75);
  assert.equal(parsed[2].end, 80);
  assert.equal(parsed[2].text, 'Third sentence after a minute.');
});

