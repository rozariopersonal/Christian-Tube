import { canonicalLanguageCode } from '../../../shared/ui/language-meta';

export interface BibleVersionInfo {
  id: string;
  label: string;
  fullName: string;
  language: string;
}

/**
 * Canonical language code -> ordered Bible version IDs.
 * Used to list and prioritize Bible versions matching the user's language preferences.
 */
export const LANGUAGE_TO_BIBLE_VERSIONS: Readonly<Record<string, readonly string[]>> = {
  en: ['nasb', 'nlt', 'niv', 'amp', 'msg', 'kjv', 'asv', 'web', 'bbe', 'ylt', 'wb'],
  ta: ['taobvsi', 'tam_tcv'],
  hi: ['hin_irv', 'hin_hcv'],
  te: ['tel_irv', 'tel_tcv'],
  ml: ['mal_irv', 'mal_mcv'],
  kn: ['kan_irv', 'kan_kcv'],
  bn: ['ben_bcv'],
  mr: ['mar_mcv'],
  pa: ['pan_pcv'],
  ur: ['urd_ucv'],
  gu: ['guj_irv'],
  as: ['asm_irv'],
  it: ['diodati', 'riveduta'],
  de: ['elberfelder', 'elberfelder1905', 'luther1545'],
  fr: ['martin'],
  pl: ['polgdanska'],
  es: ['sse'],
  nl: ['statenvertaling'],
};

export const BIBLE_VERSION_TO_LANGUAGE: Readonly<Record<string, string>> = Object.entries(
  LANGUAGE_TO_BIBLE_VERSIONS,
).reduce<Record<string, string>>((acc, [lang, ids]) => {
  for (const id of ids) acc[id] = lang;
  return acc;
}, {});

export function getVersionsForLanguages(preferredLanguageCodes: readonly string[]): {
  preferred: BibleVersionInfo[];
  others: BibleVersionInfo[];
} {
  const normalized = preferredLanguageCodes.map((c) => canonicalLanguageCode(c));
  if (normalized.length === 0 || normalized.includes('All')) {
    return { preferred: [...BIBLE_VERSIONS], others: [] };
  }

  const byId = new Map(BIBLE_VERSIONS.map((v) => [v.id, v]));
  const preferred: BibleVersionInfo[] = [];
  const seen = new Set<string>();

  for (const code of normalized) {
    const mappedIds = LANGUAGE_TO_BIBLE_VERSIONS[code] ?? [];
    for (const id of mappedIds) {
      const info = byId.get(id);
      if (info && !seen.has(id)) {
        preferred.push(info);
        seen.add(id);
      }
    }
    // Also include any version whose English language name resolves to this code
    for (const v of BIBLE_VERSIONS) {
      if (!seen.has(v.id) && canonicalLanguageCode(v.language) === code) {
        preferred.push(v);
        seen.add(v.id);
      }
    }
  }

  const others = BIBLE_VERSIONS.filter((v) => !seen.has(v.id));
  return { preferred, others };
}

export const BIBLE_VERSIONS: readonly BibleVersionInfo[] = [
  { id: 'nasb', label: 'NASB', fullName: 'New American Standard Bible', language: 'English' },
  { id: 'nlt', label: 'NLT', fullName: 'New Living Translation', language: 'English' },
  { id: 'niv', label: 'NIV', fullName: 'New International Version (2011)', language: 'English' },
  { id: 'amp', label: 'AMP', fullName: 'Amplified Bible', language: 'English' },
  { id: 'msg', label: 'MSG', fullName: 'The Message', language: 'English' },
  { id: 'kjv', label: 'KJV', fullName: 'King James Version', language: 'English' },
  { id: 'asv', label: 'ASV', fullName: 'American Standard Version', language: 'English' },
  { id: 'web', label: 'WEB', fullName: 'World English Bible', language: 'English' },
  { id: 'bbe', label: 'BBE', fullName: 'Bible in Basic English', language: 'English' },
  { id: 'ylt', label: 'YLT', fullName: "Young's Literal Translation", language: 'English' },
  { id: 'wb', label: 'WB', fullName: 'Wycliffe Bible', language: 'English' },
  { id: 'taobvsi', label: 'தமிழ் (BSI)', fullName: 'Tamil Old Version (BSI)', language: 'Tamil' },
  { id: 'tam_tcv', label: 'தமிழ் (TCV)', fullName: 'Tamil Contemporary Version (TCV)', language: 'Tamil' },
  { id: 'hin_irv', label: 'हिन्दी (IRV)', fullName: 'Hindi Indian Revised Version', language: 'Hindi' },
  { id: 'hin_hcv', label: 'हिन्दी (HCV)', fullName: 'Hindi Contemporary Version (HCV)', language: 'Hindi' },
  { id: 'tel_irv', label: 'తెలుగు (IRV)', fullName: 'Telugu Indian Revised Version', language: 'Telugu' },
  { id: 'tel_tcv', label: 'తెలుగు (TCV)', fullName: 'Telugu Contemporary Version (TCV)', language: 'Telugu' },
  { id: 'mal_irv', label: 'മലയാളം (IRV)', fullName: 'Malayalam Indian Revised Version', language: 'Malayalam' },
  { id: 'mal_mcv', label: 'മലയാളം (MCV)', fullName: 'Malayalam Contemporary Version (MCV)', language: 'Malayalam' },
  { id: 'kan_irv', label: 'ಕನ್ನಡ (IRV)', fullName: 'Kannada Indian Revised Version', language: 'Kannada' },
  { id: 'kan_kcv', label: 'ಕನ್ನಡ (KCV)', fullName: 'Kannada Contemporary Version (KCV)', language: 'Kannada' },
  { id: 'ben_bcv', label: 'বাংলা (BCV)', fullName: 'Bengali Contemporary Version (BCV)', language: 'Bengali' },
  { id: 'mar_mcv', label: 'मराठी (MCV)', fullName: 'Marathi Contemporary Version (MCV)', language: 'Marathi' },
  { id: 'pan_pcv', label: 'ਪੰਜਾਬੀ (PCV)', fullName: 'Punjabi Contemporary Version (PCV)', language: 'Punjabi' },
  { id: 'urd_ucv', label: 'اردو (UCV)', fullName: 'Urdu Contemporary Version (UCV)', language: 'Urdu' },
  { id: 'guj_irv', label: 'ગુજરાતી (IRV)', fullName: 'Gujarati Indian Revised Version', language: 'Gujarati' },
  { id: 'asm_irv', label: 'অসমীয়া (IRV)', fullName: 'Assamese Indian Revised Version', language: 'Assamese' },
  { id: 'diodati', label: 'Diodati', fullName: 'Giovanni Diodati Bibbia (1649)', language: 'Italian' },
  { id: 'riveduta', label: 'Riveduta', fullName: 'La Sacra Bibbia Riveduta (1927)', language: 'Italian' },
  { id: 'elberfelder', label: 'Elberfelder', fullName: 'Elberfelder Bibel (1871)', language: 'German' },
  { id: 'elberfelder1905', label: 'Elberfelder 1905', fullName: 'Elberfelder Bibel (1905)', language: 'German' },
  { id: 'luther1545', label: 'Luther 1545', fullName: 'Luther Bibel (1545)', language: 'German' },
  { id: 'martin', label: 'Martin', fullName: 'Bible David Martin (1744)', language: 'French' },
  { id: 'polgdanska', label: 'Gdańska', fullName: 'Biblia Gdańska (1632)', language: 'Polish' },
  { id: 'sse', label: 'SSE', fullName: 'Spanish Sagradas Escrituras (1569)', language: 'Spanish' },
  { id: 'statenvertaling', label: 'Staten', fullName: 'Statenvertaling (1637)', language: 'Dutch' },
];

export const BOOK_ABBREVS: readonly string[] = [
  '',
  'GEN', 'EXO', 'LEV', 'NUM', 'DEU', 'JOS', 'JDG', 'RUT', '1SA', '2SA',
  '1KI', '2KI', '1CH', '2CH', 'EZR', 'NEH', 'EST', 'JOB', 'PSA', 'PRO',
  'ECC', 'SNG', 'ISA', 'JER', 'LAM', 'EZK', 'DAN', 'HOS', 'JOL', 'AMO',
  'OBA', 'JON', 'MIC', 'NAM', 'HAB', 'ZEP', 'HAG', 'ZEC', 'MAL',
  'MAT', 'MRK', 'LUK', 'JHN', 'ACT', 'ROM', '1CO', '2CO', 'GAL', 'EPH',
  'PHP', 'COL', '1TH', '2TH', '1TI', '2TI', 'TIT', 'PHM', 'HEB', 'JAS',
  '1PE', '2PE', '1JN', '2JN', '3JN', 'JUD', 'REV',
];

export interface BibleBook {
  bookNumber: number;
  name: string;
  chapters: number;
}

export interface BibleVerse {
  verse: number;
  text: string;
}

export interface CrossRefTarget {
  bt: string;
  c: number;
  v: number;
  e?: number;
  s?: number;
}

export interface VerseCrossRefs {
  v: number;
  refs: CrossRefTarget[];
}

export interface StudyTerm {
  reference?: { book: number; chapter: number; verse: number };
  surface_forms?: string[];
  lemma?: string;
  concept_id?: string;
  concept_name?: string;
  english_name?: string;
  definition?: string;
  biblical_meaning?: string;
  historical_context?: string;
  citations?: string[];
}

export interface ChapterStudy {
  chapter_summary?: string;
  terms?: StudyTerm[];
}

export interface BibleBookmark {
  key: string; // e.g. "1:1:1"
  bookNumber: number;
  bookName: string;
  chapter: number;
  verse: number;
  text: string;
  createdAt: string;
}

export interface BibleSemanticHit {
  id: string;
  score: number;
  kind?: 'verse' | 'passage';
  bookNumber: number | null;
  bookName: string | null;
  chapter: number | null;
  verse: number | null;
  endVerse?: number | null;
  reference: string;
  text: string;
}

export interface BibleSemanticSearchResponse {
  query: string;
  count: number;
  results: BibleSemanticHit[];
}
