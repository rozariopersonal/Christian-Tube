import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { firstValueFrom } from 'rxjs';
import { ApiService } from '../../../core/api/api.service';
import { ReleaseDataService } from '../../../core/api/release-data.service';
import { AuthService } from '../../../core/auth/auth.service';
import { GoogleSignInButtonComponent } from '../../../core/auth/google-sign-in-button.component';
import {
  READER_FONTS,
  ReaderAppearanceService,
} from '../../../core/services/reader-appearance.service';
import { ContentPreferencesService } from '../../../core/services/content-preferences.service';
import {
  APP_COLOR_THEMES,
  APP_FONT_FAMILIES,
  ThemeService,
} from '../../../core/theme/theme.service';
import { SUPPORTED_LANGUAGES } from '../../../shared/ui/language-meta';
import { BIBLE_VERSIONS } from '../../bible/models/bible.model';
import { VideoLibraryService } from '../../videos/services/video-library.service';

const KEY_PREFERRED_LANGUAGES = 'preferred_languages';

@Component({
  selector: 'app-settings-page',
  standalone: true,
  imports: [FormsModule, RouterLink, GoogleSignInButtonComponent],
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
          @if (auth.sessionNeedsSignIn()) {
            <div class="account-actions">
              <p class="muted">Your session has expired. Sign in again to resume syncing.</p>
              <app-google-sign-in-button />
            </div>
          }
        } @else {
          <div class="account-actions">
            <p class="muted">Sign in to sync followed channels &amp; preferences.</p>
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

        <div class="field-group">
          <span class="label">App Font Family</span>
          <div class="chip-wrap">
            @for (f of appFonts; track f) {
              <button
                type="button"
                class="pill-chip"
                [class.active]="theme.appFont() === f"
                (click)="theme.setAppFont(f)"
              >
                {{ f }}
              </button>
            }
          </div>
        </div>
      </section>

      <section class="settings-card">
        <h2>Default Page on Open</h2>
        <div class="field-group">
          <span class="label">Choose which page opens first when you launch the app</span>
          <div class="chip-wrap">
            @for (opt of defaultPageOptions; track opt.id) {
              <button
                type="button"
                class="pill-chip"
                [class.active]="prefs.defaultPage() === opt.id"
                (click)="prefs.setDefaultPage(opt.id)"
              >
                {{ opt.label }}
              </button>
            }
          </div>
        </div>
      </section>

      <section class="settings-card">
        <h2>Content &amp; Languages</h2>
        <div class="field-group">
          <span class="label">Preferred Content Languages</span>
          <div class="chip-wrap">
            @for (lang of languages; track lang.code) {
              <button
                type="button"
                class="pill-chip"
                [class.active]="prefs.preferredLanguages().includes(lang.code)"
                (click)="prefs.toggleLanguage(lang.code)"
              >
                {{ lang.englishName }}
              </button>
            }
          </div>
        </div>

        <div class="field-group">
          <label class="label" for="primary-bible">Primary Bible Version</label>
          <select
            id="primary-bible"
            class="select-input"
            [ngModel]="appearance.primaryBibleVersion().toLowerCase()"
            (ngModelChange)="appearance.setPrimaryBibleVersion($event)"
          >
            <optgroup label="Preferred Languages">
              @for (v of preferredBibleVersions(); track v.id) {
                <option [value]="v.id">{{ v.label }} ({{ v.language }})</option>
              }
            </optgroup>
            @if (otherBibleVersions().length > 0) {
              <optgroup label="Other Languages">
                @for (v of otherBibleVersions(); track v.id) {
                  <option [value]="v.id">{{ v.label }} ({{ v.language }})</option>
                }
              </optgroup>
            }
          </select>
        </div>
      </section>

      <section class="settings-card">
        <h2>Playback</h2>
        <label class="toggle-row">
          <div>
            <strong>Autoplay Next Video</strong>
            <p class="muted">Automatically play the next queued or related video when playback ends</p>
          </div>
          <input
            type="checkbox"
            [ngModel]="library.autoplay()"
            (ngModelChange)="library.setAutoplay($event)"
          />
        </label>
      </section>

      <section class="settings-card">
        <h2>Reader Typography</h2>
        <div class="field-group">
          <div class="account-row">
            <span class="label">Reader Fonts (Grouped by Language)</span>
            @if (appearance.canQueryLocalFonts()) {
              <button
                type="button"
                class="pill-chip"
                [disabled]="appearance.scanningSystemFonts()"
                (click)="appearance.scanLocalSystemFonts()"
              >
                <span class="material-symbols-rounded btn-icon">computer</span>
                {{ appearance.scanningSystemFonts() ? 'Scanning...' : 'Load System Fonts' }}
              </button>
            }
          </div>
          @for (grp of appearance.fontsByLanguage(); track grp.code) {
            <div class="font-lang-group">
              <div class="account-row">
                <span class="label">
                  {{ grp.label }}
                  @if (grp.nativeLabel !== grp.label) {
                    · {{ grp.nativeLabel }}
                  }
                </span>
                @if (grp.downloadedCount < grp.onDemandCount) {
                  <button
                    type="button"
                    class="pill-chip"
                    [disabled]="appearance.isLanguageDownloading(grp.code)"
                    (click)="appearance.downloadLanguageFonts(grp.code)"
                  >
                    <span class="material-symbols-rounded btn-icon">download</span>
                    {{
                      appearance.isLanguageDownloading(grp.code)
                        ? 'Downloading...'
                        : 'Download All (' + (grp.onDemandCount - grp.downloadedCount) + ')'
                    }}
                  </button>
                }
              </div>
              <div class="chip-wrap">
                @for (f of grp.fonts; track f.id) {
                  <button
                    type="button"
                    class="pill-chip"
                    [class.active]="appearance.fontId() === f.id"
                    [style.font-family]="f.cssFamily"
                    (click)="appearance.setFont(f.id)"
                  >
                    {{ f.label }}
                  </button>
                }
              </div>
            </div>
          }
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

        <div class="field-group">
          <label class="label">
            Letter Spacing: {{ appearance.formatLetterSpacing() }}
          </label>
          <input
            type="range"
            min="-0.04"
            max="0.12"
            step="0.01"
            [ngModel]="appearance.letterSpacing()"
            (ngModelChange)="appearance.setLetterSpacing($event)"
          />
        </div>

        <div
          class="preview-box"
          [style.font-family]="appearance.activeFont().cssFamily"
          [style.font-size.px]="appearance.fontSize()"
          [style.line-height]="appearance.lineHeight()"
          [style.letter-spacing.em]="appearance.letterSpacing()"
        >
          In the beginning God created the heavens and the earth.
        </div>
      </section>

      <section class="settings-card">
        <h2>Share, Feedback &amp; Setup</h2>
        <div class="chip-wrap">
          <button type="button" class="pill-chip" (click)="shareApp()">
            <span class="material-symbols-rounded btn-icon">share</span>
            {{ shareCopied() ? 'Link Copied' : 'Share App' }}
          </button>
          <button type="button" class="pill-chip" (click)="feedbackOpen.set(true)">
            <span class="material-symbols-rounded btn-icon">feedback</span>
            Send Feedback
          </button>
          <a class="pill-chip" routerLink="/onboarding">Re-run Onboarding</a>
          <button type="button" class="pill-chip" (click)="clearCache()">
            Clear Cached Data
          </button>
        </div>
        @if (releases.revision()) {
          <p class="muted">Dataset Revision: {{ releases.revision() }}</p>
        }
      </section>

      @if (feedbackOpen()) {
        <div class="modal-backdrop" (click)="feedbackOpen.set(false)">
          <div class="modal-card" (click)="$event.stopPropagation()">
            <div class="modal-head">
              <h3>Send Feedback &amp; Bug Report</h3>
              <button type="button" class="icon-btn" (click)="feedbackOpen.set(false)">
                <span class="material-symbols-rounded">close</span>
              </button>
            </div>
            <input
              type="text"
              class="text-input"
              placeholder="Summary title..."
              [ngModel]="feedbackTitle()"
              (ngModelChange)="feedbackTitle.set($event)"
            />
            <textarea
              rows="4"
              class="text-input"
              placeholder="Describe your feedback or issue..."
              [ngModel]="feedbackBody()"
              (ngModelChange)="feedbackBody.set($event)"
            ></textarea>
            @if (feedbackStatus()) {
              <p class="muted">{{ feedbackStatus() }}</p>
            }
            <div class="modal-actions">
              <button type="button" class="pill-chip" (click)="feedbackOpen.set(false)">
                Cancel
              </button>
              <button
                type="button"
                class="pill-chip active"
                [disabled]="feedbackSending() || !feedbackTitle().trim() || !feedbackBody().trim()"
                (click)="submitFeedback()"
              >
                {{ feedbackSending() ? 'Sending...' : 'Submit' }}
              </button>
            </div>
          </div>
        </div>
      }
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

      .account-row,
      .toggle-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        flex-wrap: wrap;
      }

      .toggle-row {
        cursor: pointer;
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

      .font-lang-group {
        display: flex;
        flex-direction: column;
        gap: 6px;
        padding: 10px 12px;
        border-radius: var(--radius-md);
        background-color: var(--bg);
        border: 1px solid var(--surface-border);
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

      .btn-icon {
        font-size: 18px;
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

      .modal-backdrop {
        position: fixed;
        inset: 0;
        background: rgba(0, 0, 0, 0.55);
        display: grid;
        place-items: center;
        padding: 16px;
        z-index: 80;
      }

      .modal-card {
        width: 100%;
        max-width: 440px;
        background: var(--surface-elevated);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-lg);
        padding: 18px;
        display: flex;
        flex-direction: column;
        gap: 12px;
      }

      .modal-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
      }

      .modal-head h3 {
        margin: 0;
        font-size: 16px;
      }

      .text-input {
        width: 100%;
        padding: 10px 12px;
        border-radius: var(--radius-sm);
        border: 1px solid var(--surface-border);
        background: var(--bg);
        font-size: 14px;
      }

      .modal-actions {
        display: flex;
        justify-content: flex-end;
        gap: 8px;
      }
    `,
  ],
})
export class SettingsComponent {
  private readonly api = inject(ApiService);
  readonly auth = inject(AuthService);
  readonly theme = inject(ThemeService);
  readonly appearance = inject(ReaderAppearanceService);
  readonly releases = inject(ReleaseDataService);
  readonly library = inject(VideoLibraryService);
  readonly prefs = inject(ContentPreferencesService);

  readonly colorThemes = APP_COLOR_THEMES;
  readonly appFonts = APP_FONT_FAMILIES;
  readonly defaultPageOptions = [
    { id: 'feed', label: 'Videos' },
    { id: 'shorts', label: 'Shorts' },
    { id: 'words', label: 'Words' },
    { id: 'bible', label: 'Bible' },
    { id: 'library', label: 'Books' },
    { id: 'articles', label: 'Articles' },
    { id: 'audio', label: 'Audio' },
  ];
  readonly fonts = READER_FONTS;
  readonly bibleVersions = BIBLE_VERSIONS;
  readonly preferredBibleVersions = computed(() => {
    const matched = BIBLE_VERSIONS.filter((v) =>
      this.prefs.matchesLanguageName(v.language),
    );
    return matched.length > 0 ? matched : BIBLE_VERSIONS;
  });
  readonly otherBibleVersions = computed(() => {
    const prefIds = new Set(this.preferredBibleVersions().map((v) => v.id));
    return BIBLE_VERSIONS.filter((v) => !prefIds.has(v.id));
  });
  readonly languages = Object.values(SUPPORTED_LANGUAGES).filter(
    (l) => l.code.toLowerCase() !== 'all',
  );

  readonly shareCopied = signal<boolean>(false);
  readonly feedbackOpen = signal<boolean>(false);
  readonly feedbackTitle = signal<string>('');
  readonly feedbackBody = signal<string>('');
  readonly feedbackSending = signal<boolean>(false);
  readonly feedbackStatus = signal<string | null>(null);

  shareApp(): void {
    const url = window.location.origin;
    if (navigator.share) {
      void navigator.share({ title: 'ChristianApp', url });
    } else if (navigator.clipboard) {
      void navigator.clipboard.writeText(url);
      this.shareCopied.set(true);
      setTimeout(() => this.shareCopied.set(false), 2000);
    }
  }

  async submitFeedback(): Promise<void> {
    this.feedbackSending.set(true);
    this.feedbackStatus.set(null);
    try {
      await firstValueFrom(
        this.api.post('/api/feedback', {
          title: this.feedbackTitle().trim(),
          body: this.feedbackBody().trim(),
          route: '/settings',
        }),
      );
      this.feedbackTitle.set('');
      this.feedbackBody.set('');
      this.feedbackOpen.set(false);
    } catch {
      this.feedbackStatus.set('Unable to submit feedback right now.');
    } finally {
      this.feedbackSending.set(false);
    }
  }

  clearCache(): void {
    this.releases.clearCache();
    void this.releases.refreshRevision();
  }
}
