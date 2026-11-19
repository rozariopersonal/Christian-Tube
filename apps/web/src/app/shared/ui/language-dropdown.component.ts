import { Component, computed, inject, input, output, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ContentPreferencesService } from '../../core/services/content-preferences.service';
import { countNoun, languageMetaFromCode } from './language-meta';

@Component({
  selector: 'app-language-dropdown',
  standalone: true,
  imports: [FormsModule],
  template: `
    <button
      type="button"
      class="lang-trigger"
      (click)="openSheet()"
      [attr.aria-label]="headerTitle()"
    >
      <span class="trigger-icon">
        <span class="material-symbols-rounded">translate</span>
      </span>
      <span class="trigger-text">
        <span class="trigger-title">{{ summary().title }}</span>
      </span>
      @if (summary().count > 0) {
        <span class="count-pill">{{ summary().count }} {{ nounLabel(summary().count) }}</span>
      }
      <span class="material-symbols-rounded chevron">expand_more</span>
    </button>

    @if (open()) {
      <div class="modal-backdrop" (click)="open.set(false)">
        <div class="modal-panel lang-sheet" (click)="$event.stopPropagation()">
          <div class="sheet-head">
            <div class="head-left">
              <span class="material-symbols-rounded head-icon">translate</span>
              <h2 class="font-display">{{ headerTitle() }}</h2>
            </div>
            <button type="button" class="icon-btn" (click)="open.set(false)">
              <span class="material-symbols-rounded">close</span>
            </button>
          </div>

          @if (visibleLanguages().length >= searchThreshold()) {
            <div class="sheet-search">
              <span class="material-symbols-rounded">search</span>
              <input
                type="search"
                placeholder="Search languages..."
                [ngModel]="search()"
                (ngModelChange)="search.set($event)"
              />
            </div>
          }

          <div class="lang-list">
            <button
              type="button"
              class="lang-row"
              [class.selected]="draftIsAll()"
              (click)="selectAllDraft()"
            >
              <span class="material-symbols-rounded check-icon">
                {{ draftIsAll() ? 'check_circle' : 'radio_button_unchecked' }}
              </span>
              <div class="row-labels">
                <strong>All Languages</strong>
                <span class="native-sub">Show all available content</span>
              </div>
              <span class="row-count">
                {{ itemCounts()['All'] ?? 0 }} {{ nounLabel(itemCounts()['All'] ?? 0) }}
              </span>
            </button>

            @for (code of primaryDisplayedLanguages(); track code) {
              @let meta = metaFor(code);
              @let count = itemCounts()[code] ?? 0;
              @let checked = !draftIsAll() && draftSet().has(code);
              <button
                type="button"
                class="lang-row"
                [class.selected]="checked"
                (click)="toggleDraft(code)"
              >
                <span class="material-symbols-rounded check-icon">
                  {{ checked ? 'check_box' : 'check_box_outline_blank' }}
                </span>
                <div class="row-labels">
                  <strong>{{ meta.englishName }}</strong>
                  @if (meta.nativeName && meta.nativeName !== meta.englishName) {
                    <span class="native-sub">{{ meta.nativeName }}</span>
                  }
                </div>
                <span class="row-count">{{ count }} {{ nounLabel(count) }}</span>
              </button>
            }

            @if (!search().trim() && otherLanguages().length > 0) {
              <button
                type="button"
                class="more-toggle-btn"
                (click)="showOthers.set(!showOthers())"
              >
                <span>
                  {{ showOthers() ? 'Hide other languages' : 'More languages (' + otherLanguages().length + ')' }}
                </span>
                <span class="material-symbols-rounded">
                  {{ showOthers() ? 'expand_less' : 'expand_more' }}
                </span>
              </button>

              @if (showOthers()) {
                @for (code of otherLanguages(); track code) {
                  @let meta = metaFor(code);
                  @let count = itemCounts()[code] ?? 0;
                  @let checked = !draftIsAll() && draftSet().has(code);
                  <button
                    type="button"
                    class="lang-row"
                    [class.selected]="checked"
                    (click)="toggleDraft(code)"
                  >
                    <span class="material-symbols-rounded check-icon">
                      {{ checked ? 'check_box' : 'check_box_outline_blank' }}
                    </span>
                    <div class="row-labels">
                      <strong>{{ meta.englishName }}</strong>
                      @if (meta.nativeName && meta.nativeName !== meta.englishName) {
                        <span class="native-sub">{{ meta.nativeName }}</span>
                      }
                    </div>
                    <span class="row-count">{{ count }} {{ nounLabel(count) }}</span>
                  </button>
                }
              }
            }
          </div>

          <div class="sheet-footer">
            <button type="button" class="pill-chip" (click)="selectAllDraft()">
              Reset
            </button>
            <button type="button" class="pill-chip active" (click)="apply()">
              Apply
            </button>
          </div>
        </div>
      </div>
    }
  `,
  styles: [
    `
      :host {
        display: inline-flex;
        align-items: center;
        flex-shrink: 0;
      }

      .lang-trigger {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        height: 32px;
        padding: 0 8px 0 5px;
        border-radius: var(--radius-sm);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        text-align: left;
        max-width: 100%;
      }

      .lang-trigger:hover {
        background-color: var(--surface-variant);
      }

      .trigger-icon {
        width: 22px;
        height: 22px;
        border-radius: 6px;
        background-color: var(--accent-soft);
        color: var(--accent);
        display: grid;
        place-items: center;
        flex-shrink: 0;
      }

      .trigger-icon .material-symbols-rounded {
        font-size: 15px;
      }

      .trigger-text {
        display: flex;
        flex-direction: column;
        min-width: 0;
      }

      .trigger-title {
        font-size: 13px;
        font-weight: 600;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .trigger-sub {
        font-size: 11px;
        color: var(--on-surface-muted);
        white-space: nowrap;
      }

      .count-pill {
        padding: 2px 8px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        color: var(--on-surface-muted);
        font-size: 11px;
        font-weight: 600;
        white-space: nowrap;
      }

      .chevron {
        color: var(--on-surface-muted);
        font-size: 18px;
      }

      .lang-sheet {
        padding: 18px;
        gap: 12px;
      }

      .sheet-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
      }

      .head-left {
        display: flex;
        align-items: center;
        gap: 10px;
      }

      .head-icon {
        color: var(--accent);
      }

      .sheet-head h2 {
        margin: 0;
        font-size: 18px;
      }

      .sheet-search {
        display: flex;
        align-items: center;
        gap: 8px;
        height: 40px;
        padding: 0 12px;
        border-radius: var(--radius-md);
        background-color: var(--bg);
        border: 1px solid var(--surface-border);
      }

      .sheet-search input {
        flex: 1;
        border: none;
        outline: none;
        background: transparent;
      }

      .lang-list {
        display: flex;
        flex-direction: column;
        gap: 6px;
        max-height: 50dvh;
        overflow-y: auto;
      }

      .lang-row {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 10px 12px;
        border-radius: var(--radius-md);
        background-color: var(--bg);
        border: 1px solid var(--surface-border);
        text-align: left;
      }

      .lang-row.selected {
        border-color: var(--accent);
        background-color: var(--accent-soft);
      }

      .check-icon {
        color: var(--accent);
        flex-shrink: 0;
      }

      .row-labels {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
      }

      .native-sub {
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .row-count {
        font-size: 12px;
        font-weight: 600;
        color: var(--on-surface-muted);
        white-space: nowrap;
      }

      .sheet-footer {
        display: flex;
        justify-content: flex-end;
        gap: 8px;
        padding-top: 6px;
      }

      .more-toggle-btn {
        display: flex;
        align-items: center;
        justify-content: space-between;
        width: 100%;
        padding: 9px 12px;
        margin: 4px 0;
        border-radius: var(--radius-md);
        border: 1px dashed var(--surface-border);
        font-size: 13px;
        font-weight: 600;
        color: var(--accent);
      }

      .more-toggle-btn:hover {
        background-color: var(--surface-variant);
      }
    `,
  ],
})
export class LanguageDropdownComponent {
  private readonly prefs = inject(ContentPreferencesService);

  readonly selectedLanguages = input<string[]>(['All']);
  readonly availableLanguages = input<string[]>([]);
  readonly itemCounts = input<Record<string, number>>({});
  readonly itemNoun = input<string>('items');
  readonly headerTitle = input<string>('Library Languages');
  readonly searchThreshold = input<number>(6);
  readonly languagesChange = output<string[]>();

  readonly open = signal<boolean>(false);
  readonly search = signal<string>('');
  readonly showOthers = signal<boolean>(false);
  readonly draftSet = signal<Set<string>>(new Set());

  readonly isAllSelected = computed(() => {
    const sel = this.selectedLanguages();
    return sel.length === 0 || sel.some((l) => l.toLowerCase() === 'all');
  });

  readonly draftIsAll = computed(() => {
    const d = this.draftSet();
    return d.size === 0 || d.has('All') || d.has('all');
  });

  readonly visibleLanguages = computed(() => {
    const counts = this.itemCounts();
    const sel = new Set(this.selectedLanguages().map((s) => s.toLowerCase()));
    return this.availableLanguages().filter((code) => {
      if (code.toLowerCase() === 'all') return false;
      return (counts[code] ?? 0) > 0 || sel.has(code.toLowerCase());
    });
  });

  readonly filteredLanguages = computed(() => {
    const q = this.search().trim().toLowerCase();
    const list = this.visibleLanguages();
    if (!q) return list;
    return list.filter((code) => {
      const m = languageMetaFromCode(code);
      return (
        code.toLowerCase().includes(q) ||
        m.englishName.toLowerCase().includes(q) ||
        m.nativeName.toLowerCase().includes(q)
      );
    });
  });

  readonly preferredLanguagesList = computed(() => {
    const prefSet = new Set(
      this.prefs.preferredLanguages().map((p) => p.toLowerCase()),
    );
    const list = this.filteredLanguages();
    if (prefSet.size === 0 || prefSet.has('all')) return list;
    const matched = list.filter((code) => prefSet.has(code.toLowerCase()));
    return matched.length > 0 ? matched : list;
  });

  readonly otherLanguages = computed(() => {
    const primary = new Set(
      this.preferredLanguagesList().map((c) => c.toLowerCase()),
    );
    return this.filteredLanguages().filter(
      (c) => !primary.has(c.toLowerCase()),
    );
  });

  readonly primaryDisplayedLanguages = computed(() => {
    if (this.search().trim()) return this.filteredLanguages();
    return this.preferredLanguagesList();
  });

  readonly summary = computed(() => {
    const counts = this.itemCounts();
    if (this.isAllSelected()) {
      return {
        title: 'All Languages',
        subtitle: '',
        count: counts['All'] ?? 0,
      };
    }
    const sel = this.selectedLanguages();
    if (sel.length === 1) {
      const meta = languageMetaFromCode(sel[0]);
      return {
        title: meta.englishName,
        subtitle:
          meta.nativeName && meta.nativeName !== meta.englishName
            ? meta.nativeName
            : '',
        count: counts[sel[0]] ?? 0,
      };
    }
    const sum = sel.reduce((acc, c) => acc + (counts[c] ?? 0), 0);
    return {
      title: `${sel.length} Languages`,
      subtitle: sel.map((c) => languageMetaFromCode(c).englishName).join(', '),
      count: sum,
    };
  });

  openSheet(): void {
    this.search.set('');
    this.showOthers.set(false);
    const current = this.selectedLanguages();
    this.draftSet.set(
      this.isAllSelected() ? new Set() : new Set(current),
    );
    this.open.set(true);
  }

  selectAllDraft(): void {
    this.draftSet.set(new Set());
  }

  toggleDraft(code: string): void {
    const next = new Set(this.draftSet());
    next.delete('All');
    next.delete('all');
    if (next.has(code)) {
      next.delete(code);
    } else {
      next.add(code);
    }
    this.draftSet.set(next);
  }

  apply(): void {
    const next = this.draftIsAll() ? ['All'] : [...this.draftSet()];
    this.languagesChange.emit(next);
    this.open.set(false);
  }

  metaFor(code: string) {
    return languageMetaFromCode(code);
  }

  nounLabel(count: number): string {
    return countNoun(this.itemNoun(), count);
  }
}
