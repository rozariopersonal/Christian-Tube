import { NgTemplateOutlet } from '@angular/common';
import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  computed,
  inject,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { NavigationEnd, Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { filter } from 'rxjs';
import { AuthService } from '../auth/auth.service';
import { AccountAvatarMenuComponent } from '../auth/account-avatar-menu.component';
import { AppConfig } from '../config/app-config';
import { HeaderSearchService } from '../services/header-search.service';
import { HeaderSlotService } from '../services/header-slot.service';
import { ThemeService } from '../theme/theme.service';
import { MiniPlayerComponent } from '../../features/audio/components/mini-player.component';
import { ChannelService } from '../../features/channels/services/channel.service';
import { VideoMiniPlayerComponent } from '../../features/videos/components/video-mini-player.component';
import { VideoLibraryService } from '../../features/videos/services/video-library.service';
import { ModalSheetComponent } from '../../shared/ui/modal-sheet.component';
import { ScreenClassService } from './screen-class.service';
import { ReaderFullscreenService } from '../services/reader-fullscreen.service';

interface NavDestination {
  label: string;
  route: string;
  icon: string;
}

const PRIMARY_NAV: readonly NavDestination[] = [
  { label: 'Home', route: '/feed', icon: 'home' },
  { label: 'Shorts', route: '/shorts', icon: 'smart_display' },
];

const YOU_NAV: readonly NavDestination[] = [
  { label: 'Subscriptions', route: '/subscriptions', icon: 'subscriptions' },
  { label: 'History', route: '/history', icon: 'history' },
  { label: 'Watch Later', route: '/watch-later', icon: 'watch_later' },
];

const STUDY_NAV: readonly NavDestination[] = [
  { label: 'Words', route: '/words', icon: 'auto_awesome' },
  { label: 'Bible', route: '/bible', icon: 'menu_book' },
  { label: 'Books', route: '/books', icon: 'auto_stories' },
  { label: 'Articles', route: '/articles', icon: 'article' },
  { label: 'Songs', route: '/songs', icon: 'music_note' },
  { label: 'Audio', route: '/audio', icon: 'headphones' },
  { label: 'Channels', route: '/channels', icon: 'video_library' },
  { label: 'Settings', route: '/settings', icon: 'tune' },
];

const COMPACT_BOTTOM_NAV: readonly NavDestination[] = [
  { label: 'Videos', route: '/feed', icon: 'home' },
  { label: 'Shorts', route: '/shorts', icon: 'smart_display' },
  { label: 'Words', route: '/words', icon: 'auto_awesome' },
  { label: 'Bible', route: '/bible', icon: 'menu_book' },
];

const MORE_SHEET_READ: readonly NavDestination[] = [
  { label: 'Library Hub', route: '/library', icon: 'local_library' },
  { label: 'Books', route: '/books', icon: 'auto_stories' },
  { label: 'Articles', route: '/articles', icon: 'article' },
  { label: 'Songs', route: '/songs', icon: 'music_note' },
  { label: 'Audio', route: '/audio', icon: 'headphones' },
];

const MORE_SHEET_LIBRARY: readonly NavDestination[] = [
  { label: 'Channels', route: '/channels', icon: 'video_library' },
  { label: 'Subscriptions', route: '/subscriptions', icon: 'subscriptions' },
  { label: 'History', route: '/history', icon: 'history' },
  { label: 'Watch Later', route: '/watch-later', icon: 'watch_later' },
];

const COMPACT_SUBPAGE_PREFIXES = [
  '/watch/',
  '/books/',
  '/article/',
  '/song/',
  '/audio/series/',
  '/channels/',
];

@Component({
  selector: 'app-main-shell',
  standalone: true,
  imports: [
    NgTemplateOutlet,
    RouterOutlet,
    RouterLink,
    RouterLinkActive,
    FormsModule,
    MiniPlayerComponent,
    VideoMiniPlayerComponent,
    ModalSheetComponent,
    AccountAvatarMenuComponent,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div
      class="shell"
      [class.reader-fullscreen]="readerFullscreen.activeReader() !== null"
      [style.--sidebar-width]="sidebarWidthCss()"
      [style.--shell-top-offset]="screen.showNavigationRail() ? 'var(--topbar-height)' : '0px'"
      [style.--shell-bottom-offset]="showBottomBar() ? 'var(--shell-bottom-height)' : '0px'"
    >
      @if (screen.showNavigationRail()) {
        <header class="yt-topbar">
          <div class="topbar-left">
            <button
              type="button"
              class="icon-btn"
              aria-label="Toggle navigation sidebar"
              (click)="toggleSidebar()"
            >
              <span class="material-symbols-rounded">menu</span>
            </button>
            <a class="top-brand" routerLink="/feed" aria-label="Home">
              <img src="logo.png" alt="ChristianApp" width="28" height="28" />
              @if (screen.isDesktop()) {
                <span class="font-display brand-name">{{ appName }}</span>
              }
            </a>
          </div>

          @if (headerSlot.centerTemplate(); as cTpl) {
            <div class="topbar-slot-center">
              <ng-container *ngTemplateOutlet="cTpl" />
            </div>
          } @else if (showHeaderSearch()) {
            <div class="topbar-center">
            <form class="search-form" (ngSubmit)="submitSearch()">
              <div class="search-input-wrap">
                <span class="material-symbols-rounded search-leading">search</span>
                <input
                  type="search"
                  class="search-input"
                  [placeholder]="headerSearch.pageConfig()?.placeholder || 'Search sermons, channels, scripture...'"
                  aria-label="Search"
                  [ngModel]="headerSearch.pageConfig() ? headerSearch.pageQuery() : searchText()"
                  name="q"
                  (ngModelChange)="onHeaderSearchInput($event)"
                  (focus)="searchFocused.set(true)"
                  (blur)="onSearchBlur()"
                />
                @if (headerSearch.pageConfig() ? headerSearch.pageQuery() : searchText()) {
                  <button
                    type="button"
                    class="clear-btn"
                    aria-label="Clear search"
                    (mousedown)="$event.preventDefault(); clearHeaderSearch()"
                  >
                    <span class="material-symbols-rounded">close</span>
                  </button>
                }
              </div>
              <button
                type="submit"
                class="search-submit-btn"
                aria-label="Search"
                title="Search"
              >
                <span class="material-symbols-rounded">search</span>
              </button>
            </form>

            @if (!headerSearch.pageConfig() && searchFocused() && (matchedChannels().length > 0 || library.recentSearches().length > 0)) {
              <div class="search-dropdown">
                @for (term of filteredRecent(); track term) {
                  <div class="dropdown-row">
                    <button
                      type="button"
                      class="dropdown-main"
                      (mousedown)="$event.preventDefault(); runSearch(term)"
                    >
                      <span class="material-symbols-rounded">history</span>
                      <span>{{ term }}</span>
                    </button>
                    <button
                      type="button"
                      class="dropdown-remove"
                      aria-label="Remove search"
                      (mousedown)="$event.preventDefault(); library.removeRecentSearch(term)"
                    >
                      <span class="material-symbols-rounded">close</span>
                    </button>
                  </div>
                }

                @for (ch of matchedChannels(); track ch.id) {
                  <a
                    class="dropdown-main"
                    [routerLink]="['/channels', ch.id]"
                    (mousedown)="$event.preventDefault(); goToChannel(ch.id)"
                  >
                    @if (ch.avatarUrl) {
                      <img class="dropdown-avatar" [src]="ch.avatarUrl" [alt]="ch.title" />
                    } @else {
                      <span class="material-symbols-rounded">tv</span>
                    }
                    <span>{{ ch.title }}</span>
                    <span class="dropdown-tag">Channel</span>
                  </a>
                }
              </div>
            }
          </div>
          }

          <div class="topbar-right">
            @if (headerSlot.rightTemplate(); as rTpl) {
              <ng-container *ngTemplateOutlet="rTpl" />
              <span class="topbar-divider" aria-hidden="true"></span>
            }
            <button
              type="button"
              class="icon-btn"
              [title]="theme.isDark() ? 'Switch to light mode' : 'Switch to dark mode'"
              [attr.aria-label]="theme.isDark() ? 'Switch to light mode' : 'Switch to dark mode'"
              (click)="theme.setThemeMode(theme.isDark() ? 'light' : 'dark')"
            >
              <span class="material-symbols-rounded">
                {{ theme.isDark() ? 'light_mode' : 'dark_mode' }}
              </span>
            </button>
            <app-account-avatar-menu />
          </div>
        </header>
      }

      <div class="shell-body" [class.has-sidebar]="screen.showNavigationRail()">
        @if (screen.showNavigationRail()) {
          @if (isDrawerMode() && drawerOpen()) {
            <div class="drawer-backdrop" (click)="drawerOpen.set(false)"></div>
          }

          <aside
            class="yt-sidebar"
            [class.expanded]="sidebarExpanded()"
            [class.mini]="!sidebarExpanded() && !(isDrawerMode() && drawerOpen())"
            [class.drawer-open]="isDrawerMode() && drawerOpen()"
            aria-label="Sidebar navigation"
          >
            @if (sidebarExpanded() || (isDrawerMode() && drawerOpen())) {
              <div class="sidebar-scroll">
                <div class="nav-group">
                  @for (dest of primaryNav; track dest.route) {
                    <a
                      class="side-link"
                      [routerLink]="dest.route"
                      routerLinkActive="active"
                      (click)="closeDrawerIfNeeded()"
                    >
                      <span class="material-symbols-rounded">{{ dest.icon }}</span>
                      <span>{{ dest.label }}</span>
                    </a>
                  }
                </div>

                <div class="nav-divider"></div>
                <div class="nav-group">
                  <span class="nav-heading">You</span>
                  @for (dest of youNav; track dest.route) {
                    <a
                      class="side-link"
                      [routerLink]="dest.route"
                      routerLinkActive="active"
                      [routerLinkActiveOptions]="{ exact: dest.route === '/channels' }"
                      (click)="closeDrawerIfNeeded()"
                    >
                      <span class="material-symbols-rounded">{{ dest.icon }}</span>
                      <span>{{ dest.label }}</span>
                    </a>
                  }
                </div>

                @if (auth.isAdmin()) {
                  <div class="nav-divider"></div>
                  <div class="nav-group">
                    <span class="nav-heading">Admin</span>
                    <a
                      class="side-link"
                      routerLink="/admin/users"
                      routerLinkActive="active"
                      (click)="closeDrawerIfNeeded()"
                    >
                      <span class="material-symbols-rounded">admin_panel_settings</span>
                      <span>Manage Users</span>
                    </a>
                    <a
                      class="side-link"
                      routerLink="/channels"
                      routerLinkActive="active"
                      [routerLinkActiveOptions]="{ exact: true }"
                      (click)="closeDrawerIfNeeded()"
                    >
                      <span class="material-symbols-rounded">tune</span>
                      <span>Manage Channels</span>
                    </a>
                  </div>
                }

                <div class="nav-divider"></div>
                <div class="nav-group">
                  <span class="nav-heading">Study &amp; Read</span>
                  @for (dest of studyNav; track dest.route) {
                    <a
                      class="side-link"
                      [routerLink]="dest.route"
                      routerLinkActive="active"
                      (click)="closeDrawerIfNeeded()"
                    >
                      <span class="material-symbols-rounded">{{ dest.icon }}</span>
                      <span>{{ dest.label }}</span>
                    </a>
                  }
                </div>
              </div>
            } @else {
              <div class="mini-rail">
                @for (dest of miniRailNav; track dest.route) {
                  <a
                    class="rail-link"
                    [routerLink]="dest.route"
                    routerLinkActive="active"
                  >
                    <span class="material-symbols-rounded">{{ dest.icon }}</span>
                    <span class="rail-label">{{ dest.label }}</span>
                  </a>
                }
              </div>
            }
          </aside>
        }

        <main class="shell-content" [class.with-bottom-bar]="showBottomBar()">
          <router-outlet />
        </main>
      </div>

      <app-video-mini-player />
      @if (isAudioPage()) {
        <app-mini-player />
      }

      @if (showBottomBar()) {
        <nav class="bottom-nav" aria-label="Primary navigation">
          @for (dest of compactNav; track dest.route) {
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
          <button
            type="button"
            class="bottom-item"
            [class.active]="isMoreRouteActive() || moreSheetOpen()"
            (click)="moreSheetOpen.set(true)"
          >
            <span class="pill-indicator">
              <span class="material-symbols-rounded">apps</span>
            </span>
            <span class="bottom-label">More</span>
          </button>
        </nav>
      }

      @if (moreSheetOpen()) {
        <app-modal-sheet title="More" (closed)="moreSheetOpen.set(false)">
          <div class="more-section">
            <span class="more-heading">Read &amp; Listen</span>
            <div class="more-grid">
              @for (dest of moreRead; track dest.route) {
                <a
                  class="more-tile"
                  [routerLink]="dest.route"
                  routerLinkActive="active"
                  (click)="moreSheetOpen.set(false)"
                >
                  <span class="material-symbols-rounded">{{ dest.icon }}</span>
                  <span>{{ dest.label }}</span>
                </a>
              }
            </div>
          </div>

          <div class="more-section">
            <span class="more-heading">Library</span>
            <div class="more-grid">
              @for (dest of moreLibrary; track dest.route) {
                <a
                  class="more-tile"
                  [routerLink]="dest.route"
                  routerLinkActive="active"
                  (click)="moreSheetOpen.set(false)"
                >
                  <span class="material-symbols-rounded">{{ dest.icon }}</span>
                  <span>{{ dest.label }}</span>
                </a>
              }
            </div>
          </div>

          <div class="more-section">
            <span class="more-heading">App</span>
            <div class="more-grid">
              <a
                class="more-tile"
                routerLink="/settings"
                routerLinkActive="active"
                (click)="moreSheetOpen.set(false)"
              >
                <span class="material-symbols-rounded">tune</span>
                <span>Settings</span>
              </a>
              <button
                type="button"
                class="more-tile"
                (click)="theme.setThemeMode(theme.isDark() ? 'light' : 'dark')"
              >
                <span class="material-symbols-rounded">
                  {{ theme.isDark() ? 'light_mode' : 'dark_mode' }}
                </span>
                <span>{{ theme.isDark() ? 'Light Mode' : 'Dark Mode' }}</span>
              </button>
              @if (auth.isAdmin()) {
                <a
                  class="more-tile"
                  routerLink="/admin/users"
                  routerLinkActive="active"
                  (click)="moreSheetOpen.set(false)"
                >
                  <span class="material-symbols-rounded">admin_panel_settings</span>
                  <span>Admin Users</span>
                </a>
              }
            </div>
          </div>
        </app-modal-sheet>
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

      .yt-topbar {
        position: sticky;
        top: 0;
        z-index: 45;
        height: var(--topbar-height);
        padding: 0 16px;
        background-color: var(--surface);
        border-bottom: 1px solid var(--surface-border);
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 16px;
      }

      .topbar-left {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-shrink: 0;
      }

      .top-brand {
        display: inline-flex;
        align-items: center;
        gap: 8px;
      }

      .brand-name {
        font-size: 17px;
        font-weight: 700;
        letter-spacing: -0.02em;
      }

      @media (max-width: 899px) {
        .brand-name {
          display: none;
        }
      }

      .topbar-center {
        position: relative;
        flex: 1;
        max-width: 580px;
        margin: 0 auto;
      }

      .topbar-slot-center {
        flex: 1;
        min-width: 0;
        overflow: hidden;
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 10px;
      }

      .search-form {
        display: flex;
        align-items: center;
        height: 40px;
      }

      .search-input-wrap {
        flex: 1;
        height: 100%;
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 0 12px;
        background-color: var(--bg);
        border: 1px solid var(--surface-border);
        border-right: none;
        border-radius: var(--radius-pill) 0 0 var(--radius-pill);
      }

      .search-input-wrap:focus-within {
        border-color: var(--accent);
      }

      .search-leading {
        font-size: 18px;
        color: var(--on-surface-muted);
      }

      .search-input {
        flex: 1;
        min-width: 0;
        border: none;
        outline: none;
        background: transparent;
        font-size: 14px;
      }

      .clear-btn {
        width: 24px;
        height: 24px;
        border-radius: var(--radius-pill);
        display: grid;
        place-items: center;
        color: var(--on-surface-muted);
      }

      .clear-btn .material-symbols-rounded {
        font-size: 16px;
      }

      .search-submit-btn {
        height: 100%;
        width: 56px;
        display: grid;
        place-items: center;
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        border-radius: 0 var(--radius-pill) var(--radius-pill) 0;
        color: var(--on-surface);
      }

      .search-submit-btn:hover {
        background-color: var(--surface-elevated);
      }

      .search-dropdown {
        position: absolute;
        top: calc(100% + 6px);
        left: 0;
        right: 0;
        background-color: var(--surface-elevated);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
        padding: 6px;
        box-shadow: 0 10px 28px rgba(0, 0, 0, 0.24);
        z-index: 60;
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .dropdown-row {
        display: flex;
        align-items: center;
      }

      .dropdown-main {
        flex: 1;
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 8px 10px;
        border-radius: var(--radius-sm);
        font-size: 13px;
        text-align: left;
      }

      .dropdown-main:hover {
        background-color: var(--surface-variant);
      }

      .dropdown-main .material-symbols-rounded {
        font-size: 18px;
        color: var(--on-surface-muted);
      }

      .dropdown-remove {
        width: 28px;
        height: 28px;
        display: grid;
        place-items: center;
        color: var(--on-surface-muted);
      }

      .dropdown-remove .material-symbols-rounded {
        font-size: 16px;
      }

      .dropdown-avatar {
        width: 22px;
        height: 22px;
        border-radius: var(--radius-pill);
        object-fit: cover;
      }

      .dropdown-tag {
        margin-left: auto;
        font-size: 11px;
        color: var(--on-surface-muted);
      }

      .topbar-right {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-shrink: 0;
      }

      .topbar-divider {
        width: 1px;
        height: 20px;
        background-color: var(--surface-border);
        margin-inline: 2px;
      }

      .user-avatar {
        width: 28px;
        height: 28px;
        border-radius: var(--radius-pill);
        object-fit: cover;
      }

      .shell-body {
        flex: 1;
        display: flex;
        min-width: 0;
      }

      .yt-sidebar {
        flex-shrink: 0;
        background-color: var(--surface);
        border-right: 1px solid var(--surface-border);
        position: sticky;
        top: var(--topbar-height);
        height: calc(100dvh - var(--topbar-height));
        overflow-y: auto;
        scrollbar-width: thin;
      }

      .yt-sidebar.expanded {
        width: 232px;
      }

      .yt-sidebar.mini {
        width: 72px;
      }

      @media (max-width: 839px) {
        .yt-sidebar.drawer-open {
          position: fixed;
          top: var(--topbar-height);
          left: 0;
          bottom: 0;
          width: 240px;
          height: auto;
          z-index: 55;
          box-shadow: 4px 0 24px rgba(0, 0, 0, 0.28);
        }
      }

      .drawer-backdrop {
        position: fixed;
        inset: var(--topbar-height) 0 0 0;
        background-color: rgba(0, 0, 0, 0.45);
        z-index: 50;
      }

      .sidebar-scroll {
        padding: 10px 8px 24px;
        display: flex;
        flex-direction: column;
        gap: 6px;
      }

      .nav-group {
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .nav-heading {
        padding: 6px 12px 4px;
        font-size: 12px;
        font-weight: 700;
        color: var(--on-surface-muted);
      }

      .nav-divider {
        height: 1px;
        background-color: var(--surface-border);
        margin: 6px 8px;
      }

      .side-link {
        display: flex;
        align-items: center;
        gap: 14px;
        height: 38px;
        padding: 0 12px;
        border-radius: var(--radius-sm);
        font-size: 13px;
        font-weight: 500;
        color: var(--on-surface);
        transition: background-color 140ms ease;
      }

      .side-link:hover {
        background-color: var(--surface-variant);
      }

      .side-link.active {
        background-color: var(--accent-soft);
        color: var(--accent);
        font-weight: 600;
      }

      .side-link .material-symbols-rounded {
        font-size: 20px;
        flex-shrink: 0;
      }

      .side-link.active .material-symbols-rounded {
        font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24;
      }

      .side-avatar {
        width: 22px;
        height: 22px;
        border-radius: var(--radius-pill);
        object-fit: cover;
        flex-shrink: 0;
      }

      .side-avatar.fallback {
        display: grid;
        place-items: center;
        font-size: 11px;
        font-weight: 700;
        background-color: var(--accent-soft);
        color: var(--accent);
      }

      .side-label-trunc {
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .mini-rail {
        padding: 8px 4px;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 4px;
      }

      .rail-link {
        width: 64px;
        padding: 10px 4px;
        border-radius: var(--radius-sm);
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 4px;
        color: var(--on-surface-muted);
      }

      .rail-link:hover {
        background-color: var(--surface-variant);
        color: var(--on-surface);
      }

      .rail-link.active {
        background-color: var(--accent-soft);
        color: var(--accent);
        font-weight: 600;
      }

      .rail-link .material-symbols-rounded {
        font-size: 22px;
      }

      .rail-label {
        font-size: 10px;
        text-align: center;
        line-height: 1.15;
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
        grid-template-columns: repeat(5, minmax(0, 1fr));
        align-items: center;
        z-index: 50;
      }

      .more-section {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .more-heading {
        font-size: 11px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--on-surface-muted);
      }

      .more-grid {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 8px;
      }

      .more-tile {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 6px;
        padding: 12px 8px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        font-size: 12px;
        font-weight: 600;
        text-align: center;
        color: var(--on-surface);
      }

      .more-tile.active {
        background-color: var(--accent-soft);
        border-color: var(--accent);
        color: var(--accent);
      }

      .shell.reader-fullscreen {
        position: fixed;
        inset: 0;
        z-index: 1000;
        height: 100dvh;
        min-height: 100dvh;
        overflow: hidden;
        --shell-top-offset: 0px;
      }

      .shell.reader-fullscreen .yt-topbar,
      .shell.reader-fullscreen .yt-sidebar,
      .shell.reader-fullscreen .drawer-backdrop,
      .shell.reader-fullscreen .bottom-nav,
      .shell.reader-fullscreen app-video-mini-player,
      .shell.reader-fullscreen app-mini-player {
        display: none !important;
      }

      .shell.reader-fullscreen .shell-body {
        flex: 1;
        min-height: 0;
        height: auto;
        overflow: hidden;
      }

      .shell.reader-fullscreen .shell-content {
        min-height: 0;
        height: 100%;
      }

      .shell.reader-fullscreen .shell-content.with-bottom-bar {
        padding-bottom: 0;
      }
    `,
  ],
})
export class MainShellComponent implements OnInit {
  readonly screen = inject(ScreenClassService);
  readonly auth = inject(AuthService);
  readonly channels = inject(ChannelService);
  readonly library = inject(VideoLibraryService);
  readonly headerSearch = inject(HeaderSearchService);
  readonly headerSlot = inject(HeaderSlotService);
  readonly theme = inject(ThemeService);
  readonly readerFullscreen = inject(ReaderFullscreenService);
  private readonly router = inject(Router);

  readonly appName = AppConfig.appName;
  readonly primaryNav = PRIMARY_NAV;
  readonly youNav = YOU_NAV;
  readonly studyNav = STUDY_NAV;
  readonly compactNav = COMPACT_BOTTOM_NAV;
  readonly moreRead = MORE_SHEET_READ;
  readonly moreLibrary = MORE_SHEET_LIBRARY;
  readonly miniRailNav: readonly NavDestination[] = [
    ...PRIMARY_NAV,
    { label: 'Words', route: '/words', icon: 'auto_awesome' },
    { label: 'Bible', route: '/bible', icon: 'menu_book' },
    { label: 'Books', route: '/books', icon: 'auto_stories' },
    { label: 'Articles', route: '/articles', icon: 'article' },
    { label: 'Audio', route: '/audio', icon: 'headphones' },
    { label: 'Channels', route: '/channels', icon: 'video_library' },
    { label: 'Settings', route: '/settings', icon: 'tune' },
  ];

  readonly sidebarExpanded = signal<boolean>(false);
  readonly drawerOpen = signal<boolean>(false);
  readonly moreSheetOpen = signal<boolean>(false);
  readonly isDrawerMode = computed(() => !this.screen.isDesktop());
  readonly currentUrl = signal<string>(this.router.url);

  readonly showBottomBar = computed(() => {
    if (!this.screen.isCompact() || this.screen.isLandscapeCompact()) return false;
    const path = this.currentUrl().split('?')[0];
    return !COMPACT_SUBPAGE_PREFIXES.some((prefix) => path.startsWith(prefix));
  });

  readonly isMoreRouteActive = computed(() => {
    const path = this.currentUrl().split('?')[0];
    return (
      MORE_SHEET_READ.some((d) => path.startsWith(d.route)) ||
      MORE_SHEET_LIBRARY.some((d) => path.startsWith(d.route)) ||
      path.startsWith('/settings') ||
      path.startsWith('/admin/')
    );
  });

  readonly sidebarWidthCss = computed(() => {
    if (!this.screen.showNavigationRail()) return '0px';
    if (this.sidebarExpanded() && !this.isDrawerMode()) return '232px';
    return '72px';
  });

  readonly isAudioPage = computed(() =>
    this.currentUrl().split('?')[0].startsWith('/audio'),
  );

  readonly showHeaderSearch = computed(() => {
    if (this.headerSearch.pageConfig()) return true;
    const url = this.currentUrl().split('?')[0];
    return (
      url === '/' ||
      url.startsWith('/feed') ||
      url.startsWith('/watch/') ||
      url.startsWith('/search') ||
      url.startsWith('/shorts') ||
      url.startsWith('/channels/')
    );
  });

  readonly searchText = signal<string>('');
  readonly searchFocused = signal<boolean>(false);

  readonly filteredRecent = computed(() => {
    const q = this.searchText().trim().toLowerCase();
    const list = this.library.recentSearches();
    return (q ? list.filter((t) => t.toLowerCase().includes(q)) : list).slice(0, 5);
  });

  readonly matchedChannels = computed(() => {
    const q = this.searchText().trim().toLowerCase();
    if (!q) return [];
    return this.channels
      .channels()
      .filter((c) => c.title.toLowerCase().includes(q))
      .slice(0, 4);
  });

  ngOnInit(): void {
    void this.channels.loadSubscriptions();
    void this.channels.fetchChannels();
    this.router.events
      .pipe(filter((ev): ev is NavigationEnd => ev instanceof NavigationEnd))
      .subscribe((ev) => {
        this.currentUrl.set(ev.urlAfterRedirects);
        this.sidebarExpanded.set(false);
        this.drawerOpen.set(false);
      });
  }

  toggleSidebar(): void {
    if (this.isDrawerMode()) {
      this.drawerOpen.update((v) => !v);
    } else {
      this.sidebarExpanded.update((v) => !v);
    }
  }

  closeDrawerIfNeeded(): void {
    this.sidebarExpanded.set(false);
    this.drawerOpen.set(false);
  }

  onHeaderSearchInput(value: string): void {
    if (this.headerSearch.pageConfig()) {
      this.headerSearch.updatePageQuery(value);
    } else {
      this.searchText.set(value);
    }
  }

  clearHeaderSearch(): void {
    if (this.headerSearch.pageConfig()) {
      this.headerSearch.updatePageQuery('');
    } else {
      this.searchText.set('');
    }
  }

  submitSearch(): void {
    if (this.headerSearch.pageConfig()) {
      this.headerSearch.submitPageQuery();
      return;
    }
    this.runSearch(this.searchText());
  }

  runSearch(query: string): void {
    const q = query.trim();
    this.searchFocused.set(false);
    if (!q) {
      void this.router.navigate(['/search']);
      return;
    }
    this.searchText.set(q);
    this.library.addRecentSearch(q);
    void this.router.navigate(['/search'], { queryParams: { q } });
  }

  goToChannel(channelId: string): void {
    this.searchFocused.set(false);
    void this.router.navigate(['/channels', channelId]);
  }

  onSearchBlur(): void {
    setTimeout(() => this.searchFocused.set(false), 120);
  }
}
