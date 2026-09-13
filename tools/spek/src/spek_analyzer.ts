import { ZodType } from 'zod';
import { ChapterSpekOutput, ChapterSpekOutputSchema, InputChapter } from './types.js';
import { OllamaStudyClient } from './ollama_client.js';

/**
 * Pass 3 — per-verse SPECK analysis. Web research brief grounds the
 * historical/cultural context, and the glossary is bilingual (en + ta).
 */
export class SpekAnalyzer {
  private llm: OllamaStudyClient;

  constructor(llm: OllamaStudyClient) {
    this.llm = llm;
  }

  public async analyzeChapter(
    input: InputChapter,
    researchBrief?: string | null
  ): Promise<{ output: ChapterSpekOutput; inputTokens?: number; outputTokens?: number }> {
    const chapterPayload = JSON.stringify(input, null, 2);

    let researchSection =
      'No research brief was provided. Base historical/cultural content on general biblical scholarship and set certainty to "assumed".';
    if (researchBrief && researchBrief.trim().length > 0) {
      researchSection = researchBrief.trim();
    }

    const user = [
      '### CHAPTER JSON',
      '```json',
      chapterPayload,
      '```',
      '',
      '### RESEARCH BRIEF (web-sourced facts to support historical/cultural context)',
      researchSection,
      '',
      'Produce ONLY the output JSON object defined in your instructions. No prose, no markdown fences.',
    ].join('\n');

    const { data, inputTokens, outputTokens } = await this.llm.generate<ChapterSpekOutput>(
      this.llm.getSystemPrompt('spek'),
      user,
      ChapterSpekOutputSchema as unknown as ZodType<ChapterSpekOutput>
    );

    data.version_id = data.version_id || input.version_id;
    data.source_version = input.source_version ?? input.version_id;
    data.book = data.book ?? input.book;
    data.book_name = data.book_name || input.book_name;
    data.chapter = data.chapter ?? input.chapter;
    data.verses = data.verses || [];

    return { output: data, inputTokens, outputTokens };
  }
}