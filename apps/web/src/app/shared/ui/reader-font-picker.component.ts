import {
  ChangeDetectionStrategy,
  Component,
  computed,
  inject,
  input,
  output,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import {
  ReaderAppearanceService,
  ReaderFontCategory,
  ReaderFontGroup,
  ReaderFontLanguageCode,
  ReaderFontOption,
} from '../../core/services/reader-appearance.service';

type CategoryFilter = 'all' | ReaderFontCategory;

@Component({
  selector: 'app-reader-font-picker',
  standalone: true,
  imports: [FormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (!browsing()) {
      <div class="font-tile-wrap">
        <div class="section-head">
          <label class="label">Font Family</label>
          <button type="button" class="browse-link-btn" (click)="openBrowser()">
            <span>Browse all fonts</span>
            <span class="material-symbols-rounded browse-arrow">chevron_right</span>
          </button>
        </div>

        <button type="button" class="selected-font-tile" (click)="openBrowser()">
          <span
            class="font-glyph-badge"
            [style.font-family]="appearance.activeFont().cssFamily"
          >
            Aa
          </span>
          <span class="font-tile-meta">
            <span class="font-tile-name">{{ appearance.activeFont().label }}</span>
            <span class="font-tile-sub">
              {{ appearance.activeFont().subtitle || 'Reading Typeface' }}
            </span>
          </span>
          <span class="font-tile-action">
            @if (appearance.isFontDownloading(appearance.activeFont())) {
              <span class="status-pill downloading">Downloading</span>
            } @else {
              <span class="status-pill">Change</span>
            }
            <span class="material-symbols-rounded chevron">chevron_right</span>
          </span>
        </button>
      </div>
    } @else {
      <div class="font-browser">
        <div class="browser-head">
          <button
            type="button"
            class="back-btn"
            aria-label="Back to appearance settings"
            (click)="closeBrowser()"
          >
            <span class="material-symbols-rounded">chevron_left</span>
            <span>Appearance</span>
          </button>
          <span class="browser-title">Typography</span>
          @if (appearance.canQueryLocalFonts()) {
            <button
              type="button"
              class="sys-scan-btn"
              [disabled]="appearance.scanningSystemFonts()"
              (click)="appearance.scanLocalSystemFonts()"
            >
              <span class="material-symbols-rounded">computer</span>
              <span>{{ appearance.scanningSystemFonts() ? 'Scanning...' : 'System Fonts' }}</span>
            </button>
          }
        </div>

        <div class="search-row">
          <span class="material-symbols-rounded search-ic">search</span>
          <input
            type="search"
            class="font-search-input"
            placeholder="Search fonts or styles (e.g. Literata, Serif)..."
            [ngModel]="searchQuery()"
            (ngModelChange)="searchQuery.set($event)"
          />
          @if (searchQuery()) {
            <button
              type="button"
              class="clear-search-btn"
              aria-label="Clear search"
              (click)="searchQuery.set('')"
            >
              <span class="material-symbols-rounded">close</span>
            </button>
          }
        </div>

        <div class="filter-strip" aria-label="Language filter">
          <button
            type="button"
            class="filter-chip"
            [class.active]="selectedLang() === 'all'"
            (click)="selectedLang.set('all')"
          >
            All
          </button>
          @for (grp of fontGroups(); track grp.code) {
            <button
              type="button"
              class="filter-chip"
              [class.active]="selectedLang() === grp.code"
              (click)="selectedLang.set(grp.code)"
            >
              {{ grp.code === 'en' ? 'English' : grp.nativeLabel }}
            </button>
          }
        </div>

        <div class="filter-strip" aria-label="Category filter">
          @for (cat of categories; track cat.id) {
            <button
              type="button"
              class="filter-chip subtle"
              [class.active]="selectedCategory() === cat.id"
              (click)="selectedCategory.set(cat.id)"
            >
              {{ cat.label }}
            </button>
          }
        </div>

        <div class="specimen-list">
          @if (filteredGroups().length === 0) {
            <div class="empty-state">
              <span class="material-symbols-rounded empty-ic">font_download_off</span>
              <span>No fonts match your current filter.</span>
            </div>
          } @else {
            @for (grp of filteredGroups(); track grp.code) {
              <div class="group-section">
                <div class="group-head">
                  <span class="group-title">
                    {{ grp.label }}
                    @if (grp.nativeLabel !== grp.label) {
                      <span class="group-native">· {{ grp.nativeLabel }}</span>
                    }
                    <span class="group-count">({{ grp.fonts.length }})</span>
                  </span>
                  @if (grp.downloadedCount < grp.onDemandCount) {
                    <button
                      type="button"
                      class="dl-all-btn"
                      [disabled]="appearance.isLanguageDownloading(grp.code)"
                      (click)="appearance.downloadLanguageFonts(grp.code)"
                    >
                      <span class="material-symbols-rounded">download</span>
                      <span>
                        {{
                          appearance.isLanguageDownloading(grp.code)
                            ? 'Downloading...'
                            : 'Download All (' + (grp.onDemandCount - grp.downloadedCount) + ')'
                        }}
                      </span>
                    </button>
                  }
                </div>

                <div class="specimen-grid">
                  @for (f of grp.fonts; track f.id) {
                    @let isSelected = appearance.fontId() === f.id;
                    @let isDownloading = appearance.isFontDownloading(f);
                    @let isDownloaded = appearance.isFontDownloaded(f);
                    <button
                      type="button"
                      class="specimen-card"
                      [class.active]="isSelected"
                      (click)="selectFont(f)"
                    >
                      <div class="specimen-top">
                        <span
                          class="specimen-avatar"
                          [style.font-family]="f.cssFamily"
                        >
                          Aa
                        </span>
                        <span class="specimen-info">
                          <span class="specimen-name">{{ f.label }}</span>
                          <span class="specimen-sub">
                            {{ f.subtitle || categoryLabel(f) }}
                          </span>
                        </span>
                        <span class="specimen-badge">
                          @if (isSelected) {
                            <span class="material-symbols-rounded badge-ic selected">
                              check_circle
                            </span>
                          } @else if (isDownloading) {
                            <span class="material-symbols-rounded badge-ic downloading">
                              downloading
                            </span>
                          } @else if (!isDownloaded) {
                            <span
                              class="material-symbols-rounded badge-ic cloud"
                              title="Downloaded on demand"
                            >
                              cloud_download
                            </span>
                          } @else if (f.source === 'system') {
                            <span class="source-tag">System</span>
                          }
                        </span>
                      </div>
                      <div
                        class="specimen-sample"
                        [style.font-family]="f.cssFamily"
                      >
                        {{ appearance.fontSampleText(f) }}
                      </div>
                    </button>
                  }
                </div>
              </div>
            }
          }
        </div>
      </div>
    }
  `,
  styles: [
    `
      .font-tile-wrap {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .section-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
      }

      .label {
        font-size: 12px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        color: var(--on-surface-muted);
      }

      .browse-link-btn {
        display: inline-flex;
        align-items: center;
        gap: 2px;
        border: none;
        background: transparent;
        color: var(--accent);
        font-size: 12px;
        font-weight: 600;
        cursor: pointer;
        padding: 2px 4px;
        border-radius: 6px;
      }

      .browse-link-btn:hover {
        background: var(--accent-soft);
      }

      .browse-arrow {
        font-size: 16px;
      }

      .selected-font-tile {
        width: 100%;
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 10px 12px;
        border-radius: 12px;
        border: 1px solid var(--surface-border);
        background: var(--surface-variant);
        color: var(--on-surface);
        text-align: left;
        cursor: pointer;
        transition: border-color 140ms ease, background 140ms ease;
      }

      .selected-font-tile:hover {
        border-color: var(--accent);
      }

      .font-glyph-badge {
        width: 40px;
        height: 40px;
        flex-shrink: 0;
        border-radius: 10px;
        background: var(--surface);
        border: 1px solid var(--surface-border);
        display: grid;
        place-items: center;
        font-size: 17px;
        font-weight: 700;
        color: var(--accent);
      }

      .font-tile-meta {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .font-tile-name {
        font-size: 14px;
        font-weight: 600;
        color: var(--on-surface);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .font-tile-sub {
        font-size: 12px;
        color: var(--on-surface-muted);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .font-tile-action {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        flex-shrink: 0;
      }

      .status-pill {
        font-size: 11px;
        font-weight: 600;
        padding: 3px 8px;
        border-radius: var(--radius-pill);
        background: var(--surface);
        border: 1px solid var(--surface-border);
        color: var(--on-surface-muted);
      }

      .status-pill.downloading {
        color: var(--accent);
        border-color: var(--accent);
      }

      .chevron {
        font-size: 18px;
        color: var(--on-surface-muted);
      }

      /* ── Level 2 Font Browser ── */
      .font-browser {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .browser-head {
        display: flex;
        align-items: center;
        gap: 8px;
      }

      .back-btn {
        display: inline-flex;
        align-items: center;
        gap: 2px;
        padding: 5px 10px 5px 4px;
        border-radius: var(--radius-pill);
        border: 1px solid var(--surface-border);
        background: var(--surface-variant);
        color: var(--on-surface);
        font-size: 12px;
        font-weight: 600;
        cursor: pointer;
      }

      .back-btn:hover {
        border-color: var(--accent);
        color: var(--accent);
      }

      .back-btn .material-symbols-rounded {
        font-size: 18px;
      }

      .browser-title {
        flex: 1;
        font-size: 15px;
        font-weight: 700;
        color: var(--on-surface);
      }

      .sys-scan-btn {
        display: inline-flex;
        align-items: center;
        gap: 5px;
        padding: 5px 10px;
        border-radius: var(--radius-pill);
        border: 1px solid var(--surface-border);
        background: var(--surface-variant);
        color: var(--on-surface);
        font-size: 12px;
        font-weight: 600;
        cursor: pointer;
      }

      .sys-scan-btn:hover:not(:disabled) {
        border-color: var(--accent);
        color: var(--accent);
      }

      .sys-scan-btn .material-symbols-rounded {
        font-size: 15px;
      }

      .search-row {
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 7px 10px;
        border-radius: 10px;
        border: 1px solid var(--surface-border);
        background: var(--surface-variant);
      }

      .search-row:focus-within {
        border-color: var(--accent);
      }

      .search-ic {
        font-size: 18px;
        color: var(--on-surface-muted);
      }

      .font-search-input {
        flex: 1;
        min-width: 0;
        border: none;
        outline: none;
        background: transparent;
        color: var(--on-surface);
        font-size: 13px;
      }

      .clear-search-btn {
        border: none;
        background: transparent;
        color: var(--on-surface-muted);
        display: grid;
        place-items: center;
        cursor: pointer;
        padding: 2px;
      }

      .clear-search-btn .material-symbols-rounded {
        font-size: 16px;
      }

      .filter-strip {
        display: flex;
        align-items: center;
        gap: 6px;
        overflow-x: auto;
        padding-bottom: 2px;
        scrollbar-width: none;
      }

      .filter-strip::-webkit-scrollbar {
        display: none;
      }

      .filter-chip {
        flex-shrink: 0;
        padding: 5px 11px;
        border-radius: var(--radius-pill);
        border: 1px solid var(--surface-border);
        background: var(--surface-variant);
        color: var(--on-surface);
        font-size: 12px;
        font-weight: 600;
        cursor: pointer;
        transition: all 140ms ease;
      }

      .filter-chip.subtle {
        padding: 4px 10px;
        font-size: 11px;
      }

      .filter-chip.active {
        background: var(--accent-soft);
        border-color: var(--accent);
        color: var(--accent);
      }

      .specimen-list {
        display: flex;
        flex-direction: column;
        gap: 14px;
        max-height: min(56vh, 420px);
        overflow-y: auto;
        padding-right: 2px;
      }

      .empty-state {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 6px;
        padding: 28px 16px;
        color: var(--on-surface-muted);
        font-size: 13px;
      }

      .empty-ic {
        font-size: 28px;
      }

      .group-section {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .group-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }

      .group-title {
        font-size: 12px;
        font-weight: 700;
        color: var(--on-surface);
      }

      .group-native {
        color: var(--accent);
      }

      .group-count {
        color: var(--on-surface-muted);
        font-weight: 500;
        margin-left: 4px;
      }

      .dl-all-btn {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        padding: 4px 9px;
        border-radius: var(--radius-pill);
        border: 1px solid var(--accent);
        background: var(--accent-soft);
        color: var(--accent);
        font-size: 11px;
        font-weight: 600;
        cursor: pointer;
      }

      .dl-all-btn .material-symbols-rounded {
        font-size: 14px;
      }

      .specimen-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(230px, 1fr));
        gap: 8px;
      }

      .specimen-card {
        display: flex;
        flex-direction: column;
        gap: 8px;
        padding: 11px 12px;
        border-radius: 12px;
        border: 1px solid var(--surface-border);
        background: var(--surface-variant);
        color: var(--on-surface);
        text-align: left;
        cursor: pointer;
        transition: border-color 140ms ease, background 140ms ease;
      }

      .specimen-card:hover {
        border-color: var(--accent);
      }

      .specimen-card.active {
        background: var(--accent-soft);
        border-color: var(--accent);
        box-shadow: inset 0 0 0 1px var(--accent);
      }

      .specimen-top {
        display: flex;
        align-items: center;
        gap: 10px;
      }

      .specimen-avatar {
        width: 34px;
        height: 34px;
        flex-shrink: 0;
        border-radius: 8px;
        background: var(--surface);
        border: 1px solid var(--surface-border);
        display: grid;
        place-items: center;
        font-size: 15px;
        font-weight: 700;
        color: var(--on-surface);
      }

      .specimen-card.active .specimen-avatar {
        color: var(--accent);
        border-color: var(--accent);
      }

      .specimen-info {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 1px;
      }

      .specimen-name {
        font-size: 13px;
        font-weight: 600;
        color: var(--on-surface);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .specimen-sub {
        font-size: 11px;
        color: var(--on-surface-muted);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .specimen-badge {
        flex-shrink: 0;
        display: inline-flex;
        align-items: center;
      }

      .badge-ic {
        font-size: 18px;
      }

      .badge-ic.selected,
      .badge-ic.downloading {
        color: var(--accent);
      }

      .badge-ic.cloud {
        color: var(--on-surface-muted);
      }

      .source-tag {
        font-size: 10px;
        font-weight: 600;
        padding: 2px 6px;
        border-radius: 6px;
        background: var(--surface);
        border: 1px solid var(--surface-border);
        color: var(--on-surface-muted);
      }

      .specimen-sample {
        font-size: 14px;
        line-height: 1.4;
        color: var(--on-surface);
        opacity: 0.88;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        padding-top: 4px;
        border-top: 1px dashed var(--surface-border);
      }
    `,
  ],
})
export class ReaderFontPickerComponent {
  readonly appearance = inject(ReaderAppearanceService);
  readonly browsing = input<boolean>(false);
  readonly browsingChange = output<boolean>();

  readonly selectedLang = signal<'all' | ReaderFontLanguageCode>('all');
  readonly selectedCategory = signal<CategoryFilter>('all');
  readonly searchQuery = signal<string>('');

  readonly categories: readonly { id: CategoryFilter; label: string }[] = [
    { id: 'all', label: 'All' },
    { id: 'serif', label: 'Serif' },
    { id: 'sans', label: 'Sans' },
    { id: 'display', label: 'Display' },
    { id: 'handwriting', label: 'Script' },
  ];

  readonly fontGroups = this.appearance.fontsByLanguage;

  readonly filteredGroups = computed<readonly ReaderFontGroup[]>(() => {
    const lang = this.selectedLang();
    const cat = this.selectedCategory();
    const q = this.searchQuery().trim().toLowerCase();

    return this.fontGroups()
      .filter((g) => lang === 'all' || g.code === lang)
      .map((g) => {
        const fonts = g.fonts.filter((f) => {
          if (cat !== 'all' && this.appearance.fontCategory(f) !== cat) {
            return false;
          }
          if (q) {
            const hay = `${f.label} ${f.subtitle ?? ''} ${f.shortLabel ?? ''}`.toLowerCase();
            if (!hay.includes(q)) return false;
          }
          return true;
        });
        return { ...g, fonts };
      })
      .filter((g) => g.fonts.length > 0);
  });

  openBrowser(): void {
    this.browsingChange.emit(true);
  }

  closeBrowser(): void {
    this.browsingChange.emit(false);
  }

  selectFont(font: ReaderFontOption): void {
    this.appearance.setFont(font.id);
  }

  categoryLabel(font: ReaderFontOption): string {
    const cat = this.appearance.fontCategory(font);
    switch (cat) {
      case 'serif':
        return 'Serif';
      case 'sans':
        return 'Sans-Serif';
      case 'display':
        return 'Display';
      case 'handwriting':
        return 'Script & Calligraphy';
      case 'mono':
        return 'Monospace';
    }
  }
}
