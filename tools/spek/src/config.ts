import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { execSync } from 'node:child_process';
import yaml from 'yaml';
import dotenv from 'dotenv';
import { AppConfig } from './types.js';

const __filename = fileURLToPath(import.meta.url);
export const SOURCE_DIR = path.dirname(__filename);
export const PROJECT_ROOT = path.resolve(SOURCE_DIR, '..');

dotenv.config({ path: path.join(PROJECT_ROOT, '.env') });
dotenv.config({ path: path.resolve(PROJECT_ROOT, '../../.env') });

/** Resolves a config-relative path against the tools/spek project root. */
export function resolveFromProject(p: string | undefined | null, fallback: string): string {
  return path.resolve(PROJECT_ROOT, p || fallback);
}

export function loadConfig(configPath?: string): AppConfig {
  const resolvedConfigPath = configPath
    ? path.resolve(process.cwd(), configPath)
    : path.join(PROJECT_ROOT, 'config.yaml');

  if (!fs.existsSync(resolvedConfigPath)) {
    throw new Error(`Configuration file not found at: ${resolvedConfigPath}`);
  }

  const rawYaml = fs.readFileSync(resolvedConfigPath, 'utf8');
  const parsed = yaml.parse(rawYaml) as any;

  const releasesDir = resolveFromProject(parsed.releases_dir, '../../releases');
  const backendDataDir = resolveFromProject(parsed.backend_data_dir, '../../apps/backend/data');

  const researchProvider = (
    parsed.research?.provider ||
    process.env.SPEK_RESEARCH_PROVIDER ||
    'duckduckgo'
  ) as AppConfig['research']['provider'];

  const config: AppConfig = {
    version_id: parsed.version_id || 'ta_ovbsi',
    language: parsed.language || 'ta',
    llm: {
      ollama: {
        base_url:
          process.env.OLLAMA_BASE_URL ||
          parsed.llm?.ollama?.base_url ||
          'http://localhost:11434',
        model:
          process.env.SPEK_LLM ||
          parsed.llm?.ollama?.model ||
          'qwen2.5:7b',
        num_ctx: parsed.llm?.ollama?.num_ctx ?? 32768,
        temperature: parsed.llm?.ollama?.temperature ?? 0.1,
        max_retries: parsed.llm?.ollama?.max_retries ?? 4,
        retry_base_delay_ms: parsed.llm?.ollama?.retry_base_delay_ms ?? 2000,
        timeout_ms: parsed.llm?.ollama?.timeout_ms ?? 120000,
      },
    },
    bible_source_dirs: Object.fromEntries(
      Object.entries(parsed.bible_source_dirs || { web: '' }).map(([k, v]) => [
        k,
        resolveFromProject(String(v), ''),
      ])
    ),
    strongs_source: parsed.strongs_source
      ? resolveFromProject(parsed.strongs_source, '')
      : null,
    releases_dir: releasesDir,
    backend_data_dir: backendDataDir,
    research: {
      provider: researchProvider,
      queries_per_chapter: parsed.research?.queries_per_chapter ?? 3,
      max_snippets_per_query: parsed.research?.max_snippets_per_query ?? 5,
    },
    opencode: {
      model_id: parsed.opencode?.model_id || 'ollama/qwen2.5:7b',
      run_path: parsed.opencode?.run_path || '',
    },
    passes: {
      feed: {
        enabled: parsed.passes?.feed?.enabled ?? true,
        source_version: parsed.passes?.feed?.source_version || 'web',
        batch_units: parsed.passes?.feed?.batch_units ?? 10,
        max_retries: parsed.passes?.feed?.max_retries ?? 3,
        num_ctx: parsed.passes?.feed?.num_ctx ?? 8192,
      },
      study: {
        enabled: parsed.passes?.study?.enabled ?? true,
        source_version: parsed.passes?.study?.source_version || 'ta_ovbsi',
      },
      spek: {
        enabled: parsed.passes?.spek?.enabled ?? true,
        source_version: parsed.passes?.spek?.source_version || 'web',
      },
    },
    processing: {
      pause_between_requests_ms: parsed.processing?.pause_between_requests_ms ?? 800,
      dry_run: parsed.processing?.dry_run ?? false,
    },
  };

  return config;
}

/** Canonical output directories for the three passes. */
export function passDirs(config: AppConfig) {
  return {
    feed: {
      cacheDir: resolveFromProject('.cache/feed', '.cache/feed'),
      chapFile: path.join(config.releases_dir, 'scriptures.json'),
      mirrorFile: path.join(config.backend_data_dir, 'scriptures.json'),
    },
    study: {
      baseDir: path.join(config.releases_dir, 'study', config.version_id),
    },
    spek: {
      baseDir: path.join(config.releases_dir, 'spek', config.version_id),
    },
  };
}

export function resolveOpenCodePath(configPath: string): string {
  if (configPath && fs.existsSync(configPath)) return configPath;
  const candidates = [
    path.join(process.env.USERPROFILE || '', '.opencode', 'bin', 'opencode.exe'),
    path.join(process.env.USERPROFILE || '', '.opencode', 'bin', 'opencode'),
    'opencode',
  ];
  for (const c of candidates) {
    try {
      if (c === 'opencode') {
        execSync('opencode --version', { stdio: 'ignore' });
        return c;
      }
      if (fs.existsSync(c)) return c;
    } catch {
      continue;
    }
  }
  throw new Error(
    'opencode executable not found. Set `opencode.run_path` in config.yaml or add opencode to PATH.'
  );
}