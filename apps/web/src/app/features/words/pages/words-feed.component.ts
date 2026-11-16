import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  inject,
} from '@angular/core';
import { Router } from '@angular/router';
import { BOOK_ABBREVS } from '../../bible/models/bible.model';
import {
  WordFeedItem,
  WordsFeedService,
} from '../services/words-feed.service';

const PRESET_GRADIENTS: readonly string[] = [
  'linear-gradient(135deg, #1e3a8a, #0f172a)',
  'linear-gradient(135deg, #7c2d12, #1c1917)',
  'linear-gradient(135deg, #065f46, #0f172a)',
  'linear-gradient(135deg, #581c87, #1e1b4b)',
  'linear-gradient(135deg, #991b1b, #18181b)',
];

@Component({
  selector: 'app-words-feed',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="words-page max-width-box">
      <header class="page-head">
        <h1 class="font-display">Word Feed</h1>
      </header>

      <div class="topic-strip">
        <button
          type="button"
          class="pill-chip"
          [class.active]="words.activeTopic() === 'daily'"
          (click)="words.loadDaily()"
        >
          Daily Word
        </button>
        @for (t of words.manifest()?.topTopics?.slice(0, 14) ?? []; track t.slug) {
          <button
            type="button"
            class="pill-chip"
            [class.active]="words.activeTopic() === t.slug"
            (click)="words.loadTopic(t.slug)"
          >
            {{ t.name }}
          </button>
        }
      </div>

      @if (words.loading() && words.items().length === 0) {
        <p class="status-msg">Loading scripture feed...</p>
      } @else if (words.error()) {
        <div class="status-msg">
          <p>{{ words.error() }}</p>
          <button
            type="button"
            class="pill-chip active"
            (click)="words.loadDaily()"
          >
            Retry
          </button>
        </div>
      } @else {
        <div class="words-grid">
          @for (item of words.items(); track $index) {
            <article
              class="word-card"
              [style.background]="gradientFor($index)"
            >
              <div class="card-top">
                @if (item.theme) {
                  <span class="theme-pill">{{ item.theme }}</span>
                }
                <span class="ver-tag">{{ words.versionId().toUpperCase() }}</span>
              </div>

              <blockquote class="verse-quote">
                “{{ item.verseText || item.theme || item.referenceLabel }}”
              </blockquote>

              <div class="card-bottom">
                <strong class="ref-label">{{ item.referenceLabel }}</strong>
                <div class="card-actions">
                  <button
                    type="button"
                    class="action-pill"
                    (click)="copyWord(item)"
                  >
                    <span class="material-symbols-rounded">content_copy</span>
                  </button>
                  <button
                    type="button"
                    class="action-pill"
                    (click)="shareWord(item)"
                  >
                    <span class="material-symbols-rounded">share</span>
                  </button>
                  <button
                    type="button"
                    class="action-pill primary"
                    (click)="openInBible(item)"
                  >
                    Read
                  </button>
                </div>
              </div>
            </article>
          }
        </div>
      }
    </div>
  `,
  styles: [
    `
      .words-page {
        padding-top: 16px;
        padding-bottom: 32px;
      }

      .page-head h1 {
        margin: 0 0 14px;
        font-size: 22px;
        font-weight: 700;
      }

      .topic-strip {
        display: flex;
        gap: 8px;
        overflow-x: auto;
        padding-bottom: 12px;
        margin-bottom: 14px;
        scrollbar-width: none;
      }

      .topic-strip::-webkit-scrollbar {
        display: none;
      }

      .words-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
        gap: 16px;
      }

      .word-card {
        border-radius: var(--radius-lg);
        padding: 18px;
        color: #ffffff;
        display: flex;
        flex-direction: column;
        gap: 14px;
        min-height: 210px;
        box-shadow: 0 6px 18px rgba(0, 0, 0, 0.22);
      }

      .card-top {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }

      .theme-pill {
        font-size: 11px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        padding: 3px 9px;
        border-radius: var(--radius-pill);
        background-color: rgba(255, 255, 255, 0.16);
      }

      .ver-tag {
        font-size: 11px;
        font-weight: 700;
        opacity: 0.85;
      }

      .verse-quote {
        margin: 0;
        font-family: Georgia, serif;
        font-size: 16px;
        line-height: 1.55;
        flex: 1;
      }

      .card-bottom {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        flex-wrap: wrap;
      }

      .ref-label {
        font-size: 13px;
        font-weight: 700;
      }

      .card-actions {
        display: flex;
        align-items: center;
        gap: 6px;
      }

      .action-pill {
        height: 30px;
        padding: 0 10px;
        border-radius: var(--radius-pill);
        background-color: rgba(255, 255, 255, 0.16);
        color: #ffffff;
        font-size: 12px;
        font-weight: 600;
        display: inline-flex;
        align-items: center;
        gap: 4px;
      }

      .action-pill .material-symbols-rounded {
        font-size: 16px;
      }

      .action-pill.primary {
        background-color: #ffffff;
        color: #0f172a;
      }

      .status-msg {
        text-align: center;
        padding: 36px 0;
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class WordsFeedComponent implements OnInit {
  private readonly router = inject(Router);
  readonly words = inject(WordsFeedService);

  ngOnInit(): void {
    void this.words.loadDaily();
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
