import { Component, inject } from '@angular/core';
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
  { label: 'Bible', route: '/bible', icon: 'menu_book' },
  { label: 'Books', route: '/books', icon: 'auto_stories' },
  { label: 'Audio', route: '/audio', icon: 'headphones' },
  { label: 'Settings', route: '/settings', icon: 'tune' },
];

@Component({
  selector: 'app-main-shell',
  standalone: true,
  imports: [RouterOutlet, RouterLink, RouterLinkActive, MiniPlayerComponent],
  template: `
    <div class="shell" [class.has-rail]="screen.isMediumOrExpanded()">
      @if (screen.isMediumOrExpanded()) {
        <nav class="nav-rail" aria-label="Primary navigation">
          <a class="rail-brand" routerLink="/feed" aria-label="Home">
            <img src="logo.png" alt="ChristianApp" width="28" height="28" />
          </a>
          <div class="rail-items">
            @for (dest of destinations; track dest.route) {
              <a
                class="rail-item"
                [routerLink]="dest.route"
                routerLinkActive="active"
              >
                <span class="pill-indicator">
                  <span class="material-symbols-rounded">{{ dest.icon }}</span>
                </span>
                <span class="rail-label">{{ dest.label }}</span>
              </a>
            }
          </div>
        </nav>
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

      .shell.has-rail {
        flex-direction: row;
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

      .nav-rail {
        position: sticky;
        top: 0;
        height: 100dvh;
        width: var(--shell-rail-width);
        flex-shrink: 0;
        background-color: var(--surface);
        border-right: 1px solid var(--surface-border);
        display: flex;
        flex-direction: column;
        align-items: center;
        padding: 14px 8px;
        gap: 16px;
        z-index: 40;
      }

      .rail-brand {
        width: 44px;
        height: 44px;
        border-radius: var(--radius-md);
        display: grid;
        place-items: center;
      }

      .rail-items {
        display: flex;
        flex-direction: column;
        gap: 8px;
        width: 100%;
      }

      .rail-item,
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
        width: 56px;
        height: 32px;
        border-radius: var(--radius-pill);
        display: grid;
        place-items: center;
        transition: background-color 150ms ease, color 150ms ease;
      }

      .rail-item.active,
      .bottom-item.active {
        color: var(--on-surface);
        font-weight: 600;
      }

      .rail-item.active .pill-indicator,
      .bottom-item.active .pill-indicator {
        background-color: var(--accent-soft);
        color: var(--accent);
      }

      .rail-item.active .material-symbols-rounded,
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
        grid-template-columns: repeat(5, 1fr);
        align-items: center;
        z-index: 50;
      }
    `,
  ],
})
export class MainShellComponent {
  readonly screen = inject(ScreenClassService);
  readonly destinations = DESTINATIONS;
}
