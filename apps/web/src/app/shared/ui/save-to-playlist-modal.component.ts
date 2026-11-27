import {
  ChangeDetectionStrategy,
  Component,
  inject,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { UserPlaylist } from '../../features/videos/models/playlist.model';
import { Video } from '../../features/videos/models/video.model';
import { PlaylistService } from '../../features/videos/services/playlist.service';
import { VideoLibraryService } from '../../features/videos/services/video-library.service';
import { ModalSheetComponent } from './modal-sheet.component';
import { SaveToPlaylistModalService } from './save-to-playlist-modal.service';
import { ToastService } from './toast.service';

@Component({
  selector: 'app-save-to-playlist-modal',
  standalone: true,
  imports: [FormsModule, ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (modal.activeVideo(); as video) {
      <app-modal-sheet title="Save video to..." (closed)="close()">
        <div class="save-body">
          <p class="video-caption">{{ video.title }}</p>

          <div class="checklist">
            <label class="check-row">
              <input
                type="checkbox"
                [checked]="library.isWatchLater(video.id)"
                (change)="toggleWatchLater(video)"
              />
              <span class="material-symbols-rounded row-icon">watch_later</span>
              <span class="row-label">Watch Later</span>
              <span class="row-count">{{ library.watchLater().length }}</span>
            </label>

            @for (pl of playlistService.playlists(); track pl.id) {
              <label class="check-row">
                <input
                  type="checkbox"
                  [checked]="containsVideo(pl, video.id)"
                  (change)="togglePlaylist(pl, video)"
                />
                <span class="material-symbols-rounded row-icon">playlist_play</span>
                <span class="row-label">{{ pl.title }}</span>
                <span class="row-count">{{ pl.videoCount }}</span>
              </label>
            }
          </div>

          <div class="create-section">
            @if (!creating()) {
              <button
                type="button"
                class="new-playlist-btn"
                (click)="creating.set(true)"
              >
                <span class="material-symbols-rounded">add</span>
                New Playlist
              </button>
            } @else {
              <form class="create-form" (ngSubmit)="createAndAdd(video)">
                <input
                  type="text"
                  class="text-input"
                  name="title"
                  placeholder="Playlist title"
                  maxlength="120"
                  [ngModel]="newTitle()"
                  (ngModelChange)="newTitle.set($event)"
                  required
                />
                <input
                  type="text"
                  class="text-input"
                  name="description"
                  placeholder="Description (optional)"
                  maxlength="500"
                  [ngModel]="newDescription()"
                  (ngModelChange)="newDescription.set($event)"
                />
                <div class="form-actions">
                  <button
                    type="button"
                    class="pill-chip"
                    (click)="cancelCreate()"
                  >
                    Cancel
                  </button>
                  <button type="submit" class="pill-chip active">
                    Create &amp; Add
                  </button>
                </div>
              </form>
            }
          </div>
        </div>
      </app-modal-sheet>
    }
  `,
  styles: [
    `
      .save-body {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }

      .video-caption {
        margin: 0;
        font-size: 13px;
        color: var(--on-surface-muted);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .checklist {
        display: flex;
        flex-direction: column;
        gap: 4px;
        max-height: 45dvh;
        overflow-y: auto;
      }

      .check-row {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 10px 8px;
        border-radius: var(--radius-sm);
        cursor: pointer;
        user-select: none;
      }

      .check-row:hover {
        background-color: var(--surface-variant);
      }

      .check-row input[type='checkbox'] {
        width: 18px;
        height: 18px;
        accent-color: var(--accent);
        flex-shrink: 0;
      }

      .row-icon {
        font-size: 20px;
        color: var(--on-surface-muted);
        flex-shrink: 0;
      }

      .row-label {
        flex: 1;
        min-width: 0;
        font-size: 14px;
        font-weight: 500;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .row-count {
        font-size: 12px;
        color: var(--on-surface-muted);
        flex-shrink: 0;
      }

      .create-section {
        border-top: 1px solid var(--surface-border);
        padding-top: 12px;
      }

      .new-playlist-btn {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        padding: 8px 10px;
        border-radius: var(--radius-sm);
        color: var(--accent);
        font-size: 14px;
        font-weight: 600;
      }

      .new-playlist-btn:hover {
        background-color: var(--accent-soft);
      }

      .create-form {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .text-input {
        width: 100%;
        padding: 10px 12px;
        border-radius: var(--radius-sm);
        border: 1px solid var(--surface-border);
        background-color: var(--bg);
        font-size: 14px;
      }

      .text-input:focus {
        outline: none;
        border-color: var(--accent);
      }

      .form-actions {
        display: flex;
        justify-content: flex-end;
        gap: 8px;
      }
    `,
  ],
})
export class SaveToPlaylistModalComponent {
  readonly modal = inject(SaveToPlaylistModalService);
  readonly library = inject(VideoLibraryService);
  readonly playlistService = inject(PlaylistService);
  private readonly toast = inject(ToastService);

  readonly creating = signal<boolean>(false);
  readonly newTitle = signal<string>('');
  readonly newDescription = signal<string>('');

  containsVideo(playlist: UserPlaylist, videoId: string): boolean {
    return playlist.videos.some((v) => v.id === videoId);
  }

  toggleWatchLater(video: Video): void {
    const added = this.library.toggleWatchLater(video);
    this.toast.show(
      added ? 'Saved to Watch Later' : 'Removed from Watch Later',
      'success',
    );
  }

  togglePlaylist(playlist: UserPlaylist, video: Video): void {
    if (this.containsVideo(playlist, video.id)) {
      const ok = this.playlistService.removeVideoFromPlaylist(
        playlist.id,
        video.id,
      );
      if (ok) {
        this.toast.show(`Removed from ${playlist.title}`, 'info');
      }
    } else {
      const ok = this.playlistService.addVideoToPlaylist(playlist.id, video);
      if (ok) {
        this.toast.show(`Added to ${playlist.title}`, 'success');
      }
    }
  }

  createAndAdd(video: Video): void {
    const created = this.playlistService.createPlaylist(
      this.newTitle(),
      this.newDescription(),
      video,
    );
    if (!created) {
      this.toast.show('Please enter a valid playlist title', 'error');
      return;
    }
    this.toast.show(`Created "${created.title}" and added video`, 'success');
    this.cancelCreate();
  }

  cancelCreate(): void {
    this.creating.set(false);
    this.newTitle.set('');
    this.newDescription.set('');
  }

  close(): void {
    this.cancelCreate();
    this.modal.close();
  }
}
