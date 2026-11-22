export type ReadingOrder = 'daily' | 'random' | 'canonical' | 'bookmarked';
export type TestamentFilter = 'all' | 'ot' | 'nt';
export type TextAlignOption = 'left' | 'center' | 'right';

export interface WordFeedTopic {
  slug: string;
  name: string;
  count: number;
}

export interface WordFeedManifest {
  totalItems: number;
  topTopics: WordFeedTopic[];
}

export interface VerseMappingEntry {
  bookNumber: number;
  chapter: number;
  startVerse: number;
  endVerse?: number;
}

export interface WordComparisonEntry {
  version: string;
  text: string;
}

export interface WordFeedItem {
  id: string;
  dayOfYear?: number;
  bookNumber: number;
  bookName: string;
  chapter: number;
  startVerse: number;
  endVerse?: number;
  referenceLabel: string;
  category?: string;
  theme?: string;
  backgroundPreset?: string;
  tags?: string[];
  verseMappings?: Record<string, VerseMappingEntry>;
  verseText?: string;
  resolvedVersion?: string;
  comparisons?: WordComparisonEntry[];
  isSaved?: boolean;
  customBackgroundPreset?: string;
  customFontFamily?: string;
}

export interface WordsFilterState {
  readingOrder: ReadingOrder;
  activeTopic: string; // 'daily' or topic slug when readingOrder === 'daily'
  testamentFilter: TestamentFilter;
  bookNumberFilter: number | null;
  selectedCategories: string[];
  selectedTags: string[];
}

export interface WordsAppearanceState {
  activeVersionId: string;
  comparisonVersionIds: string[];
  fontSizeScale: number;
  activeFontFamily: string;
  textColorHex: string;
  isBold: boolean;
  isItalic: boolean;
  textAlign: TextAlignOption;
  backgroundPreset: string;
}

export interface CategoryDefinition {
  id: string;
  label: string;
  icon: string;
}

export const CATEGORY_DEFINITIONS: readonly CategoryDefinition[] = [
  { id: 'comfort', label: 'Peace & Comfort', icon: 'spa' },
  { id: 'wisdom', label: 'Wisdom & Guidance', icon: 'lightbulb' },
  { id: 'faith', label: 'Faith & Trust', icon: 'favorite_border' },
  { id: 'salvation', label: 'Salvation & Grace', icon: 'all_inclusive' },
  { id: 'prayer', label: 'Prayer & Consecration', icon: 'self_improvement' },
  { id: 'courage', label: 'Courage & Strength', icon: 'shield' },
  { id: 'praise', label: 'Praise & Worship', icon: 'celebration' },
  { id: 'doctrine', label: 'Doctrine & Truth', icon: 'menu_book' },
];

export const TAG_DEFINITIONS: readonly string[] = [
  'anxiety_fear',
  'courage',
  'faith',
  'god_character',
  'comfort',
  'praise',
  'wisdom',
  'prayer',
  'doctrine',
  'consecration',
  'promises',
  'hope',
  'healing',
  'forgiveness',
  'patience',
];

export interface BibleBookEntry {
  bookNumber: number;
  name: string;
  testament: 'ot' | 'nt';
}

export const BIBLE_BOOK_LIST: readonly BibleBookEntry[] = [
  { bookNumber: 1, name: 'Genesis', testament: 'ot' },
  { bookNumber: 2, name: 'Exodus', testament: 'ot' },
  { bookNumber: 3, name: 'Leviticus', testament: 'ot' },
  { bookNumber: 4, name: 'Numbers', testament: 'ot' },
  { bookNumber: 5, name: 'Deuteronomy', testament: 'ot' },
  { bookNumber: 6, name: 'Joshua', testament: 'ot' },
  { bookNumber: 7, name: 'Judges', testament: 'ot' },
  { bookNumber: 8, name: 'Ruth', testament: 'ot' },
  { bookNumber: 9, name: '1 Samuel', testament: 'ot' },
  { bookNumber: 10, name: '2 Samuel', testament: 'ot' },
  { bookNumber: 11, name: '1 Kings', testament: 'ot' },
  { bookNumber: 12, name: '2 Kings', testament: 'ot' },
  { bookNumber: 13, name: '1 Chronicles', testament: 'ot' },
  { bookNumber: 14, name: '2 Chronicles', testament: 'ot' },
  { bookNumber: 15, name: 'Ezra', testament: 'ot' },
  { bookNumber: 16, name: 'Nehemiah', testament: 'ot' },
  { bookNumber: 17, name: 'Esther', testament: 'ot' },
  { bookNumber: 18, name: 'Job', testament: 'ot' },
  { bookNumber: 19, name: 'Psalms', testament: 'ot' },
  { bookNumber: 20, name: 'Proverbs', testament: 'ot' },
  { bookNumber: 21, name: 'Ecclesiastes', testament: 'ot' },
  { bookNumber: 22, name: 'Song of Solomon', testament: 'ot' },
  { bookNumber: 23, name: 'Isaiah', testament: 'ot' },
  { bookNumber: 24, name: 'Jeremiah', testament: 'ot' },
  { bookNumber: 25, name: 'Lamentations', testament: 'ot' },
  { bookNumber: 26, name: 'Ezekiel', testament: 'ot' },
  { bookNumber: 27, name: 'Daniel', testament: 'ot' },
  { bookNumber: 28, name: 'Hosea', testament: 'ot' },
  { bookNumber: 29, name: 'Joel', testament: 'ot' },
  { bookNumber: 30, name: 'Amos', testament: 'ot' },
  { bookNumber: 31, name: 'Obadiah', testament: 'ot' },
  { bookNumber: 32, name: 'Jonah', testament: 'ot' },
  { bookNumber: 33, name: 'Micah', testament: 'ot' },
  { bookNumber: 34, name: 'Nahum', testament: 'ot' },
  { bookNumber: 35, name: 'Habakkuk', testament: 'ot' },
  { bookNumber: 36, name: 'Zephaniah', testament: 'ot' },
  { bookNumber: 37, name: 'Haggai', testament: 'ot' },
  { bookNumber: 38, name: 'Zechariah', testament: 'ot' },
  { bookNumber: 39, name: 'Malachi', testament: 'ot' },
  { bookNumber: 40, name: 'Matthew', testament: 'nt' },
  { bookNumber: 41, name: 'Mark', testament: 'nt' },
  { bookNumber: 42, name: 'Luke', testament: 'nt' },
  { bookNumber: 43, name: 'John', testament: 'nt' },
  { bookNumber: 44, name: 'Acts', testament: 'nt' },
  { bookNumber: 45, name: 'Romans', testament: 'nt' },
  { bookNumber: 46, name: '1 Corinthians', testament: 'nt' },
  { bookNumber: 47, name: '2 Corinthians', testament: 'nt' },
  { bookNumber: 48, name: 'Galatians', testament: 'nt' },
  { bookNumber: 49, name: 'Ephesians', testament: 'nt' },
  { bookNumber: 50, name: 'Philippians', testament: 'nt' },
  { bookNumber: 51, name: 'Colossians', testament: 'nt' },
  { bookNumber: 52, name: '1 Thessalonians', testament: 'nt' },
  { bookNumber: 53, name: '2 Thessalonians', testament: 'nt' },
  { bookNumber: 54, name: '1 Timothy', testament: 'nt' },
  { bookNumber: 55, name: '2 Timothy', testament: 'nt' },
  { bookNumber: 56, name: 'Titus', testament: 'nt' },
  { bookNumber: 57, name: 'Philemon', testament: 'nt' },
  { bookNumber: 58, name: 'Hebrews', testament: 'nt' },
  { bookNumber: 59, name: 'James', testament: 'nt' },
  { bookNumber: 60, name: '1 Peter', testament: 'nt' },
  { bookNumber: 61, name: '2 Peter', testament: 'nt' },
  { bookNumber: 62, name: '1 John', testament: 'nt' },
  { bookNumber: 63, name: '2 John', testament: 'nt' },
  { bookNumber: 64, name: '3 John', testament: 'nt' },
  { bookNumber: 65, name: 'Jude', testament: 'nt' },
  { bookNumber: 66, name: 'Revelation', testament: 'nt' },
];

export function countActiveFilters(state: WordsFilterState): number {
  let count = 0;
  if (state.readingOrder !== 'daily') count++;
  if (state.testamentFilter !== 'all') count++;
  if (state.bookNumberFilter !== null) count++;
  count += state.selectedCategories.length;
  count += state.selectedTags.length;
  return count;
}

export function buildCardId(raw: {
  id?: string | number;
  bookNumber: number;
  chapter: number;
  startVerse: number;
  endVerse?: number;
}): string {
  if (raw.id !== undefined && raw.id !== null && String(raw.id).trim() !== '') {
    return String(raw.id);
  }
  const end = raw.endVerse ?? raw.startVerse;
  return `${raw.bookNumber}_${raw.chapter}_${raw.startVerse}_${end}`;
}
