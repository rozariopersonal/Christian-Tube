import { provideHttpClient } from '@angular/common/http';
import {
  HttpTestingController,
  provideHttpClientTesting,
} from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { AppConfig } from '../../core/config/app-config';
import { BibleService } from './services/bible.service';

describe('BibleService semantic search', () => {
  let service: BibleService;
  let httpMock: HttpTestingController;

  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    service = TestBed.inject(BibleService);
    httpMock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    httpMock.match((r) => r.url.includes('manifest.json'));
    httpMock.verify();
  });

  it('calls /api/bible/search and returns passage and verse hits', async () => {
    const promise = service.searchSemantic('jesus wept', 30);

    const req = httpMock.expectOne(
      (r) =>
        r.url === `${AppConfig.apiBaseUrl}/api/bible/search` &&
        r.params.get('q') === 'jesus wept' &&
        r.params.get('limit') === '30',
    );
    expect(req.request.method).toBe('GET');

    req.flush({
      query: 'jesus wept',
      count: 2,
      results: [
        {
          id: '43:11:35',
          score: 1.67,
          kind: 'verse',
          bookNumber: 43,
          bookName: 'John',
          chapter: 11,
          verse: 35,
          endVerse: null,
          reference: 'John 11:35',
          text: 'Jesus wept.',
        },
        {
          id: 'w:43:11:34-38',
          score: 1.27,
          kind: 'passage',
          bookNumber: 43,
          bookName: 'John',
          chapter: 11,
          verse: 34,
          endVerse: 38,
          reference: 'John 11:34-38',
          text: '34. Where have you laid him? 35. Jesus wept.',
        },
      ],
    });

    const res = await promise;
    expect(res.count).toBe(2);
    expect(res.results[0].reference).toBe('John 11:35');
    expect(res.results[1].kind).toBe('passage');
    expect(res.results[1].endVerse).toBe(38);
  });

  it('resolves displayed hits into another Bible version cleanly', async () => {
    const resolvePromise = service.resolveSearchHitsInVersion(
      [
        {
          bookNumber: 43,
          bookName: 'John',
          chapter: 11,
          verse: 34,
          endVerse: 35,
          reference: 'John 11:34-35',
          text: 'WEB original',
        },
      ],
      'kjv',
    );

    const manifestReqs = httpMock.match((r) => r.url.includes('manifest.json'));
    for (const m of manifestReqs) {
      m.flush({ revision: '1' });
    }
    await new Promise((r) => setTimeout(r, 0));

    const req = httpMock.expectOne((r) =>
      r.url.includes('bibles/kjv/43/11.json'),
    );
    req.flush([
      { verse: 34, text: 'And said, Where have ye laid him?' },
      { verse: 35, text: 'Jesus wept.' },
    ]);

    const localized = await resolvePromise;
    expect(localized[0].text).toBe(
      '34. And said, Where have ye laid him? 35. Jesus wept.',
    );
  });
});
