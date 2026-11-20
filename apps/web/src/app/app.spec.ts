import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { App } from './app';
import { ReleaseDataService } from './core/api/release-data.service';
import { MainShellComponent } from './core/layout/main-shell.component';
import {
  ScreenClassService,
  needsCollapsedActions,
  screenClassOfWidth,
  supportsPersistentSidebar,
} from './core/layout/screen-class.service';
import { APP_COLOR_THEMES, ThemeService } from './core/theme/theme.service';
import { BooksService } from './features/books/services/books.service';
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

    expect(supportsPersistentSidebar(320)).toBe(false);
    expect(supportsPersistentSidebar(768)).toBe(false);
    expect(supportsPersistentSidebar(840)).toBe(false);
    expect(supportsPersistentSidebar(1023)).toBe(false);
    expect(supportsPersistentSidebar(1024)).toBe(true);
    expect(supportsPersistentSidebar(1400)).toBe(true);

    const screen = TestBed.inject(ScreenClassService);
    screen.width.set(768);
    expect(screen.isDesktop()).toBe(false);
    screen.width.set(900);
    expect(screen.isDesktop()).toBe(false);
    screen.width.set(1024);
    expect(screen.isDesktop()).toBe(true);
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

  it('places Channels in the left sidebar immediately before Settings and not in topbar', () => {
    const screen = TestBed.inject(ScreenClassService);
    screen.width.set(1280);
    const fixture = TestBed.createComponent(MainShellComponent);
    fixture.detectChanges();

    const shell = fixture.componentInstance;
    const miniRoutes = shell.miniRailNav.map((d) => d.route);
    const channelsMiniIdx = miniRoutes.indexOf('/channels');
    const settingsMiniIdx = miniRoutes.indexOf('/settings');
    expect(channelsMiniIdx).toBeGreaterThan(-1);
    expect(channelsMiniIdx).toBe(settingsMiniIdx - 1);

    const studyRoutes = shell.studyNav.map((d) => d.route);
    const channelsStudyIdx = studyRoutes.indexOf('/channels');
    const settingsStudyIdx = studyRoutes.indexOf('/settings');
    expect(channelsStudyIdx).toBeGreaterThan(-1);
    expect(channelsStudyIdx).toBe(settingsStudyIdx - 1);

    const el = fixture.nativeElement as HTMLElement;
    const topbarChannelsLink = el.querySelector('.topbar-right a[routerLink="/channels"]');
    expect(topbarChannelsLink).toBeNull();
  });

  it('infers book language from bookId prefix and generates multi-mirror page & cover image URLs', () => {
    const books = TestBed.inject(BooksService);
    expect(books.inferBookLanguage('ta_a_good_family')).toBe('ta');
    expect(books.inferBookLanguage('hi_woman_why_are_you_weeping')).toBe('hi');
    expect(books.inferBookLanguage('a_godly_family_life')).toBe('en');

    const pageUrls = books.pageImageUrls('ta_a_good_family', 'p1.jpg');
    expect(pageUrls.length).toBeGreaterThanOrEqual(4);
    expect(pageUrls[0]).toContain('cdn.jsdelivr.net/gh/rozariopersonal/Christian-Tube-Releases@main/books/ta/ta_a_good_family/pages/p1.jpg');
    expect(pageUrls[1]).toContain('raw.githubusercontent.com/rozariopersonal/Christian-Tube-Releases/main/books/ta/ta_a_good_family/pages/p1.jpg');

    const coverUrls = books.coverUrls('a_godly_family_life.jpg');
    expect(coverUrls.length).toBe(2);
    expect(coverUrls[0]).toContain('cdn.jsdelivr.net');
    expect(coverUrls[1]).toContain('raw.githubusercontent.com');
  });
});
