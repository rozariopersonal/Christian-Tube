import {
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  OnInit,
  ViewChild,
  effect,
  inject,
  signal,
  untracked,
} from '@angular/core';
import { Router } from '@angular/router';
import { AuthService } from '../../../core/auth/auth.service';
import {
  ContentPreferencesService,
  resolveDefaultWebRoute,
} from '../../../core/services/content-preferences.service';
import { ReaderAppearanceService } from '../../../core/services/reader-appearance.service';
import { UserSyncService } from '../../../core/services/user-sync.service';
import {
  SUPPORTED_LANGUAGES,
  canonicalLanguageCode,
} from '../../../shared/ui/language-meta';
import { getVersionsForLanguages } from '../../bible/models/bible.model';
import { Channel } from '../../channels/models/channel.model';
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

const POPULAR_CHANNEL_LIMIT = 4;

@Component({
  selector: 'app-onboarding',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="onboarding-wrap max-width-box">
      <main class="quickstart-card">
        <header class="welcome-head">
          <img src="logo.png" alt="ChristianApp" width="56" height="56" class="brand-logo" />
          <div>
            <h1 class="font-display">Welcome to ChristianApp</h1>
            <p class="muted">
              Choose your preferred languages to personalize videos, Bible reading, books, and audio sermons.
            </p>
          </div>
        </header>

        <section class="section-block" aria-labelledby="account-heading">
          <div class="section-head">
            <h2 id="account-heading">Sync Across Devices (Optional)</h2>
            <p class="muted">
              Sign in with Google to restore your saved setup or keep your library synced across devices.
            </p>
          </div>

          @if (auth.isAuthenticated()) {
            <div class="signed-in-pill">
              <span class="material-symbols-rounded" aria-hidden="true">verified_user</span>
              <span>Signed in as {{ auth.currentUser()!.displayName }}</span>
            </div>
          } @else {
            <div class="auth-actions">
              <div #gsiHost class="gsi-host"></div>
              @if (!gsiRendered()) {
                <button
                  type="button"
                  class="pill-chip"
                  (click)="auth.promptGoogleSignIn()"
                >
                  Sign in with Google
                </button>
              }
            </div>
          }
        </section>

        <section class="section-block" aria-labelledby="languages-heading">
          <div class="section-head">
            <h2 id="languages-heading">Choose Your Languages</h2>
            <p class="muted">
              We’ll automatically select a matching Bible version and popular channels for you.
            </p>
          </div>

          <div class="chip-grid" role="group" aria-label="Preferred languages">
            @for (lang of languages; track lang.code) {
              <button
                type="button"
                class="pill-chip"
                [class.active]="selectedLanguages().has(lang.code)"
                [attr.aria-pressed]="selectedLanguages().has(lang.code)"
                (click)="toggleLanguage(lang.code)"
              >
                {{ lang.name }}
              </button>
            }
          </div>
        </section>

        <footer class="cta-footer">
          <button
            type="button"
            class="start-btn"
            [disabled]="saving()"
            (click)="startExploring()"
          >
            {{ saving() ? 'Setting up...' : 'Start Exploring' }}
          </button>
        </footer>
      </main>
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
        justify-content: center;
        max-width: 640px;
      }

      .quickstart-card {
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-lg);
        padding: 24px;
        display: flex;
        flex-direction: column;
        gap: 24px;
      }

      .welcome-head {
        display: flex;
        flex-direction: column;
        align-items: flex-start;
        gap: 12px;
      }

      .brand-logo {
        border-radius: 12px;
      }

      .welcome-head h1 {
        margin: 0 0 6px;
        font-size: 24px;
        line-height: 1.25;
      }

      .section-block {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }

      .section-head h2 {
        margin: 0 0 4px;
        font-size: 16px;
        font-weight: 700;
      }

      .muted {
        margin: 0;
        font-size: 14px;
        color: var(--on-surface-muted);
        line-height: 1.45;
      }

      .auth-actions {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 10px;
      }

      .gsi-host {
        min-height: 0;
      }

      .signed-in-pill {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        align-self: flex-start;
        padding: 10px 14px;
        border-radius: var(--radius-md);
        background-color: var(--accent-soft);
        color: var(--accent);
        font-weight: 600;
        font-size: 14px;
      }

      .chip-grid {
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
      }

      .cta-footer {
        display: flex;
        justify-content: stretch;
        padding-top: 4px;
      }

      .start-btn {
        width: 100%;
        min-height: 46px;
        padding: 12px 20px;
        border-radius: var(--radius-pill);
        background-color: var(--accent);
        color: var(--bg);
        font-size: 15px;
        font-weight: 700;
        text-align: center;
        cursor: pointer;
        transition: opacity 150ms ease;
      }

      .start-btn:disabled {
        opacity: 0.65;
        cursor: wait;
      }
    `,
  ],
})
export class OnboardingComponent implements OnInit {
  private readonly router = inject(Router);
  private readonly preferences = inject(ContentPreferencesService);
  private readonly userSync = inject(UserSyncService);
  private readonly channels = inject(ChannelService);
  private readonly appearance = inject(ReaderAppearanceService);
  readonly auth = inject(AuthService);

  readonly saving = signal<boolean>(false);
  readonly gsiRendered = signal<boolean>(false);
  readonly selectedLanguages = signal(
    new Set(this.preferences.preferredLanguages()),
  );
  readonly languages = LANGUAGES;

  private languageSelectionEdited = false;
  private wasSignedOutOnEntry = !this.auth.isAuthenticated();
  private autoNavigated = false;

  @ViewChild('gsiHost')
  set gsiHost(ref: ElementRef<HTMLElement> | undefined) {
    if (ref && !this.auth.isAuthenticated()) {
      this.tryRenderGsiButton(ref.nativeElement);
    }
  }

  constructor() {
    effect(() => {
      const authed = this.auth.isAuthenticated();
      const remote = this.userSync.remoteState();
      if (!authed) {
        this.wasSignedOutOnEntry = true;
        return;
      }

      untracked(() => {
        if (
          !this.languageSelectionEdited &&
          remote?.preferences?.languages &&
          remote.preferences.languages.length > 0
        ) {
          this.selectedLanguages.set(new Set(remote.preferences.languages));
        }

        if (
          this.wasSignedOutOnEntry &&
          !this.autoNavigated &&
          remote?.preferences?.hasCompletedOnboarding
        ) {
          this.autoNavigated = true;
          this.markCompletedLocally();
          const targetRoute = resolveDefaultWebRoute(
            remote.preferences.defaultPage ?? this.preferences.defaultPage(),
          );
          void this.router.navigateByUrl(`/${targetRoute}`);
        }
      });
    });
  }

  ngOnInit(): void {
    void this.channels.fetchChannels();
    if (this.auth.isAuthenticated() && this.auth.canSync()) {
      void this.channels.loadSubscriptions();
    }
  }

  toggleLanguage(code: string): void {
    this.languageSelectionEdited = true;
    const next = new Set(this.selectedLanguages());
    if (next.has(code) && next.size > 1) {
      next.delete(code);
    } else {
      next.add(code);
    }
    this.selectedLanguages.set(next);
  }

  async startExploring(): Promise<void> {
    if (this.saving()) return;
    this.saving.set(true);
    try {
      const selectedLangs = [...this.selectedLanguages()];
      this.preferences.setLanguages(selectedLangs);

      const { preferred } = getVersionsForLanguages(selectedLangs);
      if (preferred.length > 0) {
        this.appearance.setPrimaryBibleVersion(preferred[0].id.toUpperCase());
      }

      await this.autoFollowPopularChannels(selectedLangs);

      if (this.auth.isAuthenticated()) {
        this.userSync.enqueuePreference('hasCompletedOnboarding', true);
      }
      this.markCompletedLocally();
      await this.router.navigateByUrl(`/${this.preferences.defaultRoute()}`);
    } finally {
      this.saving.set(false);
    }
  }

  private async autoFollowPopularChannels(
    selectedLangs: readonly string[],
  ): Promise<void> {
    if (this.channels.subscribedIds().length > 0) {
      return;
    }
    if (this.channels.channels().length === 0) {
      await this.channels.fetchChannels();
    }
    const activeChannels = this.channels
      .channels()
      .filter((c) => c.isActive);
    if (activeChannels.length === 0) {
      return;
    }

    const langSet = new Set(
      selectedLangs.map((code) => canonicalLanguageCode(code).toLowerCase()),
    );
    const matching = activeChannels.filter(
      (c) =>
        c.language &&
        langSet.has(canonicalLanguageCode(c.language).toLowerCase()),
    );
    const pool = matching.length > 0 ? matching : activeChannels;
    const popularIds = this.pickTopChannelIds(pool, POPULAR_CHANNEL_LIMIT);
    if (popularIds.length > 0) {
      await this.channels.subscribeMany(popularIds);
    }
  }

  private pickTopChannelIds(
    channels: readonly Channel[],
    limit: number,
  ): string[] {
    return [...channels]
      .sort(
        (a, b) =>
          b.subscriberCount - a.subscriberCount ||
          b.videoCount - a.videoCount,
      )
      .slice(0, limit)
      .map((c) => c.id);
  }

  private markCompletedLocally(): void {
    try {
      localStorage.setItem('onboarding_completed', 'true');
    } catch {
      // ignore storage errors
    }
  }

  private tryRenderGsiButton(host: HTMLElement): void {
    const ok = this.auth.initGoogleSignIn();
    if (!ok) {
      this.gsiRendered.set(false);
      return;
    }
    this.auth.renderGoogleButton(host);
    this.gsiRendered.set(host.childElementCount > 0);
  }
}
