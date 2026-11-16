import {
  ChangeDetectionStrategy,
  Component,
  HostListener,
  OnInit,
  computed,
  inject,
  signal,
} from '@angular/core';
import { Router } from '@angular/router';
import { BOOK_ABBREVS } from '../../bible/models/bible.model';
import {
  WordFeedItem,
  WordsFeedService,
} from '../services/words-feed.service';

const PRESET_GRADIENTS: readonly string[] = [
  'linear-gradient(155deg, #1e3a8a 0%, #0f172a 100%)',
  'linear-gradient(155deg, #7c2d12 0%, #1c1917 100%)',
  'linear-gradient(155deg, #065f46 0%, #0f172a 100%)',
  'linear-gradient(155deg, #581c87 0%, #1e1b4b 100%)',
  'linear-gradient(155deg, #991b1b 0%, #18181b 100%)',
];

@Component({
  selector: 'app-words-feed',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div
      class="words-stage"
      [style.background]="gradientFor(activeIndex())"
    >
      <header class="stage-header">
        <div class="topic-strip">
          <button
            type="button"
            class="topic-chip"
            [class.active]="words.activeTopic() === 'daily'"
            (click)="selectTopic('daily')"
          >
            Daily Word
          </button>
          @for (t of words.manifest()?.topTopics?.slice(0, 14) ?? []; track t.slug) {
            <button
              type="button"
              class="topic-chip"
              [class.active]="words.activeTopic() === t.slug"
              (click)="selectTopic(t.slug)"
            >
              {{ t.name }}
            </button>
          }
        </div>
        @if (words.items().length > 0) {
          <span class="counter">
            {{ activeIndex() + 1 }} / {{ words.items().length }}
          </span>
        }
      </header>

      <div class="stage-body">
        @if (words.loading() && words.items().length === 0) {
          <p class="status-msg">Loading scripture...</p>
        } @else if (words.error()) {
          <div class="status-msg">
            <p>{{ words.error() }}</p>
            <button
              type="button"
              class="topic-chip active"
              (click)="words.loadDaily()"
            >
              Retry
            </button>
          </div>
        } @else if (currentItem(); as item) {
          <article class="word-spotlight">
            <div class="spotlight-meta">
              @if (item.theme) {
                <span class="theme-pill">{{ item.theme }}</span>
              }
              <span class="ver-tag">{{ words.versionId().toUpperCase() }}</span>
            </div>

            <blockquote class="verse-quote">
              “{{ item.verseText || item.theme || item.referenceLabel }}”
            </blockquote>

            <div class="spotlight-footer">
              <strong class="ref-label">{{ item.referenceLabel }}</strong>
              <button
                type="button"
                class="read-btn"
                (click)="openInBible(item)"
              >
                <span class="material-symbols-rounded">menu_book</span>
                Open in Bible
              </button>
            </div>
          </article>

          <div class="side-rail">
            <button
              type="button"
              class="rail-btn"
              title="Previous Word"
              [disabled]="activeIndex() <= 0"
              (click)="prev()"
            >
              <span class="material-symbols-rounded">keyboard_arrow_up</span>
            </button>
            <button
              type="button"
              class="rail-btn"
              title="Next Word"
              [disabled]="!canGoNext()"
              (click)="next()"
            >
              <span class="material-symbols-rounded">keyboard_arrow_down</span>
            </button>
            <button
              type="button"
              class="rail-btn"
              title="Copy Verse"
              (click)="copyWord(item)"
            >
              <span class="material-symbols-rounded">content_copy</span>
            </button>
            <button
              type="button"
              class="rail-btn"
              title="Share Verse"
              (click)="shareWord(item)"
            >
              <span class="material-symbols-rounded">share</span>
            </button>
          </div>
        } @else {
          <p class="status-msg">No scripture cards available.</p>
        }
      </div>
    </div>
  `,
  styles: [
    `
      .words-stage {
        height: calc(100dvh - var(--shell-bottom-height) - var(--shell-top-offset));
        color: #ffffff;
        display: flex;
        flex-direction: column;
        padding: 12px 16px;
        gap: 12px;
        transition: background 300ms ease;
      }

      @media (min-width: 600px) {
        .words-stage {
          height: calc(100dvh - var(--shell-top-offset));
          padding: 16px 28px;
        }
      }

      .stage-header {
        display: flex;
        align-items: center;
        gap: 12px;
      }

      .topic-strip {
        flex: 1;
        min-width: 0;
        display: flex;
        gap: 8px;
        overflow-x: auto;
        scrollbar-width: none;
      }

      .topic-strip::-webkit-scrollbar {
        display: none;
      }

      .topic-chip {
        height: 32px;
        padding: 0 12px;
        border-radius: var(--radius-pill);
        background-color: rgba(255, 255, 255, 0.14);
        color: #ffffff;
        font-size: 13px;
        font-weight: 500;
        white-space: nowrap;
        flex-shrink: 0;
      }

      .topic-chip.active {
        background-color: #ffffff;
        color: #0f172a;
        font-weight: 600;
      }

      .counter {
        font-size: 12px;
        font-weight: 600;
        color: rgba(255, 255, 255, 0.78);
        white-space: nowrap;
      }

      .stage-body {
        flex: 1;
        min-height: 0;
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 16px;
      }

      .word-spotlight {
        flex: 1;
        max-width: 720px;
        max-height: 100%;
        overflow-y: auto;
        padding: clamp(20px, 4vw, 40px);
        border-radius: var(--radius-lg);
        background-color: rgba(0, 0, 0, 0.24);
        backdrop-filter: blur(12px);
        -webkit-backdrop-filter: blur(12px);
        border: 1px solid rgba(255, 255, 255, 0.14);
        display: flex;
        flex-direction: column;
        gap: 20px;
      }

      .spotlight-meta {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }

      .theme-pill {
        font-size: 11px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        padding: 4px 10px;
        border-radius: var(--radius-pill);
        background-color: rgba(255, 255, 255, 0.16);
      }

      .ver-tag {
        font-size: 12px;
        font-weight: 700;
        opacity: 0.85;
      }

      .verse-quote {
        margin: 0;
        font-family: Georgia, serif;
        font-size: clamp(18px, 2.6vw, 26px);
        line-height: 1.55;
      }

      .spotlight-footer {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        flex-wrap: wrap;
        padding-top: 8px;
        border-top: 1px solid rgba(255, 255, 255, 0.14);
      }

      .ref-label {
        font-size: 15px;
        font-weight: 700;
      }

      .read-btn {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        height: 36px;
        padding: 0 14px;
        border-radius: var(--radius-pill);
        background-color: #ffffff;
        color: #0f172a;
        font-size: 13px;
        font-weight: 600;
      }

      .read-btn .material-symbols-rounded {
        font-size: 18px;
      }

      .side-rail {
        display: flex;
        flex-direction: column;
        gap: 10px;
        flex-shrink: 0;
      }

      .rail-btn {
        width: 44px;
        height: 44px;
        border-radius: var(--radius-pill);
        background-color: rgba(255, 255, 255, 0.16);
        color: #ffffff;
        display: grid;
        place-items: center;
      }

      .rail-btn[disabled] {
        opacity: 0.3;
        cursor: not-allowed;
      }

      .status-msg {
        text-align: center;
        color: rgba(255, 255, 255, 0.82);
      }
    `,
  ],
})
export class WordsFeedComponent implements OnInit {
  private readonly router = inject(Router);
  readonly words = inject(WordsFeedService);

  readonly activeIndex = signal<number>(0);

  readonly currentItem = computed<WordFeedItem | null>(
    () => this.words.items()[this.activeIndex()] ?? null,
  );

  readonly canGoNext = computed(
    () =>
      this.activeIndex() + 1 < this.words.items().length ||
      this.words.hasMore(),
  );

  @HostListener('window:keydown', ['$event'])
  onKeyDown(event: KeyboardEvent): void {
    if (event.key === 'ArrowDown' || event.key === 'ArrowRight') {
      this.next();
    } else if (event.key === 'ArrowUp' || event.key === 'ArrowLeft') {
      this.prev();
    }
  }

  ngOnInit(): void {
    void this.words.loadDaily();
  }

  selectTopic(slug: string): void {
    this.activeIndex.set(0);
    void this.words.loadTopic(slug);
  }

  prev(): void {
    if (this.activeIndex() > 0) {
      this.activeIndex.update((i) => i - 1);
    }
  }

  next(): void {
    const nextIdx = this.activeIndex() + 1;
    if (nextIdx < this.words.items().length) {
      this.activeIndex.set(nextIdx);
      if (
        this.words.hasMore() &&
        nextIdx >= this.words.items().length - 4
      ) {
        void this.words.loadMore();
      }
    } else if (this.words.hasMore()) {
      void this.words.loadMore();
    }
  }

  gradientFor(index: number): string {
    return PRESET_GRADIENTS[index % PRESET_GRADIENTS.length];
  }

  openInBible(item: WordFeedItem): void {
    const abbrev = BOOK_ABBREVS[item.bookNumber] || String(item.bookNumber);
    void this.router.navigate(['/bible'], {
      queryParams: {
        version: this.words.versionId(),
        book: abbrev,
        chapter: item.chapter,
        verse: item.startVerse,
      },
    });
  }

  copyWord(item: WordFeedItem): void {
    const text = item.verseText
      ? `"${item.verseText}" — ${item.referenceLabel} (${this.words.versionId().toUpperCase()})`
      : item.referenceLabel;
    void navigator.clipboard?.writeText(text);
  }

  shareWord(item: WordFeedItem): void {
    const abbrev = BOOK_ABBREVS[item.bookNumber] || String(item.bookNumber);
    const url = `${window.location.origin}/bible?version=${encodeURIComponent(this.words.versionId())}&book=${encodeURIComponent(abbrev)}&chapter=${item.chapter}&verse=${item.startVerse}`;
    if (navigator.share) {
      void navigator.share({ title: item.referenceLabel, url }).catch(() => {
        void navigator.clipboard?.writeText(url);
      });
    } else {
      void navigator.clipboard?.writeText(url);
    }
  }
}
