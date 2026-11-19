import { Injectable, signal } from '@angular/core';

export interface PageSearchConfig {
  placeholder: string;
  onChange?: (query: string) => void;
  onSubmit?: (query: string) => void;
  initialValue?: string;
}

@Injectable({ providedIn: 'root' })
export class HeaderSearchService {
  readonly pageConfig = signal<PageSearchConfig | null>(null);
  readonly pageQuery = signal<string>('');

  register(config: PageSearchConfig): () => void {
    this.pageConfig.set(config);
    this.pageQuery.set(config.initialValue ?? '');
    return () => {
      if (this.pageConfig() === config) {
        this.pageConfig.set(null);
        this.pageQuery.set('');
      }
    };
  }

  updatePageQuery(value: string): void {
    this.pageQuery.set(value);
    this.pageConfig()?.onChange?.(value);
  }

  submitPageQuery(): void {
    this.pageConfig()?.onSubmit?.(this.pageQuery());
  }
}
