import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import yaml from 'yaml';
import dotenv from 'dotenv';
import { AppConfig } from './types.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PROJECT_ROOT = path.resolve(__dirname, '..');

// Load environment variables from .env if present
dotenv.config({ path: path.join(PROJECT_ROOT, '.env') });
// Also check root repo .env as fallback
dotenv.config({ path: path.resolve(PROJECT_ROOT, '../../.env') });

export function loadConfig(configPath?: string): AppConfig {
  const resolvedConfigPath = configPath
    ? path.resolve(process.cwd(), configPath)
    : path.join(PROJECT_ROOT, 'config.yaml');

  if (!fs.existsSync(resolvedConfigPath)) {
    throw new Error(`Configuration file not found at: ${resolvedConfigPath}`);
  }

  const rawYaml = fs.readFileSync(resolvedConfigPath, 'utf8');
  const parsed = yaml.parse(rawYaml) as Partial<AppConfig>;

  const config: AppConfig = {
    version_id: parsed.version_id || 'ta_ovbsi',
    language: parsed.language || 'ta',
    bible_source_dir: parsed.bible_source_dir
      ? path.resolve(PROJECT_ROOT, parsed.bible_source_dir)
      : null,
    bible_database: parsed.bible_database
      ? path.resolve(PROJECT_ROOT, parsed.bible_database)
      : null,
    strongs_source: parsed.strongs_source
      ? path.resolve(PROJECT_ROOT, parsed.strongs_source)
      : null,
    output_dir: parsed.output_dir
      ? path.resolve(PROJECT_ROOT, parsed.output_dir)
      : path.join(PROJECT_ROOT, 'output'),
    gemini: {
      model: parsed.gemini?.model || 'gemini-2.5-flash',
      temperature: parsed.gemini?.temperature ?? 0.1,
      max_retries: parsed.gemini?.max_retries ?? 5,
      retry_base_delay_ms: parsed.gemini?.retry_base_delay_ms ?? 1500,
      timeout_ms: parsed.gemini?.timeout_ms ?? 60000,
    },
    processing: {
      chapters_per_request: parsed.processing?.chapters_per_request ?? 1,
      pause_between_requests_ms: parsed.processing?.pause_between_requests_ms ?? 1000,
      dry_run: parsed.processing?.dry_run ?? false,
    },
  };

  return config;
}

export function getGeminiApiKey(): string {
  const key = process.env.GEMINI_API_KEY;
  if (!key) {
    throw new Error(
      'GEMINI_API_KEY environment variable is not set.\nPlease add it to tools/bible_study/.env or set it in your shell environment.'
    );
  }
  return key;
}

export { PROJECT_ROOT };
