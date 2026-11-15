import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { ChannelService } from '../services/channel.service';

@Component({
  selector: 'app-channels-page',
  standalone: true,
  imports: [FormsModule, RouterLink],
  template: `
    <div class="channels-page max-width-box">
      <header class="header-row">
        <h1 class="font-display">Channels</h1>
        <button
          type="button"
          class="pill-chip active"
          (click)="showRequestModal.set(true)"
        >
          <span class="material-symbols-rounded btn-icon">playlist_add</span>
          Request Channel
        </button>
      </header>

      <div class="tab-bar">
        <button
          type="button"
          class="tab-btn"
          [class.active]="activeTab() === 'browse'"
          (click)="activeTab.set('browse')"
        >
          Browse Channels
        </button>
        <button
          type="button"
          class="tab-btn"
          [class.active]="activeTab() === 'requests'"
          (click)="activeTab.set('requests')"
        >
          Requests ({{ channelService.channelRequests().length }})
        </button>
      </div>

      @if (activeTab() === 'browse') {
        <div class="search-box">
          <span class="material-symbols-rounded">search</span>
          <input
            type="search"
            placeholder="Filter channels..."
            [ngModel]="search()"
            (ngModelChange)="search.set($event)"
          />
        </div>

        <div class="channels-grid">
          @for (ch of filteredChannels(); track ch.id) {
            <div class="channel-card">
              <a [routerLink]="['/channels', ch.id]" class="card-banner-wrap">
                @if (ch.bannerUrl) {
                  <img class="banner" [src]="ch.bannerUrl" [alt]="ch.title" loading="lazy" />
                } @else {
                  <div class="banner fallback"></div>
                }
              </a>

              <div class="card-body">
                <a [routerLink]="['/channels', ch.id]" class="avatar-row">
                  @if (ch.avatarUrl) {
                    <img class="avatar" [src]="ch.avatarUrl" [alt]="ch.title" loading="lazy" />
                  } @else {
                    <span class="avatar fallback">{{ ch.title.slice(0, 1).toUpperCase() }}</span>
                  }
                  <div class="ch-info">
                    <h2 class="ch-title">{{ ch.title }}</h2>
                    <p class="ch-meta">
                      {{ ch.videoCount }} videos
                      @if (ch.language) {
                        · {{ ch.language.toUpperCase() }}
                      }
                    </p>
                  </div>
                </a>

                @if (ch.description) {
                  <p class="ch-desc">{{ ch.description }}</p>
                }

                <div class="card-footer">
                  <button
                    type="button"
                    class="pill-chip"
                    [class.active]="!ch.isSubscribed"
                    (click)="channelService.toggleSubscribe(ch.id)"
                  >
                    {{ ch.isSubscribed ? 'Subscribed' : 'Subscribe' }}
                  </button>
                </div>
              </div>
            </div>
          }
        </div>
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
                <span class="status-badge">{{ req.status }}</span>
              </div>
            }
          }
        </div>
      }

      @if (showRequestModal()) {
        <div class="modal-backdrop" (click)="showRequestModal.set(false)">
          <div class="modal-panel req-modal" (click)="$event.stopPropagation()">
            <h2 class="font-display">Request a Channel</h2>
            <label class="field">
              <span>Channel Name</span>
              <input type="text" [(ngModel)]="reqName" placeholder="e.g. Grace Fellowship" />
            </label>
            <label class="field">
              <span>YouTube Channel URL</span>
              <input type="url" [(ngModel)]="reqUrl" placeholder="https://youtube.com/@..." />
            </label>
            <label class="field">
              <span>Reason (optional)</span>
              <textarea rows="3" [(ngModel)]="reqReason"></textarea>
            </label>
            <div class="modal-actions">
              <button type="button" class="pill-chip" (click)="showRequestModal.set(false)">
                Cancel
              </button>
              <button type="button" class="pill-chip active" (click)="submitRequest()">
                Submit
              </button>
            </div>
          </div>
        </div>
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

      .search-box {
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 0 12px;
        height: 42px;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
        margin-bottom: 16px;
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

      .channel-card {
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
        overflow: hidden;
        display: flex;
        flex-direction: column;
      }

      .card-banner-wrap {
        display: block;
        height: 84px;
        background-color: var(--surface-variant);
      }

      .banner {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }

      .banner.fallback {
        background: linear-gradient(135deg, var(--accent-soft), var(--surface-variant));
      }

      .card-body {
        padding: 14px;
        display: flex;
        flex-direction: column;
        gap: 10px;
        flex: 1;
      }

      .avatar-row {
        display: flex;
        align-items: center;
        gap: 10px;
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

      .ch-info {
        min-width: 0;
      }

      .ch-title {
        margin: 0;
        font-size: 15px;
        font-weight: 700;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .ch-meta {
        margin: 2px 0 0;
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .ch-desc {
        margin: 0;
        font-size: 13px;
        color: var(--on-surface-muted);
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .card-footer {
        margin-top: auto;
        display: flex;
        justify-content: flex-end;
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

      .req-modal {
        padding: 20px;
        gap: 12px;
      }

      .req-modal h2 {
        margin: 0;
        font-size: 18px;
      }

      .field {
        display: flex;
        flex-direction: column;
        gap: 6px;
        font-size: 13px;
        font-weight: 500;
      }

      .field input,
      .field textarea {
        padding: 10px 12px;
        border-radius: var(--radius-sm);
        border: 1px solid var(--surface-border);
        background-color: var(--bg);
      }

      .modal-actions {
        display: flex;
        justify-content: flex-end;
        gap: 8px;
        margin-top: 8px;
      }
    `,
  ],
})
export class ChannelsComponent implements OnInit {
  readonly channelService = inject(ChannelService);

  readonly activeTab = signal<'browse' | 'requests'>('browse');
  readonly search = signal<string>('');
  readonly showRequestModal = signal<boolean>(false);

  reqName = '';
  reqUrl = '';
  reqReason = '';

  readonly filteredChannels = computed(() => {
    const q = this.search().trim().toLowerCase();
    const list = this.channelService.channels();
    if (!q) return list;
    return list.filter(
      (c) =>
        c.title.toLowerCase().includes(q) ||
        (c.description?.toLowerCase().includes(q) ?? false),
    );
  });

  ngOnInit(): void {
    void this.channelService.loadSubscriptions();
    void this.channelService.fetchChannels();
    void this.channelService.fetchRequests();
  }

  async submitRequest(): Promise<void> {
    if (!this.reqName.trim() || !this.reqUrl.trim()) return;
    await this.channelService.submitRequest(
      this.reqName.trim(),
      this.reqUrl.trim(),
      this.reqReason.trim() || undefined,
    );
    this.reqName = '';
    this.reqUrl = '';
    this.reqReason = '';
    this.showRequestModal.set(false);
    this.activeTab.set('requests');
  }
}
