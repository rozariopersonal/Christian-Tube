import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { firstValueFrom } from 'rxjs';
import { ApiService } from '../../../core/api/api.service';
import { AuthService } from '../../../core/auth/auth.service';
import { ReaderAppearanceService } from '../../../core/services/reader-appearance.service';
import {
  APP_COLOR_THEMES,
  ThemeService,
} from '../../../core/theme/theme.service';
import { SUPPORTED_LANGUAGES } from '../../../shared/ui/language-meta';
import { ChannelService } from '../../channels/services/channel.service';

const LANGUAGES = Object.values(SUPPORTED_LANGUAGES)
  .filter((l) => l.code !== 'All')
  .map((l) => ({
    code: l.code,
    name:
      l.nativeName && l.nativeName !== l.englishName
        ? `${l.englishName} (${l.nativeName})`
        : l.englishName,
  }));

const BIBLE_VERSIONS = ['NASB', 'KJV', 'ASV', 'NLT', 'WEB', 'TAOBVSI'];

@Component({
  selector: 'app-onboarding',
  standalone: true,
  imports: [FormsModule],
  template: `
    <div class="onboarding-wrap max-width-box">
      <div class="progress-bar">
        <div class="progress-fill" [style.width.%]="((step() + 1) / 5) * 100"></div>
      </div>
      <p class="step-label">Step {{ step() + 1 }} of 5</p>

      @switch (step()) {
        @case (0) {
          <section class="step-card">
            <img src="logo.png" alt="ChristianApp" width="56" height="56" />
            <h1 class="font-display">Welcome to ChristianApp</h1>
            <p class="muted">
              Sign in with Google to sync your followed channels, preferences, and reading progress — or continue as a guest.
            </p>
            @if (auth.isAuthenticated()) {
              <div class="signed-in-pill">
                Signed in as {{ auth.currentUser()!.displayName }}
              </div>
            } @else {
              <div class="auth-actions">
                <button type="button" class="pill-chip active" (click)="auth.promptGoogleSignIn()">
                  Sign in with Google
                </button>
                <button type="button" class="pill-chip" (click)="auth.signInAsGuest()">
                  Continue as Guest
                </button>
              </div>
            }
          </section>
        }

        @case (1) {
          <section class="step-card">
            <h1 class="font-display">Choose Your Languages</h1>
            <p class="muted">Used to filter books, audio sermons, and Bible resources.</p>
            <div class="chip-grid">
              @for (lang of languages; track lang.code) {
                <button
                  type="button"
                  class="pill-chip"
                  [class.active]="selectedLanguages().has(lang.code)"
                  (click)="toggleLanguage(lang.code)"
                >
                  {{ lang.name }}
                </button>
              }
            </div>
          </section>
        }

        @case (2) {
          <section class="step-card">
            <h1 class="font-display">Follow Channels</h1>
            <p class="muted">Pick ministries and teachers for your video feed.</p>
            <input
              type="search"
              class="search-input"
              placeholder="Search channels..."
              [ngModel]="channelSearch()"
              (ngModelChange)="channelSearch.set($event)"
            />
            <div class="channel-list">
              @for (ch of filteredChannels(); track ch.id) {
                <button
                  type="button"
                  class="channel-row"
                  [class.selected]="selectedChannelIds().has(ch.id)"
                  (click)="toggleChannel(ch.id)"
                >
                  <span class="ch-title">{{ ch.title }}</span>
                  <span class="material-symbols-rounded">
                    {{ selectedChannelIds().has(ch.id) ? 'check_circle' : 'add_circle_outline' }}
                  </span>
                </button>
              }
            </div>
          </section>
        }

        @case (3) {
          <section class="step-card">
            <h1 class="font-display">Primary Bible Version</h1>
            <p class="muted">You can switch versions anytime in the Bible reader.</p>
            <div class="chip-grid">
              @for (v of bibleVersions; track v) {
                <button
                  type="button"
                  class="pill-chip"
                  [class.active]="primaryBible() === v"
                  (click)="primaryBible.set(v)"
                >
                  {{ v }}
                </button>
              }
            </div>
          </section>
        }

        @case (4) {
          <section class="step-card">
            <h1 class="font-display">Personalize Appearance</h1>
            <p class="muted">Choose your theme mode and accent color.</p>

            <div class="chip-grid">
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

            <div class="swatch-row">
              @for (c of colorThemes; track c.id) {
                <button
                  type="button"
                  class="swatch"
                  [style.background-color]="c.color"
                  [class.selected]="theme.colorTheme().id === c.id"
                  [attr.aria-label]="c.name"
                  (click)="theme.setColorTheme(c.id)"
                ></button>
              }
            </div>
          </section>
        }
      }

      <footer class="nav-footer">
        @if (step() > 0) {
          <button type="button" class="pill-chip" (click)="step.set(step() - 1)">
            Back
          </button>
        } @else {
          <button type="button" class="pill-chip" (click)="finish()">
            Skip
          </button>
        }

        @if (step() < 4) {
          <button type="button" class="pill-chip active" (click)="step.set(step() + 1)">
            Continue
          </button>
        } @else {
          <button type="button" class="pill-chip active" [disabled]="saving()" (click)="finish()">
            {{ saving() ? 'Saving...' : 'Get Started' }}
          </button>
        }
      </footer>
    </div>
  `,
  styles: [
    `
      .onboarding-wrap {
        min-height: 100dvh;
        padding-top: 24px;
        padding-bottom: 32px;
        display: flex;
        flex-direction: column;
        gap: 16px;
        max-width: 640px;
      }

      .progress-bar {
        height: 6px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        overflow: hidden;
      }

      .progress-fill {
        height: 100%;
        background-color: var(--accent);
        transition: width 200ms ease;
      }

      .step-label {
        margin: 0;
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .step-card {
        flex: 1;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-lg);
        padding: 24px;
        display: flex;
        flex-direction: column;
        gap: 16px;
      }

      .step-card h1 {
        margin: 0;
        font-size: 22px;
      }

      .muted {
        margin: 0;
        color: var(--on-surface-muted);
      }

      .auth-actions,
      .chip-grid {
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
      }

      .signed-in-pill {
        padding: 10px 14px;
        border-radius: var(--radius-md);
        background-color: var(--accent-soft);
        color: var(--accent);
        font-weight: 600;
      }

      .search-input {
        padding: 10px 12px;
        border-radius: var(--radius-md);
        border: 1px solid var(--surface-border);
        background-color: var(--bg);
      }

      .channel-list {
        max-height: 300px;
        overflow-y: auto;
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .channel-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 10px 12px;
        border-radius: var(--radius-md);
        border: 1px solid var(--surface-border);
        background-color: var(--bg);
      }

      .channel-row.selected {
        border-color: var(--accent);
        background-color: var(--accent-soft);
      }

      .swatch-row {
        display: flex;
        flex-wrap: wrap;
        gap: 12px;
      }

      .swatch {
        width: 36px;
        height: 36px;
        border-radius: var(--radius-pill);
        border: 2px solid transparent;
      }

      .swatch.selected {
        border-color: var(--on-surface);
        transform: scale(1.1);
      }

      .nav-footer {
        display: flex;
        justify-content: space-between;
        align-items: center;
      }
    `,
  ],
})
export class OnboardingComponent implements OnInit {
  private readonly router = inject(Router);
  private readonly api = inject(ApiService);
  private readonly channels = inject(ChannelService);
  private readonly appearance = inject(ReaderAppearanceService);
  readonly auth = inject(AuthService);
  readonly theme = inject(ThemeService);

  readonly step = signal<number>(0);
  readonly saving = signal<boolean>(false);
  readonly selectedLanguages = signal<Set<string>>(new Set(['en']));
  readonly selectedChannelIds = signal<Set<string>>(new Set());
  readonly channelSearch = signal<string>('');
  readonly primaryBible = signal<string>(this.appearance.primaryBibleVersion());

  readonly languages = LANGUAGES;
  readonly bibleVersions = BIBLE_VERSIONS;
  readonly colorThemes = APP_COLOR_THEMES;

  readonly filteredChannels = computed(() => {
    const q = this.channelSearch().trim().toLowerCase();
    const all = this.channels.channels();
    if (!q) return all;
    return all.filter((c) => c.title.toLowerCase().includes(q));
  });

  ngOnInit(): void {
    void this.channels.fetchChannels();
  }

  toggleLanguage(code: string): void {
    const next = new Set(this.selectedLanguages());
    if (next.has(code) && next.size > 1) {
      next.delete(code);
    } else {
      next.add(code);
    }
    this.selectedLanguages.set(next);
  }

  toggleChannel(id: string): void {
    const next = new Set(this.selectedChannelIds());
    if (next.has(id)) {
      next.delete(id);
    } else {
      next.add(id);
    }
    this.selectedChannelIds.set(next);
  }

  async finish(): Promise<void> {
    this.saving.set(true);
    try {
      this.appearance.setPrimaryBibleVersion(this.primaryBible());
      const langs = [...this.selectedLanguages()];
      localStorage.setItem('selected_languages', JSON.stringify(langs));
      localStorage.setItem('onboarding_completed', 'true');

      const chIds = [...this.selectedChannelIds()];
      if (chIds.length > 0) {
        await this.channels.subscribeMany(chIds);
      }

      if (this.auth.isAuthenticated()) {
        await firstValueFrom(
          this.api.put('/api/users/preferences', {
            languages: langs,
            primaryBibleVersion: this.primaryBible(),
            themeMode: this.theme.themeMode(),
            colorTheme: this.theme.colorTheme().id,
            isAmoled: this.theme.isAmoled(),
          }),
        ).catch(() => null);
      }
      await this.router.navigateByUrl('/feed');
    } finally {
      this.saving.set(false);
    }
  }
}
