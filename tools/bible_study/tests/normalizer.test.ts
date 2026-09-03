import test from 'node:test';
import assert from 'node:assert/strict';
import {
  normalizeUnicode,
  normalizeSurfaceForm,
  toConceptId,
  isTamil,
  stripTamilClitics,
} from '../src/normalizer.js';

test('normalizeUnicode strips zero-width and invisible characters', () => {
  const dirty = 'தேவன்\u200B\u200C\uFEFF';
  const clean = normalizeUnicode(dirty);
  assert.equal(clean, 'தேவன்');
});

test('normalizeSurfaceForm cleans punctuation edges', () => {
  const punctuated = '“சிருஷ்டித்தார்,”';
  const cleaned = normalizeSurfaceForm(punctuated);
  assert.equal(cleaned, 'சிருஷ்டித்தார்');
});

test('toConceptId formats snake_case slug', () => {
  assert.equal(toConceptId('Theological Creation'), 'theological_creation');
  assert.equal(toConceptId('ஆதியிலே!'), 'concept'); // Tamil slug fallback
  assert.equal(toConceptId('tohu-bohu_state'), 'tohu_bohu_state');
});

test('isTamil detects Tamil script correctly', () => {
  assert.equal(isTamil('ஆதியாகமம்'), true);
  assert.equal(isTamil('Genesis'), false);
  assert.equal(isTamil('בראשית'), false);
});

test('stripTamilClitics identifies root candidates', () => {
  const candidates = stripTamilClitics('வானத்தையும்');
  assert.ok(candidates.includes('வானத்தை'));
});
