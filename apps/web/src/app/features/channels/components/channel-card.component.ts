import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { RouterLink } from '@angular/router';
import { Channel } from '../models/channel.model';

@Component({
  selector: 'app-channel-card',
  standalone: true,
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="channel-card">
      <a [routerLink]="['/channels', channel().id]" class="banner-stack">
        @if (channel().bannerUrl) {
          <img
            class="banner"
            [src]="channel().bannerUrl"
            [alt]="channel().title"
            loading="lazy"
          />
        } @else {
          <div class="banner fallback"></div>
        }
        <div class="banner-scrim"></div>
        <div class="overlapping-avatar">
          @if (channel().avatarUrl) {
            <img
              class="avatar"
              [src]="channel().avatarUrl"
              [alt]="channel().title"
              loading="lazy"
            />
          } @else {
            <span class="avatar fallback">
              {{ channel().title.slice(0, 1).toUpperCase() }}
            </span>
          }
        </div>
      </a>

      <div class="card-body">
        <a [routerLink]="['/channels', channel().id]" class="title-link">
          <h2 class="ch-title">{{ channel().title }}</h2>
        </a>

        <p class="ch-meta">
          @if (channel().subscriberCount > 0) {
            <span>{{ formatCount(channel().subscriberCount) }} subscribers · </span>
          }
          <span>{{ channel().videoCount }} videos</span>
          @if (channel().language) {
            <span class="lang-tag">{{ channel().language!.toUpperCase() }}</span>
          }
        </p>

        @if (channel().description) {
          <p class="ch-desc">{{ channel().description }}</p>
        }

        <div class="card-footer">
          <button
            type="button"
            class="pill-chip"
            [class.active]="!channel().isSubscribed"
            (click)="subscribeToggled.emit(channel().id)"
          >
            {{ channel().isSubscribed ? 'Subscribed' : 'Subscribe' }}
          </button>
        </div>
      </div>
    </div>
  `,
  styles: [
    `
      .channel-card {
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-lg);
        overflow: hidden;
        display: flex;
        flex-direction: column;
        height: 100%;
      }

      .banner-stack {
        position: relative;
        height: 80px;
        display: block;
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

      .banner-scrim {
        position: absolute;
        inset: 0;
        background: linear-gradient(to bottom, rgba(0, 0, 0, 0), rgba(0, 0, 0, 0.3));
      }

      .overlapping-avatar {
        position: absolute;
        left: 16px;
        bottom: -20px;
        width: 52px;
        height: 52px;
        border-radius: var(--radius-pill);
        border: 3px solid var(--surface);
        background-color: var(--surface);
        overflow: hidden;
      }

      .avatar {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }

      .avatar.fallback {
        display: grid;
        place-items: center;
        font-weight: 700;
        font-size: 18px;
        background-color: var(--accent-soft);
        color: var(--accent);
      }

      .card-body {
        padding: 26px 16px 14px;
        display: flex;
        flex-direction: column;
        gap: 6px;
        flex: 1;
      }

      .ch-title {
        margin: 0;
        font-size: 16px;
        font-weight: 700;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .ch-meta {
        margin: 0;
        font-size: 12px;
        color: var(--on-surface-muted);
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 4px;
      }

      .lang-tag {
        padding: 1px 6px;
        border-radius: 4px;
        background-color: var(--surface-variant);
        font-size: 11px;
        font-weight: 600;
      }

      .ch-desc {
        margin: 4px 0 0;
        font-size: 13px;
        color: var(--on-surface-muted);
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .card-footer {
        margin-top: auto;
        padding-top: 8px;
        display: flex;
        justify-content: flex-end;
      }
    `,
  ],
})
export class ChannelCardComponent {
  readonly channel = input.required<Channel>();
  readonly subscribeToggled = output<string>();

  formatCount(n: number): string {
    if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
    if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
    return String(n);
  }
}
