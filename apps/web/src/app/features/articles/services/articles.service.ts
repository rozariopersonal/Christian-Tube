import { Injectable, inject, signal } from '@angular/core';
import { ReleaseDataService } from '../../../core/api/release-data.service';
import { ArticleData, ArticleIndexEntry } from '../models/article.model';

@Injectable({ providedIn: 'root' })
export class ArticlesService {
  private readonly releases = inject(ReleaseDataService);

  readonly entries = signal<ArticleIndexEntry[]>([]);
  readonly loading = signal<boolean>(false);
  readonly error = signal<string | null>(null);

  async loadIndex(): Promise<void> {
    if (this.entries().length > 0) return;
    this.loading.set(true);
    this.error.set(null);
    try {
      const list = await this.releases.getJson<ArticleIndexEntry[]>(
        'articles/articles_index.json',
      );
      const sorted = Array.isArray(list)
        ? [...list].sort((a, b) => (b.date || '').localeCompare(a.date || ''))
        : [];
      this.entries.set(sorted);
    } catch (err) {
      this.error.set(
        err instanceof Error ? err.message : 'Unable to load articles',
      );
    } finally {
      this.loading.set(false);
    }
  }

  async fetchArticle(id: string, lang?: string): Promise<ArticleData> {
    const code = (lang ?? 'en').trim().toLowerCase() || 'en';
    const path =
      code === 'en'
        ? `articles/wftw/${id}.json`
        : `articles/${code}/${id}.json`;
    try {
      return await this.releases.getJson<ArticleData>(path);
    } catch {
      if (code !== 'en') {
        return await this.releases.getJson<ArticleData>(
          `articles/wftw/${id}.json`,
        );
      }
      throw new Error('Article not found');
    }
  }
}
