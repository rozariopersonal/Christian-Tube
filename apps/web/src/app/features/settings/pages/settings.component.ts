import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { ReleaseDataService } from '../../../core/api/release-data.service';
import { AuthService } from '../../../core/auth/auth.service';
import {
  READER_FONTS,
  ReaderAppearanceService,
} from '../../../core/services/reader-appearance.service';
import {
  APP_COLOR_THEMES,
  ThemeService,
} from '../../../core/theme/theme.service';
import { BIBLE_VERSIONS } from '../../bible/models/bible.model';

@Component({
  selector: 'app-settings-page',
  standalone: true,
  imports: [FormsModule, RouterLink],
  template: `
    <div class="settings-page max-width-box">
      <header class="page-head">
        <h1 class="font-display">Settings</h1>
      </header>

      <section class="settings-card">
        <h2>Account</h2>
        @if (auth.currentUser(); as user) {
          <div class="account-row">
            <div class="account-left">
              @if (user.photoUrl) {
                <img class="avatar" [src]="user.photoUrl" [alt]="user.displayName" />
              } @else {
                <span class="avatar fallback">{{ user.displayName.slice(0, 1).toUpperCase() }}</span>
              }
              <div>
                <strong>{{ user.displayName }}</strong>
                <p class="muted">{{ user.email }}</p>
              </div>
            </div>
            <button type="button" class="pill-chip" (click)="auth.signOut()">
              Sign Out
            </button>
          </div>
        } @else {
          <div class="account-actions">
            <p class="muted">Sign in to sync subscriptions & preferences.</p>
            <div class="chip-wrap">
              <button type="button" class="pill-chip active" (click)="auth.promptGoogleSignIn()">
                Sign in with Google
              </button>
              <button type="button" class="pill-chip" (click)="auth.signInAsGuest()">
                Guest Sign-In
              </button>
            </div>
          </div>
        }
      </section>

      <section class="settings-card">
        <h2>Appearance</h2>
        <div class="field-group">
          <span class="label">Theme Mode</span>
          <div class="chip-wrap">
            @for (mode of ['system', 'light', 'dark']; track mode) {
              <button
                type="button"
                class="pill-chip"
                [class.active]="theme.themeMode() === mode"
                (click)="theme.setThemeMode($any(mode))"
              >
                {{ mode[0].toUpperCase() + mode.slice(1) }}
              </button>
            }
            <button
              type="button"
              class="pill-chip"
              [class.active]="theme.isAmoled()"
              (click)="theme.setAmoled(!theme.isAmoled())"
            >
              AMOLED Black
            </button>
          </div>
        </div>

        <div class="field-group">
          <span class="label">Accent Color</span>
          <div class="swatch-row">
            @for (c of colorThemes; track c.id) {
              <button
                type="button"
                class="swatch"
                [style.background-color]="c.color"
                [class.selected]="theme.colorTheme().id === c.id"
                [attr.aria-label]="c.name"
                [title]="c.name"
                (click)="theme.setColorTheme(c.id)"
              ></button>
            }
          </div>
        </div>
      </section>

      <section class="settings-card">
        <h2>Reader Typography</h2>
        <div class="field-group">
          <span class="label">Font Family</span>
          <div class="chip-wrap">
            @for (f of fonts; track f.id) {
              <button
                type="button"
                class="pill-chip"
                [class.active]="appearance.fontId() === f.id"
                (click)="appearance.setFont(f.id)"
              >
                {{ f.label }}
              </button>
            }
          </div>
        </div>

        <div class="field-group">
          <label class="label">Font Size: {{ appearance.fontSize() }}px</label>
          <input
            type="range"
            min="13"
            max="28"
            [ngModel]="appearance.fontSize()"
            (ngModelChange)="appearance.setFontSize($event)"
          />
        </div>

        <div class="field-group">
          <label class="label">Line Spacing: {{ appearance.lineHeight() }}</label>
          <input
            type="range"
            min="1.3"
            max="2.2"
            step="0.05"
            [ngModel]="appearance.lineHeight()"
            (ngModelChange)="appearance.setLineHeight($event)"
          />
        </div>

        <div
          class="preview-box"
          [style.font-family]="appearance.activeFont().cssFamily"
          [style.font-size.px]="appearance.fontSize()"
          [style.line-height]="appearance.lineHeight()"
        >
          In the beginning God created the heavens and the earth.
        </div>
      </section>

      <section class="settings-card">
        <h2>Bible & Setup</h2>
        <div class="field-group">
          <label class="label" for="primary-bible">Primary Bible Version</label>
          <select
            id="primary-bible"
            class="select-input"
            [ngModel]="appearance.primaryBibleVersion().toLowerCase()"
            (ngModelChange)="appearance.setPrimaryBibleVersion($event)"
          >
            @for (v of bibleVersions; track v.id) {
              <option [value]="v.id">{{ v.label }} ({{ v.language }})</option>
            }
          </select>
        </div>

        <div class="chip-wrap">
          <a class="pill-chip" routerLink="/onboarding">Re-run Onboarding</a>
          <button type="button" class="pill-chip" (click)="clearCache()">
            Clear Cached Data
          </button>
        </div>
        @if (releases.revision()) {
          <p class="muted">Dataset Revision: {{ releases.revision() }}</p>
        }
      </section>
    </div>
  `,
  styles: [
    `
      .settings-page {
        padding-top: 16px;
        padding-bottom: 90px;
        display: flex;
        flex-direction: column;
        gap: 16px;
      }

      .page-head h1 {
        margin: 0;
        font-size: 22px;
        font-weight: 700;
      }

      .settings-card {
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-lg);
        padding: 18px;
        display: flex;
        flex-direction: column;
        gap: 14px;
      }

      .settings-card h2 {
        margin: 0;
        font-size: 16px;
        font-weight: 700;
      }

      .account-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        flex-wrap: wrap;
      }

      .account-left {
        display: flex;
        align-items: center;
        gap: 12px;
        min-width: 0;
      }

      .avatar {
        width: 44px;
        height: 44px;
        border-radius: var(--radius-pill);
        object-fit: cover;
        flex-shrink: 0;
      }

      .avatar.fallback {
        display: grid;
        place-items: center;
        font-weight: 700;
        background-color: var(--accent-soft);
        color: var(--accent);
      }

      .muted {
        margin: 2px 0 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .field-group {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .label {
        font-size: 13px;
        font-weight: 600;
        color: var(--on-surface-muted);
      }

      .chip-wrap {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }

      .swatch-row {
        display: flex;
        flex-wrap: wrap;
        gap: 12px;
      }

      .swatch {
        width: 34px;
        height: 34px;
        border-radius: var(--radius-pill);
        border: 2px solid transparent;
      }

      .swatch.selected {
        border-color: var(--on-surface);
        transform: scale(1.1);
      }

      .preview-box {
        padding: 14px;
        border-radius: var(--radius-md);
        background-color: var(--bg);
        border: 1px solid var(--surface-border);
      }

      .select-input {
        max-width: 280px;
        height: 40px;
        padding: 0 12px;
        border-radius: var(--radius-sm);
        background-color: var(--bg);
        border: 1px solid var(--surface-border);
      }
    `,
  ],
})
export class SettingsComponent {
  readonly auth = inject(AuthService);
  readonly theme = inject(ThemeService);
  readonly appearance = inject(ReaderAppearanceService);
  readonly releases = inject(ReleaseDataService);

  readonly colorThemes = APP_COLOR_THEMES;
  readonly fonts = READER_FONTS;
  readonly bibleVersions = BIBLE_VERSIONS;

  clearCache(): void {
    this.releases.clearCache();
    void this.releases.refreshRevision();
  }
}
