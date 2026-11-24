import {
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  HostListener,
  ViewChild,
  computed,
  inject,
  input,
  output,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import {
  BIBLE_VERSIONS,
  BibleVersionInfo,
  getVersionsForLanguages,
} from '../../features/bible/models/bible.model';
import {
  BibleVersionSelectionService,
  DEFAULT_MAX_VERSIONS,
} from '../../core/services/bible-version-selection.service';
import { ContentPreferencesService } from '../../core/services/content-preferences.service';
import { SearchInputComponent } from './search-input.component';

export interface BibleVersionSelectionEvent {
  primary: string;
  comparisons: string[];
  all: string[];
  kind: 'primary' | 'comparison';
}

@Component({
  selector: 'app-bible-version-picker',
  standalone: true,
  imports: [SearchInputComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="ver-dropdown-wrap">
      <button
        #triggerBtn
        type="button"
        class="version-trigger"
        [class.glass]="triggerVariant() === 'glass'"
        [attr.aria-expanded]="open()"
        [title]="maxSelections() > 1 ? 'Select up to ' + maxSelections() + ' Bible versions' : 'Select Bible version'"
        (click)="toggleOpen()"
      >
        <span class="material-symbols-rounded pill-icon">translate</span>
        <span class="trigger-label">{{ triggerLabel() }}</span>
        @if (maxSelections() > 1 && selectedCount() > 1) {
          <span class="sel-count">{{ selectedCount() }}/{{ maxSelections() }}</span>
        }
        <span class="material-symbols-rounded pill-caret">
          {{ open() ? 'expand_less' : 'expand_more' }}
        </span>
      </button>

      @if (open()) {
        <div
          class="dropdown-panel"
          [style.top.px]="panelPos().top"
          [style.left.px]="panelPos().left"
          [style.width.px]="panelPos().width"
          [style.maxHeight.px]="panelPos().maxHeight"
          (click)="$event.stopPropagation()"
          (wheel)="$event.stopPropagation()"
          (touchstart)="$event.stopPropagation()"
          (touchend)="$event.stopPropagation()"
        >
          <app-search-input
            placeholder="Search versions or languages..."
            [value]="search()"
            (valueChange)="search.set($event)"
          />

          @if (maxSelections() > 1) {
            <div class="dropdown-hint">
              <span>Tap a version to switch · checkbox to compare (max {{ maxSelections() }})</span>
              <span>{{ selectedCount() }}/{{ maxSelections() }}</span>
            </div>
          }

          <div class="dropdown-list">
            @if (selectedList().length > 0) {
              <div class="group-label">
                {{ selectedCount() > 1 ? 'Selected (Primary on Top)' : 'Current Version' }}
              </div>
              @for (v of selectedList(); track v.id; let first = $first) {
                <div class="ver-row selected" [class.primary]="first">
                  <button
                    type="button"
                    class="ver-main"
                    (click)="onSelectSingle(v.id)"
                  >
                    <span class="ver-badge">{{ v.label }}</span>
                    <div class="ver-meta">
                      <strong>{{ v.fullName }}</strong>
                      <span class="muted">{{ v.language }}</span>
                    </div>
                  </button>
                  @if (first) {
                    <span class="primary-tag">Primary</span>
                  } @else {
                    <button
                      type="button"
                      class="pin-btn"
                      title="Make Primary (pin to top)"
                      (click)="$event.stopPropagation(); onMakePrimary(v.id)"
                    >
                      <span class="material-symbols-rounded">vertical_align_top</span>
                    </button>
                  }
                  @if (maxSelections() > 1) {
                    <button
                      type="button"
                      class="ver-compare-btn checked"
                      [title]="first ? 'Primary version' : 'Remove from parallel compare'"
                      [attr.aria-label]="'Compare ' + v.fullName"
                      (click)="$event.stopPropagation(); onToggleComparison(v.id)"
                    >
                      <span class="material-symbols-rounded check-ico">check_box</span>
                    </button>
                  }
                </div>
              }
            }

            @for (grp of preferredGroups(); track grp.language) {
              <div class="group-label">{{ grp.language }}</div>
              @for (v of grp.versions; track v.id) {
                <div class="ver-row">
                  <button
                    type="button"
                    class="ver-main"
                    (click)="onSelectSingle(v.id)"
                  >
                    <span class="ver-badge">{{ v.label }}</span>
                    <div class="ver-meta">
                      <strong>{{ v.fullName }}</strong>
                      <span class="muted">{{ v.language }}</span>
                    </div>
                  </button>
                  @if (maxSelections() > 1) {
                    <button
                      type="button"
                      class="ver-compare-btn"
                      title="Add to parallel compare"
                      [attr.aria-label]="'Compare ' + v.fullName"
                      (click)="$event.stopPropagation(); onToggleComparison(v.id)"
                    >
                      <span class="material-symbols-rounded check-ico muted-ico">check_box_outline_blank</span>
                    </button>
                  }
                </div>
              }
            }

            @if (otherGroups().length > 0) {
              @if (!search().trim()) {
                <button
                  type="button"
                  class="more-toggle"
                  (click)="showOthers.set(!showOthers())"
                >
                  <span>
                    {{ showOthers() ? 'Hide other languages' : 'Other languages (' + otherUnselectedCount() + ')' }}
                  </span>
                  <span class="material-symbols-rounded">
                    {{ showOthers() ? 'expand_less' : 'expand_more' }}
                  </span>
                </button>
              }

              @if (showOthers() || search().trim()) {
                @for (grp of otherGroups(); track grp.language) {
                  <div class="group-label">{{ grp.language }}</div>
                  @for (v of grp.versions; track v.id) {
                    <div class="ver-row">
                      <button
                        type="button"
                        class="ver-main"
                        (click)="onSelectSingle(v.id)"
                      >
                        <span class="ver-badge">{{ v.label }}</span>
                        <div class="ver-meta">
                          <strong>{{ v.fullName }}</strong>
                          <span class="muted">{{ v.language }}</span>
                        </div>
                      </button>
                      @if (maxSelections() > 1) {
                        <button
                          type="button"
                          class="ver-compare-btn"
                          title="Add to parallel compare"
                          [attr.aria-label]="'Compare ' + v.fullName"
                          (click)="$event.stopPropagation(); onToggleComparison(v.id)"
                        >
                          <span class="material-symbols-rounded check-ico muted-ico">check_box_outline_blank</span>
                        </button>
                      }
                    </div>
                  }
                }
              }
            }

            @if (selectedList().length === 0 && preferredGroups().length === 0 && otherGroups().length === 0) {
              <p class="empty-msg">No Bible versions match "{{ search() }}"</p>
            }
          </div>
        </div>
      }
    </div>
  `,
  styles: [
    `
      :host {
        display: inline-block;
        max-width: 100%;
        min-width: 0;
      }

      .ver-dropdown-wrap {
        position: relative;
        display: inline-block;
        max-width: 100%;
        min-width: 0;
      }

      .version-trigger {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        height: 34px;
        max-width: 100%;
        min-width: 0;
        padding: 0 11px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        color: var(--on-surface);
        font-size: 12.5px;
        font-weight: 700;
      }

      .version-trigger.glass {
        background-color: rgba(255, 255, 255, 0.14);
        backdrop-filter: blur(10px);
        color: inherit;
        border-color: rgba(255, 255, 255, 0.16);
      }

      :host-context(.light-stage) .version-trigger.glass {
        background-color: rgba(15, 23, 42, 0.08);
        border-color: rgba(15, 23, 42, 0.12);
      }

      .trigger-label {
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        min-width: 0;
      }

      .sel-count {
        padding: 1px 6px;
        border-radius: 999px;
        background-color: var(--accent);
        color: var(--on-accent);
        font-size: 10.5px;
        font-weight: 700;
        flex-shrink: 0;
      }

      .pill-icon {
        font-size: 16px;
        flex-shrink: 0;
      }

      .pill-caret {
        font-size: 16px;
        opacity: 0.75;
        flex-shrink: 0;
      }

      .dropdown-panel {
        position: fixed;
        z-index: 200;
        padding: 12px;
        border-radius: var(--radius-lg);
        background-color: var(--surface);
        color: var(--on-surface);
        border: 1px solid var(--surface-border);
        box-shadow: 0 16px 40px rgba(0, 0, 0, 0.3);
        display: flex;
        flex-direction: column;
        gap: 10px;
        overflow: hidden;
      }

      .dropdown-hint {
        display: flex;
        align-items: center;
        justify-content: space-between;
        font-size: 11px;
        font-weight: 600;
        color: var(--on-surface-muted);
        padding: 0 4px;
        flex-shrink: 0;
      }

      .dropdown-list {
        display: flex;
        flex-direction: column;
        gap: 4px;
        flex: 1;
        min-height: 0;
        overflow-y: auto;
        overscroll-behavior: contain;
        padding-right: 4px;
        scrollbar-width: thin;
        scrollbar-color: var(--surface-border) transparent;
      }

      .dropdown-list::-webkit-scrollbar {
        width: 5px;
      }

      .dropdown-list::-webkit-scrollbar-thumb {
        border-radius: 999px;
        background-color: var(--surface-border);
      }

      .group-label {
        font-size: 11px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--on-surface-muted);
        padding: 6px 6px 2px;
      }

      .ver-row {
        display: flex;
        align-items: center;
        gap: 6px;
        padding: 6px 8px;
        border-radius: var(--radius-md);
        border: 1px solid transparent;
        text-align: left;
        width: 100%;
        flex-shrink: 0;
      }

      .ver-row:hover {
        background-color: var(--surface-variant);
      }

      .ver-row.selected {
        background-color: var(--accent-soft);
        border-color: var(--accent);
      }

      .ver-main {
        flex: 1;
        min-width: 0;
        display: flex;
        align-items: center;
        gap: 8px;
        text-align: left;
      }

      .check-ico {
        font-size: 20px;
        color: var(--accent);
        flex-shrink: 0;
      }

      .ver-compare-btn {
        width: 32px;
        height: 32px;
        border-radius: var(--radius-sm);
        display: grid;
        place-items: center;
        flex-shrink: 0;
      }

      .ver-compare-btn:hover {
        background-color: var(--surface-variant);
      }

      .muted-ico {
        color: var(--on-surface-muted);
      }

      .ver-badge {
        padding: 2px 7px;
        border-radius: var(--radius-sm);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        font-size: 11px;
        font-weight: 700;
        flex-shrink: 0;
      }

      .ver-meta {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
      }

      .ver-meta strong {
        font-size: 12.5px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .ver-meta .muted {
        font-size: 11px;
        color: var(--on-surface-muted);
      }

      .primary-tag {
        font-size: 10px;
        font-weight: 700;
        text-transform: uppercase;
        padding: 2px 6px;
        border-radius: var(--radius-pill);
        background-color: var(--accent);
        color: var(--on-accent);
        flex-shrink: 0;
      }

      .pin-btn {
        width: 26px;
        height: 26px;
        border-radius: 999px;
        display: grid;
        place-items: center;
        color: var(--on-surface-muted);
        flex-shrink: 0;
      }

      .pin-btn:hover {
        background-color: var(--surface);
        color: var(--accent);
      }

      .pin-btn .material-symbols-rounded {
        font-size: 16px;
      }

      .more-toggle {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 8px 10px;
        margin-top: 4px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        font-size: 12px;
        font-weight: 600;
        color: var(--on-surface-muted);
      }

      .empty-msg {
        text-align: center;
        font-size: 13px;
        color: var(--on-surface-muted);
        padding: 16px 0;
        margin: 0;
      }
    `,
  ],
})
export class BibleVersionPickerComponent {
  private readonly el = inject(ElementRef<HTMLElement>);
  private readonly selectionService = inject(BibleVersionSelectionService);
  private readonly contentPrefs = inject(ContentPreferencesService);

  readonly contextKey = input.required<string>();
  readonly maxSelections = input<number>(DEFAULT_MAX_VERSIONS);
  readonly triggerVariant = input<'glass' | 'surface'>('surface');
  readonly alignRight = input<boolean>(false);

  readonly selectionChanged = output<BibleVersionSelectionEvent>();

  @ViewChild('triggerBtn') triggerBtn?: ElementRef<HTMLButtonElement>;

  readonly open = signal<boolean>(false);
  readonly search = signal<string>('');
  readonly showOthers = signal<boolean>(false);
  readonly panelPos = signal<{
    top: number;
    left: number;
    width: number;
    maxHeight: number;
  }>({ top: 64, left: 16, width: 460, maxHeight: 420 });

  private readonly byId = new Map(BIBLE_VERSIONS.map((v) => [v.id, v]));

  readonly selectedVersions = computed(() =>
    this.selectionService.selectedVersionsSignal(
      this.contextKey(),
      this.maxSelections(),
    )(),
  );

  readonly selectedCount = computed(() => this.selectedVersions().length);

  readonly triggerLabel = computed(() =>
    this.selectedVersions()
      .map((id) => this.byId.get(id)?.label ?? id.toUpperCase())
      .join(' · '),
  );

  readonly selectedList = computed<BibleVersionInfo[]>(() => {
    const q = this.search().trim().toLowerCase();
    return this.selectedVersions()
      .map((id) => this.byId.get(id))
      .filter((v): v is BibleVersionInfo => !!v && this.matchesQuery(v, q));
  });

  readonly preferredGroups = computed(() => {
    const selectedSet = new Set(this.selectedVersions());
    const q = this.search().trim().toLowerCase();
    const { preferred } = getVersionsForLanguages(
      this.contentPrefs.preferredLanguages(),
    );
    return this.groupByLanguage(
      preferred.filter((v) => !selectedSet.has(v.id) && this.matchesQuery(v, q)),
    );
  });

  readonly otherGroups = computed(() => {
    const selectedSet = new Set(this.selectedVersions());
    const q = this.search().trim().toLowerCase();
    const { others } = getVersionsForLanguages(
      this.contentPrefs.preferredLanguages(),
    );
    return this.groupByLanguage(
      others.filter((v) => !selectedSet.has(v.id) && this.matchesQuery(v, q)),
    );
  });

  readonly otherUnselectedCount = computed(() =>
    this.otherGroups().reduce((sum, g) => sum + g.versions.length, 0),
  );

  private groupByLanguage(
    list: BibleVersionInfo[],
  ): { language: string; versions: BibleVersionInfo[] }[] {
    const map = new Map<string, BibleVersionInfo[]>();
    for (const v of list) {
      const bucket = map.get(v.language);
      if (bucket) bucket.push(v);
      else map.set(v.language, [v]);
    }
    return [...map.entries()].map(([language, versions]) => ({
      language,
      versions,
    }));
  }

  @HostListener('document:click', ['$event'])
  onDocumentClick(event: MouseEvent): void {
    if (!this.open()) return;
    if (!this.el.nativeElement.contains(event.target as Node)) {
      this.open.set(false);
    }
  }

  @HostListener('window:keydown.escape')
  onEscape(): void {
    if (this.open()) {
      this.open.set(false);
    }
  }

  @HostListener('window:resize')
  onResize(): void {
    if (this.open()) {
      this.updatePanelPosition();
    }
  }

  toggleOpen(): void {
    const next = !this.open();
    if (next) {
      this.updatePanelPosition();
    } else {
      this.search.set('');
    }
    this.open.set(next);
  }

  private updatePanelPosition(): void {
    const btn = this.triggerBtn?.nativeElement;
    if (!btn || typeof window === 'undefined') return;
    const rect = btn.getBoundingClientRect();
    const width = Math.min(460, window.innerWidth - 32);
    const left = this.alignRight()
      ? Math.max(16, rect.right - width)
      : Math.max(16, Math.min(rect.left, window.innerWidth - width - 16));
    const top = rect.bottom + 8;
    const maxHeight = Math.max(220, Math.min(440, window.innerHeight - top - 16));
    this.panelPos.set({ top, left, width, maxHeight });
  }

  onSelectSingle(versionId: string): void {
    const res = this.selectionService.selectSingle(this.contextKey(), versionId);
    this.open.set(false);
    this.search.set('');
    if (res !== 'noop') {
      this.emitChange('primary');
    }
  }

  onToggleComparison(versionId: string): void {
    const res = this.selectionService.toggleVersion(
      this.contextKey(),
      versionId,
      this.maxSelections(),
    );
    if (res === 'noop') return;
    this.emitChange(res === 'primary-changed' ? 'primary' : 'comparison');
  }

  onMakePrimary(versionId: string): void {
    if (
      this.selectionService.promoteToPrimary(
        this.contextKey(),
        versionId,
        this.maxSelections(),
      )
    ) {
      this.emitChange('primary');
    }
  }

  private emitChange(kind: 'primary' | 'comparison'): void {
    const all = this.selectionService.getSelectedVersions(
      this.contextKey(),
      this.maxSelections(),
    );
    this.selectionChanged.emit({
      primary: all[0],
      comparisons: all.slice(1),
      all,
      kind,
    });
  }

  private matchesQuery(v: BibleVersionInfo, q: string): boolean {
    if (!q) return true;
    return (
      v.id.toLowerCase().includes(q) ||
      v.label.toLowerCase().includes(q) ||
      v.fullName.toLowerCase().includes(q) ||
      v.language.toLowerCase().includes(q)
    );
  }
}
