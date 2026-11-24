import {
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  HostListener,
  computed,
  inject,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import {
  LETTER_SPACING_PRESETS,
  LINE_HEIGHT_PRESETS,
  READER_FONTS,
  ReaderAppearanceService,
  ReaderFontGroup,
  ReaderFontLanguageCode,
  ReaderFontOption,
} from '../../core/services/reader-appearance.service';

@Component({
  selector: 'app-reader-typography-toggle',
  standalone: true,
  imports: [FormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="reader-typography-seg">
      <div class="typo-pill" role="group" aria-label="Typography and text styling">
        <!-- 1. Font Family Dropdown Trigger -->
        <div class="popover-anchor">
          <button
            type="button"
            class="typo-btn font-trigger-btn"
            [class.active]="fontMenuOpen()"
            [title]="'Font: ' + activeFont().label"
            aria-label="Select font family"
            [attr.aria-expanded]="fontMenuOpen()"
            (click)="toggleFontMenu($event)"
          >
            <span class="material-symbols-rounded typo-icon" aria-hidden="true">text_fields</span>
            <span class="font-name">{{ activeFont().shortLabel || activeFont().label }}</span>
            <span class="material-symbols-rounded caret-icon" aria-hidden="true">expand_more</span>
          </button>

          @if (fontMenuOpen()) {
            <div
              class="font-menu-popover"
              role="menu"
              aria-label="Font family selection"
              (click)="$event.stopPropagation()"
            >
              <div class="popover-head">
                <div class="popover-title">Reading Fonts by Language</div>
                @if (appearance.canQueryLocalFonts()) {
                  <button
                    type="button"
                    class="scan-sys-btn"
                    [disabled]="appearance.scanningSystemFonts()"
                    title="List all installed system fonts from your device"
                    (click)="appearance.scanLocalSystemFonts()"
                  >
                    <span class="material-symbols-rounded">computer</span>
                    <span>{{ appearance.scanningSystemFonts() ? 'Scanning...' : 'System Fonts' }}</span>
                  </button>
                }
              </div>

              <div class="lang-filter-row" role="tablist" aria-label="Filter fonts by language">
                <button
                  type="button"
                  class="lang-chip"
                  [class.active]="selectedLang() === 'all'"
                  (click)="selectedLang.set('all')"
                >
                  All
                </button>
                @for (grp of fontGroups(); track grp.code) {
                  <button
                    type="button"
                    class="lang-chip"
                    [class.active]="selectedLang() === grp.code"
                    (click)="selectedLang.set(grp.code)"
                  >
                    {{ grp.code === 'en' ? 'EN' : grp.nativeLabel }}
                  </button>
                }
              </div>

              <div class="style-filter-row" role="tablist" aria-label="Filter fonts by style">
                @for (cat of categoryChips; track cat.id) {
                  <button
                    type="button"
                    class="style-chip"
                    [class.active]="selectedCategory() === cat.id"
                    (click)="selectedCategory.set(cat.id)"
                  >
                    {{ cat.label }}
                  </button>
                }
              </div>

              <div class="font-groups-scroll">
                @for (grp of visibleFontGroups(); track grp.code) {
                  <div class="font-group-section">
                    <div class="font-group-header">
                      <span class="font-group-title">
                        {{ grp.label }}
                        @if (grp.nativeLabel !== grp.label) {
                          <span class="font-group-native">· {{ grp.nativeLabel }}</span>
                        }
                      </span>
                      @if (grp.downloadedCount < grp.onDemandCount) {
                        <button
                          type="button"
                          class="group-dl-btn"
                          [disabled]="appearance.isLanguageDownloading(grp.code)"
                          title="Download all {{ grp.label }} reading fonts for offline/instant use"
                          (click)="downloadGroup(grp.code, $event)"
                        >
                          <span class="material-symbols-rounded">download</span>
                          <span>
                            {{
                              appearance.isLanguageDownloading(grp.code)
                                ? 'Loading...'
                                : 'Get All (' + (grp.onDemandCount - grp.downloadedCount) + ')'
                            }}
                          </span>
                        </button>
                      }
                    </div>

                    @for (f of grp.fonts; track f.id) {
                      <button
                        type="button"
                        class="font-menu-item"
                        [class.active]="appearance.fontId() === f.id"
                        [style.font-family]="f.cssFamily"
                        role="menuitemradio"
                        [attr.aria-checked]="appearance.fontId() === f.id"
                        (click)="selectFont(f.id)"
                      >
                        <div class="font-item-main">
                          <span class="font-preview">{{ f.label }}</span>
                          @if (f.subtitle) {
                            <span class="font-subtitle">{{ f.subtitle }}</span>
                          }
                          <span class="font-sample">{{ f.sampleText || grp.sampleText }}</span>
                        </div>
                        <div class="font-item-meta">
                          @if (appearance.isFontDownloading(f)) {
                            <span
                              class="material-symbols-rounded dl-status-icon"
                              title="Downloading font..."
                              aria-hidden="true"
                            >
                              downloading
                            </span>
                          } @else if (appearance.fontId() === f.id) {
                            <span
                              class="material-symbols-rounded check-icon"
                              aria-hidden="true"
                            >
                              check
                            </span>
                          } @else if (!appearance.isFontDownloaded(f)) {
                            <span
                              class="material-symbols-rounded dl-status-icon"
                              title="Downloaded on demand when selected"
                              aria-hidden="true"
                            >
                              cloud_download
                            </span>
                          } @else if (f.source === 'system') {
                            <span class="font-source-tag">System</span>
                          }
                        </div>
                      </button>
                    }
                  </div>
                }
              </div>
            </div>
          }
        </div>

        <span class="seg-divider" aria-hidden="true"></span>

        <!-- 2. Font Size Stepper -->
        <div class="size-group">
          <button
            type="button"
            class="typo-btn size-step-btn"
            title="Decrease font size"
            aria-label="Decrease font size"
            [disabled]="appearance.fontSize() <= 13"
            (click)="appearance.stepFontSize(-1)"
          >
            <span class="material-symbols-rounded" aria-hidden="true">remove</span>
          </button>
          <span class="size-val" [title]="'Font size: ' + appearance.fontSize() + 'px'">
            {{ appearance.fontSize() }}
          </span>
          <button
            type="button"
            class="typo-btn size-step-btn"
            title="Increase font size"
            aria-label="Increase font size"
            [disabled]="appearance.fontSize() >= 28"
            (click)="appearance.stepFontSize(1)"
          >
            <span class="material-symbols-rounded" aria-hidden="true">add</span>
          </button>
        </div>

        <span class="seg-divider" aria-hidden="true"></span>

        <!-- 3. Line & Letter Spacing Popover Trigger -->
        <div class="popover-anchor">
          <button
            type="button"
            class="typo-btn spacing-trigger-btn"
            [class.active]="spacingOpen() || isCustomSpacing()"
            [title]="
              'Spacing (Line: ' +
              appearance.lineHeight() +
              ', Letter: ' +
              appearance.formatLetterSpacing() +
              ')'
            "
            aria-label="Line and letter spacing"
            [attr.aria-expanded]="spacingOpen()"
            (click)="toggleSpacing($event)"
          >
            <span class="material-symbols-rounded" aria-hidden="true">format_line_spacing</span>
          </button>

          @if (spacingOpen()) {
            <div
              class="spacing-popover"
              role="dialog"
              aria-label="Line and letter spacing"
              (click)="$event.stopPropagation()"
            >
              <!-- Line Spacing -->
              <section class="spacing-block">
                <div class="spacing-head">
                  <span class="spacing-title">Line Spacing</span>
                  <div class="spacing-controls">
                    <span class="spacing-val">{{ appearance.lineHeight() }}</span>
                    <button
                      type="button"
                      class="step-mini-btn"
                      aria-label="Decrease line spacing"
                      title="Decrease line spacing"
                      [disabled]="appearance.lineHeight() <= 1.3"
                      (click)="appearance.stepLineHeight(-0.05)"
                    >
                      −
                    </button>
                    <button
                      type="button"
                      class="step-mini-btn"
                      aria-label="Increase line spacing"
                      title="Increase line spacing"
                      [disabled]="appearance.lineHeight() >= 2.2"
                      (click)="appearance.stepLineHeight(0.05)"
                    >
                      +
                    </button>
                  </div>
                </div>
                <div class="preset-row">
                  @for (p of linePresets; track p.id) {
                    <button
                      type="button"
                      class="preset-chip"
                      [class.active]="Math.abs(appearance.lineHeight() - p.value) < 0.03"
                      (click)="appearance.setLineHeight(p.value)"
                    >
                      {{ p.label }}
                    </button>
                  }
                </div>
                <input
                  type="range"
                  class="spacing-range"
                  min="1.3"
                  max="2.2"
                  step="0.05"
                  aria-label="Line spacing slider"
                  [ngModel]="appearance.lineHeight()"
                  (ngModelChange)="appearance.setLineHeight($event)"
                />
              </section>

              <!-- Letter Spacing -->
              <section class="spacing-block">
                <div class="spacing-head">
                  <span class="spacing-title">Letter Spacing</span>
                  <div class="spacing-controls">
                    <span class="spacing-val">{{ appearance.formatLetterSpacing() }}</span>
                    <button
                      type="button"
                      class="step-mini-btn"
                      aria-label="Decrease letter spacing"
                      title="Decrease letter spacing"
                      [disabled]="appearance.letterSpacing() <= -0.04"
                      (click)="appearance.stepLetterSpacing(-0.01)"
                    >
                      −
                    </button>
                    <button
                      type="button"
                      class="step-mini-btn"
                      aria-label="Increase letter spacing"
                      title="Increase letter spacing"
                      [disabled]="appearance.letterSpacing() >= 0.12"
                      (click)="appearance.stepLetterSpacing(0.01)"
                    >
                      +
                    </button>
                  </div>
                </div>
                <div class="preset-row">
                  @for (p of letterPresets; track p.id) {
                    <button
                      type="button"
                      class="preset-chip"
                      [class.active]="Math.abs(appearance.letterSpacing() - p.value) < 0.005"
                      (click)="appearance.setLetterSpacing(p.value)"
                    >
                      {{ p.label }}
                    </button>
                  }
                </div>
                <input
                  type="range"
                  class="spacing-range"
                  min="-0.04"
                  max="0.12"
                  step="0.01"
                  aria-label="Letter spacing slider"
                  [ngModel]="appearance.letterSpacing()"
                  (ngModelChange)="appearance.setLetterSpacing($event)"
                />
              </section>
            </div>
          }
        </div>
      </div>
    </div>
  `,
  styles: [
    `
      .reader-typography-seg {
        position: relative;
        display: inline-flex;
        align-items: center;
      }

      .typo-pill {
        display: inline-flex;
        align-items: center;
        gap: 2px;
        height: 32px;
        padding: 0 4px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .popover-anchor {
        position: relative;
        display: inline-flex;
        align-items: center;
      }

      .typo-btn {
        height: 24px;
        border-radius: var(--radius-pill);
        color: var(--on-surface-muted);
        display: inline-flex;
        align-items: center;
        justify-content: center;
        transition: background-color 140ms ease, color 140ms ease;
      }

      .typo-btn:hover:not(:disabled) {
        background-color: color-mix(in srgb, var(--on-surface) 8%, transparent);
        color: var(--on-surface);
      }

      .typo-btn:disabled {
        opacity: 0.35;
        cursor: default;
      }

      .font-trigger-btn {
        padding: 0 6px 0 6px;
        gap: 4px;
        font-size: 12px;
        font-weight: 600;
        color: var(--on-surface);
      }

      .font-trigger-btn.active {
        background-color: color-mix(in srgb, var(--accent) 15%, transparent);
        color: var(--accent);
      }

      .typo-icon {
        font-size: 15px;
        color: var(--on-surface-muted);
      }

      .font-name {
        max-width: 82px;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      @media (max-width: 900px) {
        .font-name {
          display: none;
        }
      }

      .caret-icon {
        font-size: 16px;
        color: var(--on-surface-muted);
        margin-left: -2px;
      }

      .seg-divider {
        width: 1px;
        height: 16px;
        background-color: var(--surface-border);
        margin: 0 2px;
      }

      .size-group {
        display: inline-flex;
        align-items: center;
        gap: 1px;
      }

      .size-step-btn {
        width: 22px;
        height: 22px;
      }

      .size-step-btn .material-symbols-rounded {
        font-size: 14px;
      }

      .size-val {
        font-size: 11.5px;
        font-weight: 700;
        min-width: 18px;
        text-align: center;
        color: var(--on-surface);
        font-variant-numeric: tabular-nums;
        user-select: none;
      }

      .spacing-trigger-btn {
        width: 24px;
        height: 24px;
      }

      .spacing-trigger-btn .material-symbols-rounded {
        font-size: 15px;
      }

      .spacing-trigger-btn.active {
        background-color: var(--accent);
        color: var(--on-accent);
      }

      /* Font Selection Popover */
      .font-menu-popover {
        position: absolute;
        top: calc(100% + 8px);
        right: 0;
        width: min(320px, calc(100vw - 24px));
        padding: 8px;
        border-radius: var(--radius-md);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        box-shadow: 0 12px 32px rgba(0, 0, 0, 0.24);
        z-index: 60;
        display: flex;
        flex-direction: column;
        gap: 6px;
      }

      .popover-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        padding: 2px 4px 0;
      }

      .popover-title {
        font-size: 11px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--on-surface-muted);
      }

      .scan-sys-btn {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        padding: 3px 8px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        font-size: 10.5px;
        font-weight: 600;
        color: var(--on-surface);
      }

      .scan-sys-btn:hover:not(:disabled) {
        border-color: var(--accent);
        color: var(--accent);
      }

      .scan-sys-btn .material-symbols-rounded {
        font-size: 13px;
      }

      .lang-filter-row {
        display: flex;
        align-items: center;
        gap: 4px;
        overflow-x: auto;
        scrollbar-width: none;
        padding: 2px 2px 4px;
        border-bottom: 1px solid var(--surface-border);
      }

      .lang-filter-row::-webkit-scrollbar {
        display: none;
      }

      .lang-chip {
        height: 24px;
        padding: 0 8px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        font-size: 11px;
        font-weight: 600;
        color: var(--on-surface-muted);
        white-space: nowrap;
        flex-shrink: 0;
      }

      .lang-chip.active {
        background-color: var(--accent);
        border-color: var(--accent);
        color: var(--on-accent);
      }

      .font-groups-scroll {
        max-height: 340px;
        overflow-y: auto;
        scrollbar-width: thin;
        display: flex;
        flex-direction: column;
        gap: 8px;
        padding-right: 2px;
      }

      .font-group-section {
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .font-group-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 6px;
        padding: 4px 8px 2px;
      }

      .font-group-title {
        font-size: 11px;
        font-weight: 700;
        color: var(--on-surface-muted);
      }

      .font-group-native {
        font-weight: 600;
        color: var(--accent);
      }

      .group-dl-btn {
        display: inline-flex;
        align-items: center;
        gap: 3px;
        padding: 2px 7px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        font-size: 10px;
        font-weight: 600;
        color: var(--accent);
      }

      .group-dl-btn:hover:not(:disabled) {
        background-color: var(--accent-soft);
      }

      .group-dl-btn .material-symbols-rounded {
        font-size: 12px;
      }

      .font-menu-item {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        padding: 7px 10px;
        border-radius: var(--radius-sm);
        font-size: 13.5px;
        color: var(--on-surface);
        text-align: left;
        width: 100%;
        transition: background-color 140ms ease, color 140ms ease;
      }

      .font-menu-item:hover {
        background-color: var(--surface-variant);
      }

      .font-menu-item.active {
        background-color: color-mix(in srgb, var(--accent) 12%, transparent);
        color: var(--accent);
        font-weight: 700;
      }

      .font-item-main {
        display: flex;
        flex-direction: column;
        min-width: 0;
        gap: 1px;
      }

      .font-preview {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .font-subtitle {
        font-family: 'Inter', system-ui, sans-serif;
        font-size: 10.5px;
        font-weight: 500;
        color: var(--on-surface-muted);
      }

      .font-item-meta {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        flex-shrink: 0;
      }

      .check-icon {
        font-size: 16px;
        color: var(--accent);
        flex-shrink: 0;
      }

      .dl-status-icon {
        font-size: 15px;
        color: var(--on-surface-muted);
      }

      .font-source-tag {
        font-family: 'Inter', system-ui, sans-serif;
        font-size: 9.5px;
        font-weight: 600;
        padding: 1px 6px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        color: var(--on-surface-muted);
      }

      /* Spacing Popover */
      .spacing-popover {
        position: absolute;
        top: calc(100% + 8px);
        right: 0;
        width: min(286px, calc(100vw - 24px));
        padding: 12px;
        border-radius: var(--radius-md);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        box-shadow: 0 12px 32px rgba(0, 0, 0, 0.22);
        z-index: 60;
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .spacing-block {
        display: flex;
        flex-direction: column;
        gap: 8px;
        padding: 10px;
        border-radius: var(--radius-sm);
        background-color: var(--surface-variant);
      }

      .spacing-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }

      .spacing-title {
        font-size: 12px;
        font-weight: 700;
        color: var(--on-surface);
      }

      .spacing-controls {
        display: inline-flex;
        align-items: center;
        gap: 4px;
      }

      .spacing-val {
        font-size: 11px;
        font-weight: 600;
        color: var(--on-surface-muted);
        font-variant-numeric: tabular-nums;
        margin-right: 2px;
      }

      .step-mini-btn {
        width: 22px;
        height: 22px;
        border-radius: var(--radius-pill);
        border: 1px solid var(--surface-border);
        background-color: var(--surface);
        color: var(--on-surface);
        font-size: 13px;
        font-weight: 700;
        display: grid;
        place-items: center;
      }

      .step-mini-btn:hover:not(:disabled) {
        border-color: var(--accent);
        color: var(--accent);
      }

      .step-mini-btn:disabled {
        opacity: 0.35;
        cursor: default;
      }

      .preset-row {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 6px;
      }

      .preset-chip {
        height: 26px;
        border-radius: var(--radius-sm);
        border: 1px solid var(--surface-border);
        background-color: var(--surface);
        color: var(--on-surface);
        font-size: 11.5px;
        font-weight: 600;
        transition: background-color 140ms ease, color 140ms ease, border-color 140ms ease;
      }

      .preset-chip.active {
        background-color: var(--accent);
        border-color: var(--accent);
        color: var(--on-accent);
      }

      .spacing-range {
        width: 100%;
        accent-color: var(--accent);
      }

      .font-sample {
        display: block;
        margin-top: 3px;
        font-size: 13px;
        line-height: 1.35;
        color: var(--on-surface-muted);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .style-filter-row {
        display: flex;
        flex-wrap: wrap;
        gap: 4px;
        padding: 4px 10px 6px;
        border-bottom: 1px solid var(--surface-border);
      }

      .style-chip {
        padding: 3px 8px;
        border-radius: 999px;
        border: 1px solid var(--surface-border);
        background: var(--surface);
        color: var(--on-surface-muted);
        font-size: 11px;
        font-weight: 600;
        cursor: pointer;
      }

      .style-chip.active {
        background: var(--accent);
        border-color: var(--accent);
        color: var(--on-accent);
      }
    `,
  ],
})
export class ReaderTypographyToggleComponent {
  private readonly el = inject(ElementRef<HTMLElement>);
  readonly appearance = inject(ReaderAppearanceService);
  readonly Math = Math;

  readonly fonts = READER_FONTS;
  readonly fontGroups = this.appearance.fontsByLanguage;
  readonly selectedLang = signal<'all' | ReaderFontLanguageCode>('all');
  readonly selectedCategory = signal<'all' | 'serif' | 'sans' | 'display' | 'handwriting'>('all');
  readonly categoryChips = [
    { id: 'all', label: 'All Styles' },
    { id: 'serif', label: 'Serif' },
    { id: 'sans', label: 'Sans' },
    { id: 'display', label: 'Display' },
    { id: 'handwriting', label: 'Script' },
  ] as const;

  readonly visibleFontGroups = computed<readonly ReaderFontGroup[]>(() => {
    const lang = this.selectedLang();
    const cat = this.selectedCategory();
    const groups = this.fontGroups();
    const byLang = lang === 'all' ? groups : groups.filter((g) => g.code === lang);
    if (cat === 'all') return byLang;
    return byLang
      .map((g) => ({
        ...g,
        fonts: g.fonts.filter((f) => !f.category || f.category === cat),
      }))
      .filter((g) => g.fonts.length > 0);
  });

  readonly linePresets = LINE_HEIGHT_PRESETS;
  readonly letterPresets = LETTER_SPACING_PRESETS;

  readonly fontMenuOpen = signal<boolean>(false);
  readonly spacingOpen = signal<boolean>(false);

  readonly activeFont = computed<ReaderFontOption>(() => this.appearance.activeFont());

  readonly isCustomSpacing = computed<boolean>(() => {
    return (
      Math.abs(this.appearance.lineHeight() - 1.65) > 0.01 ||
      Math.abs(this.appearance.letterSpacing()) > 0.005
    );
  });

  toggleFontMenu(event: MouseEvent): void {
    event.stopPropagation();
    const next = !this.fontMenuOpen();
    this.fontMenuOpen.set(next);
    if (next) this.spacingOpen.set(false);
  }

  selectFont(fontId: string): void {
    this.appearance.setFont(fontId);
    this.fontMenuOpen.set(false);
  }

  downloadGroup(lang: ReaderFontLanguageCode, event: MouseEvent): void {
    event.stopPropagation();
    void this.appearance.downloadLanguageFonts(lang);
  }

  toggleSpacing(event: MouseEvent): void {
    event.stopPropagation();
    const next = !this.spacingOpen();
    this.spacingOpen.set(next);
    if (next) this.fontMenuOpen.set(false);
  }

  @HostListener('document:click', ['$event'])
  onDocumentClick(event: MouseEvent): void {
    if (
      (this.fontMenuOpen() || this.spacingOpen()) &&
      !this.el.nativeElement.contains(event.target as Node)
    ) {
      this.fontMenuOpen.set(false);
      this.spacingOpen.set(false);
    }
  }

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.fontMenuOpen.set(false);
    this.spacingOpen.set(false);
  }
}
