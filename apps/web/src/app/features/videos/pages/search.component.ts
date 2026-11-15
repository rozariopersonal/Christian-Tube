import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { ScreenClassService } from '../../../core/layout/screen-class.service';
import { VideoCardComponent } from '../../../shared/ui/video-card.component';
import { ChannelService } from '../../channels/services/channel.service';
import { Video } from '../models/video.model';
import { VideoService } from '../services/video.service';

@Component({
  selector: 'app-search-page',
  standalone: true,
  imports: [FormsModule, RouterLink, VideoCardComponent],
  template: `
    <div class="search-page max-width-box">
      <div class="search-bar">
        <span class="material-symbols-rounded search-icon">search</span>
        <input
          type="search"
          class="search-input"
          placeholder="Search videos & channels..."
          [ngModel]="query()"
          (ngModelChange)="onQueryChange($event)"
        />
      </div>

      @if (loading()) {
        <p class="hint">Searching...</p>
      } @else if (query().trim().length === 0) {
        <p class="hint">Type to search sermons, worship, and channels.</p>
      } @else if (results().length === 0 && matchedChannels().length === 0) {
        <p class="hint">No results for "{{ query() }}".</p>
      } @else {
        @if (matchedChannels().length > 0) {
          <section class="section">
            <h2 class="section-title">Channels</h2>
            <div class="channel-chips">
              @for (ch of matchedChannels(); track ch.id) {
                <a class="channel-pill" [routerLink]="['/channels', ch.id]">
                  @if (ch.avatarUrl) {
                    <img class="pill-avatar" [src]="ch.avatarUrl" [alt]="ch.title" />
                  }
                  <span>{{ ch.title }}</span>
                </a>
              }
            </div>
          </section>
        }

        @if (results().length > 0) {
          <section class="section">
            <h2 class="section-title">Videos</h2>
            <div class="video-grid" [attr.data-cols]="screen.feedColumns()">
              @for (v of results(); track v.id) {
                <app-video-card [video]="v" />
              }
            </div>
          </section>
        }
      }
    </div>
  `,
  styles: [
    `
      .search-page {
        padding-top: 16px;
        padding-bottom: 32px;
      }

      .search-bar {
        display: flex;
        align-items: center;
        gap: 10px;
        height: 46px;
        padding: 0 14px;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-pill);
        margin-bottom: 20px;
      }

      .search-icon {
        color: var(--on-surface-muted);
      }

      .search-input {
        flex: 1;
        border: none;
        outline: none;
        background: transparent;
        font-size: 15px;
      }

      .hint {
        color: var(--on-surface-muted);
        text-align: center;
        padding: 32px 0;
      }

      .section {
        margin-bottom: 24px;
      }

      .section-title {
        margin: 0 0 12px;
        font-size: 15px;
        font-weight: 700;
      }

      .channel-chips {
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
      }

      .channel-pill {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        padding: 6px 12px;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-pill);
        font-size: 13px;
        font-weight: 500;
      }

      .pill-avatar {
        width: 24px;
        height: 24px;
        border-radius: var(--radius-pill);
        object-fit: cover;
      }

      .video-grid {
        display: grid;
        gap: 20px 16px;
        grid-template-columns: 1fr;
      }

      .video-grid[data-cols='2'] {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      .video-grid[data-cols='3'] {
        grid-template-columns: repeat(3, minmax(0, 1fr));
      }
    `,
  ],
})
export class SearchComponent {
  private readonly videoService = inject(VideoService);
  private readonly channelService = inject(ChannelService);
  readonly screen = inject(ScreenClassService);

  readonly query = signal<string>('');
  readonly results = signal<Video[]>([]);
  readonly loading = signal<boolean>(false);

  private debounceTimer?: ReturnType<typeof setTimeout>;

  matchedChannels() {
    const q = this.query().trim().toLowerCase();
    if (!q) return [];
    return this.channelService
      .channels()
      .filter((c) => c.title.toLowerCase().includes(q));
  }

  onQueryChange(val: string): void {
    this.query.set(val);
    if (this.debounceTimer) clearTimeout(this.debounceTimer);
    if (!val.trim()) {
      this.results.set([]);
      return;
    }
    this.debounceTimer = setTimeout(() => {
      void this.runSearch(val);
    }, 300);
  }

  private async runSearch(q: string): Promise<void> {
    this.loading.set(true);
    try {
      this.results.set(await this.videoService.searchVideos(q));
    } finally {
      this.loading.set(false);
    }
  }
}
