import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { App } from './app';
import { ReleaseDataService } from './core/api/release-data.service';
import {
  needsCollapsedActions,
  screenClassOfWidth,
} from './core/layout/screen-class.service';
import { APP_COLOR_THEMES, ThemeService } from './core/theme/theme.service';

describe('App & Phase 1 Core Services', () => {
  beforeEach(async () => {
    localStorage.clear();
    await TestBed.configureTestingModule({
      imports: [App],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
      ],
    }).compileComponents();
  });

  it('should create the root app', () => {
    const fixture = TestBed.createComponent(App);
    expect(fixture.componentInstance).toBeTruthy();
  });

  it('should classify Material 3 ScreenClass breakpoints accurately', () => {
    expect(screenClassOfWidth(320)).toBe('compact');
    expect(screenClassOfWidth(599)).toBe('compact');
    expect(screenClassOfWidth(600)).toBe('medium');
    expect(screenClassOfWidth(839)).toBe('medium');
    expect(screenClassOfWidth(840)).toBe('expanded');
    expect(screenClassOfWidth(1400)).toBe('expanded');

    expect(needsCollapsedActions(320)).toBe(true);
    expect(needsCollapsedActions(360)).toBe(false);
  });

  it('should apply light, dark, amoled, and 7 accent themes to documentElement', () => {
    const theme = TestBed.inject(ThemeService);
    expect(APP_COLOR_THEMES.length).toBe(7);

    theme.setThemeMode('dark');
    theme.setAmoled(true);
    theme.setColorTheme('red');
    TestBed.flushEffects();

    const root = document.documentElement;
    expect(root.getAttribute('data-theme')).toBe('dark');
    expect(root.getAttribute('data-amoled')).toBe('true');
    expect(root.style.getPropertyValue('--accent')).toBe('#DC2626');
  });

  it('should build jsDelivr + raw GitHub fallback URLs with revision cache-busting', () => {
    const releases = TestBed.inject(ReleaseDataService);
    releases.revision.set('rev-42');

    const urls = releases.urlsFor('bibles/NASB/books.json');
    expect(urls.length).toBe(2);
    expect(urls[0]).toContain('cdn.jsdelivr.net/gh/rozariopersonal/Christian-Tube-Releases@main/bibles/NASB/books.json?rv=rev-42');
    expect(urls[1]).toContain('raw.githubusercontent.com/rozariopersonal/Christian-Tube-Releases/main/bibles/NASB/books.json?rv=rev-42');

    const manifestUrls = releases.urlsFor('manifest.json', true);
    expect(manifestUrls[0].endsWith('/manifest.json')).toBe(true);
  });
});
