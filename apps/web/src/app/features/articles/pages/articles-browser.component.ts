import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  OnInit,
  computed,
  effect,
  inject,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { ScreenClassService } from '../../../core/layout/screen-class.service';
import { ContentPreferencesService } from '../../../core/services/content-preferences.service';
import { HeaderSearchService } from '../../../core/services/header-search.service';
import { InfiniteScrollTriggerDirective } from '../../../shared/ui/infinite-scroll-trigger.directive';
import { LanguageDropdownComponent } from '../../../shared/ui/language-dropdown.component';
import {
  canonicalLanguageCode,
  languageMetaFromCode,
} from '../../../shared/ui/language-meta';
import { ArticlesService } from '../services/articles.service';

@Component({
  selector: 'app-articles-browser',
  standalone: true,
  imports: [
    FormsModule,
    RouterLink,
    LanguageDropdownComponent,
    InfiniteScrollTriggerDirective,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="articles-page max-width-box">
      <header class="page-head">
        <h1 class="font-display">Articles</h1>

        <div class="header-filters">
          @if (screen.isCompact()) {
            <div class="search-box">
              <span class="material-symbols-rounded">search</span>
              <input
                type="search"
                placeholder="Search articles by title or date..."
                [ngModel]="search()"
                (ngModelChange)="search.set($event)"
              />
            </div>
          }

          <div class="lang-strip">
            <button
              type="button"
              class="pill-chip"
              [class.active]="isAllQuickSelected()"
              (click)="selectAllQuickLanguages()"
            >
              All
            </button>
            @for (code of quickLanguages(); track code) {
              <button
                type="button"
                class="pill-chip"
                [class.active]="selectedLanguages().includes(code)"
                (click)="selectLanguageChip(code)"
              >
                {{ langLabel(code) }}
              </button>
            }
          </div>

          <app-language-dropdown
            [selectedLanguages]="selectedLanguages()"
            [availableLanguages]="languages()"
            [itemCounts]="languageCounts()"
            itemNoun="articles"
            headerTitle="Article Languages"
            (languagesChange)="selectedLanguages.set($event)"
          />
        </div>
      </header>

      <div class="year-strip">
        @for (y of years(); track y) {
          <button
            type="button"
            class="pill-chip"
            [class.active]="selectedYear() === y"
            (click)="selectedYear.set(y)"
          >
            {{ y }}
          </button>
        }
      </div>

      @if (articlesService.loading() && articlesService.entries().length === 0) {
        <p class="status-msg">Loading articles...</p>
      } @else if (articlesService.error()) {
        <div class="status-msg">
          <p>{{ articlesService.error() }}</p>
          <button
            type="button"
            class="pill-chip active"
            (click)="articlesService.loadIndex()"
          >
            Retry
          </button>
        </div>
      } @else if (filteredArticles().length === 0) {
        <p class="status-msg">No articles match your filter.</p>
      } @else {
        <div class="articles-grid">
          @for (item of visibleArticles(); track item.id + ':' + item.lang) {
            <a
              class="article-card"
              [routerLink]="['/article', item.id]"
              [queryParams]="{ lang: item.lang }"
            >
              <div class="card-top">
                <span class="date-badge">{{ item.date }}</span>
                <span class="lang-tag">{{ item.lang.toUpperCase() }}</span>
              </div>
              <h2 class="article-title">{{ item.title }}</h2>
              <span class="read-more">
                Read article
                <span class="material-symbols-rounded arrow">arrow_forward</span>
              </span>
            </a>
          }
        </div>

        @if (filteredArticles().length > visibleLimit()) {
          <div
            class="load-more-wrap"
            appInfiniteScrollTrigger
            (triggered)="showMore()"
          ></div>
        }
      }
    </div>
  `,
  styles: [
    `
      .articles-page {
        padding-top: 16px;
        padding-bottom: 32px;
      }

      .page-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        flex-wrap: wrap;
        margin-bottom: 12px;
      }

      .page-head h1 {
        margin: 0;
        font-size: 22px;
        font-weight: 700;
      }

      .header-filters {
        display: flex;
        align-items: center;
        gap: 10px;
        flex-wrap: wrap;
      }

      .search-box {
        flex: 1;
        min-width: 200px;
        display: flex;
        align-items: center;
        gap: 8px;
        height: 42px;
        padding: 0 12px;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
      }

      .search-box input {
        flex: 1;
        border: none;
        outline: none;
        background: transparent;
      }

      .lang-strip {
        display: flex;
        align-items: center;
        gap: 8px;
        overflow-x: auto;
        scrollbar-width: none;
      }

      .year-strip {
        display: flex;
        gap: 8px;
        overflow-x: auto;
        padding-bottom: 10px;
        margin-bottom: 10px;
        scrollbar-width: none;
      }

      .lang-strip::-webkit-scrollbar {
        display: none;
      }

      .year-strip::-webkit-scrollbar {
        display: none;
      }

      .articles-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
        gap: 14px;
      }

      .article-card {
        display: flex;
        flex-direction: column;
        gap: 8px;
        padding: 14px 16px;
        border-radius: var(--radius-md);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        transition: border-color 150ms ease;
      }

      .article-card:hover {
        border-color: var(--accent);
      }

      .card-top {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }

      .date-badge {
        font-size: 12px;
        font-weight: 600;
        color: var(--on-surface-muted);
      }

      .lang-tag {
        padding: 2px 7px;
        border-radius: var(--radius-sm);
        background-color: var(--accent-soft);
        color: var(--accent);
        font-size: 11px;
        font-weight: 700;
      }

      .article-title {
        margin: 0;
        font-size: 15px;
        font-weight: 600;
        line-height: 1.35;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .read-more {
        margin-top: auto;
        display: inline-flex;
        align-items: center;
        gap: 4px;
        font-size: 12px;
        font-weight: 600;
        color: var(--accent);
      }

      .arrow {
        font-size: 16px;
      }

      .load-more-wrap {
        margin-top: 20px;
        display: flex;
        justify-content: center;
      }

      .status-msg {
        text-align: center;
        padding: 36px 0;
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class ArticlesBrowserComponent implements OnInit {
  readonly articlesService = inject(ArticlesService);
  readonly screen = inject(ScreenClassService);
  private readonly prefs = inject(ContentPreferencesService);
  private readonly headerSearch = inject(HeaderSearchService);
  private readonly destroyRef = inject(DestroyRef);

  readonly search = signal<string>('');
  readonly selectedLanguages = signal<string[]>(this.prefs.preferredLanguages());
  readonly selectedYear = signal<string>('All');
  readonly visibleLimit = signal<number>(60);

  constructor() {
    effect(() => {
      this.selectedLanguages.set(this.prefs.preferredLanguages());
    });
  }

  readonly quickLanguages = computed(() => {
    const counts = this.languageCounts();
    const pref = this.prefs.preferredLanguages().filter((l) => l.toLowerCase() !== 'all');
    const sel = this.selectedLanguages().filter((l) => l.toLowerCase() !== 'all');
    return Array.from(new Set([...pref, ...sel])).filter(
      (code) => (counts[code] ?? 0) > 0,
    );
  });

  readonly isAllQuickSelected = computed(() => {
    const quick = this.quickLanguages();
    const sel = new Set(this.selectedLanguages());
    return quick.length > 0 && quick.every((c) => sel.has(c));
  });

  langLabel(code: string): string {
    return languageMetaFromCode(code).englishName;
  }

  selectAllQuickLanguages(): void {
    const quick = this.quickLanguages();
    this.selectedLanguages.set(quick.length > 0 ? quick : ['All']);
  }

  selectLanguageChip(code: string): void {
    const cur = this.selectedLanguages().filter((l) => l.toLowerCase() !== 'all');
    const next = cur.includes(code)
      ? cur.filter((c) => c !== code)
      : [...cur, code];
    if (next.length === 0) {
      this.selectAllQuickLanguages();
    } else {
      this.selectedLanguages.set(next);
    }
  }

  readonly languageCounts = computed(() => {
    const counts: Record<string, number> = {
      All: this.articlesService.entries().length,
    };
    for (const a of this.articlesService.entries()) {
      const code = canonicalLanguageCode(a.lang);
      counts[code] = (counts[code] ?? 0) + 1;
    }
    return counts;
  });

  readonly languages = computed(() => {
    const counts = this.languageCounts();
    return Object.keys(counts)
      .filter((k) => k !== 'All')
      .sort((a, b) => (counts[b] ?? 0) - (counts[a] ?? 0));
  });

  readonly years = computed(() => {
    const set = new Set<string>(['All']);
    for (const a of this.articlesService.entries()) {
      const y = a.year ?? (a.date ? Number(a.date.slice(0, 4)) : null);
      if (y && Number.isFinite(y)) {
        set.add(String(y));
      }
    }
    return [...set];
  });

  readonly filteredArticles = computed(() => {
    const q = this.search().trim().toLowerCase();
    const selLangs = this.selectedLanguages();
    const allLangs = selLangs.length === 0 || selLangs.includes('All');
    const langSet = new Set(selLangs.map((l) => l.toLowerCase()));
    const yr = this.selectedYear();

    return this.articlesService.entries().filter((a) => {
      if (
        !allLangs &&
        !langSet.has(canonicalLanguageCode(a.lang).toLowerCase())
      ) {
        return false;
      }
      if (yr !== 'All') {
        const entryYear = String(a.year ?? a.date?.slice(0, 4) ?? '');
        if (entryYear !== yr) return false;
      }
      if (
        q &&
        !a.title.toLowerCase().includes(q) &&
        !(a.date?.toLowerCase().includes(q) ?? false)
      ) {
        return false;
      }
      return true;
    });
  });

  readonly visibleArticles = computed(() =>
    this.filteredArticles().slice(0, this.visibleLimit()),
  );

  ngOnInit(): void {
    void this.articlesService.loadIndex();
    const unregister = this.headerSearch.register({
      placeholder: 'Search articles by title or date...',
      onChange: (q) => this.search.set(q),
    });
    this.destroyRef.onDestroy(unregister);
  }

  showMore(): void {
    this.visibleLimit.update((n) => n + 60);
  }
}
