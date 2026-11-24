import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { ReleaseDataService } from '../../core/api/release-data.service';
import {
  LANGUAGE_TO_BIBLE_VERSIONS,
  getVersionsForLanguages,
} from '../bible/models/bible.model';
import { OnlineBibleService } from '../bible/services/online-bible.service';
import { countActiveFilters } from './models/words-feed.model';
import {
  BACKGROUND_PRESETS,
  getFontsForLanguage,
  getLanguageForVersion,
  getPreset,
  resolvePresetCssBackground,
} from './models/words-theme.catalog';
import { WordsFeedComponent } from './pages/words-feed.component';
import { WordsFeedService } from './services/words-feed.service';
import { WordsPreferencesService } from './services/words-preferences.service';

const MOCK_SCRIPTURES = [
  {
    bookNumber: 19,
    bookName: 'Psalms',
    chapter: 23,
    startVerse: 1,
    endVerse: 1,
    referenceLabel: 'Psalms 23:1',
    category: 'comfort',
    tags: ['comfort', 'promises'],
    backgroundPreset: 'mountain_dawn',
  },
  {
    bookNumber: 43,
    bookName: 'John',
    chapter: 3,
    startVerse: 16,
    endVerse: 16,
    referenceLabel: 'John 3:16',
    category: 'salvation',
    tags: ['faith', 'hope'],
    backgroundPreset: 'ocean_calm',
    verseMappings: {
      kjv: { bookNumber: 43, chapter: 3, startVerse: 16, endVerse: 16 },
    },
  },
  {
    bookNumber: 45,
    bookName: 'Romans',
    chapter: 8,
    startVerse: 28,
    endVerse: 28,
    referenceLabel: 'Romans 8:28',
    category: 'courage',
    tags: ['courage', 'promises'],
    backgroundPreset: 'true_minimalist',
  },
];

describe('Web Word Feed Feature', () => {
  beforeEach(async () => {
    localStorage.clear();
    await TestBed.configureTestingModule({
      imports: [WordsFeedComponent],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
      ],
    }).compileComponents();
  });

  it('resolves theme-aware presets, legacy aliases, and language fonts', () => {
    expect(BACKGROUND_PRESETS.length).toBe(10);
    expect(getPreset('mountain_dawn').id).toBe('gradient_celestial_dawn');
    expect(getPreset('ocean_calm').id).toBe('gradient_living_waters');

    const minimal = getPreset('true_minimalist');
    expect(resolvePresetCssBackground(minimal, true)).toBe('#000000');
    expect(resolvePresetCssBackground(minimal, false)).toBe('#FFFFFF');

    expect(getLanguageForVersion('taobvsi')).toBe('tam');
    expect(getLanguageForVersion('hin_irv')).toBe('hin');
    expect(getLanguageForVersion('kjv')).toBe('en');

    expect(getFontsForLanguage('tam').some((f) => f.id === 'MuktaMalar')).toBe(true);
    expect(getFontsForLanguage('en').some((f) => f.id === 'Playfair')).toBe(true);
  });

  it('maps language preferences to Bible versions and caps dropdown selections at 3', () => {
    expect(LANGUAGE_TO_BIBLE_VERSIONS['ta']).toEqual(['taobvsi', 'tam_tcv']);
    expect(LANGUAGE_TO_BIBLE_VERSIONS['en']).toContain('nasb');
    expect(LANGUAGE_TO_BIBLE_VERSIONS['en']).toContain('niv');

    const taOnly = getVersionsForLanguages(['ta']);
    expect(taOnly.preferred.map((v) => v.id)).toEqual(['taobvsi', 'tam_tcv']);
    expect(taOnly.others.some((v) => v.id === 'kjv')).toBe(true);

    const prefs = TestBed.inject(WordsPreferencesService);
    prefs.setVersion('nasb');
    prefs.toggleVersionSelection('kjv');
    prefs.toggleVersionSelection('web');
    prefs.toggleVersionSelection('asv'); // replaces last comparison, stays at 3 total
    expect(prefs.selectedVersions()).toEqual(['nasb', 'kjv', 'asv']);

    prefs.promoteVersionToPrimary('kjv');
    expect(prefs.selectedVersions()[0]).toBe('kjv');
    expect(prefs.selectedVersions().length).toBe(3);
  });

  it('counts active filters and persists per-language preferences & bookmarks', () => {
    expect(
      countActiveFilters({
        readingOrder: 'daily',
        activeTopic: 'daily',
        testamentFilter: 'all',
        bookNumberFilter: null,
        selectedCategories: [],
        selectedTags: [],
      }),
    ).toBe(0);

    expect(
      countActiveFilters({
        readingOrder: 'random',
        activeTopic: 'daily',
        testamentFilter: 'nt',
        bookNumberFilter: 43,
        selectedCategories: ['faith'],
        selectedTags: ['hope', 'promises'],
      }),
    ).toBe(6);

    const prefs = TestBed.inject(WordsPreferencesService);
    prefs.setVersion('kjv');
    prefs.setFontScale(1.3);
    expect(prefs.appearance().fontSizeScale).toBe(1.3);

    prefs.setVersion('taobvsi');
    expect(prefs.appearance().fontSizeScale).toBe(1.0);
    expect(prefs.appearance().activeFontFamily).toBe('MuktaMalar');

    const savedNow = prefs.toggleSave({
      id: '43_3_16_16',
      bookNumber: 43,
      bookName: 'John',
      chapter: 3,
      startVerse: 16,
      referenceLabel: 'John 3:16',
    });
    expect(savedNow).toBe(true);
    expect(prefs.isSaved('43_3_16_16')).toBe(true);
  });

  it('filters, sorts canonically, and hydrates primary + comparison versions', async () => {
    const releases = TestBed.inject(ReleaseDataService);
    const online = TestBed.inject(OnlineBibleService);
    const prefs = TestBed.inject(WordsPreferencesService);
    const service = TestBed.inject(WordsFeedService);

    prefs.setVersion('nasb');
    prefs.addComparisonVersion('kjv');
    prefs.addComparisonVersion('web');

    vi.spyOn(releases, 'getJson').mockImplementation(async (path: string) => {
      if (path === 'words_feed/manifest.json') {
        return { totalItems: 3, topTopics: [] };
      }
      if (path === 'scriptures.json') {
        return MOCK_SCRIPTURES;
      }
      if (path === 'bibles/kjv/43/3.json') {
        return [{ verse: 16, text: 'For God so loved the world (KJV)' }];
      }
      if (path === 'bibles/web/43/3.json') {
        return [{ verse: 16, text: 'For God so loved the world (WEB)' }];
      }
      if (path === 'bibles/kjv/45/8.json') {
        return [{ verse: 28, text: 'And we know that all things (KJV)' }];
      }
      if (path === 'bibles/web/45/8.json') {
        return [{ verse: 28, text: 'We know that all things (WEB)' }];
      }
      return [];
    });

    vi.spyOn(online, 'fetchChapter').mockImplementation(async (_v, book, ch) => {
      if (book === 43 && ch === 3) {
        return [{ verse: 16, text: 'For God so loved the world (NASB)' }];
      }
      if (book === 45 && ch === 8) {
        return [{ verse: 28, text: 'And we know that God causes (NASB)' }];
      }
      return [];
    });

    await service.applyFilterState({
      readingOrder: 'canonical',
      activeTopic: 'daily',
      testamentFilter: 'nt',
      bookNumberFilter: null,
      selectedCategories: [],
      selectedTags: [],
    });

    const items = service.items();
    expect(items.length).toBe(2);
    expect(items[0].referenceLabel).toBe('John 3:16');
    expect(items[0].verseText).toBe('For God so loved the world (NASB)');
    expect(items[0].comparisons).toEqual([
      { version: 'kjv', text: 'For God so loved the world (KJV)' },
      { version: 'web', text: 'For God so loved the world (WEB)' },
    ]);
    expect(items[1].referenceLabel).toBe('Romans 8:28');
  });

  it('keeps the latest version when an older request finishes last', async () => {
    const releases = TestBed.inject(ReleaseDataService);
    const prefs = TestBed.inject(WordsPreferencesService);
    const service = TestBed.inject(WordsFeedService);
    service.items.set([{ ...MOCK_SCRIPTURES[1], id: 'john', verseText: 'KJV', resolvedVersion: 'kjv' }]);

    let finishWeb!: (verses: { verse: number; text: string }[]) => void;
    vi.spyOn(releases, 'getJson').mockImplementation((path: string) => {
      if (path.includes('/web/')) return new Promise((resolve) => { finishWeb = resolve; });
      return Promise.resolve([{ verse: 16, text: 'ASV' }]);
    });
    prefs.setVersion('web');
    const older = service.rehydrateVersion(0);
    prefs.setVersion('asv');
    await service.rehydrateVersion(0);
    finishWeb([{ verse: 16, text: 'WEB' }]);
    await older;
    expect(service.items()[0].resolvedVersion).toBe('asv');
    expect(service.items()[0].verseText).toBe('ASV');
  });

  it('renders WordsFeedComponent and supports stepping font scale & bookmarks', async () => {
    const releases = TestBed.inject(ReleaseDataService);
    const prefs = TestBed.inject(WordsPreferencesService);
    prefs.setVersion('kjv');

    vi.spyOn(releases, 'getJson').mockImplementation(async (path: string) => {
      if (path === 'words_feed/manifest.json') {
        return { totalItems: 1, topTopics: [{ slug: 'faith', name: 'Faith', count: 1 }] };
      }
      if (path === 'words_feed/daily.json') {
        return [MOCK_SCRIPTURES[1]];
      }
      if (path === 'bibles/kjv/43/3.json') {
        return [{ verse: 16, text: 'For God so loved the world' }];
      }
      return [];
    });

    const fixture = TestBed.createComponent(WordsFeedComponent);
    const comp = fixture.componentInstance;
    fixture.detectChanges();
    await comp.words.initialize();
    fixture.detectChanges();

    expect(comp.currentItem()?.referenceLabel).toBe('John 3:16');
    expect(comp.currentItem()?.verseText).toBe('For God so loved the world');

    comp.stepFont(0.1);
    expect(prefs.appearance().fontSizeScale).toBe(1.1);

    comp.toggleSave(comp.currentItem()!);
    expect(comp.currentItem()?.isSaved).toBe(true);
  });
});
