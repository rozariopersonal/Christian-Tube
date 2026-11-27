import { Injectable, Signal, computed, inject, signal } from '@angular/core';
import { BIBLE_VERSIONS } from '../../features/bible/models/bible.model';
import { ReaderAppearanceService } from './reader-appearance.service';

export const DEFAULT_MAX_VERSIONS = 3;
const STORAGE_PREFIX = 'bible_ctx_versions_';

interface ContextVersionState {
  primary: string;
  comparisons: string[];
}

@Injectable({ providedIn: 'root' })
export class BibleVersionSelectionService {
  private readonly appearance = inject(ReaderAppearanceService);
  private readonly stateMap = new Map<
    string,
    ReturnType<typeof signal<ContextVersionState>>
  >();

  selectedVersionsSignal(
    contextKey: string,
    maxSelections = DEFAULT_MAX_VERSIONS,
  ): Signal<string[]> {
    const stateSig = this.ensureContext(contextKey);
    return computed(() => {
      const s = stateSig();
      return [s.primary, ...s.comparisons].slice(0, Math.max(1, maxSelections));
    });
  }

  getSelectedVersions(
    contextKey: string,
    maxSelections = DEFAULT_MAX_VERSIONS,
  ): string[] {
    const s = this.ensureContext(contextKey)();
    return [s.primary, ...s.comparisons].slice(0, Math.max(1, maxSelections));
  }

  getPrimaryVersion(contextKey: string): string {
    return this.ensureContext(contextKey)().primary;
  }

  getComparisonVersions(contextKey: string): string[] {
    return this.ensureContext(contextKey)().comparisons;
  }

  setSelection(
    contextKey: string,
    primary: string,
    comparisons: string[] = [],
    maxSelections = DEFAULT_MAX_VERSIONS,
  ): void {
    const cleanPrimary = this.normalizeId(primary);
    const maxCmp = Math.max(0, maxSelections - 1);
    const cleanCmp = comparisons
      .map((c) => c.toLowerCase())
      .filter((c, idx, arr) => c && c !== cleanPrimary && arr.indexOf(c) === idx)
      .slice(0, maxCmp);
    this.writeState(contextKey, {
      primary: cleanPrimary,
      comparisons: cleanCmp,
    });
  }

  selectSingle(
    contextKey: string,
    versionId: string,
  ): 'primary-changed' | 'noop' {
    const clean = versionId.toLowerCase();
    const cur = this.ensureContext(contextKey)();
    if (clean === cur.primary && cur.comparisons.length === 0) {
      return 'noop';
    }
    this.writeState(contextKey, { primary: clean, comparisons: [] });
    return 'primary-changed';
  }

  toggleVersion(
    contextKey: string,
    versionId: string,
    maxSelections = DEFAULT_MAX_VERSIONS,
  ): 'primary-changed' | 'comparison-changed' | 'noop' {
    const clean = versionId.toLowerCase();
    const sig = this.ensureContext(contextKey);
    const cur = sig();

    if (maxSelections <= 1) {
      if (clean === cur.primary) return 'noop';
      this.writeState(contextKey, { primary: clean, comparisons: [] });
      return 'primary-changed';
    }

    if (clean === cur.primary) {
      if (cur.comparisons.length === 0) return 'noop';
      const [nextPrimary, ...rest] = cur.comparisons;
      this.writeState(contextKey, {
        primary: nextPrimary,
        comparisons: rest,
      });
      return 'primary-changed';
    }

    if (cur.comparisons.includes(clean)) {
      this.writeState(contextKey, {
        primary: cur.primary,
        comparisons: cur.comparisons.filter((v) => v !== clean),
      });
      return 'comparison-changed';
    }

    const maxCmp = Math.max(0, maxSelections - 1);
    const nextCmp =
      cur.comparisons.length >= maxCmp
        ? [...cur.comparisons.slice(0, Math.max(0, maxCmp - 1)), clean]
        : [...cur.comparisons, clean];
    this.writeState(contextKey, {
      primary: cur.primary,
      comparisons: nextCmp,
    });
    return 'comparison-changed';
  }

  promoteToPrimary(
    contextKey: string,
    versionId: string,
    maxSelections = DEFAULT_MAX_VERSIONS,
  ): boolean {
    const clean = versionId.toLowerCase();
    const cur = this.ensureContext(contextKey)();
    if (clean === cur.primary) return false;
    const maxCmp = Math.max(0, maxSelections - 1);
    const nextCmp = [
      cur.primary,
      ...cur.comparisons.filter((v) => v !== clean),
    ].slice(0, maxCmp);
    this.writeState(contextKey, {
      primary: clean,
      comparisons: nextCmp,
    });
    return true;
  }

  private ensureContext(contextKey: string) {
    let sig = this.stateMap.get(contextKey);
    if (!sig) {
      sig = signal<ContextVersionState>(this.readState(contextKey));
      this.stateMap.set(contextKey, sig);
    }
    return sig;
  }

  private readState(contextKey: string): ContextVersionState {
    const fallbackPrimary = this.normalizeId(
      this.appearance.primaryBibleVersion(),
    );
    try {
      const raw = localStorage.getItem(`${STORAGE_PREFIX}${contextKey}`);
      if (!raw) {
        return { primary: fallbackPrimary, comparisons: [] };
      }
      const parsed = JSON.parse(raw) as Partial<ContextVersionState>;
      const primary = this.normalizeId(parsed.primary ?? fallbackPrimary);
      const comparisons = Array.isArray(parsed.comparisons)
        ? parsed.comparisons
            .map((v) => String(v).toLowerCase())
            .filter((v, idx, arr) => v && v !== primary && arr.indexOf(v) === idx)
            .slice(0, DEFAULT_MAX_VERSIONS - 1)
        : [];
      return { primary, comparisons };
    } catch {
      return { primary: fallbackPrimary, comparisons: [] };
    }
  }

  private writeState(contextKey: string, state: ContextVersionState): void {
    this.ensureContext(contextKey).set(state);
    try {
      localStorage.setItem(
        `${STORAGE_PREFIX}${contextKey}`,
        JSON.stringify(state),
      );
    } catch {
      // ignore storage quota errors
    }
  }

  private normalizeId(raw?: string | null): string {
    const clean = (raw ?? '').trim().toLowerCase();
    return BIBLE_VERSIONS.some((v) => v.id === clean) ? clean : 'nasb';
  }
}
