import { z } from 'zod';

// ==========================================
// Shared input
// ==========================================

export const VerseItemSchema = z.object({
  verse: z.number().int().positive(),
  text: z.string().min(1),
});
export type VerseItem = z.infer<typeof VerseItemSchema>;

export const InputChapterSchema = z.object({
  version_id: z.string().min(1),
  source_version: z.string().optional(),
  book: z.number().int().min(1).max(66),
  book_name: z.string().min(1),
  chapter: z.number().int().positive(),
  verses: z.array(VerseItemSchema).min(1),
});
export type InputChapter = z.infer<typeof InputChapterSchema>;

// ==========================================
// Pass 1 — FEED (scriptures.json / words_feed)
// ==========================================

export const FeedCategoryEnum = z.enum([
  'words_of_god', 'jesus_words', 'prophecy', 'promise', 'commandment',
  'wisdom', 'doctrine', 'comfort', 'warning', 'prayer', 'praise', 'parable',
  'salvation', 'divine_action', 'consecration',
]);
export type FeedCategory = z.infer<typeof FeedCategoryEnum>;

export const SPECK_TAGS = ['S', 'P', 'E', 'C', 'K'] as const;
export type SpeckLetter = typeof SPECK_TAGS[number];

export interface SentenceUnit {
  start: number;
  end: number;
  verses: VerseItem[];
}

export const FeedVerdictSchema = z.object({
  id: z.number().int(),
  include: z.boolean().optional().nullable(),
  category: z.string().optional().nullable(),
  theme: z.string().optional().nullable(),
  speck: z.array(z.string()).optional().nullable(),
});
export type FeedVerdict = z.infer<typeof FeedVerdictSchema>;

export const FeedBatchResponseSchema = z.object({
  verdicts: z.array(FeedVerdictSchema),
});
export type FeedBatchResponse = z.infer<typeof FeedBatchResponseSchema>;

export interface FeedPassage {
  book: number;
  bookName: string;
  chapter: number;
  start: number;
  end: number;
  category: string;
  theme: string;
  speck: string[];
}

export interface ScriptureRecord {
  engine: string;
  bookNumber: number;
  bookName: string;
  chapter: number;
  startVerse: number;
  endVerse: number;
  referenceLabel: string;
  verseMappings: Record<string, never>;
  category: string;
  tags: string[];
  speck: string[];
  theme: string;
  backgroundPreset: string;
  isFeatured: boolean;
}

// ==========================================
// Pass 2 — STUDY (concepts knowledge base, TAOVBSI-aware)
// ==========================================

export const StudyCategoryEnum = z.enum([
  'theological_term', 'biblical_concept', 'person', 'place', 'people_group',
  'religious_group', 'object', 'custom', 'ceremony', 'plant', 'animal',
  'food', 'measurement', 'money', 'title', 'office', 'geographical_term',
  'historical_term', 'idiom', 'archaic_term', 'other',
]);
export type StudyCategory = z.infer<typeof StudyCategoryEnum>;

export const StudyCertaintyEnum = z.enum(['verified', 'probable', 'assumed', 'debated', 'unknown']);
export type StudyCertainty = z.infer<typeof StudyCertaintyEnum>;

export const TermReferenceSchema = z.object({
  book: z.number().int().min(1).max(66),
  chapter: z.number().int().positive(),
  verse: z.number().int().positive(),
});
export type TermReference = z.infer<typeof TermReferenceSchema>;

export const OriginalLanguageSchema = z
  .object({
    language: z.string().optional().nullable(),
    original_word: z.string().optional().nullable(),
    word: z.string().optional().nullable(),
    lemma: z.string().optional().nullable(),
    script: z.string().optional().nullable(),
    transliteration: z.string().optional().nullable(),
    strongs: z.string().optional().nullable(),
    strongs_number: z.string().optional().nullable(),
    lexical_meaning: z.string().optional().nullable(),
    lexical_root_meaning: z.string().optional().nullable(),
  })
  .transform((data) => {
    const rawStrongs = data.strongs || data.strongs_number || null;
    const cleanStrongs =
      rawStrongs && /^[HG]\d{1,5}$/i.test(rawStrongs.trim())
        ? rawStrongs.trim().toUpperCase()
        : null;
    let lang = data.language;
    if (!lang && cleanStrongs) {
      if (cleanStrongs.startsWith('H')) lang = 'Hebrew';
      else if (cleanStrongs.startsWith('G')) lang = 'Greek';
    }
    const originalScript = data.original_word || data.word || data.script || data.lemma || '';
    return {
      language: lang || 'Hebrew',
      original_word: originalScript,
      lemma: originalScript,
      transliteration: data.transliteration || null,
      strongs: cleanStrongs,
      lexical_meaning: data.lexical_meaning || data.lexical_root_meaning || null,
    };
  });
export type OriginalLanguage = z.infer<typeof OriginalLanguageSchema>;

export const TermMetadataSchema = z
  .object({
    location_type: z.string().optional().nullable(),
    modern_name: z.string().optional().nullable(),
    modern_location: z.string().optional().nullable(),
    modern_lociation: z.string().optional().nullable(),
    coordinates: z.object({
      latitude: z.number().optional().nullable(),
      longitude: z.number().optional().nullable(),
    }).optional().nullable(),
    unit_type: z.string().optional().nullable(),
    biblical_amount: z.string().optional().nullable(),
    modern_equivalent: z.string().optional().nullable(),
    name_meaning: z.string().optional().nullable(),
    gender: z.string().optional().nullable(),
    roles: z.array(z.string()).optional().nullable(),
    feast_name_hebrew: z.string().optional().nullable(),
    feast_timing: z.string().optional().nullable(),
    feast_significance: z.string().optional().nullable(),
    certainty: z.string().optional().nullable(),
    certainty_notes: z.string().optional().nullable(),
  })
  .optional()
  .nullable()
  .transform((data) => {
    if (!data) return null;
    return { ...data, modern_location: data.modern_location || data.modern_lociation || null };
  });
export type TermMetadata = z.infer<typeof TermMetadataSchema>;

export const StudyTermSchema = z
  .object({
    reference: TermReferenceSchema.optional().nullable(),
    surface_forms: z.array(z.string().min(1)).default([]),
    lemma: z.string().optional().nullable(),
    concept_id: z.string().optional().nullable(),
    concept_name: z.string().min(1),
    english_name: z.string().optional().nullable(),
    category: z.string().default('biblical_concept'),
    importance: z.enum(['high', 'medium', 'low']).default('medium'),
    certainty: z.enum(['verified', 'probable', 'assumed', 'debated', 'unknown']).default('verified'),
    certainty_notes: z.string().optional().nullable(),
    dictionary_worthy: z.boolean().default(true),
    contemporary_language: z.string().optional().nullable(),
    contemporary_meaning: z.string().optional().nullable(),
    definition: z.string().optional().nullable(),
    definition_tamil: z.string().optional().nullable(),
    meaning: z.string().optional().nullable(),
    biblical_meaning: z.string().optional().nullable(),
    biblical_meaning_tamil: z.string().optional().nullable(),
    theological_meaning: z.string().optional().nullable(),
    historical_context: z.string().optional().nullable(),
    cultural_context: z.string().optional().nullable(),
    citations: z.union([z.array(z.string()), z.string()]).optional().nullable(),
    original_language: OriginalLanguageSchema.optional().nullable(),
    metadata: TermMetadataSchema,
    notes: z.string().optional().nullable(),
  })
  .transform((data) => {
    const cleanDef =
      data.definition || data.definition_tamil || data.meaning ||
      data.biblical_meaning || data.contemporary_language ||
      data.contemporary_meaning || data.concept_name;
    const cleanBiblicalMeaning =
      data.biblical_meaning || data.biblical_meaning_tamil ||
      data.theological_meaning || cleanDef;
    const cleanForms =
      data.surface_forms && data.surface_forms.length > 0
        ? data.surface_forms
        : [data.concept_name];
    const slug = (data.concept_id || data.concept_name)
      .toLowerCase()
      .replace(/[\s\-_]+/g, '_')
      .replace(/[^a-z0-9_]/g, '')
      .replace(/^_+|_+$/g, '') || 'concept';
    const rawCertainty = (data.certainty || data.metadata?.certainty || 'verified').toLowerCase();
    const cleanCertainty: StudyCertainty = (
      ['verified', 'probable', 'assumed', 'debated', 'unknown'].includes(rawCertainty)
        ? rawCertainty : 'assumed'
    ) as StudyCertainty;
    const cleanCitations = Array.isArray(data.citations)
      ? data.citations.filter((c) => typeof c === 'string' && c.trim().length > 0)
      : (typeof data.citations === 'string' && data.citations.trim() ? [data.citations.trim()] : []);
    return {
      reference: data.reference || { book: 1, chapter: 1, verse: 1 },
      surface_forms: cleanForms,
      lemma: data.lemma || cleanForms[0] || data.concept_name,
      concept_id: slug,
      concept_name: data.concept_name,
      english_name: data.english_name || null,
      category: data.category,
      importance: data.importance,
      certainty: cleanCertainty,
      certainty_notes: data.certainty_notes || data.metadata?.certainty_notes || null,
      dictionary_worthy: data.dictionary_worthy,
      contemporary_language: data.contemporary_language || data.contemporary_meaning || null,
      definition: cleanDef,
      biblical_meaning: cleanBiblicalMeaning,
      historical_context: data.historical_context || null,
      cultural_context: data.cultural_context || null,
      citations: cleanCitations,
      original_language: data.original_language || null,
      metadata: data.metadata || null,
      notes: data.notes || null,
    };
  });
export type StudyTerm = z.infer<typeof StudyTermSchema>;

export const StudyChapterOutputSchema = z.object({
  version_id: z.string().optional().nullable(),
  source_version: z.string().optional().nullable(),
  book: z.number().int().optional().nullable(),
  book_name: z.string().optional().nullable(),
  chapter: z.number().int().optional().nullable(),
  chapter_summary: z.string().optional().nullable(),
  terms: z.array(StudyTermSchema).default([]),
});
export type StudyChapterOutput = z.infer<typeof StudyChapterOutputSchema>;

// ==========================================
// Pass 3 — SPEK (per-verse analysis)
// ==========================================

export const CertaintyEnum = z.enum(['verified', 'probable', 'assumed']);
export type Certainty = z.infer<typeof CertaintyEnum>;

export const SpeckCategoriesSchema = z.object({
  S: z.string().optional().nullable().default(''),
  P: z.string().optional().nullable().default(''),
  E: z.string().optional().nullable().default(''),
  C: z.string().optional().nullable().default(''),
  K: z.string().optional().nullable().default(''),
});
export type SpeckCategories = z.infer<typeof SpeckCategoriesSchema>;

export const GlossaryTermSchema = z.object({
  term: z.string().min(1),
  en: z.string().optional().nullable(),
  ta: z.string().optional().nullable(),
  strongs: z.string().optional().nullable(),
});
export type GlossaryTerm = z.infer<typeof GlossaryTermSchema>;

export const VerseSpekSchema = z.object({
  v: z.number().int().positive(),
  speck: SpeckCategoriesSchema,
  glossary: z.array(GlossaryTermSchema).default([]),
});
export type VerseSpek = z.infer<typeof VerseSpekSchema>;

export const ChapterSpekOutputSchema = z.object({
  version_id: z.string().optional().nullable(),
  source_version: z.string().optional().nullable(),
  book: z.number().int().optional().nullable(),
  book_name: z.string().optional().nullable(),
  chapter: z.number().int().optional().nullable(),
  chapter_summary: z.string().optional().nullable(),
  historical_context: z.string().optional().nullable(),
  cultural_context: z.string().optional().nullable(),
  certainty: CertaintyEnum.default('assumed'),
  sources: z.array(z.string()).default([]),
  verses: z.array(VerseSpekSchema).default([]),
});
export type ChapterSpekOutput = z.infer<typeof ChapterSpekOutputSchema>;

// ==========================================
// Research
// ==========================================

export interface ResearchSnippet {
  title: string;
  url: string;
  snippet: string;
}

export interface ResearchBrief {
  provider: string;
  queries: string[];
  snippets: ResearchSnippet[];
  text?: string;
  error?: string;
}

// ==========================================
// Status tracking
// ==========================================

export type ProcessStatus = 'pending' | 'in_progress' | 'completed' | 'failed';

export interface ChapterStatusRecord {
  book: number;
  chapter: number;
  status: ProcessStatus;
  count?: number;
  attempts: number;
  processed_at?: string;
  error?: string;
  model?: string;
  input_tokens?: number;
  output_tokens?: number;
}

export interface StatusManifest {
  pass: string;
  version_id: string;
  created_at: string;
  updated_at: string;
  total_chapters: number;
  completed_chapters: number;
  failed_chapters: number;
  total_items: number;
  chapters: Record<string, ChapterStatusRecord>; // Key: `${book}_${chapter}`
}

// ==========================================
// Configuration
// ==========================================

export interface AppConfig {
  version_id: string;
  language: string;
  llm: {
    ollama: {
      base_url: string;
      model: string;
      temperature: number;
      max_retries: number;
      retry_base_delay_ms: number;
      timeout_ms: number;
      num_ctx: number;
    };
  };
  bible_source_dirs: Record<string, string>;
  strongs_source?: string | null;
  releases_dir: string;
  backend_data_dir: string;
  research: {
    provider: 'none' | 'duckduckgo' | 'opencode';
    queries_per_chapter: number;
    max_snippets_per_query: number;
  };
  opencode: { model_id: string; run_path: string };
  passes: {
    feed: { enabled: boolean; source_version: string; batch_units: number; max_retries: number; num_ctx: number };
    study: { enabled: boolean; source_version: string };
    spek: { enabled: boolean; source_version: string };
  };
  processing: {
    pause_between_requests_ms: number;
    dry_run: boolean;
  };
}