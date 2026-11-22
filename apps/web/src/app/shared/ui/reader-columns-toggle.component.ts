import {
  ChangeDetectionStrategy,
  Component,
  computed,
  inject,
  input,
} from '@angular/core';
import { ScreenClassService } from '../../core/layout/screen-class.service';
import { ReaderAppearanceService } from '../../core/services/reader-appearance.service';

@Component({
  selector: 'app-reader-columns-toggle',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (hasLayoutOptions()) {
      <div class="reader-toolbar-seg">
        <div class="cols-seg" role="group" aria-label="Reader layout and columns">
          @if (options().length > 1) {
            <span class="material-symbols-rounded cols-icon" aria-hidden="true">view_column</span>
            @for (c of options(); track c) {
              <button
                type="button"
                class="col-btn"
                [class.active]="activeCols() === c"
                [title]="c + (c === 1 ? ' column' : ' columns')"
                (click)="appearance.setBookColumns(c)"
              >
                {{ c }}
              </button>
            }
          }

          @if (allowContinuous() && activeCols() === 1 && options().length > 1) {
            <span class="seg-divider" aria-hidden="true"></span>
            <button
              type="button"
              class="layout-btn"
              [class.active]="appearance.singleColPaginated()"
              [title]="
                appearance.singleColPaginated()
                  ? 'Paginated pages (click for vertical scroll)'
                  : 'Vertical scroll (click for paginated pages)'
              "
              aria-label="Toggle single-column pagination"
              (click)="appearance.toggleSingleColPaginated()"
            >
              <span class="material-symbols-rounded">menu_book</span>
            </button>
          }

          @if (showLayoutToggle()) {
            @if (options().length > 1) {
              <span class="seg-divider" aria-hidden="true"></span>
            }
            <button
              type="button"
              class="layout-btn"
              [class.active]="appearance.bibleLayout() === 'verses'"
              title="Verse by verse"
              aria-label="Verse by verse"
              (click)="appearance.setBibleLayout('verses')"
            >
              <span class="material-symbols-rounded">format_list_numbered</span>
            </button>
            <button
              type="button"
              class="layout-btn"
              [class.active]="appearance.bibleLayout() === 'paragraph'"
              title="Paragraph flow"
              aria-label="Paragraph flow"
              (click)="appearance.setBibleLayout('paragraph')"
            >
              <span class="material-symbols-rounded">subject</span>
            </button>
          }
        </div>
      </div>
    }
  `,
  styles: [
    `
      .reader-toolbar-seg {
        position: relative;
        display: inline-flex;
        align-items: center;
      }

      .cols-seg {
        display: inline-flex;
        align-items: center;
        gap: 2px;
        height: 32px;
        padding: 0 4px 0 8px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .cols-icon {
        font-size: 16px;
        color: var(--on-surface-muted);
        margin-right: 2px;
      }

      .col-btn,
      .layout-btn {
        width: 24px;
        height: 24px;
        border-radius: var(--radius-pill);
        font-size: 12px;
        font-weight: 700;
        color: var(--on-surface-muted);
        display: grid;
        place-items: center;
      }

      .layout-btn .material-symbols-rounded {
        font-size: 15px;
      }

      .col-btn.active,
      .layout-btn.active {
        background-color: var(--accent);
        color: var(--on-accent);
      }

      .seg-divider {
        width: 1px;
        height: 16px;
        background-color: var(--surface-border);
        margin: 0 3px;
      }
    `,
  ],
})
export class ReaderColumnsToggleComponent {
  readonly screen = inject(ScreenClassService);
  readonly appearance = inject(ReaderAppearanceService);

  readonly showLayoutToggle = input<boolean>(false);
  readonly maxColumns = input<2 | 3>(3);
  readonly allowContinuous = input(true);
  readonly hideSpacing = input<boolean>(false);

  readonly options = computed<readonly (1 | 2 | 3)[]>(() => {
    const cls = this.screen.screenClass();
    if (cls === 'compact') return [];
    if (cls === 'medium' || this.maxColumns() === 2) return [1, 2];
    return [1, 2, 3];
  });

  readonly activeCols = computed(() => {
    const cols = this.appearance.effectiveColumns(this.screen.screenClass());
    return Math.min(this.maxColumns(), cols) as 1 | 2 | 3;
  });

  readonly hasLayoutOptions = computed(() => {
    return this.options().length > 1 || this.showLayoutToggle();
  });
}
