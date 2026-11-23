import {
  ChangeDetectionStrategy,
  Component,
  computed,
  inject,
  input,
  output,
  signal,
} from '@angular/core';
import { ThemeService } from '../../../core/theme/theme.service';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { TextAlignOption, WordFeedItem } from '../models/words-feed.model';
import {
  BACKGROUND_PRESETS,
  COLOR_PALETTE,
  getFontsForLanguage,
  getLanguageForVersion,
  resolvePresetCssBackground,
} from '../models/words-theme.catalog';
import { WordsPreferencesService } from '../services/words-preferences.service';

@Component({
  selector: 'app-words-style-drawer',
  standalone: true,
  imports: [ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet title="Style Studio" (closed)="closed.emit()">
      <div class="style-scroll">
        <div class="scope-row">
          <span class="scope-label">Apply changes to</span>
          <div class="seg-mini">
            <button
              type="button"
              [class.active]="applyToAll()"
              (click)="applyToAll.set(true)"
            >
              All Cards
            </button>
            <button
              type="button"
              [class.active]="!applyToAll()"
              (click)="applyToAll.set(false)"
            >
              This Card
            </button>
          </div>
        </div>

        <section class="sec">
          <div class="sec-head">
            <h3 class="sec-title">Typography</h3>
            <span class="scale-val">{{ (appearance().fontSizeScale * 100).toFixed(0) }}%</span>
          </div>
          <div class="typo-controls">
            <input
              type="range"
              min="0.8"
              max="1.5"
              step="0.1"
              [value]="appearance().fontSizeScale"
              (input)="onScaleInput($event)"
            />
            <div class="fmt-btns">
              <button
                type="button"
                class="fmt-btn"
                [class.active]="appearance().isBold"
                title="Bold"
                (click)="toggleBold()"
              >
                <strong>B</strong>
              </button>
              <button
                type="button"
                class="fmt-btn"
                [class.active]="appearance().isItalic"
                title="Italic"
                (click)="toggleItalic()"
              >
                <em>I</em>
              </button>
              @for (al of alignments; track al.id) {
                <button
                  type="button"
                  class="fmt-btn"
                  [class.active]="appearance().textAlign === al.id"
                  [title]="al.label"
                  (click)="setAlign(al.id)"
                >
                  <span class="material-symbols-rounded">{{ al.icon }}</span>
                </button>
              }
            </div>
          </div>
        </section>

        <section class="sec">
          <h3 class="sec-title">Font Family</h3>
          <div class="font-grid">
            @for (f of fonts(); track f.id) {
              <button
                type="button"
                class="font-card"
                [class.active]="activeFontId() === f.id"
                (click)="selectFont(f.id)"
              >
                <span class="font-glyph" [style.fontFamily]="f.cssFamily">{{ f.sampleGlyph }}</span>
                <span class="font-name">{{ f.name }}</span>
                <span class="font-sub">{{ f.subtitle }}</span>
              </button>
            }
          </div>
        </section>

        <section class="sec">
          <div class="sec-head">
            <h3 class="sec-title">Text Color</h3>
            <button type="button" class="link-btn" (click)="resetTextColor()">
              Auto
            </button>
          </div>
          <div class="color-row">
            @for (c of colors; track c.hex) {
              <button
                type="button"
                class="color-dot"
                [style.backgroundColor]="c.hex"
                [class.active]="appearance().textColorHex.toUpperCase() === c.hex.toUpperCase()"
                [title]="c.name"
                (click)="selectColor(c.hex)"
              ></button>
            }
          </div>
        </section>

        <section class="sec">
          <h3 class="sec-title">Background Theme</h3>
          <div class="preset-grid">
            @for (p of presets; track p.id) {
              <button
                type="button"
                class="preset-tile"
                [class.active]="activePresetId() === p.id"
                (click)="selectPreset(p.id)"
              >
                <span
                  class="preset-swatch"
                  [style.background]="presetBg(p.id)"
                ></span>
                <span class="preset-name">{{ p.name }}</span>
              </button>
            }
          </div>
        </section>
      </div>
    </app-modal-sheet>
  `,
  styles: [
    `
      .style-scroll {
        display: flex;
        flex-direction: column;
        gap: 18px;
        max-height: 68dvh;
        overflow-y: auto;
        padding: 4px 8px 6px 2px;
        scrollbar-width: thin;
        scrollbar-color: var(--surface-border) transparent;
      }

      .style-scroll::-webkit-scrollbar {
        width: 5px;
      }

      .style-scroll::-webkit-scrollbar-thumb {
        border-radius: 999px;
        background-color: var(--surface-border);
      }

      .scope-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
        padding: 8px 12px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .scope-label {
        font-size: 13px;
        font-weight: 600;
      }

      .seg-mini {
        display: flex;
        gap: 4px;
      }

      .seg-mini button {
        height: 28px;
        padding: 0 10px;
        border-radius: var(--radius-pill);
        font-size: 12px;
        font-weight: 600;
        color: var(--on-surface-muted);
      }

      .seg-mini button.active {
        background-color: var(--accent);
        color: #ffffff;
      }

      .sec {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .sec-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
      }

      .sec-title {
        margin: 0;
        font-size: 12px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--on-surface-muted);
      }

      .scale-val {
        font-size: 12px;
        font-weight: 700;
        color: var(--accent);
      }

      .link-btn {
        font-size: 12px;
        font-weight: 600;
        color: var(--accent);
      }

      .typo-controls {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .typo-controls input[type='range'] {
        width: 100%;
        accent-color: var(--accent);
      }

      .fmt-btns {
        display: flex;
        gap: 8px;
      }

      .fmt-btn {
        flex: 1;
        height: 36px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        color: var(--on-surface);
        display: grid;
        place-items: center;
        font-size: 14px;
      }

      .fmt-btn.active {
        background-color: var(--accent-soft);
        border-color: var(--accent);
        color: var(--accent);
      }

      .fmt-btn .material-symbols-rounded {
        font-size: 18px;
      }

      .font-grid {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: 8px;
      }

      .font-card {
        display: flex;
        flex-direction: column;
        align-items: flex-start;
        gap: 2px;
        padding: 10px 12px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        text-align: left;
      }

      .font-card.active {
        background-color: var(--accent-soft);
        border-color: var(--accent);
      }

      .font-glyph {
        font-size: 18px;
        line-height: 1.25;
      }

      .font-name {
        font-size: 12px;
        font-weight: 600;
      }

      .font-sub {
        font-size: 11px;
        color: var(--on-surface-muted);
      }

      .color-row {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }

      .color-dot {
        width: 30px;
        height: 30px;
        border-radius: 999px;
        border: 2px solid var(--surface-border);
      }

      .color-dot.active {
        outline: 2px solid var(--accent);
        outline-offset: 2px;
      }

      .preset-grid {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: 8px;
      }

      .preset-tile {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 8px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        text-align: left;
      }

      .preset-tile.active {
        border-color: var(--accent);
        background-color: var(--accent-soft);
      }

      .preset-swatch {
        width: 32px;
        height: 32px;
        border-radius: var(--radius-sm);
        border: 1px solid var(--surface-border);
        flex-shrink: 0;
      }

      .preset-name {
        font-size: 12px;
        font-weight: 600;
      }
    `,
  ],
})
export class WordsStyleDrawerComponent {
  private readonly prefs = inject(WordsPreferencesService);
  private readonly theme = inject(ThemeService);

  readonly card = input<WordFeedItem | null>(null);
  readonly cardUpdated = output<{
    customBackgroundPreset?: string;
    customFontFamily?: string;
  }>();
  readonly closed = output<void>();

  readonly applyToAll = signal<boolean>(true);
  readonly appearance = this.prefs.appearance;
  readonly colors = COLOR_PALETTE;
  readonly presets = BACKGROUND_PRESETS;
  readonly alignments: readonly {
    id: TextAlignOption;
    label: string;
    icon: string;
  }[] = [
    { id: 'left', label: 'Align Left', icon: 'format_align_left' },
    { id: 'center', label: 'Align Center', icon: 'format_align_center' },
    { id: 'right', label: 'Align Right', icon: 'format_align_right' },
  ];

  readonly fonts = computed(() =>
    getFontsForLanguage(
      getLanguageForVersion(this.appearance().activeVersionId),
    ),
  );

  readonly activeFontId = computed(() => {
    const c = this.card();
    return (!this.applyToAll() && c?.customFontFamily) ||
      this.appearance().activeFontFamily;
  });

  readonly activePresetId = computed(() => {
    const c = this.card();
    return (!this.applyToAll() && c?.customBackgroundPreset) ||
      this.appearance().backgroundPreset;
  });

  presetBg(id: string): string {
    const p = BACKGROUND_PRESETS.find((x) => x.id === id) ?? BACKGROUND_PRESETS[0];
    return resolvePresetCssBackground(p, this.theme.isDark());
  }

  onScaleInput(event: Event): void {
    const val = Number((event.target as HTMLInputElement).value);
    if (!Number.isNaN(val)) {
      this.prefs.setFontScale(val);
    }
  }

  toggleBold(): void {
    this.prefs.updateLangPref({ isBold: !this.appearance().isBold });
  }

  toggleItalic(): void {
    this.prefs.updateLangPref({ isItalic: !this.appearance().isItalic });
  }

  setAlign(align: TextAlignOption): void {
    this.prefs.updateLangPref({ textAlign: align });
  }

  selectFont(fontId: string): void {
    const lang = getLanguageForVersion(this.appearance().activeVersionId);
    this.prefs.ensureFontLoaded(fontId, lang);
    if (this.applyToAll()) {
      this.cardUpdated.emit({ customFontFamily: undefined });
      this.prefs.updateLangPref({ activeFontFamily: fontId });
    } else {
      this.cardUpdated.emit({ customFontFamily: fontId });
    }
  }

  selectColor(hex: string): void {
    this.prefs.updateLangPref({ textColorHex: hex });
  }

  resetTextColor(): void {
    this.prefs.updateLangPref({ textColorHex: null });
  }

  selectPreset(presetId: string): void {
    if (this.applyToAll()) {
      this.cardUpdated.emit({ customBackgroundPreset: undefined });
      this.prefs.updateLangPref({ backgroundPreset: presetId });
    } else {
      this.cardUpdated.emit({ customBackgroundPreset: presetId });
    }
  }
}
