import {
  ChangeDetectionStrategy,
  Component,
  HostListener,
  OnInit,
  computed,
  inject,
  signal,
} from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { combineLatest } from 'rxjs';
import { ReaderAppearanceService } from '../../../core/services/reader-appearance.service';
import { BookAppearanceSheetComponent } from '../../books/components/book-appearance-sheet.component';
import { DictionarySheetComponent } from '../../books/components/dictionary-sheet.component';
import { ScriptureVerseSheetComponent } from '../../books/components/scripture-verse-sheet.component';
import {
  ParsedScriptureRef,
  ScriptureRefParserService,
  ScriptureSpanToken,
} from '../../books/services/scripture-ref-parser.service';
import { ArticleData, ArticleLine } from '../models/article.model';
import { ArticlesService } from '../services/articles.service';

@Component({
  selector: 'app-article-reader',
  standalone: true,
  imports: [
    BookAppearanceSheetComponent,
    DictionarySheetComponent,
    ScriptureVerseSheetComponent,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="article-page" [attr.data-paper]="appearance.paperTheme()">
      @if (!immersive()) {
        <header class="reader-bar">
          <div class="bar-inner">
            <div class="bar-title">
              <span class="material-symbols-rounded">article</span>
              <span class="title-text">{{ article()?.title || 'Article' }}</span>
            </div>

            <div class="bar-actions">
              <button
                type="button"
                class="icon-btn"
                title="Share article link"
                (click)="shareArticle()"
              >
                <span class="material-symbols-rounded">share</span>
              </button>
              <button
                type="button"
                class="icon-btn aa-btn"
                title="Display & Layout"
                (click)="showAppearance.set(true)"
              >
                Aa
              </button>
              <button
                type="button"
                class="icon-btn"
                title="Focus mode (F)"
                (click)="immersive.set(true)"
              >
                <span class="material-symbols-rounded">fullscreen</span>
              </button>
            </div>
          </div>
        </header>
      } @else {
        <button
          type="button"
          class="exit-focus-btn"
          title="Exit focus mode (Esc / F)"
          (click)="immersive.set(false)"
        >
          <span class="material-symbols-rounded">fullscreen_exit</span>
        </button>
      }

      <div
        class="reader-content"
        [attr.data-margin]="appearance.bookMargin()"
      >
        @if (loading()) {
          <p class="status-msg">Loading article...</p>
        } @else if (error()) {
          <p class="status-msg">{{ error() }}</p>
        } @else if (article(); as art) {
          <header class="article-hero">
            <span class="hero-eyebrow">
              Word for the Week · {{ lang().toUpperCase() }}
            </span>
            <h1 class="hero-title font-display">{{ art.title }}</h1>
            <div class="hero-meta">
              <span>{{ art.author }}</span>
              @if (art.date) {
                <span>·</span>
                <span>{{ art.date }}</span>
              }
              <span>·</span>
              <span>{{ readingMinutes() }} min read</span>
            </div>
          </header>

          <article
            class="article-body"
            [class.two-col-body]="appearance.bookColumns() === 2"
            [style.font-family]="appearance.activeFont().cssFamily"
            [style.font-size.px]="appearance.fontSize()"
            [style.line-height]="appearance.lineHeight()"
            [style.text-align]="appearance.bookAlign()"
            (dblclick)="lookupFromSelection()"
          >
            @for (item of parsedLines(); track $index) {
              @if (item.line.isHeading) {
                <h2 class="article-heading">{{ item.line.text }}</h2>
              } @else {
                <p class="article-para">
                  @for (tok of item.tokens; track $index) {
                    @if (tok.ref) {
                      <button
                        type="button"
                        class="scripture-link"
                        (click)="activeScriptureRef.set(tok.ref!)"
                      >
                        {{ tok.text }}
                      </button>
                    } @else {
                      <span>{{ tok.text }}</span>
                    }
                  }
                </p>
              }
            }
          </article>
        }
      </div>

      @if (showAppearance()) {
        <app-book-appearance-sheet (closed)="showAppearance.set(false)" />
      }

      @if (activeScriptureRef(); as sRef) {
        <app-scripture-verse-sheet
          [ref]="sRef"
          (closed)="activeScriptureRef.set(null)"
        />
      }

      @if (lookupWord(); as word) {
        <app-dictionary-sheet
          [word]="word"
          (closed)="lookupWord.set(null)"
        />
      }
    </div>
  `,
  styles: [
    `
      .article-page {
        min-height: calc(100dvh - var(--shell-top-offset));
        background-color: var(--reader-bg, var(--bg));
        color: var(--reader-fg, var(--on-surface));
        transition: background-color 180ms ease, color 180ms ease;
      }

      .article-page[data-paper='paper'] {
        --reader-bg: #faf8f5;
        --reader-fg: #1f2937;
        --reader-muted: #6b7280;
        --reader-border: rgba(31, 41, 55, 0.12);
      }

      .article-page[data-paper='sepia'] {
        --reader-bg: #f4ecd8;
        --reader-fg: #433422;
        --reader-muted: #78644c;
        --reader-border: rgba(67, 52, 34, 0.14);
      }

      .article-page[data-paper='night'] {
        --reader-bg: #121620;
        --reader-fg: #e2e8f0;
        --reader-muted: #94a3b8;
        --reader-border: rgba(226, 232, 240, 0.12);
      }

      .reader-bar {
        position: sticky;
        top: var(--shell-top-offset);
        z-index: 30;
        background-color: color-mix(in srgb, var(--reader-bg, var(--bg)) 90%, transparent);
        backdrop-filter: blur(12px);
        -webkit-backdrop-filter: blur(12px);
        border-bottom: 1px solid var(--reader-border, var(--surface-border));
      }

      .bar-inner {
        height: var(--topbar-height);
        width: 100%;
        padding-inline: clamp(16px, 3vw, 32px);
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }

      .bar-title {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        min-width: 0;
        font-weight: 700;
        font-size: 15px;
      }

      .title-text {
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .bar-actions {
        display: flex;
        align-items: center;
        gap: 4px;
        flex-shrink: 0;
      }

      .aa-btn {
        font-family: Georgia, serif;
        font-weight: 700;
        font-size: 16px;
      }

      .exit-focus-btn {
        position: fixed;
        top: calc(var(--shell-top-offset) + 12px);
        right: 16px;
        z-index: 40;
        width: 40px;
        height: 40px;
        border-radius: var(--radius-pill);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        display: grid;
        place-items: center;
        opacity: 0.75;
      }

      .reader-content {
        width: 100%;
        padding: 28px clamp(16px, 3vw, 40px) 64px;
      }

      .reader-content[data-margin='narrow'] {
        padding-inline: clamp(16px, 5vw, 72px);
      }

      .reader-content[data-margin='wide'] {
        padding-inline: clamp(12px, 1.5vw, 24px);
      }

      @media (min-width: 840px) {
        .article-body.two-col-body {
          display: block;
          column-count: 2;
          column-gap: 44px;
          column-rule: 1px solid var(--reader-border, var(--surface-border));
        }

        .article-body.two-col-body .article-para,
        .article-body.two-col-body .article-heading {
          break-inside: avoid;
          margin-bottom: 12px;
        }
      }

      .article-hero {
        margin-bottom: 24px;
        padding-bottom: 18px;
        border-bottom: 1px solid var(--reader-border, var(--surface-border));
      }

      .hero-eyebrow {
        display: block;
        font-size: 12px;
        font-weight: 700;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--accent);
        margin-bottom: 6px;
      }

      .hero-title {
        margin: 0 0 8px;
        font-size: clamp(22px, 3vw, 30px);
        line-height: 1.25;
        font-weight: 700;
      }

      .hero-meta {
        display: flex;
        align-items: center;
        gap: 6px;
        flex-wrap: wrap;
        font-size: 13px;
        color: var(--reader-muted, var(--on-surface-muted));
      }

      .article-body {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }

      .article-heading {
        margin: 16px 0 4px;
        font-size: 1.15em;
        font-weight: 700;
      }

      .article-para {
        margin: 0;
      }

      .scripture-link {
        color: var(--accent);
        text-decoration: underline;
        text-decoration-style: dotted;
        text-underline-offset: 3px;
        font-weight: 600;
      }

      .status-msg {
        text-align: center;
        padding: 48px 0;
        color: var(--reader-muted, var(--on-surface-muted));
      }
    `,
  ],
})
export class ArticleReaderComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly articlesService = inject(ArticlesService);
  private readonly scriptureParser = inject(ScriptureRefParserService);
  readonly appearance = inject(ReaderAppearanceService);

  readonly article = signal<ArticleData | null>(null);
  readonly lang = signal<string>('en');
  readonly loading = signal<boolean>(true);
  readonly error = signal<string | null>(null);
  readonly showAppearance = signal<boolean>(false);
  readonly immersive = signal<boolean>(false);
  readonly activeScriptureRef = signal<ParsedScriptureRef | null>(null);
  readonly lookupWord = signal<string | null>(null);

  readonly parsedLines = computed<
    Array<{ line: ArticleLine; tokens: ScriptureSpanToken[] }>
  >(() =>
    (this.article()?.lines ?? []).map((line) => ({
      line,
      tokens: line.isHeading ? [] : this.scriptureParser.parse(line.text),
    })),
  );

  readonly readingMinutes = computed(() => {
    const words = (this.article()?.lines ?? []).reduce(
      (acc, l) => acc + (l.text ? l.text.split(/\s+/).length : 0),
      0,
    );
    return Math.max(1, Math.round(words / 220));
  });

  @HostListener('window:keydown', ['$event'])
  onKeyDown(event: KeyboardEvent): void {
    if (event.key === 'Escape') {
      this.showAppearance.set(false);
      this.activeScriptureRef.set(null);
      this.lookupWord.set(null);
      this.immersive.set(false);
    } else if (event.key === 'f' || event.key === 'F') {
      this.immersive.set(!this.immersive());
    }
  }

  ngOnInit(): void {
    combineLatest([this.route.paramMap, this.route.queryParamMap]).subscribe(
      ([params, query]) => {
        const id = params.get('id');
        if (!id) return;
        const lang = query.get('lang') ?? 'en';
        void this.load(id, lang);
      },
    );
  }

  private async load(id: string, lang: string): Promise<void> {
    this.lang.set(lang);
    this.loading.set(true);
    this.error.set(null);
    try {
      const data = await this.articlesService.fetchArticle(id, lang);
      this.article.set(data);
    } catch (err) {
      this.error.set(
        err instanceof Error ? err.message : 'Unable to load article',
      );
    } finally {
      this.loading.set(false);
    }
  }

  lookupFromSelection(): void {
    const raw = window.getSelection()?.toString().trim() ?? '';
    const firstWord = raw.split(/\s+/)[0]?.replace(/[^a-zA-Z'-]/g, '');
    if (firstWord && firstWord.length >= 2) {
      this.lookupWord.set(firstWord);
    }
  }

  shareArticle(): void {
    const art = this.article();
    if (!art) return;
    const url = new URL(
      `/article/${encodeURIComponent(art.id)}`,
      window.location.origin,
    );
    if (this.lang() && this.lang() !== 'en') {
      url.searchParams.set('lang', this.lang());
    }
    const shareUrl = url.toString();
    if (navigator.share) {
      void navigator.share({ title: art.title, url: shareUrl }).catch(() => {
        void navigator.clipboard?.writeText(shareUrl);
      });
    } else {
      void navigator.clipboard?.writeText(shareUrl);
    }
  }
}
