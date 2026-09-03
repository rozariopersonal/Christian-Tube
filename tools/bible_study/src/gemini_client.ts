import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { GoogleGenAI } from '@google/genai';
import { AppConfig, ChapterOutput, ChapterOutputSchema, InputChapter } from './types.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PROMPT_PATH = path.resolve(__dirname, '../prompts/chapter_extraction.txt');

export class GeminiStudyClient {
  private config: AppConfig;
  private ai: GoogleGenAI;
  private promptTemplate: string;

  constructor(config: AppConfig, apiKey: string) {
    this.config = config;
    this.ai = new GoogleGenAI({ apiKey });
    this.promptTemplate = fs.readFileSync(PROMPT_PATH, 'utf8');
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  /**
   * Processes a single chapter by sending the structured chapter JSON to Gemini.
   */
  public async extractChapterStudy(
    input: InputChapter
  ): Promise<{ output: ChapterOutput; inputTokens?: number; outputTokens?: number }> {
    const systemPrompt = this.promptTemplate;
    const userPayload = JSON.stringify(input, null, 2);

    const fullPrompt = `${systemPrompt}\n\nHere is the chapter to analyze:\n\`\`\`json\n${userPayload}\n\`\`\``;

    let attempt = 0;
    const maxRetries = this.config.gemini.max_retries;
    let delay = this.config.gemini.retry_base_delay_ms;

    while (attempt <= maxRetries) {
      attempt++;
      try {
        const reqConfig: any = {
          responseMimeType: 'application/json',
          temperature: this.config.gemini.temperature,
        };
        if (this.config.gemini.model.includes('2.5')) {
          reqConfig.thinkingConfig = { thinkingBudget: 0 };
        }

        const response = await this.ai.models.generateContent({
          model: this.config.gemini.model,
          contents: fullPrompt,
          config: reqConfig,
        });

        const text = response.text;
        if (!text) {
          throw new Error('Received empty response from Gemini API.');
        }

        // Clean any markdown block wrapping if present
        let cleanedText = text.trim();
        if (cleanedText.startsWith('```json')) {
          cleanedText = cleanedText.slice(7);
        } else if (cleanedText.startsWith('```')) {
          cleanedText = cleanedText.slice(3);
        }
        if (cleanedText.endsWith('```')) {
          cleanedText = cleanedText.slice(0, -3);
        }
        cleanedText = cleanedText.trim();

        const parsedJson = JSON.parse(cleanedText);
        console.log('[GeminiClient] Keys returned by Gemini:', Object.keys(parsedJson));
        if (Array.isArray(parsedJson)) {
          console.log('[GeminiClient] Root is Array with length:', parsedJson.length);
        }

        // Handle case where Gemini names the terms array differently
        const termsArray =
          parsedJson.terms ||
          parsedJson.bible_study_terms ||
          parsedJson.study_terms ||
          parsedJson.words ||
          parsedJson.vocabulary ||
          parsedJson.items ||
          parsedJson.concepts ||
          (Array.isArray(parsedJson) ? parsedJson : []);

        const normalizedPayload = {
          ...parsedJson,
          terms: termsArray,
        };

        // Strictly validate with Zod
        const validated = ChapterOutputSchema.parse(normalizedPayload);

        // Ensure contextual coordinates from input are accurately stamped
        validated.book = input.book;
        validated.book_name = input.book_name;
        validated.chapter = input.chapter;
        validated.version_id = input.version_id;

        for (const term of validated.terms) {
          if (!term.reference || !term.reference.book) {
            term.reference = {
              book: input.book,
              chapter: input.chapter,
              verse: 1,
            };
          } else {
            term.reference.book = input.book;
            term.reference.chapter = input.chapter;
          }
        }

        const inputTokens = response.usageMetadata?.promptTokenCount;
        const outputTokens = response.usageMetadata?.candidatesTokenCount;

        return {
          output: validated,
          inputTokens,
          outputTokens,
        };
      } catch (err: any) {
        const isRateLimit =
          err?.status === 429 ||
          err?.message?.includes('429') ||
          err?.message?.includes('RESOURCE_EXHAUSTED') ||
          err?.message?.includes('quota');

        console.warn(
          `[GeminiClient] Attempt ${attempt}/${maxRetries} failed for Book ${input.book} Chapter ${input.chapter}: ${err.message}`
        );

        if (attempt > maxRetries) {
          throw err;
        }

        // Free Tier Rate Limit Management:
        // Free tier enforces 15 RPM. When 429 / RESOURCE_EXHAUSTED is returned,
        // wait at least 25-30s for the 60s sliding window to clear.
        const jitter = Math.floor(Math.random() * 1000);
        const waitTime = isRateLimit ? Math.max(delay, 25000) + jitter : delay + jitter;
        console.log(
          `[GeminiClient] ${isRateLimit ? 'Free tier rate limit (15 RPM) reached.' : 'API error.'} Waiting ${Math.round(waitTime / 1000)}s before retry...`
        );
        await this.sleep(waitTime);
        delay = isRateLimit ? Math.min(delay * 1.5, 60000) : delay * 2;
      }
    }

    throw new Error(`Failed to process Book ${input.book} Chapter ${input.chapter} after ${maxRetries} retries.`);
  }
}
