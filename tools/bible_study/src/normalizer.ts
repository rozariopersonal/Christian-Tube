/**
 * Text and Tamil normalization utilities.
 */

// Zero-width characters and invisible format controls
const ZERO_WIDTH_REGEX = /[\u200B-\u200D\uFEFF\u00AD]/g;

/**
 * Applies Unicode NFC normalization and strips invisible zero-width characters.
 */
export function normalizeUnicode(text: string): string {
  if (!text) return '';
  return text.normalize('NFC').replace(ZERO_WIDTH_REGEX, '').trim();
}

/**
 * Normalizes a Tamil or multilingual surface form for dictionary indexing:
 * - Trims whitespace
 * - Unicode NFC
 * - Removes sentence punctuation at edges (.,:;!?"'«»“”)
 */
export function normalizeSurfaceForm(text: string): string {
  const clean = normalizeUnicode(text);
  // Remove leading and trailing punctuation while preserving letters, marks (\p{M}), and numbers
  return clean
    .replace(/^[^\p{L}\p{M}\p{N}]+/u, '')
    .replace(/[^\p{L}\p{M}\p{N}]+$/u, '')
    .trim();
}

/**
 * Generates a clean snake_case slug for concept_id if needed.
 */
export function toConceptId(text: string): string {
  return normalizeUnicode(text)
    .toLowerCase()
    .replace(/[\s\-_]+/g, '_')
    .replace(/[^a-z0-9_]/g, '')
    .replace(/^_+|_+$/g, '') || 'concept';
}

/**
 * Checks if a word is in Tamil script.
 */
export function isTamil(text: string): boolean {
  return /[\u0B80-\u0BFF]/.test(text);
}

/**
 * Strips common Tamil coordinating and emphatic suffixes (-உம், -ஏ, -ஆ, -ஓ, -தான்)
 * for candidate root matching.
 */
export function stripTamilClitics(word: string): string[] {
  const normalized = normalizeSurfaceForm(word);
  const candidates: string[] = [normalized];

  const clitics = [
    { suffix: 'உம்', minLen: 4 },
    { suffix: 'யும்', minLen: 4 },
    { suffix: 'வும்', minLen: 4 },
    { suffix: 'ஏ', minLen: 3 },
    { suffix: 'யே', minLen: 4 },
    { suffix: 'வே', minLen: 4 },
    { suffix: 'தான்', minLen: 5 },
    { suffix: 'தானே', minLen: 6 },
  ];

  for (const { suffix, minLen } of clitics) {
    if (normalized.endsWith(suffix) && normalized.length >= minLen) {
      const stripped = normalized.slice(0, normalized.length - suffix.length);
      if (!candidates.includes(stripped)) {
        candidates.push(stripped);
      }
    }
  }

  return candidates;
}
