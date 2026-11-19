import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  OnInit,
  computed,
  effect,
  inject,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../../core/auth/auth.service';
import { ScreenClassService } from '../../../core/layout/screen-class.service';
import { ContentPreferencesService } from '../../../core/services/content-preferences.service';
import { HeaderSearchService } from '../../../core/services/header-search.service';
import { LanguageDropdownComponent } from '../../../shared/ui/language-dropdown.component';
import { canonicalLanguageCode } from '../../../shared/ui/language-meta';
import { ChannelCardComponent } from '../components/channel-card.component';
import {
  ChannelRequestModalComponent,
  ChannelRequestPayload,
} from '../components/channel-request-modal.component';
import { Channel } from '../models/channel.model';
import { ChannelService } from '../services/channel.service';

@Component({
  selector: 'app-channels-page',
  standalone: true,
  imports: [
    FormsModule,
    LanguageDropdownComponent,
    ChannelCardComponent,
    ChannelRequestModalComponent,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="channels-page max-width-box">
      <header class="header-row">
        <h1 class="font-display">
          {{ auth.isAdmin() ? 'Channel Administration' : 'Channels' }}
        </h1>
        <button
          type="button"
          class="pill-chip active"
          (click)="showRequestModal.set(true)"
        >
          <span class="material-symbols-rounded btn-icon">playlist_add</span>
          Request Channel
        </button>
      </header>

      @if (auth.isAdmin()) {
        <div class="tab-bar">
          <button
            type="button"
            class="tab-btn"
            [class.active]="activeTab() === 'browse'"
            (click)="activeTab.set('browse')"
          >
            Channels
            <span class="tab-badge">{{ channelService.channels().length }}</span>
          </button>
          <button
            type="button"
            class="tab-btn"
            [class.active]="activeTab() === 'requests'"
            (click)="activeTab.set('requests')"
          >
            Requests
            @if (pendingCount() > 0) {
              <span class="tab-badge accent">{{ pendingCount() }}</span>
            }
          </button>
        </div>
      }

      @if (!auth.isAdmin() || activeTab() === 'browse') {
        <div class="controls">
          @if (screen.isCompact()) {
            <div class="search-box">
              <span class="material-symbols-rounded">search</span>
              <input
                type="search"
                placeholder="Search channels..."
                [ngModel]="search()"
                (ngModelChange)="search.set($event)"
              />
            </div>
          }

          <app-language-dropdown
            [selectedLanguages]="selectedLanguages()"
            [availableLanguages]="languages()"
            [itemCounts]="languageCounts()"
            itemNoun="channels"
            headerTitle="Channel Languages"
            (languagesChange)="selectedLanguages.set($event)"
          />
        </div>

        @if (auth.isAdmin()) {
          <div class="status-filter-row">
            @for (st of ['all', 'active', 'suspended']; track st) {
              <button
                type="button"
                class="pill-chip"
                [class.active]="statusFilter() === st"
                (click)="statusFilter.set($any(st))"
              >
                {{ st[0].toUpperCase() + st.slice(1) }}
              </button>
            }
          </div>
        }

        @if (channelService.isLoading() && channelService.channels().length === 0) {
          <p class="empty-msg">Loading channels...</p>
        } @else if (filteredChannels().length === 0) {
          <div class="empty-card">
            <span class="material-symbols-rounded empty-icon">tv_off</span>
            <h2>No channels found</h2>
            <p class="muted">Try adjusting your search or language filter.</p>
          </div>
        } @else {
          <div class="channels-grid">
            @for (ch of filteredChannels(); track ch.id) {
              <app-channel-card
                [channel]="ch"
                [isAdmin]="auth.isAdmin()"
                (subscribeToggled)="channelService.toggleSubscribe($event)"
                (suspendToggled)="channelService.toggleChannelActive($event)"
                (deleteRequested)="channelToDelete.set($event)"
              />
            }
          </div>
        }
      } @else {
        <div class="requests-list">
          @if (channelService.channelRequests().length === 0) {
            <p class="empty-msg">No channel requests yet.</p>
          } @else {
            @for (req of channelService.channelRequests(); track req.id) {
              <div class="request-row">
                <div>
                  <strong>{{ req.channelName }}</strong>
                  <p class="req-url">{{ req.channelUrl }}</p>
                </div>
                <div class="req-actions">
                  <span class="status-badge">{{ req.status }}</span>
                  @if (req.status === 'PENDING') {
                    <button
                      type="button"
                      class="pill-chip active"
                      (click)="channelService.approveRequest(req.id)"
                    >
                      Approve
                    </button>
                    <button
                      type="button"
                      class="pill-chip"
                      (click)="channelService.rejectRequest(req.id)"
                    >
                      Reject
                    </button>
                  }
                </div>
              </div>
            }
          }
        </div>
      }

      @if (channelToDelete(); as target) {
        <div class="confirm-backdrop" (click)="channelToDelete.set(null)">
          <div class="confirm-modal" (click)="$event.stopPropagation()">
            <h3>Delete Channel?</h3>
            <p>
              Are you sure you want to permanently delete
              <strong>{{ target.title }}</strong> and all of its videos?
            </p>
            <div class="confirm-actions">
              <button type="button" class="pill-chip" (click)="channelToDelete.set(null)">
                Cancel
              </button>
              <button type="button" class="pill-chip danger-btn" (click)="confirmDelete()">
                Delete
              </button>
            </div>
          </div>
        </div>
      }

      @if (showRequestModal()) {
        <app-channel-request-modal
          (submitted)="submitRequest($event)"
          (closed)="showRequestModal.set(false)"
        />
      }
    </div>
  `,
  styles: [
    `
      .channels-page {
        padding-top: 16px;
        padding-bottom: 32px;
      }

      .header-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        flex-wrap: wrap;
        margin-bottom: 12px;
      }

      .header-row h1 {
        margin: 0;
        font-size: 22px;
        font-weight: 700;
      }

      .btn-icon {
        font-size: 18px;
      }

      .tab-bar {
        display: flex;
        gap: 8px;
        border-bottom: 1px solid var(--surface-border);
        margin-bottom: 16px;
      }

      .tab-btn {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        padding: 10px 14px;
        font-size: 14px;
        font-weight: 600;
        color: var(--on-surface-muted);
        border-bottom: 2px solid transparent;
      }

      .tab-btn.active {
        color: var(--accent);
        border-bottom-color: var(--accent);
      }

      .tab-badge {
        padding: 1px 7px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        font-size: 11px;
        font-weight: 700;
      }

      .tab-badge.accent {
        background-color: var(--accent);
        color: var(--on-accent);
      }

      .controls {
        display: flex;
        gap: 10px;
        flex-wrap: wrap;
        margin-bottom: 16px;
      }

      .search-box {
        flex: 1;
        min-width: 200px;
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 0 12px;
        height: 42px;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
      }

      .search-box input {
        flex: 1;
        border: none;
        outline: none;
        background: transparent;
      }

      .channels-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
        gap: 16px;
      }

      .empty-card {
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-lg);
        padding: 36px 24px;
        text-align: center;
      }

      .empty-icon {
        font-size: 48px;
        color: var(--on-surface-disabled);
      }

      .muted {
        color: var(--on-surface-muted);
      }

      .requests-list {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .request-row {
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
        padding: 12px 14px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
      }

      .req-url {
        margin: 4px 0 0;
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .status-badge {
        padding: 4px 10px;
        border-radius: var(--radius-pill);
        font-size: 12px;
        font-weight: 600;
        background-color: var(--surface-variant);
      }

      .empty-msg {
        text-align: center;
        color: var(--on-surface-muted);
        padding: 32px 0;
      }

      .status-filter-row {
        display: flex;
        gap: 8px;
        margin-bottom: 14px;
      }

      .req-actions {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-wrap: wrap;
      }

      .confirm-backdrop {
        position: fixed;
        inset: 0;
        background: rgba(0, 0, 0, 0.55);
        display: grid;
        place-items: center;
        padding: 16px;
        z-index: 80;
      }

      .confirm-modal {
        width: 100%;
        max-width: 400px;
        background: var(--surface-elevated);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-lg);
        padding: 18px;
        display: flex;
        flex-direction: column;
        gap: 12px;
      }

      .confirm-modal h3 {
        margin: 0;
        font-size: 17px;
      }

      .confirm-modal p {
        margin: 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .confirm-actions {
        display: flex;
        justify-content: flex-end;
        gap: 8px;
      }

      .danger-btn {
        background-color: var(--error);
        border-color: var(--error);
        color: var(--on-error);
      }
    `,
  ],
})
export class ChannelsComponent implements OnInit {
  readonly channelService = inject(ChannelService);
  readonly auth = inject(AuthService);
  readonly screen = inject(ScreenClassService);
  private readonly prefs = inject(ContentPreferencesService);
  private readonly headerSearch = inject(HeaderSearchService);
  private readonly destroyRef = inject(DestroyRef);

  readonly activeTab = signal<'browse' | 'requests'>('browse');
  readonly search = signal<string>('');
  readonly selectedLanguages = signal<string[]>(this.prefs.preferredLanguages());
  readonly statusFilter = signal<'all' | 'active' | 'suspended'>('all');
  readonly showRequestModal = signal<boolean>(false);
  readonly channelToDelete = signal<Channel | null>(null);

  constructor() {
    effect(() => {
      this.selectedLanguages.set(this.prefs.preferredLanguages());
    });
  }

  readonly pendingCount = computed(
    () =>
      this.channelService
        .channelRequests()
        .filter((r) => r.status === 'PENDING').length,
  );

  readonly languageCounts = computed(() => {
    const counts: Record<string, number> = {
      All: this.channelService.channels().length,
    };
    for (const c of this.channelService.channels()) {
      const code = canonicalLanguageCode(c.language);
      counts[code] = (counts[code] ?? 0) + 1;
    }
    return counts;
  });

  readonly languages = computed(() => {
    const counts = this.languageCounts();
    return Object.keys(counts)
      .filter((k) => k !== 'All')
      .sort((a, b) => (counts[b] ?? 0) - (counts[a] ?? 0));
  });

  readonly filteredChannels = computed(() => {
    const q = this.search().trim().toLowerCase();
    const selLangs = this.selectedLanguages();
    const allLangs = selLangs.length === 0 || selLangs.includes('All');
    const langSet = new Set(selLangs.map((l) => l.toLowerCase()));
    const st = this.statusFilter();
    return this.channelService.channels().filter((c) => {
      if (this.auth.isAdmin()) {
        if (st === 'active' && !c.isActive) return false;
        if (st === 'suspended' && c.isActive) return false;
      }
      if (
        !allLangs &&
        !langSet.has(canonicalLanguageCode(c.language).toLowerCase())
      ) {
        return false;
      }
      if (
        q &&
        !c.title.toLowerCase().includes(q) &&
        !(c.description?.toLowerCase().includes(q) ?? false)
      ) {
        return false;
      }
      return true;
    });
  });

  ngOnInit(): void {
    void this.channelService.loadSubscriptions();
    if (this.auth.isAdmin()) {
      void this.channelService.fetchAdminChannels();
    } else {
      void this.channelService.fetchChannels();
    }
    void this.channelService.fetchRequests();
    const unregister = this.headerSearch.register({
      placeholder: 'Search channels...',
      onChange: (q) => this.search.set(q),
    });
    this.destroyRef.onDestroy(unregister);
  }

  async confirmDelete(): Promise<void> {
    const target = this.channelToDelete();
    if (!target) return;
    await this.channelService.removeChannel(target.id);
    this.channelToDelete.set(null);
  }

  async submitRequest(payload: ChannelRequestPayload): Promise<void> {
    await this.channelService.submitRequest(
      payload.name,
      payload.url,
      payload.reason,
    );
    this.showRequestModal.set(false);
    if (this.auth.isAdmin()) {
      this.activeTab.set('requests');
    }
  }
}
