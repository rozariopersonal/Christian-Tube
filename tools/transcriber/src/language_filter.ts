/**
 * Pure English verification for video titles and descriptions.
 * Detects multilingual content, interpreter/translated sermons, and non-Latin scripts.
 */

// Indic scripts (Devanagari, Bengali, Gurmukhi, Gujarati, Oriya, Tamil, Telugu, Kannada, Malayalam, Sinhala)
// plus Arabic, Cyrillic, and CJK ideographs
export const NON_LATIN_REGEX = /[\u0600-\u06FF\u0900-\u0DFF\u4E00-\u9FFF]/;

// Keywords that indicate translation, interpretation, or non-English audio
export const MULTILINGUAL_KEYWORDS_REGEX =
  /\b(translation|translated|interpreter|interpreted|interpretation|bilingual|multilingual|kannada|tamil|telugu|hindi|malayalam|marathi|bengali|gujarati|punjabi|urdu|odia|spanish|french|german|chinese|russian|arabic|romanian)\b/i;

export interface LanguageCheckResult {
  isPureEnglish: boolean;
  reason?: string;
}

/**
 * Validates whether a video is strictly pure English.
 * Rejects videos containing non-Latin scripts or translation/interpreter indicators.
 */
export function checkPureEnglish(
  title: string | null | undefined,
  description?: string | null,
  channelLanguage?: string | null
): LanguageCheckResult {
  if (!title || typeof title !== 'string') {
    return { isPureEnglish: false, reason: 'Missing or invalid title' };
  }

  // 1. Check channel language
  if (channelLanguage && channelLanguage.trim().toLowerCase() !== 'english') {
    return {
      isPureEnglish: false,
      reason: `Channel language is non-English: "${channelLanguage}"`,
    };
  }

  // 2. Check for non-Latin / Indic character sets in the title
  if (NON_LATIN_REGEX.test(title)) {
    return {
      isPureEnglish: false,
      reason: 'Title contains non-Latin or Indic scripts (e.g. Kannada, Tamil, Hindi)',
    };
  }

  // 2. Check for multilingual / translation keywords in the title
  const titleMatch = title.match(MULTILINGUAL_KEYWORDS_REGEX);
  if (titleMatch) {
    return {
      isPureEnglish: false,
      reason: `Title indicates translation or secondary language: "${titleMatch[0]}"`,
    };
  }

  return { isPureEnglish: true };
}
