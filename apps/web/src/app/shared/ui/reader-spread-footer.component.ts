import { ChangeDetectionStrategy, Component, computed, input, output } from '@angular/core';

@Component({
  selector: 'app-reader-spread-footer',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <footer class="spread-footer" aria-label="Page navigation">
      <div class="progress-line" [style.width.%]="progressPct()"></div>

      <button
        type="button"
        class="pill-chip"
        [disabled]="!canPrev()"
        (click)="prevPage.emit()"
      >
        <span class="material-symbols-rounded">chevron_left</span>
        Prev
      </button>

      <span class="page-status">
        @if (label()) {
          <strong class="label-text">{{ label() }}</strong>
          <span class="dot">·</span>
        }
        <span>Page {{ page() }} of {{ totalPages() }}</span>
      </span>

      <button
        type="button"
        class="pill-chip"
        [disabled]="!canNext()"
        (click)="nextPage.emit()"
      >
        Next
        <span class="material-symbols-rounded">chevron_right</span>
      </button>
    </footer>
  `,
  styles: [
    `
      .spread-footer {
        position: relative;
        height: 52px;
        padding: 0 16px;
        background-color: var(--reader-bg, var(--surface));
        border-top: 1px solid var(--reader-border, var(--surface-border));
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        flex-shrink: 0;
      }

      .progress-line {
        position: absolute;
        top: -1px;
        left: 0;
        height: 2px;
        background-color: var(--accent);
        transition: width 200ms ease;
      }

      .page-status {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        font-size: 13px;
        color: var(--reader-muted, var(--on-surface-muted));
        min-width: 0;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .label-text {
        color: var(--reader-fg, var(--on-surface));
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .pill-chip:disabled {
        opacity: 0.4;
        cursor: not-allowed;
      }

      .pill-chip .material-symbols-rounded {
        font-size: 18px;
      }
    `,
  ],
})
export class ReaderSpreadFooterComponent {
  readonly label = input<string>('');
  readonly page = input<number>(1);
  readonly totalPages = input<number>(1);
  readonly hasPrevChapter = input<boolean>(false);
  readonly hasNextChapter = input<boolean>(false);

  readonly prevPage = output<void>();
  readonly nextPage = output<void>();

  readonly canPrev = computed(() => this.page() > 1 || this.hasPrevChapter());
  readonly canNext = computed(
    () => this.page() < this.totalPages() || this.hasNextChapter(),
  );
  readonly progressPct = computed(() => {
    const total = Math.max(1, this.totalPages());
    return Math.min(100, Math.round((this.page() / total) * 100));
  });
}
