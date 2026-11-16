import { ChangeDetectionStrategy, Component, computed, input, output } from '@angular/core';

@Component({
  selector: 'app-book-reader-nav',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="reader-bottom-bar">
      <div class="progress-track">
        <div class="progress-fill" [style.width.%]="progressPercent()"></div>
      </div>
      <div class="nav-inner max-width-box">
        <button
          type="button"
          class="icon-btn"
          aria-label="Previous chapter"
          [disabled]="chapterIndex() <= 1"
          (click)="previous.emit()"
        >
          <span class="material-symbols-rounded">chevron_left</span>
        </button>

        <button type="button" class="center-meta" (click)="openToc.emit()">
          @if (chapterTitle()) {
            <span class="ch-title">{{ chapterTitle() }}</span>
          }
          <span class="ch-sub">
            Ch. {{ chapterIndex() }} of {{ totalChapters() }} · {{ progressPercent() }}%
          </span>
        </button>

        <button
          type="button"
          class="icon-btn"
          aria-label="Next chapter"
          [disabled]="chapterIndex() >= totalChapters()"
          (click)="next.emit()"
        >
          <span class="material-symbols-rounded">chevron_right</span>
        </button>
      </div>
    </div>
  `,
  styles: [
    `
      .reader-bottom-bar {
        position: fixed;
        left: 0;
        right: 0;
        bottom: var(--shell-bottom-height);
        z-index: 32;
        background-color: color-mix(in srgb, var(--surface) 86%, transparent);
        backdrop-filter: blur(14px);
        -webkit-backdrop-filter: blur(14px);
        border-top: 1px solid var(--surface-border);
      }

      @media (min-width: 600px) {
        .reader-bottom-bar {
          bottom: 0;
        }
      }

      .progress-track {
        height: 2px;
        background-color: var(--surface-border);
      }

      .progress-fill {
        height: 100%;
        background-color: var(--accent);
        transition: width 200ms ease;
      }

      .nav-inner {
        height: 54px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }

      .center-meta {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 1px;
        text-align: center;
      }

      .ch-title {
        max-width: 100%;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-size: 13px;
        font-weight: 600;
      }

      .ch-sub {
        font-size: 11px;
        color: var(--on-surface-muted);
      }

      .icon-btn[disabled] {
        opacity: 0.35;
        cursor: not-allowed;
      }
    `,
  ],
})
export class BookReaderNavComponent {
  readonly chapterIndex = input.required<number>();
  readonly totalChapters = input.required<number>();
  readonly chapterTitle = input<string>('');

  readonly previous = output<void>();
  readonly next = output<void>();
  readonly openToc = output<void>();

  readonly progressPercent = computed(() => {
    const total = Math.max(1, this.totalChapters());
    return Math.min(100, Math.round((this.chapterIndex() / total) * 100));
  });
}
