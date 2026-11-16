import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';

@Component({
  selector: 'app-bible-reader-nav',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="bible-bottom-bar">
      <div class="nav-inner max-width-box">
        <button
          type="button"
          class="icon-btn"
          aria-label="Previous chapter"
          (click)="previous.emit()"
        >
          <span class="material-symbols-rounded">chevron_left</span>
        </button>

        <button
          type="button"
          class="center-meta"
          (click)="openPicker.emit()"
        >
          <span class="ch-title">
            {{ bookName() }} {{ chapter() }}
            <span class="material-symbols-rounded ch-chev">expand_more</span>
          </span>
          <span class="ch-sub">
            {{ versionLabel() }} · {{ verseCount() }} verses
          </span>
        </button>

        <button
          type="button"
          class="icon-btn"
          aria-label="Next chapter"
          (click)="next.emit()"
        >
          <span class="material-symbols-rounded">chevron_right</span>
        </button>
      </div>
    </div>
  `,
  styles: [
    `
      .bible-bottom-bar {
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
        .bible-bottom-bar {
          bottom: 0;
        }
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
        display: inline-flex;
        align-items: center;
        gap: 2px;
        max-width: 100%;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-size: 13px;
        font-weight: 600;
      }

      .ch-chev {
        font-size: 16px;
      }

      .ch-sub {
        font-size: 11px;
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class BibleReaderNavComponent {
  readonly bookName = input.required<string>();
  readonly chapter = input.required<number>();
  readonly versionLabel = input.required<string>();
  readonly verseCount = input.required<number>();

  readonly previous = output<void>();
  readonly next = output<void>();
  readonly openPicker = output<void>();
}
