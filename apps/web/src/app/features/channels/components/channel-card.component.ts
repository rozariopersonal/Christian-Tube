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
            <span>{{ formatCount(channel().subscriberCount) }} followers · </span>
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
            {{ channel().isSubscribed ? 'Following' : 'Follow' }}
          </button>

          @if (isAdmin()) {
            <div class="admin-actions">
              <button
                type="button"
                class="pill-chip"
                [title]="channel().isActive ? 'Suspend channel' : 'Activate channel'"
                (click)="suspendToggled.emit(channel())"
              >
                {{ channel().isActive ? 'Suspend' : 'Activate' }}
              </button>
              <button
                type="button"
                class="pill-chip danger-chip"
                title="Delete channel"
                (click)="deleteRequested.emit(channel())"
              >
                Delete
              </button>
            </div>
          }
        </div>

        @if (!channel().isActive) {
          <span class="suspended-badge">Suspended</span>
        }
      </div>
    </div>
  `,
  styles: [
    `
      .channel-card {
        position: relative;
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
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        flex-wrap: wrap;
      }

      .admin-actions {
        display: flex;
        align-items: center;
        gap: 6px;
      }

      .danger-chip {
        color: var(--error);
        border-color: color-mix(in srgb, var(--error) 45%, transparent);
      }

      .suspended-badge {
        position: absolute;
        top: 10px;
        right: 10px;
        padding: 2px 8px;
        border-radius: var(--radius-pill);
        background-color: var(--error);
        color: var(--on-error);
        font-size: 11px;
        font-weight: 700;
      }

      @media (max-width: 599px) {
        .channel-card {
          border-radius: var(--radius-md);
        }

        .banner-stack,
        .desc {
          display: none;
        }

        .body {
          padding: 10px 12px;
          flex-direction: row;
          align-items: center;
          justify-content: space-between;
          gap: 10px;
        }

        .title-row {
          margin-top: 0;
          flex: 1;
          min-width: 0;
        }

        .avatar-link {
          width: 44px;
          height: 44px;
        }

        .footer-row {
          margin-top: 0;
          flex-shrink: 0;
        }
      }
    `,
  ],
})
export class ChannelCardComponent {
  readonly channel = input.required<Channel>();
  readonly isAdmin = input<boolean>(false);
  readonly subscribeToggled = output<string>();
  readonly suspendToggled = output<Channel>();
  readonly deleteRequested = output<Channel>();

  formatCount(n: number): string {
    if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
    if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
    return String(n);
  }
}
