import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { Agent } from 'undici';
import { ZodType } from 'zod';
import { AppConfig } from './types.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Long CPU generations can exceed undici's 300s default headers/body timeout;
// disable those and let the explicit AbortController (timeout_ms) govern.
const dispatcher = new Agent({ headersTimeout: 0, bodyTimeout: 0 });

function loadPrompt(name: string): string {
  return fs.readFileSync(path.join(__dirname, '../prompts', name), 'utf8');
}

export class OllamaStudyClient {
  private config: AppConfig;
  private promptCache: Map<string, string> = new Map();
  private feedSystem = '';
  private studySystem = '';
  private spekSystem = '';

  constructor(config: AppConfig) {
    this.config = config;
    this.feedSystem = loadPrompt('feed_verdicts.txt');
    this.studySystem = loadPrompt('chapter_study.txt');
    this.spekSystem = loadPrompt('verse_analysis.txt');
  }

  hasPrompt(name: string): boolean {
    if (name === 'feed') return this.feedSystem.length > 0;
    if (name === 'study') return this.studySystem.length > 0;
    if (name === 'spek') return this.spekSystem.length > 0;
    return this.promptCache.has(name);
  }

  getSystemPrompt(name: string): string {
    if (name === 'feed') return this.feedSystem;
    if (name === 'study') return this.studySystem;
    if (name === 'spek') return this.spekSystem;
    return this.promptCache.get(name) || '';
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  /** Strips a markdown fence if present, then parses JSON. */
  public static parseJson(text: string): any {
    let cleanedText = text.trim();

    const match = cleanedText.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (match) cleanedText = match[1].trim();

    const firstBrace = cleanedText.indexOf('{');
    const lastBrace = cleanedText.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      cleanedText = cleanedText.slice(firstBrace, lastBrace + 1);
    }

    return JSON.parse(cleanedText);
  }

  public baseUrl(): string {
    return this.config.llm.ollama.base_url.replace(/\/+$/, '');
  }

  public model(): string {
    return this.config.llm.ollama.model;
  }

  /**
   * Sends messages to local Ollama with shared retry/backoff, and validates
   * the parsed JSON against the provided Zod schema.
   */
  public async generate<T>(
    system: string,
    user: string,
    schema: ZodType<T>,
    opts?: { numCtx?: number; temperature?: number; maxRetries?: number }
  ): Promise<{ data: T; inputTokens?: number; outputTokens?: number }> {
    const numCtx = opts?.numCtx ?? this.config.llm.ollama.num_ctx;
    const temperature = opts?.temperature ?? this.config.llm.ollama.temperature;
    const maxRetries = opts?.maxRetries ?? this.config.llm.ollama.max_retries;
    const endpoint = `${this.baseUrl()}/api/chat`;

    let attempt = 0;
    let delay = this.config.llm.ollama.retry_base_delay_ms;

    while (attempt <= maxRetries) {
      attempt++;
      try {
        const body = {
          model: this.config.llm.ollama.model,
          messages: [
            { role: 'system', content: system },
            { role: 'user', content: user },
          ],
          stream: false,
          options: { num_ctx: numCtx, temperature },
          format: 'json',
          keep_alive: '1h',
        };

        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), this.config.llm.ollama.timeout_ms);

        let res: Response;
        try {
          res = await fetch(endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
            signal: controller.signal,
            dispatcher: dispatcher as any,
          });
        } finally {
          clearTimeout(timeout);
        }

        if (!res.ok) {
          const errText = await res.text().catch(() => '');
          throw new Error(`Ollama HTTP ${res.status}: ${errText.slice(0, 300)}`);
        }

        const data: any = await res.json();
        const textContent = data?.message?.content ?? data?.choices?.[0]?.message?.content;
        if (!textContent || typeof textContent !== 'string') {
          throw new Error('Empty response from Ollama.');
        }

        const parsed = OllamaStudyClient.parseJson(textContent);
        const validated = schema.parse(parsed);

        const usage: any = data?.usage;
        const inputTokens = usage?.prompt_tokens ?? usage?.prompt_eval_count;
        const outputTokens = usage?.completion_tokens ?? usage?.eval_count;

        return { data: validated, inputTokens, outputTokens };
      } catch (err: any) {
        const isAbort = err?.name === 'AbortError' || err?.message?.includes('aborted');
        const isTimeout = isAbort;
        const isModelError = /model .*not found/i.test(err?.message || '') || /pull the model/i.test(err?.message || '');

        console.warn(
          `[Ollama] Attempt ${attempt}/${maxRetries} failed: ${err.message}`
        );

        if (attempt > maxRetries) {
          throw err;
        }

        const jitter = Math.floor(Math.random() * 750);
        const waitTime = isTimeout ? Math.max(delay, 15000) : isModelError ? 5000 : delay + jitter;
        console.log(
          `[Ollama] ${isTimeout ? 'Request timed out (model may be loading/coin-turning).' : 'Error.'} Waiting ${Math.round(waitTime / 1000)}s before retry...`
        );
        await this.sleep(waitTime);
        delay = isTimeout ? Math.min(delay * 1.5, 45000) : delay * 2;
      }
    }

    throw new Error(`Failed after ${maxRetries} retries.`);
  }
}