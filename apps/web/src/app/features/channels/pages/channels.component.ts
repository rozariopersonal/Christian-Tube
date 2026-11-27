import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  computed,
  effect,
  inject,
  signal,
  untracked,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../../core/auth/auth.service';
import { ContentPreferencesService } from '../../../core/services/content-preferences.service';
import { LanguageDropdownComponent } from '../../../shared/ui/language-dropdown.component';
import { canonicalLanguageCode } from '../../../shared/ui/language-meta';
import { ChannelCardComponent } from '../components/channel-card.component';
import {
  ChannelModalCompletedEvent,
  ChannelRequestModalComponent,
} from '../components/channel-request-modal.component';
import { Channel, ChannelRequest } from '../models/channel.model';
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
  host: {
    '(document:keydown.escape)': 'onEscapeKey()',
  },
  template: `
    <div class="channels-page max-width-box">
      <header class="header-row">
        <h1 class="font-display">
          {{ auth.isAdmin() ? 'Channel Administration' : 'Channels' }}
        </h1>
        <div class="header-actions">
          @if (auth.isAdmin()) {
            <button
              type="button"
              class="pill-chip active"
              (click)="openModal('add')"
            >
              <span class="material-symbols-rounded btn-icon">add_circle</span>
              Add Channel
            </button>
          } @else {
            <button
              type="button"
              class="pill-chip active"
              (click)="openModal('request')"
            >
              <span class="material-symbols-rounded btn-icon">playlist_add</span>
              Request Channel
            </button>
          }
        </div>
      </header>

      @if (feedbackBanner(); as banner) {
        <div
          class="feedback-banner"
          [class.error]="banner.isError"
          role="status"
        >
          <span>{{ banner.message }}</span>
          <button
            type="button"
            class="banner-close"
            aria-label="Dismiss"
            (click)="feedbackBanner.set(null)"
          >
            <span class="material-symbols-rounded">close</span>
          </button>
        </div>
      }

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
          <div class="search-box">
            <span class="material-symbols-rounded">search</span>
            <input
              type="search"
              placeholder="Search channels..."
              aria-label="Search channels"
              [ngModel]="search()"
              (ngModelChange)="search.set($event)"
            />
            @if (search()) {
              <button
                type="button"
                class="clear-search-btn"
                aria-label="Clear channel search"
                (click)="search.set('')"
              >
                <span class="material-symbols-rounded">close</span>
              </button>
            }
          </div>

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
            @if (search().trim().length >= 2) {
              <button
                type="button"
                class="pill-chip active empty-cta"
                (click)="openModal(auth.isAdmin() ? 'add' : 'request', search().trim())"
              >
                <span class="material-symbols-rounded btn-icon">
                  {{ auth.isAdmin() ? 'add_circle' : 'playlist_add' }}
                </span>
                {{
                  auth.isAdmin()
                    ? 'Search "' + search().trim() + '" on YouTube to Add'
                    : 'Request "' + search().trim() + '" on YouTube'
                }}
              </button>
            }
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
          @if (
            channelService.isLoadingRequests() &&
            channelService.channelRequests().length === 0
          ) {
            <p class="empty-msg">Loading channel requests...</p>
          } @else if (channelService.channelRequests().length === 0) {
            <p class="empty-msg">No channel requests yet.</p>
          } @else {
            @for (req of channelService.channelRequests(); track req.id) {
              <div class="request-row">
                <div class="req-details">
                  <strong>{{ req.channelName }}</strong>
                  <p class="req-url">{{ req.channelUrl }}</p>
                  @if (req.notes && req.notes !== req.channelName) {
                    <p class="req-notes">{{ req.notes }}</p>
                  }
                  <p class="req-meta">Requested by: {{ req.submittedBy }}</p>
                </div>
                <div class="req-actions">
                  <span
                    class="status-badge"
                    [class.approved]="req.status === 'APPROVED'"
                    [class.rejected]="req.status === 'REJECTED'"
                  >
                    {{ req.status }}
                  </span>
                  @if (req.status === 'PENDING') {
                    <button
                      type="button"
                      class="pill-chip active"
                      [disabled]="isRequestBusy(req.id)"
                      (click)="approveRequest(req)"
                    >
                      {{ isRequestBusy(req.id) ? 'Working...' : 'Approve' }}
                    </button>
                    <button
                      type="button"
                      class="pill-chip"
                      [disabled]="isRequestBusy(req.id)"
                      (click)="openRejectModal(req)"
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

      @if (requestToReject(); as req) {
        <div
          class="confirm-backdrop"
          (click)="!isRequestBusy(req.id) && requestToReject.set(null)"
        >
          <form
            class="confirm-modal"
            (click)="$event.stopPropagation()"
            (ngSubmit)="confirmReject()"
          >
            <h3>Reject Channel Request</h3>
            <p>
              Reject <strong>{{ req.channelName }}</strong>?
            </p>
            <input
              type="text"
              name="rejectReason"
              class="reject-input"
              placeholder="Reason for rejection (optional)"
              [ngModel]="rejectReason()"
              (ngModelChange)="rejectReason.set($event)"
              [disabled]="isRequestBusy(req.id)"
            />
            <div class="confirm-actions">
              <button
                type="button"
                class="pill-chip"
                [disabled]="isRequestBusy(req.id)"
                (click)="requestToReject.set(null)"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="pill-chip danger-btn"
                [disabled]="isRequestBusy(req.id)"
              >
                {{ isRequestBusy(req.id) ? 'Rejecting...' : 'Reject' }}
              </button>
            </div>
          </form>
        </div>
      }

      @if (modalMode(); as mode) {
        <app-channel-request-modal
          [mode]="mode"
          [initialQuery]="modalInitialQuery()"
          (completed)="onModalCompleted($event)"
          (closed)="modalMode.set(null)"
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

      .header-actions {
        display: flex;
        gap: 8px;
        align-items: center;
      }

      .btn-icon {
        font-size: 18px;
      }

      .feedback-banner {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
        padding: 10px 14px;
        margin-bottom: 14px;
        border-radius: var(--radius-md);
        background-color: color-mix(in srgb, var(--accent) 14%, transparent);
        border: 1px solid color-mix(in srgb, var(--accent) 35%, transparent);
        font-size: 13px;
        font-weight: 500;
      }

      .feedback-banner.error {
        background-color: color-mix(in srgb, var(--error) 14%, transparent);
        border-color: color-mix(in srgb, var(--error) 35%, transparent);
        color: var(--error);
      }

      .banner-close {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        border: none;
        background: transparent;
        color: inherit;
        cursor: pointer;
        padding: 2px;
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
        min-width: 220px;
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
        min-width: 0;
        border: none;
        outline: none;
        background: transparent;
      }

      .clear-search-btn {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        border: none;
        background: transparent;
        color: var(--on-surface-muted);
        cursor: pointer;
        padding: 2px;
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

      .empty-cta {
        margin-top: 12px;
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
        flex-wrap: wrap;
      }

      .req-details {
        flex: 1;
        min-width: 200px;
      }

      .req-url,
      .req-notes,
      .req-meta {
        margin: 4px 0 0;
        font-size: 12px;
        color: var(--on-surface-muted);
        overflow-wrap: anywhere;
      }

      .status-badge {
        padding: 4px 10px;
        border-radius: var(--radius-pill);
        font-size: 12px;
        font-weight: 600;
        background-color: var(--surface-variant);
      }

      .status-badge.approved {
        color: var(--accent);
      }

      .status-badge.rejected {
        color: var(--error);
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

      .reject-input {
        padding: 10px 12px;
        border-radius: var(--radius-sm);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
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
  private readonly prefs = inject(ContentPreferencesService);

  readonly activeTab = signal<'browse' | 'requests'>('browse');
  readonly search = signal<string>('');
  readonly selectedLanguages = signal<string[]>(this.prefs.preferredLanguages());
  readonly statusFilter = signal<'all' | 'active' | 'suspended'>('all');
  readonly modalMode = signal<'request' | 'add' | null>(null);
  readonly modalInitialQuery = signal<string>('');
  readonly channelToDelete = signal<Channel | null>(null);
  readonly requestToReject = signal<ChannelRequest | null>(null);
  readonly rejectReason = signal<string>('');
  readonly busyRequestIds = signal<ReadonlySet<string>>(new Set());
  readonly feedbackBanner = signal<{ message: string; isError: boolean } | null>(
    null,
  );

  constructor() {
    effect(() => {
      this.selectedLanguages.set(this.prefs.preferredLanguages());
    });

    effect(() => {
      const isAdmin = this.auth.isAdmin();
      untracked(() => {
        if (isAdmin) {
          void this.channelService.fetchAdminChannels();
          void this.channelService.fetchRequests();
        } else {
          this.activeTab.set('browse');
          void this.channelService.fetchChannels();
        }
      });
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
  }

  openModal(mode: 'request' | 'add', initialQuery = ''): void {
    this.feedbackBanner.set(null);
    this.modalInitialQuery.set(initialQuery);
    this.modalMode.set(mode);
  }

  onEscapeKey(): void {
    const req = this.requestToReject();
    if (req) {
      if (!this.isRequestBusy(req.id)) {
        this.requestToReject.set(null);
      }
    } else if (this.channelToDelete()) {
      this.channelToDelete.set(null);
    }
  }

  onModalCompleted(ev: ChannelModalCompletedEvent): void {
    this.modalMode.set(null);
    this.feedbackBanner.set({
      message:
        ev.mode === 'add'
          ? `Added "${ev.channelName}" and started video ingestion.`
          : `Request submitted for "${ev.channelName}".`,
      isError: false,
    });
  }

  isRequestBusy(id: string): boolean {
    return this.busyRequestIds().has(id);
  }

  async approveRequest(req: ChannelRequest): Promise<void> {
    if (this.isRequestBusy(req.id)) return;
    this.setRequestBusy(req.id, true);
    try {
      const res = await this.channelService.approveRequest(req.id);
      this.feedbackBanner.set({
        message: res.ok
          ? `Approved "${req.channelName}" and started video ingestion.`
          : res.error || 'Failed to approve request.',
        isError: !res.ok,
      });
    } finally {
      this.setRequestBusy(req.id, false);
    }
  }

  openRejectModal(req: ChannelRequest): void {
    this.rejectReason.set('');
    this.requestToReject.set(req);
  }

  async confirmReject(): Promise<void> {
    const req = this.requestToReject();
    if (!req || this.isRequestBusy(req.id)) return;
    this.setRequestBusy(req.id, true);
    try {
      const res = await this.channelService.rejectRequest(
        req.id,
        this.rejectReason(),
      );
      this.requestToReject.set(null);
      this.feedbackBanner.set({
        message: res.ok
          ? `Rejected request for "${req.channelName}".`
          : res.error || 'Failed to reject request.',
        isError: !res.ok,
      });
    } finally {
      this.setRequestBusy(req.id, false);
    }
  }

  async confirmDelete(): Promise<void> {
    const target = this.channelToDelete();
    if (!target) return;
    await this.channelService.removeChannel(target.id);
    this.channelToDelete.set(null);
  }

  private setRequestBusy(id: string, busy: boolean): void {
    this.busyRequestIds.update((prev) => {
      const next = new Set(prev);
      if (busy) next.add(id);
      else next.delete(id);
      return next;
    });
  }
}
