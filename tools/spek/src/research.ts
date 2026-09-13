import { spawn } from 'node:child_process';
import { AppConfig, InputChapter, ResearchBrief } from './types.js';
import { resolveOpenCodePath } from './config.js';

export interface ResearchProvider {
  readonly name: 'none' | 'duckduckgo' | 'opencode';
  /** Returns a ResearchBrief (may be empty on graceful failure). */
  research(input: InputChapter): Promise<ResearchBrief>;
}

/** Builds search queries from a chapter using simple heuristics. */
export function buildQueries(input: InputChapter): string[] {
  const joined = input.verses.map((v) => v.text).join(' ');
  const tokens = joined.split(/\s+/).map((t) => t.replace(/[^A-Za-zÀ-ÿ'’-]/g, ''));
  const seen = new Set<string>();
  const candidates: string[] = [];

  for (const token of tokens) {
    if (!token || token.length < 3) continue;
    if (!/^[A-Z]/.test(token)) continue;
    const lower = token.toLowerCase();
    if (seen.has(lower)) continue;
    if (COMMON_STOP.has(lower)) continue;
    seen.add(lower);
    candidates.push(token);
    if (candidates.length >= 8) break;
  }

  const queries: string[] = [];
  // 1. Entity-specific query (most salient capitalized token)
  if (candidates[0]) {
    queries.push(`${candidates[0]} Bible historical context meaning`);
  }
  // 2. Chapter-level thematic query
  const label = `${input.book_name} chapter ${input.chapter}`;
  if (candidates[1]) {
    queries.push(`${candidates[1]} ${label} biblical archaeology`);
  }
  queries.push(`${label} historical cultural context study notes`);
  return queries;
}

const COMMON_STOP = new Set([
  'god', 'lord', 'jesus', 'christ', 'spirit', 'bible', 'and', 'the', 'he', 'she',
  'they', 'them', 'we', 'our', 'you', 'your', 'his', 'her', 'their', 'but', 'for',
  'not', 'no', 'so', 'then', 'there', 'is', 'are', 'was', 'were', 'had', 'have',
  'has', 'will', 'would', 'shall', 'should', 'may', 'might', 'must', 'one', 'on',
  'in', 'at', 'it', 'this', 'that', 'these', 'those', 'man', 'men', 'woman',
]);

// ---------------------------------------------------------------------------
// 1. None — offline
// ---------------------------------------------------------------------------

export class NoneResearchProvider implements ResearchProvider {
  readonly name = 'none' as const;
  async research(): Promise<ResearchBrief> {
    return { provider: 'none', queries: [], snippets: [] };
  }
}

// ---------------------------------------------------------------------------
// 2. DuckDuckGo Instant Answer (keyless, best-effort)
// ---------------------------------------------------------------------------

interface DdgResult {
  title: string;
  url: string;
  snippet: string;
}

export class DuckDuckGoResearchProvider implements ResearchProvider {
  readonly name = 'duckduckgo' as const;
  private config: AppConfig;

  constructor(config: AppConfig) {
    this.config = config;
  }

  async research(input: InputChapter): Promise<ResearchBrief> {
    const queries = buildQueries(input).slice(0, this.config.research.queries_per_chapter);
    const snippets: DdgResult[] = [];

    for (const query of queries) {
      try {
        const url = `https://api.duckduckgo.com/?q=${encodeURIComponent(query)}&format=json&no_html=1&skip_disambig=1`;
        const controller = new AbortController();
        const t = setTimeout(() => controller.abort(), 15000);
        let res: Response;
        try {
          res = await fetch(url, {
            headers: { 'User-Agent': 'spek-analyzer/1.0 (bible study research)' },
            signal: controller.signal,
          });
        } finally {
          clearTimeout(t);
        }
        if (!res.ok) throw new Error(`DDG HTTP ${res.status}`);

        const data: any = await res.json();

        if (data?.AbstractText) {
          snippets.push({
            title: 'DuckDuckGo Instant Answer',
            url: data.AbstractURL || query,
            snippet: data.AbstractText,
          });
        }
        for (const topic of data?.RelatedTopics || []) {
          if (topic.Text && topic.FirstURL) {
            snippets.push({ title: topic.Text.slice(0, 90), url: topic.FirstURL, snippet: topic.Text });
          } else if (topic.Topics) {
            for (const sub of topic.Topics) {
              if (sub.Text && sub.FirstURL) {
                snippets.push({ title: sub.Text.slice(0, 90), url: sub.FirstURL, snippet: sub.Text });
              }
            }
          }
          if (snippets.length >= this.config.research.max_snippets_per_query * 2) break;
        }
      } catch (err: any) {
        // Best-effort: skip failing queries
        if ((snippets.length === 0) && queries.indexOf(query) === queries.length - 1) {
          console.warn(`[Research/DDG] Query failed (${err?.message || err}). Degrading gracefully.`);
        } else {
          console.warn(`[Research/DDG] Query "${query}" failed: ${err?.message || err}`);
        }
      }
    }

    return {
      provider: 'duckduckgo',
      queries,
      snippets: snippets.slice(0, this.config.research.max_snippets_per_query * this.config.research.queries_per_chapter),
    };
  }
}

// ---------------------------------------------------------------------------
// 3. opencode — full websearch via opencode run against local Ollama
// ---------------------------------------------------------------------------

export class OpenCodeResearchProvider implements ResearchProvider {
  readonly name = 'opencode' as const;
  private config: AppConfig;

  constructor(config: AppConfig) {
    this.config = config;
  }

  private runOpenCode(args: string[]): Promise<string> {
    const bin = resolveOpenCodePath(this.config.opencode.run_path);
    return new Promise((resolvePromise, reject) => {
      const child = spawn(bin, args, {
        shell: false,
        windowsHide: true,
        env: {
          ...process.env,
          // Enable opencode's built-in websearch tool in the child process
          OPENCODE_ENABLE_EXA: process.env.OPENCODE_ENABLE_EXA || '1',
          OPENCODE_ENABLE_PARALLEL: process.env.OPENCODE_ENABLE_PARALLEL || '',
          OPENCODE_SERVER_PASSWORD: '',
          OPENCODE_SERVER_USERNAME: '',
        },
      });

      let stdout = '';
      let stderr = '';
      const timeout = setTimeout(() => {
        child.kill();
        reject(new Error('opencode run timed out (120s)'));
      }, 120000);

      child.stdout.on('data', (d: Buffer) => { stdout += d.toString(); });
      child.stderr.on('data', (d: Buffer) => { stderr += d.toString(); });
      child.on('error', (err) => {
        clearTimeout(timeout);
        reject(new Error(`opencode spawn failed: ${err.message}`));
      });
      child.on('close', (code) => {
        clearTimeout(timeout);
        resolvePromise(stdout || stderr); // keep raw output
      });
    });
  }

  async research(input: InputChapter): Promise<ResearchBrief> {
    const label = `${input.book_name} ${input.chapter}`;
    const prompt = [
      `Using web search, research Bible ${label}.`,
      `Find historical and cultural context for this chapter: places, people, customs, measurements, archaeology, and any scholarly facts.`,
      `Return a concise research brief (bullet points) covering the most relevant facts with their source names or domains.`,
      `Keep it under 400 words. If a fact is not well attested, say so briefly.`,
    ].join(' ');

    try {
      const output = await this.runOpenCode([
        'run',
        '--pure' as any,
        '--auto' as any,
        '-m',
        this.config.opencode.model_id,
        prompt,
      ].map(String));
      return {
        provider: 'opencode',
        queries: [label],
        snippets: [],
        text: output.trim(),
      };
    } catch (err: any) {
      return {
        provider: 'opencode',
        queries: [label],
        snippets: [],
        text: '',
        error: err?.message || String(err),
      };
    }
  }
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

export function createResearchProvider(config: AppConfig): ResearchProvider {
  switch (config.research.provider) {
    case 'duckduckgo':
      return new DuckDuckGoResearchProvider(config);
    case 'opencode':
      return new OpenCodeResearchProvider(config);
    case 'none':
    default:
      return new NoneResearchProvider();
  }
}

/** Renders a ResearchBrief into the prompt-friendly text block. */
export function renderBrief(brief: ResearchBrief): string {
  if (brief.text && brief.text.length > 0) {
    return `# Research brief (provider: ${brief.provider})\n${brief.text}`;
  }
  if (brief.snippets.length === 0) {
    return '';
  }
  const lines = [
    `# Research brief (provider: ${brief.provider})`,
    `# Queries: ${brief.queries.join(' | ')}`,
  ];
  for (const s of brief.snippets.slice(0, 8)) {
    lines.push(`- ${s.title}\n  ${s.snippet} (${s.url})`);
  }
  return lines.join('\n');
}