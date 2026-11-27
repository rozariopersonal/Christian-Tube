import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  inject,
  input,
  output,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { YouTubeChannelResult } from '../models/channel.model';
import { ChannelService } from '../services/channel.service';

export interface ChannelModalCompletedEvent {
  mode: 'request' | 'add';
  channelName: string;
}

@Component({
  selector: 'app-channel-request-modal',
  standalone: true,
  imports: [FormsModule, ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  host: {
    '(document:keydown.escape)': 'handleClose()',
  },
  template: `
    <app-modal-sheet
      [title]="mode() === 'add' ? 'Add YouTube Channel' : 'Request a Channel'"
      (closed)="handleClose()"
    >
      <p class="subtitle">
        @if (mode() === 'add') {
          Search YouTube or paste a channel URL to add it directly.
        } @else {
          Search YouTube for a channel to request, or enter its URL manually.
        }
      </p>

      <form class="yt-search-row" (ngSubmit)="runSearch()">
        <div class="yt-search-input">
          <span class="material-symbols-rounded">search</span>
          <input
            type="search"
            name="ytQuery"
            [ngModel]="searchQuery()"
            (ngModelChange)="onSearchQueryChange($event)"
            placeholder="Search YouTube channel or paste URL..."
            [disabled]="isBusy()"
          />
        </div>
        <button
          type="submit"
          class="pill-chip active"
          [disabled]="searching() || searchQuery().trim().length < 2"
        >
          {{ searching() ? 'Searching...' : 'Search' }}
        </button>
      </form>

      @if (errorMessage()) {
        <div class="error-banner" role="alert">{{ errorMessage() }}</div>
      }

      @if (searching()) {
        <p class="status-msg">Searching YouTube channels...</p>
      } @else if (searchError()) {
        <p class="status-msg error-text">{{ searchError() }}</p>
      } @else if (hasSearched() && searchResults().length === 0) {
        <p class="status-msg">
          No channels found for "{{ lastQuery() }}". You can submit the URL directly below.
        </p>
      } @else if (searchResults().length > 0) {
        <div class="results-list">
          @for (ch of searchResults(); track ch.id) {
            <div class="result-row">
              @if (ch.thumbnail) {
                <img class="ch-avatar" [src]="ch.thumbnail" [alt]="ch.name" />
              } @else {
                <span class="ch-avatar fallback">
                  {{ ch.name.slice(0, 1).toUpperCase() }}
                </span>
              }
              <div class="ch-info">
                <span class="ch-name">{{ ch.name }}</span>
                <span class="ch-meta">
                  @if (ch.isSynthetic) {
                    Unverified handle · {{ ch.handle || ch.id }}
                  } @else {
                    @if (ch.handle) {
                      {{ ch.handle }}
                    }
                    @if (ch.subscriberCount != null) {
                      @if (ch.handle) { · }
                      {{ formatSubs(ch.subscriberCount) }} subscribers
                    }
                    @if (!ch.handle && ch.subscriberCount == null && ch.description) {
                      {{ ch.description }}
                    }
                  }
                </span>
              </div>
              @if (ch.isExisting) {
                <span class="existing-badge">Already Added</span>
              } @else {
                <button
                  type="button"
                  class="pill-chip active action-btn"
                  [disabled]="submittingId() !== null || submittingManual()"
                  (click)="selectResult(ch)"
                >
                  @if (submittingId() === ch.id) {
                    {{ mode() === 'add' ? 'Adding...' : 'Requesting...' }}
                  } @else {
                    {{ mode() === 'add' ? 'Add' : 'Request' }}
                  }
                </button>
              }
            </div>
          }
        </div>
      }

      <div class="manual-section">
        <button
          type="button"
          class="manual-toggle"
          (click)="showManual.set(!showManual())"
        >
          <span class="material-symbols-rounded">
            {{ showManual() ? 'expand_less' : 'expand_more' }}
          </span>
          Or paste a YouTube channel URL manually
        </button>

        @if (showManual()) {
          <form class="manual-fields" (ngSubmit)="submitManual()">
            <label class="field">
              <span>YouTube Channel URL or @handle *</span>
              <input
                type="text"
                name="manualUrl"
                [ngModel]="manualUrl()"
                (ngModelChange)="manualUrl.set($event); errorMessage.set('')"
                placeholder="https://youtube.com/@... or @handle"
                [disabled]="submittingManual()"
              />
            </label>
            <label class="field">
              <span>Channel Name (optional)</span>
              <input
                type="text"
                name="manualName"
                [ngModel]="manualName()"
                (ngModelChange)="manualName.set($event)"
                placeholder="e.g. Grace Fellowship"
                [disabled]="submittingManual()"
              />
            </label>
            @if (mode() === 'request') {
              <label class="field">
                <span>Reason / Notes (optional)</span>
                <textarea
                  rows="2"
                  name="manualNotes"
                  [ngModel]="manualNotes()"
                  (ngModelChange)="manualNotes.set($event)"
                  placeholder="Why should this channel be added?"
                  [disabled]="submittingManual()"
                ></textarea>
              </label>
            }
            <div class="modal-actions">
              <button
                type="button"
                class="pill-chip"
                (click)="handleClose()"
                [disabled]="isBusy()"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="pill-chip active"
                [disabled]="isBusy() || !manualUrl().trim()"
              >
                @if (submittingManual()) {
                  Submitting...
                } @else {
                  {{ mode() === 'add' ? 'Add Channel' : 'Submit Request' }}
                }
              </button>
            </div>
          </form>
        }
      </div>
    </app-modal-sheet>
  `,
  styles: [
    `
      .subtitle {
        margin: 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .yt-search-row {
        display: flex;
        gap: 8px;
        align-items: center;
      }

      .yt-search-input {
        flex: 1;
        min-width: 0;
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 0 12px;
        height: 40px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .yt-search-input input {
        flex: 1;
        min-width: 0;
        border: none;
        outline: none;
        background: transparent;
      }

      .error-banner {
        padding: 10px 12px;
        border-radius: var(--radius-sm);
        background-color: color-mix(in srgb, var(--error) 14%, transparent);
        border: 1px solid color-mix(in srgb, var(--error) 35%, transparent);
        color: var(--error);
        font-size: 13px;
      }

      .status-msg {
        margin: 4px 0;
        font-size: 13px;
        color: var(--on-surface-muted);
        text-align: center;
        padding: 12px 0;
      }

      .error-text {
        color: var(--error);
      }

      .results-list {
        display: flex;
        flex-direction: column;
        gap: 8px;
        max-height: 280px;
        overflow-y: auto;
        padding-right: 2px;
      }

      .result-row {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 8px 10px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .ch-avatar {
        width: 38px;
        height: 38px;
        border-radius: 50%;
        object-fit: cover;
        flex-shrink: 0;
      }

      .ch-avatar.fallback {
        display: grid;
        place-items: center;
        background-color: var(--surface);
        font-weight: 700;
        font-size: 14px;
      }

      .ch-info {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .ch-name {
        font-size: 14px;
        font-weight: 600;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .ch-meta {
        font-size: 12px;
        color: var(--on-surface-muted);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .existing-badge {
        padding: 4px 10px;
        border-radius: var(--radius-pill);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        color: var(--on-surface-muted);
        font-size: 12px;
        font-weight: 600;
        flex-shrink: 0;
      }

      .action-btn {
        flex-shrink: 0;
      }

      .manual-section {
        border-top: 1px solid var(--surface-border);
        padding-top: 10px;
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .manual-toggle {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        align-self: flex-start;
        font-size: 13px;
        font-weight: 600;
        color: var(--accent);
        background: transparent;
        border: none;
        padding: 0;
        cursor: pointer;
      }

      .manual-fields {
        display: flex;
        flex-direction: column;
        gap: 10px;
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
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .modal-actions {
        display: flex;
        justify-content: flex-end;
        gap: 8px;
      }
    `,
  ],
})
export class ChannelRequestModalComponent implements OnInit {
  private readonly channelService = inject(ChannelService);

  readonly mode = input<'request' | 'add'>('request');
  readonly initialQuery = input<string>('');
  readonly completed = output<ChannelModalCompletedEvent>();
  readonly closed = output<void>();

  readonly searchQuery = signal<string>('');
  readonly lastQuery = signal<string>('');
  readonly searching = signal<boolean>(false);
  readonly hasSearched = signal<boolean>(false);
  readonly searchError = signal<string>('');
  readonly searchResults = signal<YouTubeChannelResult[]>([]);

  readonly showManual = signal<boolean>(false);
  readonly manualUrl = signal<string>('');
  readonly manualName = signal<string>('');
  readonly manualNotes = signal<string>('');

  readonly submittingId = signal<string | null>(null);
  readonly submittingManual = signal<boolean>(false);
  readonly errorMessage = signal<string>('');

  ngOnInit(): void {
    const q = this.initialQuery().trim();
    if (q) {
      this.searchQuery.set(q);
      if (q.length >= 2) {
        void this.runSearch();
      }
    }
  }

  isBusy(): boolean {
    return this.submittingId() !== null || this.submittingManual();
  }

  handleClose(): void {
    if (this.isBusy()) return;
    this.closed.emit();
  }

  onSearchQueryChange(value: string): void {
    this.searchQuery.set(value);
    this.errorMessage.set('');
    if (!value.trim()) {
      this.searchResults.set([]);
      this.hasSearched.set(false);
      this.searchError.set('');
    }
  }

  async runSearch(): Promise<void> {
    const q = this.searchQuery().trim();
    if (q.length < 2) {
      this.errorMessage.set('Enter at least 2 characters to search YouTube.');
      return;
    }
    this.errorMessage.set('');
    this.searchError.set('');
    this.searching.set(true);
    this.lastQuery.set(q);
    try {
      const results = await this.channelService.searchYouTubeChannels(q);
      this.searchResults.set(results);
      this.hasSearched.set(true);
      if (results.length === 0) {
        this.showManual.set(true);
        if (!this.manualUrl().trim()) {
          this.manualUrl.set(q);
        }
      }
    } catch {
      this.searchResults.set([]);
      this.hasSearched.set(true);
      this.searchError.set(
        'Could not search YouTube right now. You can paste the channel URL manually below.',
      );
      this.showManual.set(true);
    } finally {
      this.searching.set(false);
    }
  }

  async selectResult(ch: YouTubeChannelResult): Promise<void> {
    if (ch.isExisting || this.submittingId() !== null) return;
    this.errorMessage.set('');
    this.submittingId.set(ch.id);
    try {
      const result =
        this.mode() === 'add'
          ? await this.channelService.addChannel({
              channelUrl: ch.id,
              name: ch.name,
            })
          : await this.channelService.submitRequest(ch.name, ch.id);

      if (!result.ok) {
        this.errorMessage.set(result.error || 'Operation failed');
        return;
      }
      this.completed.emit({ mode: this.mode(), channelName: ch.name });
    } finally {
      this.submittingId.set(null);
    }
  }

  async submitManual(): Promise<void> {
    const trimmedUrl = this.manualUrl().trim();
    const trimmedName = this.manualName().trim();
    if (!trimmedUrl) {
      this.errorMessage.set('Please enter a YouTube channel URL or @handle.');
      return;
    }
    this.errorMessage.set('');
    this.submittingManual.set(true);
    try {
      const result =
        this.mode() === 'add'
          ? await this.channelService.addChannel({
              channelUrl: trimmedUrl,
              name: trimmedName || undefined,
            })
          : await this.channelService.submitRequest(
              trimmedName,
              trimmedUrl,
              this.manualNotes().trim() || undefined,
            );

      if (!result.ok) {
        this.errorMessage.set(result.error || 'Operation failed');
        return;
      }
      this.completed.emit({
        mode: this.mode(),
        channelName: trimmedName || trimmedUrl,
      });
    } finally {
      this.submittingManual.set(false);
    }
  }

  formatSubs(count: number): string {
    if (count >= 1_000_000) return `${(count / 1_000_000).toFixed(1)}M`;
    if (count >= 1_000) return `${(count / 1_000).toFixed(1)}K`;
    return String(count);
  }
}
