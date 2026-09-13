import { ZodType } from 'zod';
import { InputChapter, StudyChapterOutput, StudyChapterOutputSchema } from './types.js';
import { OllamaStudyClient } from './ollama_client.js';

/**
 * Pass 2 — study concepts. Sends a TAOVBSI (classical Tamil) chapter to the
 * local LLM and extracts high-value study terms with TAOVBSI-prose
 * definitions, mirroring tools/bible_study's chapter_extraction prompt.
 */
export class StudyAnalyzer {
  private llm: OllamaStudyClient;

  constructor(llm: OllamaStudyClient) {
    this.llm = llm;
  }

  public async analyzeChapter(
    input: InputChapter
  ): Promise<{ output: StudyChapterOutput; inputTokens?: number; outputTokens?: number }> {
    const userJson = JSON.stringify(input, null, 2);
    const user = [
      '### CHAPTER JSON',
      '```json',
      userJson,
      '```',
      '',
      'Extract ONLY the high-value study terms and output the JSON defined in your instructions.',
      'No prose, no code fences; the entire response must be the output object.',
    ].join('\n');

    const { data, inputTokens, outputTokens } = await this.llm.generate<StudyChapterOutput>(
      this.llm.getSystemPrompt('study'),
      user,
      StudyChapterOutputSchema as unknown as ZodType<StudyChapterOutput>
    );

    data.version_id = data.version_id || input.version_id;
    data.source_version = input.source_version ?? input.version_id;
    data.book = data.book ?? input.book;
    data.book_name = data.book_name || input.book_name;
    data.chapter = data.chapter ?? input.chapter;
    data.terms = data.terms || [];

    return { output: data, inputTokens, outputTokens };
  }
}