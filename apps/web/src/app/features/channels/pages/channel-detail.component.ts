import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { firstValueFrom } from 'rxjs';
import { ApiService } from '../../../core/api/api.service';
import { ScreenClassService } from '../../../core/layout/screen-class.service';
import { VideoCardComponent } from '../../../shared/ui/video-card.component';
import { Video, normalizeVideo } from '../../videos/models/video.model';
import { Channel } from '../models/channel.model';
import { ChannelService } from '../services/channel.service';

@Component({
  selector: 'app-channel-detail',
  standalone: true,
  imports: [VideoCardComponent],
  template: `
    <div class="channel-detail max-width-box">
      @if (loading()) {
        <p class="status-msg">Loading channel...</p>
      } @else if (!channel()) {
        <p class="status-msg">Channel not found.</p>
      } @else {
        @if (channel()!.bannerUrl) {
          <img class="banner" [src]="channel()!.bannerUrl" [alt]="channel()!.title" />
        }

        <div class="header">
          <div class="header-left">
            @if (channel()!.avatarUrl) {
              <img class="avatar" [src]="channel()!.avatarUrl" [alt]="channel()!.title" />
            } @else {
              <span class="avatar fallback">{{ channel()!.title.slice(0, 1).toUpperCase() }}</span>
            }
            <div>
              <h1 class="font-display">{{ channel()!.title }}</h1>
              <p class="sub">{{ channel()!.videoCount }} videos</p>
            </div>
          </div>

          <button
            type="button"
            class="pill-chip"
            [class.active]="!isSubscribed()"
            (click)="channelService.toggleSubscribe(channel()!.id)"
          >
            {{ isSubscribed() ? 'Subscribed' : 'Subscribe' }}
          </button>
        </div>

        <div class="tab-bar">
          @for (tab of ['videos', 'shorts', 'streams', 'about']; track tab) {
            <button
              type="button"
              class="tab-btn"
              [class.active]="activeTab() === tab"
              (click)="activeTab.set($any(tab))"
            >
              {{ tab[0].toUpperCase() + tab.slice(1) }}
            </button>
          }
        </div>

        @if (activeTab() === 'about') {
          <div class="about-card">
            <p>{{ channel()!.description || 'No description provided.' }}</p>
          </div>
        } @else {
          <div class="video-grid" [attr.data-cols]="screen.feedColumns()">
            @for (v of tabVideos(); track v.id) {
              <app-video-card [video]="v" />
            }
          </div>
          @if (tabVideos().length === 0) {
            <p class="status-msg">No {{ activeTab() }} in this channel yet.</p>
          }
        }
      }
    </div>
  `,
  styles: [
    `
      .channel-detail {
        padding-top: 16px;
        padding-bottom: 32px;
      }

      .banner {
        width: 100%;
        height: 160px;
        object-fit: cover;
        border-radius: var(--radius-md);
        margin-bottom: 16px;
      }

      .header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        flex-wrap: wrap;
        margin-bottom: 16px;
      }

      .header-left {
        display: flex;
        align-items: center;
        gap: 14px;
      }

      .avatar {
        width: 64px;
        height: 64px;
        border-radius: var(--radius-pill);
        object-fit: cover;
      }

      .avatar.fallback {
        display: grid;
        place-items: center;
        font-size: 24px;
        font-weight: 700;
        background-color: var(--accent-soft);
        color: var(--accent);
      }

      .header h1 {
        margin: 0;
        font-size: 22px;
      }

      .sub {
        margin: 4px 0 0;
        color: var(--on-surface-muted);
        font-size: 13px;
      }

      .tab-bar {
        display: flex;
        gap: 8px;
        border-bottom: 1px solid var(--surface-border);
        margin-bottom: 18px;
        overflow-x: auto;
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

      .about-card {
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
        padding: 16px;
        white-space: pre-wrap;
      }

      .status-msg {
        text-align: center;
        color: var(--on-surface-muted);
        padding: 32px 0;
      }
    `,
  ],
})
export class ChannelDetailComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly api = inject(ApiService);
  readonly channelService = inject(ChannelService);
  readonly screen = inject(ScreenClassService);

  readonly channel = signal<Channel | null>(null);
  readonly videos = signal<Video[]>([]);
  readonly loading = signal<boolean>(true);
  readonly activeTab = signal<'videos' | 'shorts' | 'streams' | 'about'>('videos');

  readonly isSubscribed = computed(() => {
    const id = this.channel()?.id;
    return id ? this.channelService.subscribedIds().includes(id) : false;
  });

  readonly tabVideos = computed(() => {
    const all = this.videos();
    switch (this.activeTab()) {
      case 'shorts':
        return all.filter((v) => v.type === 'SHORT');
      case 'streams':
        return all.filter(
          (v) => v.type === 'VIDEO' && (v.duration ?? '').split(':').length === 3,
        );
      default:
        return all.filter((v) => v.type !== 'SHORT');
    }
  });

  ngOnInit(): void {
    this.route.paramMap.subscribe((params) => {
      const id = params.get('id');
      if (id) void this.load(id);
    });
  }

  private async load(channelId: string): Promise<void> {
    this.loading.set(true);
    const [ch, vidsRes] = await Promise.all([
      this.channelService.fetchChannelDetails(channelId),
      firstValueFrom(
        this.api.get<unknown>('/api/videos', { channelId, limit: 100 }),
      ).catch(() => []),
    ]);
    this.channel.set(ch);
    const list = Array.isArray(vidsRes)
      ? vidsRes
      : ((vidsRes as Record<string, unknown>)?.['videos'] as unknown[]) ?? [];
    this.videos.set(
      list.map((v) => normalizeVideo(v as Record<string, unknown>)),
    );
    this.loading.set(false);
  }
}
