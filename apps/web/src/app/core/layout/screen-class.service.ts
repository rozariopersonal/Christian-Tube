import { Injectable, computed, signal } from '@angular/core';

export type ScreenClass = 'compact' | 'medium' | 'expanded';

export function screenClassOfWidth(width: number): ScreenClass {
  if (width < 600) return 'compact';
  if (width < 840) return 'medium';
  return 'expanded';
}

export const DESKTOP_SIDEBAR_MIN_WIDTH = 1024;

export function needsCollapsedActions(width: number): boolean {
  return width < 360;
}

export function supportsPersistentSidebar(width: number): boolean {
  return width >= DESKTOP_SIDEBAR_MIN_WIDTH;
}

@Injectable({ providedIn: 'root' })
export class ScreenClassService {
  readonly width = signal<number>(
    typeof window !== 'undefined' ? window.innerWidth : 1024,
  );
  readonly height = signal<number>(
    typeof window !== 'undefined' ? window.innerHeight : 768,
  );

  readonly screenClass = computed<ScreenClass>(() =>
    screenClassOfWidth(this.width()),
  );
  readonly isCompact = computed(() => this.screenClass() === 'compact');
  readonly isLandscapeCompact = computed(
    () => this.width() < 600 && this.height() < this.width(),
  );
  readonly showNavigationRail = computed(
    () => !this.isCompact() || this.isLandscapeCompact(),
  );
  readonly isMediumOrExpanded = computed(() => !this.isCompact());
  readonly isDesktop = computed(() => supportsPersistentSidebar(this.width()));
  readonly collapseAppBarActions = computed(() =>
    needsCollapsedActions(this.width()),
  );
  readonly collapseReaderActions = computed(() => this.width() < 480);

  readonly feedColumns = computed(() => {
    switch (this.screenClass()) {
      case 'compact':
        return 1;
      case 'medium':
        return 2;
      case 'expanded':
        return 3;
    }
  });

  constructor() {
    if (typeof window !== 'undefined') {
      window.addEventListener('resize', () => {
        this.width.set(window.innerWidth);
        this.height.set(window.innerHeight);
      });
    }
  }
}
