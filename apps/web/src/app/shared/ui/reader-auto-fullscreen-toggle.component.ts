import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { ReaderFullscreenService } from '../../core/services/reader-fullscreen.service';

@Component({
  selector: 'app-reader-auto-fullscreen-toggle',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <button
      type="button"
      class="reader-auto-fullscreen-toggle"
      [class.active]="fullscreen.autoFullscreenSeconds() > 0"
      [title]="autoLabel()"
      [attr.aria-label]="autoLabel()"
      [attr.aria-pressed]="fullscreen.autoFullscreenSeconds() > 0"
      (click)="fullscreen.toggleAutoFullscreen()"
    >
      <span class="material-symbols-rounded">{{ fullscreen.autoFullscreenSeconds() > 0 ? 'timer' : 'timer_off' }}</span>
    </button>
  `,
  styles: [`
    .reader-auto-fullscreen-toggle {
      width: 40px;
      height: 40px;
      border: 0;
      border-radius: 50%;
      display: inline-grid;
      place-items: center;
      color: var(--on-surface-muted);
      background: transparent;
      cursor: pointer;
    }
    .reader-auto-fullscreen-toggle:hover,
    .reader-auto-fullscreen-toggle.active {
      color: var(--accent);
      background: var(--accent-soft);
    }
    .reader-auto-fullscreen-toggle .material-symbols-rounded { font-size: 21px; }
  `],
})
export class ReaderAutoFullscreenToggleComponent {
  readonly fullscreen = inject(ReaderFullscreenService);

  autoLabel(): string {
    const delay = this.fullscreen.autoFullscreenSeconds();
    return delay > 0
      ? `Automatic fullscreen: ${delay} seconds. Click to change.`
      : 'Automatic fullscreen: off. Click to change.';
  }
}
