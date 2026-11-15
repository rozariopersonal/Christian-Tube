import { Injectable, computed, inject, signal } from '@angular/core';
import { ReleaseDataService } from '../../../core/api/release-data.service';
import { BIBLE_VERSIONS, BibleVerse } from '../models/bible.model';
import { BibleService } from './bible.service';

@Injectable()
export class BibleReaderStateService {
  private readonly bible = inject(BibleService);
  private readonly releases = inject(ReleaseDataService);

  readonly selectedVerse = signal<BibleVerse | null>(null);

  readonly activeVersionInfo = computed(
    () =>
      BIBLE_VERSIONS.find((v) => v.id === this.bible.version()) ?? {
        id: this.bible.version(),
        label: this.bible.version().toUpperCase(),
        fullName: this.bible.version().toUpperCase(),
        language: '',
      },
  );

  readonly selectedCrossRefs = computed(() => {
    const v = this.selectedVerse()?.verse;
    if (!v) return [];
    return this.bible.crossRefs().find((x) => x.v === v)?.refs ?? [];
  });

  readonly selectedStudyTerms = computed(() => {
    const v = this.selectedVerse()?.verse;
    if (!v) return [];
    return (
      this.bible.study()?.terms?.filter((t) => t.reference?.verse === v) ?? []
    );
  });

  toggleSelectVerse(v: BibleVerse): void {
    this.selectedVerse.set(
      this.selectedVerse()?.verse === v.verse ? null : v,
    );
  }

  clearSelection(): void {
    this.selectedVerse.set(null);
  }

  highlightFor(verseNum: number): string {
    const color = this.bible.highlights()[this.bible.verseKey(verseNum)];
    return color ? `${color}55` : 'transparent';
  }

  noteFor(verseNum: number): string | undefined {
    return this.bible.notes()[this.bible.verseKey(verseNum)];
  }

  copySelected(): void {
    const v = this.selectedVerse();
    if (!v) return;
    const text = `${this.bible.currentBook().name} ${this.bible.chapter()}:${v.verse} (${this.bible.version().toUpperCase()}) — ${v.text}`;
    void navigator.clipboard?.writeText(text);
  }

  async loadVersesForChapter(
    bookNum: number,
    chapter: number,
  ): Promise<BibleVerse[]> {
    if (bookNum === this.bible.bookNumber() && chapter === this.bible.chapter()) {
      return this.bible.verses();
    }
    try {
      return await this.releases.getJson<BibleVerse[]>(
        `bibles/${this.bible.version()}/${bookNum}/${chapter}.json`,
      );
    } catch {
      return [];
    }
  }
}
