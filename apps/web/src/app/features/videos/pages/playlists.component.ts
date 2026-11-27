import {
  ChangeDetectionStrategy,
  Component,
  inject,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { ToastService } from '../../../shared/ui/toast.service';
import { UserPlaylist } from '../models/playlist.model';
import { PlaylistService } from '../services/playlist.service';

@Component({
  selector: 'app-playlists-page',
  standalone: true,
  imports: [RouterLink, FormsModule, ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="playlists-page max-width-box">
      <header class="page-head">
        <div>
          <h1 class="font-display">Playlists</h1>
          <p class="sub">
            {{ playlistService.playlists().length }}
            {{ playlistService.playlists().length === 1 ? 'playlist' : 'playlists' }}
          </p>
        </div>
        <button
          type="button"
          class="pill-chip active"
          (click)="openCreate()"
        >
          <span class="material-symbols-rounded btn-icon">add</span>
          New Playlist
        </button>
      </header>

      @if (playlistService.playlists().length === 0) {
        <div class="state-card">
          <span class="material-symbols-rounded state-icon">playlist_play</span>
          <h2>No playlists yet</h2>
          <p class="muted">
            Organize sermons and teachings into personal playlists synced across your devices.
          </p>
          <button type="button" class="pill-chip active" (click)="openCreate()">
            <span class="material-symbols-rounded btn-icon">add</span>
            New Playlist
          </button>
        </div>
      } @else {
        <div class="playlist-grid">
          @for (pl of playlistService.playlists(); track pl.id) {
            <article class="playlist-card">
              <a class="cover-link" [routerLink]="['/playlists', pl.id]">
                @if (pl.thumbnailUrl) {
                  <img class="cover-img" [src]="pl.thumbnailUrl" [alt]="pl.title" loading="lazy" />
                } @else {
                  <div class="cover-placeholder">
                    <span class="material-symbols-rounded">playlist_play</span>
                  </div>
                }
                <span class="count-badge">
                  <span class="material-symbols-rounded">playlist_play</span>
                  {{ pl.videoCount }}
                </span>
              </a>

              <div class="card-body">
                <a class="card-title" [routerLink]="['/playlists', pl.id]">
                  {{ pl.title }}
                </a>
                @if (pl.description) {
                  <p class="card-desc">{{ pl.description }}</p>
                }
                <div class="card-actions">
                  <button
                    type="button"
                    class="pill-chip active"
                    [disabled]="pl.videos.length === 0"
                    (click)="playAll(pl)"
                  >
                    <span class="material-symbols-rounded btn-icon">play_arrow</span>
                    Play All
                  </button>
                  <button
                    type="button"
                    class="icon-btn small-btn"
                    aria-label="Edit playlist"
                    title="Edit playlist"
                    (click)="openEdit(pl)"
                  >
                    <span class="material-symbols-rounded">edit</span>
                  </button>
                  <button
                    type="button"
                    class="icon-btn small-btn danger-btn"
                    aria-label="Delete playlist"
                    title="Delete playlist"
                    (click)="confirmDelete(pl)"
                  >
                    <span class="material-symbols-rounded">delete</span>
                  </button>
                </div>
              </div>
            </article>
          }
        </div>
      }

      @if (formOpen()) {
        <app-modal-sheet
          [title]="editingPlaylist() ? 'Edit Playlist' : 'New Playlist'"
          (closed)="closeForm()"
        >
          <form class="playlist-form" (ngSubmit)="submitForm()">
            <label class="field">
              <span>Title</span>
              <input
                type="text"
                class="text-input"
                name="title"
                placeholder="Playlist title"
                maxlength="120"
                [ngModel]="formTitle()"
                (ngModelChange)="formTitle.set($event)"
                required
              />
            </label>
            <label class="field">
              <span>Description</span>
              <textarea
                class="text-input"
                name="description"
                rows="3"
                placeholder="Optional description"
                maxlength="500"
                [ngModel]="formDescription()"
                (ngModelChange)="formDescription.set($event)"
              ></textarea>
            </label>
            <div class="modal-actions">
              <button type="button" class="pill-chip" (click)="closeForm()">
                Cancel
              </button>
              <button type="submit" class="pill-chip active">
                {{ editingPlaylist() ? 'Save' : 'Create' }}
              </button>
            </div>
          </form>
        </app-modal-sheet>
      }

      @if (deletingPlaylist(); as target) {
        <app-modal-sheet title="Delete Playlist" (closed)="deletingPlaylist.set(null)">
          <div class="confirm-body">
            <p class="confirm-text">
              Delete <strong>{{ target.title }}</strong>? This removes the playlist but keeps all videos on the platform.
            </p>
            <div class="modal-actions">
              <button
                type="button"
                class="pill-chip"
                (click)="deletingPlaylist.set(null)"
              >
                Cancel
              </button>
              <button
                type="button"
                class="pill-chip danger-chip"
                (click)="executeDelete()"
              >
                Delete
              </button>
            </div>
          </div>
        </app-modal-sheet>
      }
    </div>
  `,
  styles: [
    `
      .playlists-page {
        padding-top: 16px;
        padding-bottom: 40px;
      }

      .page-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        flex-wrap: wrap;
        margin-bottom: 18px;
      }

      .page-head h1 {
        margin: 0;
        font-size: 22px;
        font-weight: 700;
      }

      .sub,
      .muted {
        margin: 2px 0 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .btn-icon {
        font-size: 18px;
      }

      .playlist-grid {
        display: grid;
        gap: 18px 16px;
        grid-template-columns: 1fr;
      }

      @media (min-width: 600px) {
        .playlist-grid {
          grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
        }
      }

      .playlist-card {
        display: flex;
        flex-direction: column;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
        overflow: hidden;
      }

      .cover-link {
        position: relative;
        width: 100%;
        aspect-ratio: 16 / 9;
        background-color: var(--surface-variant);
        display: block;
        overflow: hidden;
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
        font-size: 42px;
      }

      .count-badge {
        position: absolute;
        right: 8px;
        bottom: 8px;
        display: inline-flex;
        align-items: center;
        gap: 4px;
        padding: 3px 8px;
        border-radius: 6px;
        background-color: rgba(0, 0, 0, 0.82);
        color: #ffffff;
        font-size: 12px;
        font-weight: 600;
      }

      .count-badge .material-symbols-rounded {
        font-size: 16px;
      }

      .card-body {
        padding: 12px 14px 14px;
        display: flex;
        flex-direction: column;
        gap: 8px;
        flex: 1;
      }

      .card-title {
        font-size: 15px;
        font-weight: 700;
        line-height: 1.3;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .card-desc {
        margin: 0;
        font-size: 12px;
        color: var(--on-surface-muted);
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .card-actions {
        margin-top: auto;
        padding-top: 4px;
        display: flex;
        align-items: center;
        gap: 6px;
      }

      .card-actions .pill-chip:disabled {
        opacity: 0.45;
        cursor: not-allowed;
      }

      .small-btn {
        width: 34px;
        height: 34px;
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
        line-height: 1.5;
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
export class PlaylistsComponent {
  readonly playlistService = inject(PlaylistService);
  private readonly toast = inject(ToastService);
  private readonly router = inject(Router);

  readonly formOpen = signal<boolean>(false);
  readonly editingPlaylist = signal<UserPlaylist | null>(null);
  readonly deletingPlaylist = signal<UserPlaylist | null>(null);
  readonly formTitle = signal<string>('');
  readonly formDescription = signal<string>('');

  openCreate(): void {
    this.editingPlaylist.set(null);
    this.formTitle.set('');
    this.formDescription.set('');
    this.formOpen.set(true);
  }

  openEdit(playlist: UserPlaylist): void {
    this.editingPlaylist.set(playlist);
    this.formTitle.set(playlist.title);
    this.formDescription.set(playlist.description ?? '');
    this.formOpen.set(true);
  }

  closeForm(): void {
    this.formOpen.set(false);
    this.editingPlaylist.set(null);
    this.formTitle.set('');
    this.formDescription.set('');
  }

  submitForm(): void {
    const editing = this.editingPlaylist();
    if (editing) {
      const ok = this.playlistService.updatePlaylist(editing.id, {
        title: this.formTitle(),
        description: this.formDescription(),
      });
      if (!ok) {
        this.toast.show('Please enter a valid playlist title', 'error');
        return;
      }
      this.toast.show('Playlist updated', 'success');
      this.closeForm();
      return;
    }

    const created = this.playlistService.createPlaylist(
      this.formTitle(),
      this.formDescription(),
    );
    if (!created) {
      this.toast.show('Please enter a valid playlist title', 'error');
      return;
    }
    this.toast.show(`Created "${created.title}"`, 'success');
    this.closeForm();
  }

  confirmDelete(playlist: UserPlaylist): void {
    this.deletingPlaylist.set(playlist);
  }

  executeDelete(): void {
    const target = this.deletingPlaylist();
    if (!target) return;
    this.playlistService.deletePlaylist(target.id);
    this.deletingPlaylist.set(null);
    this.toast.show(`Deleted "${target.title}"`, 'info');
  }

  playAll(playlist: UserPlaylist): void {
    if (playlist.videos.length === 0) return;
    void this.router.navigate(['/watch', playlist.videos[0].id], {
      queryParams: { playlist: playlist.id },
    });
  }
}
