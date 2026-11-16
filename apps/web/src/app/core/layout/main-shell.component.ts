import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { MiniPlayerComponent } from '../../features/audio/components/mini-player.component';
import { ScreenClassService } from './screen-class.service';

interface NavDestination {
  label: string;
  route: string;
  icon: string;
}

const DESTINATIONS: readonly NavDestination[] = [
  { label: 'Videos', route: '/feed', icon: 'home' },
  { label: 'Shorts', route: '/shorts', icon: 'smart_display' },
  { label: 'Words', route: '/words', icon: 'auto_awesome' },
  { label: 'Bible', route: '/bible', icon: 'menu_book' },
  { label: 'Books', route: '/books', icon: 'auto_stories' },
  { label: 'Articles', route: '/articles', icon: 'article' },
  { label: 'Audio', route: '/audio', icon: 'headphones' },
  { label: 'Settings', route: '/settings', icon: 'tune' },
];

@Component({
  selector: 'app-main-shell',
  standalone: true,
  imports: [RouterOutlet, RouterLink, RouterLinkActive, MiniPlayerComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="shell">
      @if (screen.isMediumOrExpanded()) {
        <header class="top-nav">
          <div class="top-nav-inner max-width-box">
            <a class="top-brand" routerLink="/feed" aria-label="Home">
              <img src="logo.png" alt="ChristianApp" width="28" height="28" />
              <span class="font-display brand-name">ChristianApp</span>
            </a>

            <nav class="top-items" aria-label="Primary navigation">
              @for (dest of destinations; track dest.route) {
                <a
                  class="top-item"
                  [routerLink]="dest.route"
                  routerLinkActive="active"
                >
                  <span class="material-symbols-rounded">{{ dest.icon }}</span>
                  <span class="top-label">{{ dest.label }}</span>
                </a>
              }
            </nav>
          </div>
        </header>
      }

      <main class="shell-content" [class.with-bottom-bar]="screen.isCompact()">
        <router-outlet />
      </main>

      <app-mini-player />

      @if (screen.isCompact()) {
        <nav class="bottom-nav" aria-label="Primary navigation">
          @for (dest of destinations; track dest.route) {
            <a
              class="bottom-item"
              [routerLink]="dest.route"
              routerLinkActive="active"
            >
              <span class="pill-indicator">
                <span class="material-symbols-rounded">{{ dest.icon }}</span>
              </span>
              <span class="bottom-label">{{ dest.label }}</span>
            </a>
          }
        </nav>
      }
    </div>
  `,
  styles: [
    `
      .shell {
        min-height: 100dvh;
        display: flex;
        flex-direction: column;
        background-color: var(--bg);
      }

      .shell-content {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
      }

      .shell-content.with-bottom-bar {
        padding-bottom: calc(var(--shell-bottom-height) + env(safe-area-inset-bottom, 0px));
      }

      .top-nav {
        position: sticky;
        top: 0;
        z-index: 45;
        height: var(--topbar-height);
        background-color: var(--surface);
        border-bottom: 1px solid var(--surface-border);
      }

      .top-nav-inner {
        height: 100%;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 16px;
      }

      .top-brand {
        display: inline-flex;
        align-items: center;
        gap: 10px;
        flex-shrink: 0;
      }

      .brand-name {
        font-size: 16px;
        font-weight: 700;
        letter-spacing: -0.01em;
      }

      .top-items {
        display: flex;
        align-items: center;
        justify-content: flex-end;
        gap: 2px;
        margin-left: auto;
        overflow-x: auto;
        scrollbar-width: none;
        min-width: 0;
      }

      .top-items::-webkit-scrollbar {
        display: none;
      }

      .top-item {
        display: inline-flex;
        align-items: center;
        gap: 5px;
        height: 34px;
        padding: 0 10px;
        border-radius: var(--radius-pill);
        color: var(--on-surface-muted);
        font-size: 13px;
        font-weight: 500;
        white-space: nowrap;
        flex-shrink: 0;
        transition: background-color 150ms ease, color 150ms ease;
      }

      .top-item:hover {
        background-color: var(--surface-variant);
        color: var(--on-surface);
      }

      .top-item.active {
        background-color: var(--accent-soft);
        color: var(--accent);
        font-weight: 600;
      }

      .top-item .material-symbols-rounded {
        font-size: 20px;
      }

      .bottom-item {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 4px;
        color: var(--on-surface-muted);
        font-size: 11px;
        font-weight: 500;
        padding: 4px 0;
        transition: color 150ms ease;
      }

      .pill-indicator {
        width: 44px;
        height: 30px;
        border-radius: var(--radius-pill);
        display: grid;
        place-items: center;
        transition: background-color 150ms ease, color 150ms ease;
      }

      .bottom-item.active {
        color: var(--on-surface);
        font-weight: 600;
      }

      .bottom-item.active .pill-indicator {
        background-color: var(--accent-soft);
        color: var(--accent);
      }

      .top-item.active .material-symbols-rounded,
      .bottom-item.active .material-symbols-rounded {
        font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24;
      }

      .bottom-nav {
        position: fixed;
        left: 0;
        right: 0;
        bottom: 0;
        height: calc(var(--shell-bottom-height) + env(safe-area-inset-bottom, 0px));
        padding-bottom: env(safe-area-inset-bottom, 0px);
        background-color: var(--surface);
        border-top: 1px solid var(--surface-border);
        display: grid;
        grid-auto-flow: column;
        grid-auto-columns: minmax(64px, 1fr);
        overflow-x: auto;
        scrollbar-width: none;
        align-items: center;
        z-index: 50;
      }

      .bottom-nav::-webkit-scrollbar {
        display: none;
      }
    `,
  ],
})
export class MainShellComponent {
  readonly screen = inject(ScreenClassService);
  readonly destinations = DESTINATIONS;
}
