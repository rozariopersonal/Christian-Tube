export interface BibleVersionInfo {
  id: string;
  label: string;
  language: string;
}

export const BIBLE_VERSIONS: readonly BibleVersionInfo[] = [
  { id: 'nasb', label: 'NASB', language: 'English' },
  { id: 'kjv', label: 'KJV', language: 'English' },
  { id: 'asv', label: 'ASV', language: 'English' },
  { id: 'nlt', label: 'NLT', language: 'English' },
  { id: 'web', label: 'WEB', language: 'English' },
  { id: 'bbe', label: 'BBE', language: 'English' },
  { id: 'msg', label: 'MSG', language: 'English' },
  { id: 'ylt', label: 'YLT', language: 'English' },
  { id: 'taobvsi', label: 'தமிழ் (TAOBVSI)', language: 'Tamil' },
  { id: 'hin_irv', label: 'हिन्दी (IRV)', language: 'Hindi' },
  { id: 'tel_irv', label: 'తెలుగు (IRV)', language: 'Telugu' },
  { id: 'mal_irv', label: 'മലയാളം (IRV)', language: 'Malayalam' },
  { id: 'kan_irv', label: 'ಕನ್ನಡ (IRV)', language: 'Kannada' },
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
