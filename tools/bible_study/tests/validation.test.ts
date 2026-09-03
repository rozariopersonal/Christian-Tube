import test from 'node:test';
import assert from 'node:assert/strict';
import { ChapterOutputSchema } from '../src/types.js';

test('validates correct chapter output schema', () => {
  const valid = {
    version_id: 'ta_ovbsi',
    book: 1,
    book_name: 'ஆதியாகமம்',
    chapter: 1,
    chapter_summary: 'தேவன் வானத்தையும் பூமியையும் சிருஷ்டித்த அதிகாரத்தின் விவரம்.',
    terms: [
      {
        reference: { book: 1, chapter: 1, verse: 1 },
        surface_forms: ['சிருஷ்டித்தார்'],
        lemma: 'சிருஷ்டித்தல்',
        concept_id: 'theological_creation',
        concept_name: 'சிருஷ்டி',
        category: 'theological_term',
        importance: 'high',
        dictionary_worthy: true,
        contemporary_language: 'படைத்தார்',
        definition: 'இல்லாமையிலிருந்து உண்டாக்குதல்.',
        biblical_meaning: 'தேவனுடைய பிரத்தியேக படைப்பு செயல்.',
        original_language: {
          language: 'Hebrew',
          lemma: 'בָּרָא',
          transliteration: 'bara',
          strongs: 'H1254',
          lexical_meaning: 'to create',
        },
        notes: null,
      },
    ],
  };

  const parsed = ChapterOutputSchema.safeParse(valid);
  assert.equal(parsed.success, true);
});

test('sanitizes invalid Strong\'s numbers to null', () => {
  const invalidStrongs = {
    version_id: 'ta_ovbsi',
    book: 1,
    book_name: 'ஆதியாகமம்',
    chapter: 1,
    chapter_summary: 'Summary text here.',
    terms: [
      {
        reference: { book: 1, chapter: 1, verse: 1 },
        surface_forms: ['சிருஷ்டித்தார்'],
        lemma: 'சிருஷ்டித்தல்',
        concept_id: 'theological_creation',
        concept_name: 'சிருஷ்டி',
        category: 'theological_term',
        importance: 'high',
        dictionary_worthy: true,
        definition: 'Definition text here.',
        original_language: {
          language: 'Hebrew',
          lemma: 'בָּரָא',
          strongs: 'INVALID123', // Must start with H or G followed by digits
        },
      },
    ],
  };

  const parsed = ChapterOutputSchema.parse(invalidStrongs);
  assert.equal(parsed.terms[0].original_language?.strongs, null);
});

test('auto-heals unsupported categories to biblical_concept', () => {
  const invalidCategory = {
    version_id: 'ta_ovbsi',
    book: 1,
    book_name: 'ஆதியாகமம்',
    chapter: 1,
    chapter_summary: 'Summary text here.',
    terms: [
      {
        reference: { book: 1, chapter: 1, verse: 1 },
        surface_forms: ['சிருஷ்டித்தார்'],
        lemma: 'சிருஷ்டித்தல்',
        concept_id: 'theological_creation',
        concept_name: 'சிருஷ்டி',
        category: 'unsupported_category_type',
        importance: 'high',
        dictionary_worthy: true,
        definition: 'Definition text here.',
      },
    ],
  };

  const parsed = ChapterOutputSchema.parse(invalidCategory);
  assert.equal(parsed.terms[0].category, 'biblical_concept');
});
