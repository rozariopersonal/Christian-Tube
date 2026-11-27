import {
  ChangeDetectionStrategy,
  Component,
  computed,
  inject,
  signal,
} from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { map } from 'rxjs';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { ToastService } from '../../../shared/ui/toast.service';
import { Video } from '../models/video.model';
import { PlaylistService } from '../services/playlist.service';

@Component({
  selector: 'app-playlist-detail-page',
  standalone: true,
  imports: [RouterLink, FormsModule, ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="playlist-detail max-width-box">
      @if (!playlist()) {
        <div class="state-card">
          <span class="material-symbols-rounded state-icon">playlist_remove</span>
          <h2>Playlist not found</h2>
          <p class="muted">This playlist may have been deleted or has not synced yet.</p>
          <a class="pill-chip active" routerLink="/playlists">Back to Playlists</a>
        </div>
      } @else {
        @let pl = playlist()!;
        <header class="detail-head">
          <div class="cover-box">
            @if (pl.thumbnailUrl) {
              <img class="cover-img" [src]="pl.thumbnailUrl" [alt]="pl.title" />
            } @else {
              <div class="cover-placeholder">
                <span class="material-symbols-rounded">playlist_play</span>
              </div>
            }
          </div>

          <div class="head-meta">
            <h1 class="font-display">{{ pl.title }}</h1>
            @if (pl.description) {
              <p class="desc">{{ pl.description }}</p>
            }
            <p class="sub">
              {{ pl.videoCount }} {{ pl.videoCount === 1 ? 'video' : 'videos' }}
            </p>

            <div class="head-actions">
              <button
                type="button"
                class="pill-chip active"
                [disabled]="pl.videos.length === 0"
                (click)="playAll()"
              >
                <span class="material-symbols-rounded btn-icon">play_arrow</span>
                Play All
              </button>
              <button type="button" class="pill-chip" (click)="openEdit()">
                <span class="material-symbols-rounded btn-icon">edit</span>
                Edit
              </button>
              <button
                type="button"
                class="pill-chip danger-outline"
                (click)="deleteConfirmOpen.set(true)"
              >
                <span class="material-symbols-rounded btn-icon">delete</span>
                Delete
              </button>
            </div>
          </div>
        </header>

        @if (pl.videos.length === 0) {
          <div class="state-card">
            <span class="material-symbols-rounded state-icon">video_library</span>
            <h2>No videos in this playlist</h2>
            <p class="muted">Use "Save to playlist" on any video to add it here.</p>
            <a class="pill-chip active" routerLink="/feed">Browse Videos</a>
          </div>
        } @else {
          <div class="track-list">
            @for (video of pl.videos; track video.id; let idx = $index) {
              <div class="track-row">
                <span class="track-index">{{ idx + 1 }}</span>

                <a
                  class="track-main"
                  [routerLink]="['/watch', video.id]"
                  [queryParams]="{ playlist: pl.id }"
                >
                  <div class="thumb-wrap">
                    <img
                      class="track-thumb"
                      [src]="video.thumbnailUrl"
                      [alt]="video.title"
                      loading="lazy"
                    />
                    @if (video.duration && video.duration !== '0:00') {
                      <span class="dur-badge">{{ video.duration }}</span>
                    }
                  </div>
                  <div class="track-meta">
                    <span class="track-title">{{ video.title }}</span>
                    <span class="track-channel">{{ video.channelTitle }}</span>
                  </div>
                </a>

                <div class="track-controls">
                  <button
                    type="button"
                    class="icon-btn small-btn"
                    aria-label="Move up"
                    title="Move up"
                    [disabled]="idx === 0"
                    (click)="move(idx, idx - 1)"
                  >
                    <span class="material-symbols-rounded">arrow_upward</span>
                  </button>
                  <button
                    type="button"
                    class="icon-btn small-btn"
                    aria-label="Move down"
                    title="Move down"
                    [disabled]="idx === pl.videos.length - 1"
                    (click)="move(idx, idx + 1)"
                  >
                    <span class="material-symbols-rounded">arrow_downward</span>
                  </button>
                  <button
                    type="button"
                    class="icon-btn small-btn danger-btn"
                    aria-label="Remove from playlist"
                    title="Remove from playlist"
                    (click)="removeVideo(video)"
                  >
                    <span class="material-symbols-rounded">close</span>
                  </button>
                </div>
              </div>
            }
          </div>
        }

        @if (editOpen()) {
          <app-modal-sheet title="Edit Playlist" (closed)="editOpen.set(false)">
            <form class="playlist-form" (ngSubmit)="saveEdit()">
              <label class="field">
                <span>Title</span>
                <input
                  type="text"
                  class="text-input"
                  name="title"
                  maxlength="120"
                  [ngModel]="editTitle()"
                  (ngModelChange)="editTitle.set($event)"
                  required
                />
              </label>
              <label class="field">
                <span>Description</span>
                <textarea
                  class="text-input"
                  name="description"
                  rows="3"
                  maxlength="500"
                  [ngModel]="editDescription()"
                  (ngModelChange)="editDescription.set($event)"
                ></textarea>
              </label>
              <div class="modal-actions">
                <button
                  type="button"
                  class="pill-chip"
                  (click)="editOpen.set(false)"
                >
                  Cancel
                </button>
                <button type="submit" class="pill-chip active">Save</button>
              </div>
            </form>
          </app-modal-sheet>
        }

        @if (deleteConfirmOpen()) {
          <app-modal-sheet
            title="Delete Playlist"
            (closed)="deleteConfirmOpen.set(false)"
          >
            <div class="confirm-body">
              <p class="confirm-text">
                Delete <strong>{{ pl.title }}</strong>? This cannot be undone.
              </p>
              <div class="modal-actions">
                <button
                  type="button"
                  class="pill-chip"
                  (click)="deleteConfirmOpen.set(false)"
                >
                  Cancel
                </button>
                <button
                  type="button"
                  class="pill-chip danger-chip"
                  (click)="deletePlaylist()"
                >
                  Delete
                </button>
              </div>
            </div>
          </app-modal-sheet>
        }
      }
    </div>
  `,
  styles: [
    `
      .playlist-detail {
        padding-top: 16px;
        padding-bottom: 40px;
        display: flex;
        flex-direction: column;
        gap: 20px;
      }

      .detail-head {
        display: flex;
        flex-direction: column;
        gap: 16px;
        padding: 16px;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-lg);
      }

      @media (min-width: 720px) {
        .detail-head {
          flex-direction: row;
          align-items: flex-start;
        }
      }

      .cover-box {
        width: 100%;
        max-width: 300px;
        aspect-ratio: 16 / 9;
        border-radius: var(--radius-md);
        overflow: hidden;
        background-color: var(--surface-variant);
        flex-shrink: 0;
      }

      .cover-img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }

      .cover-placeholder {
        width: 100%;
        height: 100%;
        display: grid;
        place-items: center;
        color: var(--on-surface-muted);
      }

      .cover-placeholder .material-symbols-rounded {
        font-size: 48px;
      }

      .head-meta {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .head-meta h1 {
        margin: 0;
        font-size: 22px;
        font-weight: 700;
        line-height: 1.3;
      }

      .desc {
        margin: 0;
        font-size: 14px;
        color: var(--on-surface-muted);
        white-space: pre-wrap;
      }

      .sub,
      .muted {
        margin: 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .head-actions {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
        margin-top: 4px;
      }

      .head-actions .pill-chip:disabled {
        opacity: 0.45;
        cursor: not-allowed;
      }

      .btn-icon {
        font-size: 18px;
      }

      .danger-outline:hover {
        border-color: var(--error);
        color: var(--error);
      }

      .track-list {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .track-row {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 10px;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
      }

      .track-index {
        width: 24px;
        text-align: center;
        font-size: 13px;
        font-weight: 600;
        color: var(--on-surface-muted);
        flex-shrink: 0;
      }

      .track-main {
        flex: 1;
        min-width: 0;
        display: flex;
        align-items: center;
        gap: 12px;
      }

      .thumb-wrap {
        position: relative;
        width: clamp(96px, 24vw, 152px);
        aspect-ratio: 16 / 9;
        border-radius: var(--radius-sm);
        overflow: hidden;
        background-color: var(--surface-variant);
        flex-shrink: 0;
      }

      .track-thumb {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }

      .dur-badge {
        position: absolute;
        right: 4px;
        bottom: 4px;
        padding: 1px 5px;
        border-radius: 4px;
        font-size: 10px;
        font-weight: 600;
        background-color: rgba(0, 0, 0, 0.85);
        color: #ffffff;
      }

      .track-meta {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 4px;
      }

      .track-title {
        font-size: 14px;
        font-weight: 600;
        line-height: 1.35;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .track-channel {
        font-size: 12px;
        color: var(--on-surface-muted);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .track-controls {
        display: flex;
        align-items: center;
        gap: 2px;
        flex-shrink: 0;
      }

      .small-btn {
        width: 32px;
        height: 32px;
      }

      .small-btn:disabled {
        opacity: 0.35;
        cursor: not-allowed;
      }

      .small-btn .material-symbols-rounded {
        font-size: 18px;
      }

      .danger-btn:hover {
        color: var(--error);
      }

      .state-card {
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

      .state-icon {
        font-size: 40px;
        color: var(--on-surface-muted);
      }

      .playlist-form,
      .confirm-body {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }

      .field {
        display: flex;
        flex-direction: column;
        gap: 6px;
        font-size: 13px;
        font-weight: 600;
      }

      .text-input {
        width: 100%;
        padding: 10px 12px;
        border-radius: var(--radius-sm);
        border: 1px solid var(--surface-border);
        background-color: var(--bg);
        font-size: 14px;
        font-weight: 400;
        resize: vertical;
      }

      .text-input:focus {
        outline: none;
        border-color: var(--accent);
      }

      .confirm-text {
        margin: 0;
        font-size: 14px;
      }

      .modal-actions {
        display: flex;
        justify-content: flex-end;
        gap: 8px;
      }

      .danger-chip {
        background-color: var(--error);
        border-color: var(--error);
        color: var(--on-error);
      }
    `,
  ],
})
export class PlaylistDetailComponent {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  readonly playlistService = inject(PlaylistService);
  private readonly toast = inject(ToastService);

  readonly playlistId = toSignal(
    this.route.paramMap.pipe(map((p) => p.get('id') ?? '')),
    { initialValue: this.route.snapshot.paramMap.get('id') ?? '' },
  );

  readonly playlist = computed(() =>
    this.playlistService.playlistById(this.playlistId()),
  );

  readonly editOpen = signal<boolean>(false);
  readonly editTitle = signal<string>('');
  readonly editDescription = signal<string>('');
  readonly deleteConfirmOpen = signal<boolean>(false);

  playAll(): void {
    const pl = this.playlist();
    if (!pl || pl.videos.length === 0) return;
    void this.router.navigate(['/watch', pl.videos[0].id], {
      queryParams: { playlist: pl.id },
    });
  }

  openEdit(): void {
    const pl = this.playlist();
    if (!pl) return;
    this.editTitle.set(pl.title);
    this.editDescription.set(pl.description ?? '');
    this.editOpen.set(true);
  }

  saveEdit(): void {
    const pl = this.playlist();
    if (!pl) return;
    const ok = this.playlistService.updatePlaylist(pl.id, {
      title: this.editTitle(),
      description: this.editDescription(),
    });
    if (!ok) {
      this.toast.show('Please enter a valid playlist title', 'error');
      return;
    }
    this.editOpen.set(false);
    this.toast.show('Playlist updated', 'success');
  }

  deletePlaylist(): void {
    const pl = this.playlist();
    if (!pl) return;
    this.playlistService.deletePlaylist(pl.id);
    this.deleteConfirmOpen.set(false);
    this.toast.show(`Deleted "${pl.title}"`, 'info');
    void this.router.navigate(['/playlists']);
  }

  move(fromIndex: number, toIndex: number): void {
    const pl = this.playlist();
    if (!pl) return;
    const ok = this.playlistService.reorderVideos(pl.id, fromIndex, toIndex);
    if (ok) {
      this.toast.show('Playlist order updated', 'info');
    }
  }

  removeVideo(video: Video): void {
    const pl = this.playlist();
    if (!pl) return;
    const ok = this.playlistService.removeVideoFromPlaylist(pl.id, video.id);
    if (ok) {
      this.toast.show(`Removed from ${pl.title}`, 'info');
    }
  }
}
