export interface BibleVersionInfo {
  id: string;
  label: string;
  fullName: string;
  language: string;
}

export const BIBLE_VERSIONS: readonly BibleVersionInfo[] = [
  { id: 'nasb', label: 'NASB', fullName: 'New American Standard Bible', language: 'English' },
  { id: 'kjv', label: 'KJV', fullName: 'King James Version', language: 'English' },
  { id: 'asv', label: 'ASV', fullName: 'American Standard Version', language: 'English' },
  { id: 'nlt', label: 'NLT', fullName: 'New Living Translation', language: 'English' },
  { id: 'web', label: 'WEB', fullName: 'World English Bible', language: 'English' },
  { id: 'bbe', label: 'BBE', fullName: 'Bible in Basic English', language: 'English' },
  { id: 'msg', label: 'MSG', fullName: 'The Message', language: 'English' },
  { id: 'ylt', label: 'YLT', fullName: "Young's Literal Translation", language: 'English' },
  { id: 'taobvsi', label: 'தமிழ்', fullName: 'Tamil Old Version (BSI)', language: 'Tamil' },
  { id: 'hin_irv', label: 'हिन्दी', fullName: 'Hindi Indian Revised Version', language: 'Hindi' },
  { id: 'tel_irv', label: 'తెలుగు', fullName: 'Telugu Indian Revised Version', language: 'Telugu' },
  { id: 'mal_irv', label: 'മലയാളം', fullName: 'Malayalam Indian Revised Version', language: 'Malayalam' },
  { id: 'kan_irv', label: 'ಕನ್ನಡ', fullName: 'Kannada Indian Revised Version', language: 'Kannada' },
  { id: 'diodati', label: 'Diodati', fullName: 'Giovanni Diodati Bibbia (1649)', language: 'Italian' },
  { id: 'riveduta', label: 'Riveduta', fullName: 'La Sacra Bibbia Riveduta (1927)', language: 'Italian' },
  { id: 'elberfelder', label: 'Elberfelder', fullName: 'Elberfelder Bibel (1871)', language: 'German' },
  { id: 'elberfelder1905', label: 'Elberfelder 1905', fullName: 'Elberfelder Bibel (1905)', language: 'German' },
  { id: 'luther1545', label: 'Luther 1545', fullName: 'Luther Bibel (1545)', language: 'German' },
  { id: 'martin', label: 'Martin', fullName: 'Bible David Martin (1744)', language: 'French' },
  { id: 'polgdanska', label: 'Gdańska', fullName: 'Biblia Gdańska (1632)', language: 'Polish' },
  { id: 'sse', label: 'SSE', fullName: 'Spanish Sagradas Escrituras (1569)', language: 'Spanish' },
  { id: 'statenvertaling', label: 'Staten', fullName: 'Statenvertaling (1637)', language: 'Dutch' },
  { id: 'wb', label: 'WB', fullName: 'Wycliffe Bible', language: 'English' },
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
