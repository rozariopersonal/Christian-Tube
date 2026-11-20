import { provideHttpClient } from '@angular/common/http';
import {
  HttpTestingController,
  provideHttpClientTesting,
} from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { AuthService } from '../auth/auth.service';
import { BookHighlightsService } from '../../features/books/services/book-highlights.service';
import { UserItemsSyncService } from './user-items-sync.service';

describe('UserItemsSyncService & BookHighlightsService', () => {
  let httpMock: HttpTestingController;
  let authService: AuthService;
  let itemsSync: UserItemsSyncService;
  let bookHighlights: BookHighlightsService;

  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    httpMock = TestBed.inject(HttpTestingController);
    authService = TestBed.inject(AuthService);
    itemsSync = TestBed.inject(UserItemsSyncService);
    bookHighlights = TestBed.inject(BookHighlightsService);
  });

  afterEach(() => {
    httpMock.verify();
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('enqueues and flushes free-form text_range highlights for books and articles', async () => {
    authService.currentUser.set({
      id: 'user-1',
      email: 'u1@example.com',
      displayName: 'U1',
    });
    TestBed.flushEffects();
    await Promise.resolve();

    const stateReq = httpMock.expectOne((r) => r.url.endsWith('/api/user/state'));
    stateReq.flush({ serverTime: Date.now() });
    const itemsReq = httpMock.expectOne((r) => r.url.endsWith('/api/user/items'));
    itemsReq.flush({ serverTime: Date.now(), items: [] });
    await Promise.resolve();

    bookHighlights.addRange(
      'article:art-1:en',
      2,
      4,
      15,
      'amazing grace',
      '#FEF08A',
      'Key quote',
    );

    const postReq = httpMock.expectOne(
      (r) => r.url.endsWith('/api/user/items') && r.method === 'POST',
    );
    const posted = postReq.request.body.items[0];
    expect(posted).toMatchObject({
      itemType: 'text_range',
      feature: 'article',
      targetId: 'article:art-1:en',
      verseStart: 2,
      startOffset: 4,
      endOffset: 15,
      text: 'amazing grace',
      contextText: 'Key quote',
      deleted: false,
    });
    postReq.flush({ results: [{ id: posted.id, status: 'ok' }] });
    await Promise.resolve();

    expect(Object.keys(itemsSync.pendingItems())).toHaveLength(0);
  });

  it('clears book & bible local caches on signOut', () => {
    localStorage.setItem('book_highlights_u1', '{}');
    localStorage.setItem('reader_text_highlights_u1', '{}');
    localStorage.setItem('bible_highlights_u1', '{}');
    localStorage.setItem('ct_web_user_items_pending_v1_u1', '{}');

    authService.signOut();

    expect(localStorage.getItem('book_highlights_u1')).toBeNull();
    expect(localStorage.getItem('reader_text_highlights_u1')).toBeNull();
    expect(localStorage.getItem('bible_highlights_u1')).toBeNull();
    expect(localStorage.getItem('ct_web_user_items_pending_v1_u1')).toBeNull();
  });
});
