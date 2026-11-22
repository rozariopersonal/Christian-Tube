import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { FormsModule } from '@angular/forms';

@Component({
  selector: 'app-search-input',
  standalone: true,
  imports: [FormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="search-input-box">
      <span class="material-symbols-rounded search-ico">search</span>
      <input
        type="text"
        [placeholder]="placeholder()"
        [ngModel]="value()"
        (ngModelChange)="valueChange.emit($event)"
      />
      @if (value()) {
        <button
          type="button"
          class="clear-btn"
          aria-label="Clear search"
          (click)="valueChange.emit('')"
        >
          <span class="material-symbols-rounded">close</span>
        </button>
      }
    </div>
  `,
  styles: [
    `
      :host {
        display: block;
        flex-shrink: 0;
      }

      .search-input-box {
        display: flex;
        align-items: center;
        gap: 8px;
        height: 38px;
        min-height: 38px;
        padding: 0 12px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        color: var(--on-surface);
      }

      .search-input-box:focus-within {
        border-color: var(--accent);
      }

      .search-ico {
        font-size: 18px;
        color: var(--on-surface-muted);
        flex-shrink: 0;
      }

      input {
        flex: 1;
        min-width: 0;
        height: 100%;
        border: none;
        outline: none;
        background: transparent;
        color: var(--on-surface);
        font-size: 13px;
        line-height: normal;
      }

      input::placeholder {
        color: var(--on-surface-muted);
      }

      .clear-btn {
        width: 22px;
        height: 22px;
        border-radius: 999px;
        display: grid;
        place-items: center;
        color: var(--on-surface-muted);
        flex-shrink: 0;
      }

      .clear-btn:hover {
        background-color: var(--surface);
        color: var(--on-surface);
      }

      .clear-btn .material-symbols-rounded {
        font-size: 15px;
      }
    `,
  ],
})
export class SearchInputComponent {
  readonly value = input<string>('');
  readonly placeholder = input<string>('Search...');
  readonly valueChange = output<string>();
}
