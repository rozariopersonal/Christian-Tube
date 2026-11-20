import {
  ChangeDetectionStrategy,
  Component,
  computed,
  inject,
  input,
  signal,
} from '@angular/core';
import { RouterLink } from '@angular/router';
import { BookCatalogItem, BookReadingProgress } from '../models/book.model';
import { BooksService } from '../services/books.service';

@Component({
  selector: 'app-book-card',
  standalone: true,
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <a class="book-card" [routerLink]="['/books', book().id]">
      <div class="cover-wrap">
        @if (activeCoverUrl(); as src) {
          <img
            class="cover"
            [src]="src"
            [alt]="book().title"
            loading="lazy"
            (error)="onCoverError()"
          />
        } @else {
          <div class="cover fallback-jacket">
            <span class="jacket-spine"></span>
            <strong class="jacket-title">{{ book().title }}</strong>
            <span class="jacket-author">{{ book().author }}</span>
          </div>
        }
        @if (progressPercent() !== null) {
          <div class="cover-progress-track">
            <div
              class="cover-progress-fill"
              [style.width.%]="progressPercent()"
            ></div>
          </div>
        }
      </div>
      <div class="book-meta">
        <h3 class="book-title">{{ book().title }}</h3>
        <p class="book-author">{{ book().author }}</p>
      </div>
    </a>
  `,
  styles: [
    `
      .book-card {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .cover-wrap {
        position: relative;
        aspect-ratio: 2 / 3;
        border-radius: var(--radius-sm);
        overflow: hidden;
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        box-shadow: 1px 3px 8px rgba(0, 0, 0, 0.2);
      }

      .cover {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }

      .cover.fallback-jacket {
        position: relative;
        padding: 14px 12px 14px 18px;
        display: flex;
        flex-direction: column;
        justify-content: space-between;
        background: linear-gradient(145deg, var(--surface-elevated), var(--surface-variant));
      }

      .jacket-spine {
        position: absolute;
        left: 0;
        top: 0;
        bottom: 0;
        width: 6px;
        background-color: var(--accent);
      }

      .jacket-title {
        font-size: 13px;
        line-height: 1.3;
      }

      .jacket-author {
        font-size: 11px;
        color: var(--on-surface-muted);
      }

      .cover-progress-track {
        position: absolute;
        left: 0;
        right: 0;
        bottom: 0;
        height: 4px;
        background-color: rgba(0, 0, 0, 0.35);
      }

      .cover-progress-fill {
        height: 100%;
        background-color: var(--accent);
      }

      .book-title {
        margin: 0;
        font-size: 14px;
        font-weight: 600;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .book-author {
        margin: 2px 0 0;
        font-size: 12px;
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class BookCardComponent {
  private readonly booksService = inject(BooksService);
  readonly book = input.required<BookCatalogItem>();
  readonly progress = input<BookReadingProgress | undefined>();
  readonly coverUrl = input<string | null>(null);

  private readonly fallbackIdx = signal<number>(0);

  readonly candidateUrls = computed<string[]>(() => {
    const file = this.book().coverFile;
    if (file) {
      return this.booksService.coverUrls(file);
    }
    const explicit = this.coverUrl();
    return explicit ? [explicit] : [];
  });

  readonly activeCoverUrl = computed<string | null>(() => {
    const urls = this.candidateUrls();
    const idx = this.fallbackIdx();
    return idx < urls.length ? urls[idx] : null;
  });

  onCoverError(): void {
    this.fallbackIdx.update((i) => i + 1);
  }

  readonly progressPercent = computed(() => {
    const p = this.progress();
    if (!p || p.totalChapters <= 0) return null;
    return (p.chapterIndex / p.totalChapters) * 100;
  });
}
