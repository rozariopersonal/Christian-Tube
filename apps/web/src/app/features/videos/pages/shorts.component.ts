import {
  ChangeDetectionStrategy,
  Component,
  HostListener,
  OnDestroy,
  OnInit,
  computed,
  effect,
  inject,
  signal,
  untracked,
} from '@angular/core';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { InfiniteScrollTriggerDirective } from '../../../shared/ui/infinite-scroll-trigger.directive';
import { ChannelService } from '../../channels/services/channel.service';
import { Video, formatViewCount } from '../models/video.model';
import { VideoService } from '../services/video.service';

@Component({
  selector: 'app-shorts-page',
  standalone: true,
  imports: [RouterLink, InfiniteScrollTriggerDirective],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (activeShort(); as current) {
      <div
        class="shorts-stage"
        (wheel)="onStageWheel($event)"
        (touchstart)="onTouchStart($event)"
        (touchend)="onTouchEnd($event)"
      >
        <div class="stage-top">
          <button
            type="button"
            class="stage-pill"
            (click)="exitStage()"
          >
            <span class="material-symbols-rounded">grid_view</span>
            Shorts
          </button>
          <span class="stage-counter">
            {{ activeIndex()! + 1 }} / {{ visibleShorts().length }}
          </span>
        </div>

        <div
          class="stage-center"
          [class.transition-exit-next]="transitionPhase() === 'exit' && transitionDirection() === 'next'"
          [class.transition-exit-prev]="transitionPhase() === 'exit' && transitionDirection() === 'prev'"
          [class.transition-enter-next]="transitionPhase() === 'enter' && transitionDirection() === 'next'"
          [class.transition-enter-prev]="transitionPhase() === 'enter' && transitionDirection() === 'prev'"
          (animationend)="onPlayerAnimationEnd($event)"
        >
          <div
            class="vertical-player"
            (wheel)="onPlayerWheel($event)"
            (touchstart)="onPlayerTouchStart($event)"
            (touchend)="onPlayerTouchEnd($event)"
          >
            @if (current.streamUrl) {
              <video
                class="short-media"
                [src]="current.streamUrl"
                controls
                autoplay
                playsinline
                loop
              ></video>
            } @else if (activeEmbedUrl(); as safeUrl) {
              <iframe
                class="short-media"
                [src]="safeUrl"
                [title]="current.title"
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                allowfullscreen
              ></iframe>
              <div
                class="embed-gesture-surface"
                aria-hidden="true"
                (wheel)="onPlayerWheel($event)"
                (touchstart)="onPlayerTouchStart($event)"
                (touchend)="onPlayerTouchEnd($event)"
              >
                <span class="gesture-zone gesture-zone-top"></span>
                <span class="gesture-zone gesture-zone-left"></span>
                <span class="gesture-zone gesture-zone-right"></span>
              </div>
            }

            <div class="bottom-overlay">
              <div class="channel-row">
                <a
                  class="channel-link"
                  [routerLink]="['/channels', current.channelId]"
                >
                  {{ current.channelTitle }}
                </a>
                @if (current.channelId) {
                  <button
                    type="button"
                    class="follow-btn"
                    [class.active]="!isFollowing(current.channelId)"
                    (click)="channelService.toggleSubscribe(current.channelId)"
                  >
                    {{ isFollowing(current.channelId) ? 'Following' : 'Follow' }}
                  </button>
                }
              </div>
              <p class="overlay-title">{{ current.title }}</p>
            </div>
          </div>

          <div class="side-rail">
            <button
              type="button"
              class="rail-btn"
              title="Previous Short"
              [disabled]="activeIndex()! <= 0 || transitionPhase() !== 'idle'"
              (click)="prev()"
            >
              <span class="material-symbols-rounded">keyboard_arrow_up</span>
            </button>
            <button
              type="button"
              class="rail-btn"
              title="Next Short"
              [disabled]="activeIndex()! >= visibleShorts().length - 1 || transitionPhase() !== 'idle'"
              (click)="next()"
            >
              <span class="material-symbols-rounded">keyboard_arrow_down</span>
            </button>
            <button
              type="button"
              class="rail-btn"
              title="Share Short"
              (click)="shareShort(current)"
            >
              <span class="material-symbols-rounded">share</span>
            </button>
            <a
              class="rail-btn"
              title="Watch full video"
              [routerLink]="['/watch', current.id]"
            >
              <span class="material-symbols-rounded">open_in_new</span>
            </a>
          </div>
        </div>
      </div>
    } @else {
      <div class="shorts-page max-width-box">
        <header class="page-head">
          <h1 class="font-display">Shorts</h1>
        </header>

        <div class="shorts-filter-strip" aria-label="Filter shorts by channel">
          <button
            type="button"
            class="pill-chip"
            [class.active]="selectedChannelId() === null"
            (click)="selectShortChannel(null)"
          >
            All
          </button>
          @for (ch of shortChannels(); track ch.id) {
            <button
              type="button"
              class="pill-chip"
              [class.active]="selectedChannelId() === ch.id"
              (click)="selectShortChannel(ch.id)"
            >
              @if (ch.avatarUrl) {
                <img class="chip-avatar" [src]="ch.avatarUrl" [alt]="ch.title" />
              } @else {
                <span class="chip-avatar fallback">
                  {{ ch.title.slice(0, 1).toUpperCase() }}
                </span>
              }
              {{ ch.title }}
            </button>
          }
        </div>

        @if (videos.shortsLoading() && videos.shorts().length === 0) {
          <p class="status-msg">Loading shorts...</p>
        } @else if (videos.shortsError()) {
          <div class="status-msg">
            <p>{{ videos.shortsError() }}</p>
            <button
              type="button"
              class="pill-chip active"
              (click)="videos.fetchShorts(true)"
            >
              Retry
            </button>
          </div>
        } @else if (channelService.subscribedIds().length === 0) {
          <div class="empty-state">
            <span class="material-symbols-rounded empty-icon">subscriptions</span>
            <h2>Follow channels to watch Shorts</h2>
            <p class="muted">Shorts from channels you follow will appear here.</p>
            <a class="pill-chip active" routerLink="/channels">Browse Channels</a>
          </div>
        } @else if (visibleShorts().length === 0) {
          <p class="status-msg">
            @if (selectedChannelId()) {
              No shorts available from this channel right now.
            } @else {
              No shorts available from your followed channels right now.
            }
          </p>
        } @else {
          <div class="shorts-grid">
            @for (s of visibleShorts(); track s.id; let i = $index) {
              <button
                type="button"
                class="short-tile"
                (click)="activeIndex.set(i)"
              >
                <img
                  class="short-thumb"
                  [src]="s.thumbnailUrl"
                  [alt]="s.title"
                  loading="lazy"
                />
                <div class="short-scrim">
                  <span class="short-title">{{ s.title }}</span>
                  <span class="short-meta">
                    {{ s.channelTitle }}
                    @if (s.viewCount > 0) {
                      · {{ formatViews(s.viewCount) }}
                    }
                  </span>
                </div>
              </button>
            }
          </div>

          @if (videos.shortsHasMore()) {
            <div
              class="load-more-wrap"
              appInfiniteScrollTrigger
              [disabled]="videos.shortsLoading()"
              (triggered)="videos.fetchShorts()"
            >
              @if (videos.shortsLoading()) {
                <span class="status-msg">Loading more shorts...</span>
              }
            </div>
          }
        }
      </div>
    }
  `,
  styles: [
    `
      .shorts-page {
        padding-top: 16px;
        padding-bottom: 32px;
      }

      .shorts-filter-strip {
        display: flex;
        align-items: center;
        gap: 8px;
        overflow-x: auto;
        scrollbar-width: none;
        -ms-overflow-style: none;
        padding: 4px 0 12px;
      }

      .shorts-filter-strip::-webkit-scrollbar {
        display: none;
      }

      .shorts-filter-strip .pill-chip {
        flex: 0 0 auto;
      }

      .chip-avatar {
        width: 18px;
        height: 18px;
        border-radius: var(--radius-pill);
        object-fit: cover;
        flex-shrink: 0;
      }

      .chip-avatar.fallback {
        display: grid;
        place-items: center;
        font-size: 10px;
        font-weight: 700;
        background-color: var(--accent-soft);
        color: var(--accent);
      }

      .page-head h1 {
        margin: 0 0 14px;
        font-size: 22px;
        font-weight: 700;
      }

      .shorts-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(165px, 1fr));
        gap: 14px;
      }

      .short-tile {
        position: relative;
        aspect-ratio: 9 / 16;
        border-radius: var(--radius-md);
        overflow: hidden;
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        text-align: left;
      }

      .short-thumb {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }

      .short-scrim {
        position: absolute;
        inset: auto 0 0 0;
        padding: 28px 10px 10px;
        background: linear-gradient(to top, rgba(0, 0, 0, 0.82), transparent);
        color: #ffffff;
        display: flex;
        flex-direction: column;
        gap: 3px;
      }

      .short-title {
        font-size: 13px;
        font-weight: 600;
        line-height: 1.3;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .short-meta {
        font-size: 11px;
        color: rgba(255, 255, 255, 0.78);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      /* In-page Fullscreen Vertical Shorts Stage */
      .shorts-stage {
        height: calc(100dvh - var(--shell-bottom-height) - var(--shell-top-offset));
        background-color: var(--bg);
        color: var(--on-surface);
        display: flex;
        flex-direction: column;
        padding: 12px 16px;
        gap: 10px;
        overflow: hidden;
        touch-action: none;
      }

      @media (min-width: 600px) {
        .shorts-stage {
          height: calc(100dvh - var(--shell-top-offset));
          padding: 16px 24px;
        }
      }

      .stage-top {
        display: flex;
        align-items: center;
        justify-content: space-between;
      }

      .stage-pill {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        height: 34px;
        padding: 0 12px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        color: var(--on-surface);
        font-size: 13px;
        font-weight: 600;
      }

      .stage-pill:hover {
        background-color: var(--surface-elevated);
      }

      .stage-counter {
        font-size: 12px;
        font-weight: 600;
        color: var(--on-surface-muted);
      }

      .stage-center {
        flex: 1;
        min-height: 0;
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 14px;
      }

      .stage-center.transition-exit-next,
      .stage-center.transition-exit-prev,
      .stage-center.transition-enter-next,
      .stage-center.transition-enter-prev {
        will-change: transform, opacity;
      }

      .stage-center.transition-exit-next {
        animation: shorts-exit-next 180ms cubic-bezier(0.4, 0, 1, 1) both;
      }

      .stage-center.transition-exit-prev {
        animation: shorts-exit-prev 180ms cubic-bezier(0.4, 0, 1, 1) both;
      }

      .stage-center.transition-enter-next {
        animation: shorts-enter-next 220ms cubic-bezier(0, 0, 0.2, 1) both;
      }

      .stage-center.transition-enter-prev {
        animation: shorts-enter-prev 220ms cubic-bezier(0, 0, 0.2, 1) both;
      }

      @keyframes shorts-exit-next {
        to {
          transform: translate3d(0, -110%, 0);
          opacity: 0.35;
        }
      }

      @keyframes shorts-exit-prev {
        to {
          transform: translate3d(0, 110%, 0);
          opacity: 0.35;
        }
      }

      @keyframes shorts-enter-next {
        from {
          transform: translate3d(0, 110%, 0);
          opacity: 0.35;
        }
        to {
          transform: translate3d(0, 0, 0);
          opacity: 1;
        }
      }

      @keyframes shorts-enter-prev {
        from {
          transform: translate3d(0, -110%, 0);
          opacity: 0.35;
        }
        to {
          transform: translate3d(0, 0, 0);
          opacity: 1;
        }
      }

      @media (prefers-reduced-motion: reduce) {
        .stage-center.transition-exit-next,
        .stage-center.transition-exit-prev,
        .stage-center.transition-enter-next,
        .stage-center.transition-enter-prev {
          animation-duration: 1ms;
        }
      }

      .vertical-player {
        position: relative;
        height: 100%;
        max-height: 780px;
        aspect-ratio: 9 / 16;
        max-width: calc(100% - 60px);
        background-color: #000000;
        border-radius: var(--radius-lg);
        overflow: hidden;
        box-shadow: 0 12px 32px rgba(0, 0, 0, 0.45);
      }

      .short-media {
        width: 100%;
        height: 100%;
        border: none;
        display: block;
      }

      .embed-gesture-surface {
        position: absolute;
        inset: 0 0 96px;
        z-index: 1;
        pointer-events: none;
      }

      .gesture-zone {
        position: absolute;
        display: block;
        background: transparent;
        pointer-events: auto;
        touch-action: none;
      }

      .gesture-zone-top {
        inset: 0 0 auto;
        height: 16%;
      }

      .gesture-zone-left,
      .gesture-zone-right {
        top: 16%;
        bottom: 0;
        width: 18%;
      }

      .gesture-zone-left {
        left: 0;
      }

      .gesture-zone-right {
        right: 0;
      }

      .bottom-overlay {
        position: absolute;
        left: 0;
        right: 0;
        bottom: 0;
        z-index: 2;
        padding: 36px 14px 14px;
        background: linear-gradient(to top, rgba(0, 0, 0, 0.85), transparent);
        pointer-events: none;
      }

      .channel-row,
      .follow-btn,
      .channel-link {
        pointer-events: auto;
      }

      .channel-row {
        display: flex;
        align-items: center;
        gap: 10px;
        margin-bottom: 6px;
      }

      .channel-link {
        font-size: 13px;
        font-weight: 700;
        color: #ffffff;
      }

      .follow-btn {
        padding: 4px 10px;
        border-radius: var(--radius-pill);
        background-color: rgba(255, 255, 255, 0.2);
        color: #ffffff;
        font-size: 12px;
        font-weight: 600;
      }

      .follow-btn.active {
        background-color: var(--accent);
        color: var(--on-accent);
      }

      .overlay-title {
        margin: 0;
        font-size: 13px;
        line-height: 1.35;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .side-rail {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .rail-btn {
        width: 44px;
        height: 44px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        color: var(--on-surface);
        display: grid;
        place-items: center;
      }

      .rail-btn:hover:not([disabled]) {
        background-color: var(--accent-soft);
        color: var(--accent);
        border-color: var(--accent);
      }

      .rail-btn[disabled] {
        opacity: 0.3;
        cursor: not-allowed;
      }

      .status-msg {
        text-align: center;
        padding: 36px 0;
        color: var(--on-surface-muted);
      }

      .empty-state {
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-lg);
        padding: 36px 24px;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 10px;
        text-align: center;
      }

      .empty-icon {
        font-size: 40px;
        color: var(--on-surface-muted);
      }

      .muted {
        margin: 0;
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class ShortsComponent implements OnInit, OnDestroy {
  private readonly sanitizer = inject(DomSanitizer);
  private readonly route = inject(ActivatedRoute);
  readonly videos = inject(VideoService);
  readonly channelService = inject(ChannelService);

  readonly activeIndex = signal<number | null>(null);
  readonly selectedChannelId = signal<string | null>(null);
  readonly shortChannels = computed(() => {
    const channelsWithLoadedShorts = new Set(
      this.videos.shorts().map((short) => short.channelId),
    );
    return this.channelService
      .subscribedChannels()
      .filter((channel) => channelsWithLoadedShorts.has(channel.id));
  });
  readonly visibleShorts = computed(() => {
    const channelId = this.selectedChannelId();
    const shorts = this.videos.shorts();
    return channelId ? shorts.filter((short) => short.channelId === channelId) : shorts;
  });
  readonly transitionPhase = signal<'idle' | 'exit' | 'enter'>('idle');
  readonly transitionDirection = signal<'next' | 'prev'>('next');
  private readonly requestedShortId = signal<string | null>(
    this.route.snapshot.queryParamMap.get('shortId'),
  );
  private accumulatedWheelDelta = 0;
  private wheelGestureLocked = false;
  private wheelGestureResetTimer: ReturnType<typeof setTimeout> | null = null;
  private touchStartY: number | null = null;
  private lastLoadedSubKey = [...this.channelService.subscribedIds()].sort().join(',');

  constructor() {
    effect(() => {
      const shortId = this.requestedShortId();
      if (!shortId) return;

      const index = this.videos.shorts().findIndex((short) => short.id === shortId);
      if (index >= 0) {
        this.activeIndex.set(index);
        this.requestedShortId.set(null);
      }
    });

    effect(() => {
      const subKey = [...this.channelService.subscribedIds()].sort().join(',');
      if (subKey !== this.lastLoadedSubKey && this.activeIndex() === null) {
        this.lastLoadedSubKey = subKey;
        untracked(() => {
          void this.videos.fetchShorts(true);
        });
      }
    });
  }

  readonly activeShort = computed<Video | null>(() => {
    const idx = this.activeIndex();
    if (idx === null) return null;
    return this.visibleShorts()[idx] ?? null;
  });

  readonly activeEmbedUrl = computed<SafeResourceUrl | null>(() => {
    const v = this.activeShort();
    if (!v || v.streamUrl) return null;
    const id = encodeURIComponent(v.id);
    return this.sanitizer.bypassSecurityTrustResourceUrl(
      `https://www.youtube.com/embed/${id}?autoplay=1&rel=0&playsinline=1&loop=1&playlist=${id}`,
    );
  });

  formatViews = formatViewCount;

  @HostListener('window:keydown', ['$event'])
  onKeyDown(event: KeyboardEvent): void {
    if (this.activeIndex() === null) return;
    if (event.key === 'Escape') {
      this.exitStage();
    } else if (event.key === 'ArrowDown' || event.key === 'ArrowRight') {
      event.preventDefault();
      this.next();
    } else if (event.key === 'ArrowUp' || event.key === 'ArrowLeft') {
      event.preventDefault();
      this.prev();
    }
  }

  onStageWheel(event: WheelEvent): void {
    if (this.activeIndex() === null) return;

    const delta =
      Math.abs(event.deltaX) > Math.abs(event.deltaY)
        ? event.deltaX
        : event.deltaY;
    if (delta === 0) return;

    event.preventDefault();
    this.armWheelGestureReset();

    if (this.wheelGestureLocked) return;
    if (this.transitionPhase() !== 'idle') {
      this.accumulatedWheelDelta = 0;
      this.wheelGestureLocked = true;
      return;
    }

    const normalizedDelta =
      event.deltaMode === WheelEvent.DOM_DELTA_LINE
        ? delta * 40
        : event.deltaMode === WheelEvent.DOM_DELTA_PAGE
          ? delta * window.innerHeight
          : delta;
    this.accumulatedWheelDelta += normalizedDelta;
    if (Math.abs(this.accumulatedWheelDelta) < 48) return;

    const direction = this.accumulatedWheelDelta > 0 ? 'next' : 'prev';
    this.accumulatedWheelDelta = 0;
    this.wheelGestureLocked = true;
    this.navigateShort(direction);
  }

  private armWheelGestureReset(): void {
    if (this.wheelGestureResetTimer !== null) {
      clearTimeout(this.wheelGestureResetTimer);
    }
    this.wheelGestureResetTimer = setTimeout(() => {
      this.wheelGestureLocked = false;
      this.accumulatedWheelDelta = 0;
      this.wheelGestureResetTimer = null;
    }, 500);
  }

  onPlayerWheel(event: WheelEvent): void {
    event.stopPropagation();
    this.onStageWheel(event);
  }

  onTouchStart(event: TouchEvent): void {
    this.touchStartY = event.touches[0]?.clientY ?? null;
  }

  onPlayerTouchStart(event: TouchEvent): void {
    event.stopPropagation();
    this.onTouchStart(event);
  }

  onTouchEnd(event: TouchEvent): void {
    if (this.transitionPhase() !== 'idle') return;
    if (this.touchStartY === null) return;
    const endY = event.changedTouches[0]?.clientY ?? this.touchStartY;
    const dy = endY - this.touchStartY;
    this.touchStartY = null;
    if (Math.abs(dy) < 40) return;
    if (dy < 0) {
      this.next();
    } else {
      this.prev();
    }
  }

  onPlayerTouchEnd(event: TouchEvent): void {
    event.stopPropagation();
    this.onTouchEnd(event);
  }

  ngOnInit(): void {
    void this.videos.fetchShorts();
    void this.channelService.loadSubscriptions();
    void this.channelService.fetchChannels();
  }

  ngOnDestroy(): void {
    if (this.wheelGestureResetTimer !== null) {
      clearTimeout(this.wheelGestureResetTimer);
    }
  }

  exitStage(): void {
    this.activeIndex.set(null);
    const subKey = [...this.channelService.subscribedIds()].sort().join(',');
    if (subKey !== this.lastLoadedSubKey) {
      this.lastLoadedSubKey = subKey;
      void this.videos.fetchShorts(true);
    }
  }

  isFollowing(channelId: string): boolean {
    return this.channelService.subscribedIds().includes(channelId);
  }

  selectShortChannel(channelId: string | null): void {
    const currentShortId = this.activeShort()?.id;
    this.selectedChannelId.set(channelId);

    const filteredShorts = channelId
      ? this.videos.shorts().filter((short) => short.channelId === channelId)
      : this.videos.shorts();

    if (this.activeIndex() !== null) {
      const currentIndex = filteredShorts.findIndex(
        (short) => short.id === currentShortId,
      );
      this.activeIndex.set(
        currentIndex >= 0 ? currentIndex : filteredShorts.length > 0 ? 0 : null,
      );
      this.transitionPhase.set('idle');
    }

    this.accumulatedWheelDelta = 0;
    this.wheelGestureLocked = false;
    if (this.wheelGestureResetTimer !== null) {
      clearTimeout(this.wheelGestureResetTimer);
      this.wheelGestureResetTimer = null;
    }
  }

  prev(): void {
    this.navigateShort('prev');
  }

  next(): void {
    this.navigateShort('next');
  }

  onPlayerAnimationEnd(event: AnimationEvent): void {
    if (event.target !== event.currentTarget) return;

    if (this.transitionPhase() === 'exit') {
      const index = this.activeIndex();
      const targetIndex =
        index === null
          ? null
          : this.transitionDirection() === 'next'
            ? index + 1
            : index - 1;
      if (
        targetIndex !== null &&
        targetIndex >= 0 &&
        targetIndex < this.visibleShorts().length
      ) {
        this.activeIndex.set(targetIndex);
      }
      this.transitionPhase.set('enter');
    } else if (this.transitionPhase() === 'enter') {
      this.transitionPhase.set('idle');
    }
  }

  private navigateShort(direction: 'next' | 'prev'): void {
    const index = this.activeIndex();
    if (index === null || this.transitionPhase() !== 'idle') return;

    const list = this.visibleShorts();
    const targetIndex = direction === 'next' ? index + 1 : index - 1;
    if (targetIndex < 0 || targetIndex >= list.length) return;

    this.transitionDirection.set(direction);
    this.transitionPhase.set('exit');

    if (direction === 'next') {
      if (index + 3 >= list.length && this.videos.shortsHasMore()) {
        void this.videos.fetchShorts();
      }
    }
  }

  shareShort(v: Video): void {
    const url = `${window.location.origin}/watch/${encodeURIComponent(v.id)}`;
    if (navigator.share) {
      void navigator.share({ title: v.title, url }).catch(() => {
        void navigator.clipboard?.writeText(url);
      });
    } else {
      void navigator.clipboard?.writeText(url);
    }
  }
}
