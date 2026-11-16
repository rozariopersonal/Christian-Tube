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
import { ScriptureRefParserService } from './features/books/services/scripture-ref-parser.service';

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

  it('should stop prefetchBatch once maxTotalBytes budget is exceeded', async () => {
    const releases = TestBed.inject(ReleaseDataService);
    const fetched: string[] = [];
    vi.spyOn(releases, 'getJson').mockImplementation(async (path: string) => {
      fetched.push(path);
      return { payload: 'x'.repeat(600) };
    });

    await releases.prefetchBatch(['a.json', 'b.json', 'c.json', 'd.json'], {
      concurrency: 1,
      maxTotalBytes: 1000,
    });

    expect(fetched.length).toBe(2);
  });

  it('should parse inline and tagged Bible scripture references in books', () => {
    const parser = TestBed.inject(ScriptureRefParserService);

    const inline = parser.parse('Read 1 Cor 13:4-7 and John 3:16 today.');
    const refs = inline.filter((t) => t.ref !== null).map((t) => t.ref!);
    expect(refs.length).toBe(2);
    expect(refs[0].bookNumber).toBe(46);
    expect(refs[0].chapter).toBe(13);
    expect(refs[0].startVerse).toBe(4);
    expect(refs[0].endVerse).toBe(7);
    expect(refs[1].bookNumber).toBe(43);
    expect(refs[1].chapter).toBe(3);
    expect(refs[1].startVerse).toBe(16);

    const tagged = parser.parse('See [ref:19.23.1|Psalm 23:1] for comfort.');
    const taggedRef = tagged.find((t) => t.ref !== null)?.ref;
    expect(taggedRef?.bookNumber).toBe(19);
    expect(taggedRef?.chapter).toBe(23);
    expect(taggedRef?.startVerse).toBe(1);
  });
});
