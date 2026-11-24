import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterLink } from '@angular/router';

interface LibrarySection {
  title: string;
  subtitle: string;
  route: string;
  icon: string;
}

const LIBRARY_SECTIONS: readonly LibrarySection[] = [
  {
    title: 'Books',
    subtitle: 'Full-length Christian books & study guides',
    route: '/books',
    icon: 'auto_stories',
  },
  {
    title: 'Articles',
    subtitle: 'Devotionals, teachings & short reads',
    route: '/articles',
    icon: 'article',
  },
  {
    title: 'Songs & Hymns',
    subtitle: 'Worship lyrics across languages',
    route: '/songs',
    icon: 'music_note',
  },
  {
    title: 'Audio Sermons',
    subtitle: 'Series, messages & offline-ready streams',
    route: '/audio',
    icon: 'headphones',
  },
];

@Component({
  selector: 'app-library-hub',
  standalone: true,
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="max-width-box library-page">
      <header class="page-head">
        <h1 class="font-display">Library</h1>
        <p class="subtitle">Books, articles, songs, and audio teachings</p>
      </header>

      <div class="hub-grid">
        @for (item of sections; track item.route) {
          <a class="hub-card" [routerLink]="item.route">
            <div class="hub-icon">
              <span class="material-symbols-rounded">{{ item.icon }}</span>
            </div>
            <div class="hub-meta">
              <strong>{{ item.title }}</strong>
              <span>{{ item.subtitle }}</span>
            </div>
            <span class="material-symbols-rounded chevron">chevron_right</span>
          </a>
        }
      </div>
    </div>
  `,
  styles: [
    `
      .library-page {
        padding-top: 16px;
        padding-bottom: 32px;
        display: flex;
        flex-direction: column;
        gap: 16px;
      }

      .page-head h1 {
        margin: 0;
        font-size: 20px;
        font-weight: 700;
        letter-spacing: -0.3px;
      }

      .subtitle {
        margin: 4px 0 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .hub-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
        gap: 12px;
      }

      .hub-card {
        display: flex;
        align-items: center;
        gap: 14px;
        padding: 16px;
        border-radius: var(--radius-lg);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        color: var(--on-surface);
        text-decoration: none;
        transition: border-color 0.15s ease, background-color 0.15s ease;
      }

      .hub-card:hover {
        border-color: var(--accent);
        background-color: var(--surface-elevated);
      }

      .hub-icon {
        width: 46px;
        height: 46px;
        border-radius: var(--radius-md);
        background-color: var(--accent-soft);
        color: var(--accent);
        display: grid;
        place-items: center;
        flex-shrink: 0;
      }

      .hub-meta {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 3px;
      }

      .hub-meta strong {
        font-size: 15px;
        font-weight: 600;
      }

      .hub-meta span {
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .chevron {
        color: var(--on-surface-muted);
        font-size: 20px;
      }
    `,
  ],
})
export class LibraryHubComponent {
  readonly sections = LIBRARY_SECTIONS;
}
