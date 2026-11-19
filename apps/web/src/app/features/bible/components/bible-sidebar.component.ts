import {
  ChangeDetectionStrategy,
  Component,
  computed,
  input,
  output,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { BibleBook } from '../models/bible.model';

@Component({
  selector: 'app-bible-sidebar',
  standalone: true,
  imports: [FormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div
      class="nav-shell"
      [class.pinned]="pinned()"
      [class.open]="isOpen()"
      (mouseenter)="hovered.set(true)"
      (mouseleave)="hovered.set(false)"
    >
      @if (!isOpen()) {
        <div class="collapsed-rail">
          <button
            type="button"
            class="rail-toggle-btn"
            title="Expand & pin Bible navigator"
            aria-label="Expand & pin Bible navigator"
            (click)="togglePin()"
          >
            <span class="material-symbols-rounded">left_panel_open</span>
          </button>
          <span class="rail-badge" [title]="versionLabel() + ' · Ch. ' + currentChapter()">
            <span class="material-symbols-rounded rail-ic">menu_book</span>
            <span class="rail-ch">{{ currentChapter() }}</span>
          </span>
        </div>
      }

      <aside
        class="bible-sidebar"
        [class.floating]="!pinned() && hovered()"
        [class.hidden]="!isOpen()"
        aria-label="Bible books and chapters"
      >
        <div class="sidebar-header">
          <div class="sidebar-tabs">
            <button
              type="button"
              class="sidebar-ver-btn"
              (click)="openVersionPicker.emit()"
              aria-label="Bible Version"
              title="Switch Bible version"
            >
              <span class="ver-icon">
                <span class="material-symbols-rounded">menu_book</span>
              </span>
              <span class="ver-text">{{ versionLabel() }}</span>
              <span class="material-symbols-rounded ver-chev">expand_more</span>
            </button>

            <button
              type="button"
              class="sidebar-tab"
              [class.active]="testament() === 'all'"
              (click)="testament.set('all')"
            >
              All
            </button>
            <button
              type="button"
              class="sidebar-tab"
              [class.active]="testament() === 'ot'"
              (click)="testament.set('ot')"
            >
              OT
            </button>
            <button
              type="button"
              class="sidebar-tab"
              [class.active]="testament() === 'nt'"
              (click)="testament.set('nt')"
            >
              NT
            </button>
            <button
              type="button"
              class="pin-btn"
              [class.active]="pinned()"
              [title]="pinned() ? 'Collapse navigator (hover to expand)' : 'Keep navigator expanded'"
              [attr.aria-label]="pinned() ? 'Collapse navigator' : 'Keep navigator expanded'"
              (click)="togglePin()"
            >
              <span class="material-symbols-rounded">
                {{ pinned() ? 'left_panel_close' : 'keep' }}
              </span>
            </button>
          </div>
          <input
            type="search"
            class="sidebar-filter"
            [ngModel]="filter()"
            (ngModelChange)="filter.set($event)"
            placeholder="Filter books..."
            aria-label="Filter Bible books"
          />
        </div>

        <nav class="sidebar-list">
          @for (b of filteredBooks(); track b.bookNumber) {
            @let isExpanded = activeExpandedBook() === b.bookNumber;
            <div>
              <button
                type="button"
                class="sidebar-item"
                [class.active]="b.bookNumber === currentBookNumber()"
                (click)="toggleBook(b.bookNumber)"
              >
                <span class="sidebar-ch-title">{{ b.name }}</span>
                <span class="sidebar-count">{{ b.chapters }}</span>
              </button>
              @if (isExpanded) {
                <div class="sidebar-ch-grid">
                  @for (ch of chaptersFor(b.chapters); track ch) {
                    <button
                      type="button"
                      class="sidebar-ch-btn"
                      [class.active]="
                        b.bookNumber === currentBookNumber() &&
                        ch === currentChapter()
                      "
                      (click)="selectChapter.emit({ bookNumber: b.bookNumber, chapter: ch })"
                    >
                      {{ ch }}
                    </button>
                  }
                </div>
              }
            </div>
          }
        </nav>
      </aside>
    </div>
  `,
  styles: [
    `
      :host {
        display: block;
        position: sticky;
        top: var(--shell-top-offset);
        align-self: flex-start;
        flex-shrink: 0;
        z-index: 25;
      }

      .nav-shell {
        position: relative;
        width: 44px;
        height: calc(100dvh - var(--shell-top-offset));
      }

      .nav-shell.pinned {
        width: 268px;
      }

      .collapsed-rail {
        width: 44px;
        height: 100%;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 10px;
        padding: 10px 4px;
        border-right: 1px solid var(--reader-border, var(--surface-border));
        background-color: color-mix(in srgb, var(--reader-bg, var(--bg)) 96%, var(--on-surface) 4%);
      }

      .rail-toggle-btn,
      .pin-btn {
        width: 30px;
        height: 30px;
        border-radius: var(--radius-sm);
        display: grid;
        place-items: center;
        color: var(--on-surface-muted);
        flex-shrink: 0;
      }

      .rail-toggle-btn:hover,
      .pin-btn:hover {
        background-color: var(--surface-variant);
        color: var(--on-surface);
      }

      .pin-btn.active {
        color: var(--accent);
        background-color: var(--accent-soft);
      }

      .rail-toggle-btn .material-symbols-rounded,
      .pin-btn .material-symbols-rounded {
        font-size: 18px;
      }

      .rail-badge {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 2px;
        padding: 6px 4px;
        border-radius: var(--radius-sm);
        background-color: var(--accent-soft);
        color: var(--accent);
        width: 34px;
      }

      .rail-ic {
        font-size: 16px;
      }

      .rail-ch {
        font-size: 11px;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
      }

      .bible-sidebar {
        width: 268px;
        height: calc(100dvh - var(--shell-top-offset));
        display: flex;
        flex-direction: column;
        border-right: 1px solid var(--reader-border, var(--surface-border));
        background-color: color-mix(in srgb, var(--reader-bg, var(--bg)) 96%, var(--on-surface) 4%);
      }

      .bible-sidebar.floating {
        position: absolute;
        top: 0;
        left: 0;
        z-index: 30;
        background-color: var(--reader-bg, var(--surface));
        box-shadow: 6px 0 24px rgba(0, 0, 0, 0.18);
      }

      .bible-sidebar.hidden {
        display: none;
      }

      .sidebar-header {
        padding: 12px 12px 10px;
        border-bottom: 1px solid var(--reader-border, var(--surface-border));
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .sidebar-tabs {
        display: flex;
        align-items: center;
        gap: 4px;
      }

      .sidebar-ver-btn {
        flex: 1;
        min-width: 0;
        height: 32px;
        display: inline-flex;
        align-items: center;
        gap: 6px;
        padding: 0 6px 0 4px;
        border-radius: var(--radius-sm);
        font-size: 12px;
        font-weight: 600;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        color: var(--on-surface);
      }

      .sidebar-ver-btn:hover {
        background-color: var(--surface-variant);
      }

      .ver-icon {
        width: 22px;
        height: 22px;
        border-radius: 6px;
        background-color: var(--accent-soft);
        color: var(--accent);
        display: grid;
        place-items: center;
        flex-shrink: 0;
      }

      .ver-icon .material-symbols-rounded {
        font-size: 14px;
      }

      .ver-text {
        flex: 1;
        text-align: left;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .ver-chev {
        font-size: 16px;
        color: var(--on-surface-muted);
        flex-shrink: 0;
      }

      .sidebar-tab {
        height: 32px;
        padding: 0 8px;
        border-radius: var(--radius-sm);
        font-size: 11px;
        font-weight: 700;
        flex-shrink: 0;
        color: var(--reader-muted, var(--on-surface-muted));
        background-color: var(--reader-bg, var(--bg));
        border: 1px solid var(--reader-border, var(--surface-border));
      }

      .sidebar-tab.active {
        background-color: var(--accent-soft);
        border-color: var(--accent);
        color: var(--accent);
      }

      .sidebar-filter {
        width: 100%;
        padding: 7px 10px;
        border-radius: var(--radius-sm);
        border: 1px solid var(--reader-border, var(--surface-border));
        background-color: var(--reader-bg, var(--bg));
        color: var(--reader-fg, var(--on-surface));
        font-size: 13px;
      }

      .sidebar-list {
        flex: 1;
        overflow-y: auto;
        padding: 8px;
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .sidebar-item {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        width: 100%;
        padding: 7px 10px;
        border-radius: var(--radius-sm);
        text-align: left;
        font-size: 13px;
        color: var(--reader-fg, var(--on-surface));
      }

      .sidebar-item:hover {
        background-color: color-mix(in srgb, var(--accent) 8%, transparent);
      }

      .sidebar-item.active {
        background-color: var(--accent-soft);
        color: var(--accent);
        font-weight: 700;
      }

      .sidebar-ch-title {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .sidebar-count {
        font-size: 11px;
        opacity: 0.65;
        font-variant-numeric: tabular-nums;
      }

      .sidebar-ch-grid {
        display: grid;
        grid-template-columns: repeat(5, minmax(0, 1fr));
        gap: 4px;
        padding: 6px 6px 10px;
      }

      .sidebar-ch-btn {
        height: 28px;
        border-radius: var(--radius-sm);
        border: 1px solid var(--reader-border, var(--surface-border));
        background-color: var(--reader-bg, var(--bg));
        color: var(--reader-fg, var(--on-surface));
        font-size: 12px;
        font-weight: 600;
        font-variant-numeric: tabular-nums;
      }

      .sidebar-ch-btn:hover {
        border-color: var(--accent);
        color: var(--accent);
      }

      .sidebar-ch-btn.active {
        background-color: var(--accent);
        border-color: var(--accent);
        color: #fff;
      }
    `,
  ],
})
export class BibleSidebarComponent {
  readonly books = input.required<BibleBook[]>();
  readonly currentBookNumber = input.required<number>();
  readonly currentChapter = input.required<number>();
  readonly versionLabel = input<string>('NASB');
  readonly selectChapter = output<{ bookNumber: number; chapter: number }>();
  readonly openVersionPicker = output<void>();

  readonly testament = signal<'all' | 'ot' | 'nt'>('all');
  readonly filter = signal<string>('');
  readonly manualExpanded = signal<number | null>(null);
  readonly pinned = signal<boolean>(this.readPinned());
  readonly hovered = signal<boolean>(false);

  readonly isOpen = computed(() => this.pinned() || this.hovered());

  togglePin(): void {
    const next = !this.pinned();
    this.pinned.set(next);
    try {
      localStorage.setItem('bible_nav_pinned', next ? '1' : '0');
    } catch {
      // ignore
    }
  }

  private readPinned(): boolean {
    try {
      return localStorage.getItem('bible_nav_pinned') === '1';
    } catch {
      return false;
    }
  }

  readonly activeExpandedBook = computed(
    () => this.manualExpanded() ?? this.currentBookNumber(),
  );

  readonly filteredBooks = computed(() => {
    const test = this.testament();
    const q = this.filter().trim().toLowerCase();
    return this.books().filter((b) => {
      if (test === 'ot' && b.bookNumber > 39) return false;
      if (test === 'nt' && b.bookNumber <= 39) return false;
      if (q && !b.name.toLowerCase().includes(q)) return false;
      return true;
    });
  });

  toggleBook(bookNumber: number): void {
    this.manualExpanded.set(
      this.activeExpandedBook() === bookNumber ? -1 : bookNumber,
    );
  }

  chaptersFor(count: number): number[] {
    return Array.from({ length: count }, (_, i) => i + 1);
  }
}
