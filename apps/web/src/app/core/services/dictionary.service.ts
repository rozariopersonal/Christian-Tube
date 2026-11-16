import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { firstValueFrom, timeout } from 'rxjs';

export interface DictionaryDefinition {
  definition: string;
  example?: string;
}

export interface DictionaryMeaning {
  partOfSpeech: string;
  definitions: DictionaryDefinition[];
}

export interface DictionaryEntry {
  word: string;
  phonetic?: string;
  audioUrl?: string;
  meanings: DictionaryMeaning[];
}

@Injectable({ providedIn: 'root' })
export class DictionaryService {
  private readonly http = inject(HttpClient);
  private readonly cache = new Map<string, DictionaryEntry>();

  async lookup(rawWord: string): Promise<DictionaryEntry> {
    const clean = rawWord
      .trim()
      .toLowerCase()
      .replace(/^[^a-z'-]+|[^a-z'-]+$/gi, '');
    if (!clean) {
      throw new Error('Select a valid English word to look up.');
    }

    const cached = this.cache.get(clean);
    if (cached) return cached;

    const url = `https://api.dictionaryapi.dev/api/v2/entries/en/${encodeURIComponent(clean)}`;
    const payload = await firstValueFrom(
      this.http.get<Array<Record<string, unknown>>>(url).pipe(timeout(6000)),
    );

    const first = payload?.[0];
    if (!first) {
      throw new Error(`No definition found for "${clean}".`);
    }

    const phonetics = Array.isArray(first['phonetics'])
      ? (first['phonetics'] as Array<Record<string, unknown>>)
      : [];
    const phoneticText =
      (first['phonetic'] as string | undefined) ||
      (phonetics.find((p) => typeof p['text'] === 'string')?.['text'] as
        | string
        | undefined);
    const audioUrl = phonetics.find(
      (p) => typeof p['audio'] === 'string' && String(p['audio']).startsWith('http'),
    )?.['audio'] as string | undefined;

    const rawMeanings = Array.isArray(first['meanings'])
      ? (first['meanings'] as Array<Record<string, unknown>>)
      : [];

    const meanings: DictionaryMeaning[] = rawMeanings.slice(0, 4).map((m) => {
      const rawDefs = Array.isArray(m['definitions'])
        ? (m['definitions'] as Array<Record<string, unknown>>)
        : [];
      return {
        partOfSpeech: String(m['partOfSpeech'] ?? ''),
        definitions: rawDefs.slice(0, 3).map((d) => ({
          definition: String(d['definition'] ?? ''),
          example: d['example'] ? String(d['example']) : undefined,
        })),
      };
    });

    const entry: DictionaryEntry = {
      word: String(first['word'] ?? clean),
      phonetic: phoneticText,
      audioUrl,
      meanings,
    };
    this.cache.set(clean, entry);
    return entry;
  }
}
