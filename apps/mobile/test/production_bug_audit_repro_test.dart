import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile/core/api/api_client.dart';
import 'package:mobile/core/models/short.dart';
import 'package:mobile/core/models/user_preference.dart';
import 'package:mobile/core/models/video.dart';
import 'package:mobile/core/navigation/navigation_history_service.dart';
import 'package:mobile/core/services/lockscreen_word_feed_service.dart';
import 'package:mobile/core/services/user_preference_service.dart';
import 'package:mobile/core/services/user_sync_service.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/articles/services/article_sync_service.dart';
import 'package:mobile/features/articles/services/articles_download_manager.dart';
import 'package:mobile/features/audio/adapters/sqlite_audio_catalog_adapter.dart';
import 'package:mobile/features/audio/controllers/audio_library_controller.dart';
import 'package:mobile/features/audio/controllers/audio_player_controller.dart';
import 'package:mobile/features/audio/models/audio_series.dart';
import 'package:mobile/features/audio/models/audio_track.dart';
import 'package:mobile/features/audio/services/audio_catalog_service.dart';
import 'package:mobile/features/audio/services/audio_download_service.dart';
import 'package:mobile/features/audio/services/audio_local_library.dart';
import 'package:mobile/features/audio/services/audio_playback_service.dart';
import 'package:mobile/features/audio/services/audio_storage_service.dart';
import 'package:mobile/features/audio/services/audio_sync_service.dart';
import 'package:mobile/features/auth/auth_service.dart';
import 'package:mobile/features/auth/services/auth_session_client.dart';
import 'package:mobile/features/auth/services/auth_token_store.dart';
import 'package:mobile/features/auth/services/refresh_coordinator.dart';
import 'package:mobile/features/bible/services/bible_bookmark_service.dart';
import 'package:mobile/features/books/controllers/book_reader_controller.dart';
import 'package:mobile/features/books/models/book.dart';
import 'package:mobile/features/books/models/book_chapter.dart';
import 'package:mobile/features/books/models/book_highlight.dart';
import 'package:mobile/features/books/models/book_line.dart';
import 'package:mobile/features/books/models/user_reading_progress.dart';
import 'package:mobile/features/books/services/book_highlight_ranges.dart';
import 'package:mobile/features/books/services/book_service.dart';
import 'package:mobile/features/channels/channel_service.dart';
import 'package:mobile/features/dictionary/services/dictionary_download_manager.dart';
import 'package:mobile/features/downloads/controllers/downloads_controller.dart';
import 'package:mobile/features/downloads/models/storage_breakdown.dart';
import 'package:mobile/features/downloads/services/storage_calculator_service.dart';
import 'package:mobile/features/engines/scripture/models/scripture_card.dart';
import 'package:mobile/features/engines/scripture/models/scripture_filter_state.dart';
import 'package:mobile/features/engines/scripture/services/bible_download_manager.dart';
import 'package:mobile/features/engines/scripture/services/scripture_service.dart';
import 'package:mobile/features/profile/user_service.dart';
import 'package:mobile/features/songs/services/songs_download_manager.dart';
import 'package:mobile/features/update/update_service.dart';
import 'package:mobile/layout/main_layout_screen.dart';
import 'package:mobile/shared/annotations/user_item.dart';
import 'package:mobile/shared/services/library_languages_controller.dart';

// ---------------------------------------------------------------------------
// Fakes & Mocks
// ---------------------------------------------------------------------------

class _MockDio extends Mock implements Dio {}

class _MockHttpClientAdapter extends Mock implements HttpClientAdapter {}

class _MockAuthSessionClient extends Mock implements AuthSessionClient {}

class _MockAuthService extends Mock implements AuthService {}

class _MockChannelService extends Mock implements ChannelService {}

class _MockAudioCatalogService extends Mock implements AudioCatalogService {}

class _MockSqliteAudioCatalogAdapter extends Mock
    implements SqliteAudioCatalogAdapter {}

class _MockAudioSyncService extends Mock implements AudioSyncService {}

class _MockAudioLocalLibrary extends Mock implements AudioLocalLibrary {}

class _MockBookService extends Mock implements BookService {}

class _MockBibleDownloadManager extends Mock implements BibleDownloadManager {}

class _MockDictionaryDownloadManager extends Mock
    implements DictionaryDownloadManager {}

class _MockSongsDownloadManager extends Mock implements SongsDownloadManager {}

class _MockArticlesDownloadManager extends Mock
    implements ArticlesDownloadManager {}

class _MockStorageCalculatorService extends Mock
    implements StorageCalculatorService {}

class _MockFlutterLocalNotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {}

class _MockScriptureService extends Mock implements ScriptureService {}

class _MockBibleBookmarkService extends Mock implements BibleBookmarkService {}

class _FakeRequestOptions extends Fake implements RequestOptions {}

class _FakeAudioTrack extends Fake implements AudioTrack {}

class _FakeScriptureCard extends Fake implements ScriptureCard {}

class _FakeAudioPlaybackService implements AudioPlaybackService {
  final posCtrl = StreamController<Duration>.broadcast();
  final durCtrl = StreamController<Duration?>.broadcast();
  final bufCtrl = StreamController<Duration>.broadcast();
  final stateCtrl = StreamController<PlayerState>.broadcast();
  final speedCtrl = StreamController<double>.broadcast();
  final errCtrl = StreamController<PlayerException>.broadcast();

  final List<String> loadedTrackIds = [];
  final List<int> loadedStartPositions = [];
  int playCalls = 0;
  int pauseCalls = 0;
  bool _playing = false;
  ProcessingState _processingState = ProcessingState.idle;
  Duration _position = Duration.zero;
  final Duration _duration = const Duration(seconds: 120);

  @override
  Stream<Duration> get positionStream => posCtrl.stream;
  @override
  Stream<Duration?> get durationStream => durCtrl.stream;
  @override
  Stream<Duration> get bufferedPositionStream => bufCtrl.stream;
  @override
  Stream<PlayerState> get playerStateStream => stateCtrl.stream;
  @override
  Stream<double> get speedStream => speedCtrl.stream;
  @override
  Stream<PlayerException> get errorStream => errCtrl.stream;

  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  bool get isPlaying => _playing;
  @override
  PlayerState get playerState => PlayerState(_playing, _processingState);
  @override
  ProcessingState get processingState => _processingState;

  @override
  Future<Duration?> loadTrack(AudioTrack track,
      {int initialPositionSec = 0}) async {
    loadedTrackIds.add(track.id);
    loadedStartPositions.add(initialPositionSec);
    _position = Duration(seconds: initialPositionSec);
    _processingState = ProcessingState.ready;
    _playing = false;
    return _duration;
  }

  @override
  Future<void> play() async {
    playCalls++;
    _playing = true;
    stateCtrl.add(PlayerState(true, _processingState));
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _playing = false;
    // Matches just_audio: pausing while completed emits (false, completed).
    stateCtrl.add(PlayerState(false, _processingState));
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _processingState = ProcessingState.idle;
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
  }

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {
    await posCtrl.close();
    await durCtrl.close();
    await bufCtrl.close();
    await stateCtrl.close();
    await speedCtrl.close();
    await errCtrl.close();
  }

  void emitCompleted() {
    _playing = true;
    _processingState = ProcessingState.completed;
    stateCtrl.add(PlayerState(true, ProcessingState.completed));
  }
}

AudioTrack _makeTrack(String id, String title) => AudioTrack(
      id: id,
      seriesId: 'series-1',
      seriesTitle: 'Series 1',
      speaker: 'Speaker',
      title: title,
      streamUrl: 'https://example.com/$id.mp3',
      audioUrl: 'https://example.com/$id.mp3',
      durationSeconds: 180,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_FakeRequestOptions());
    registerFallbackValue(_FakeAudioTrack());
    registerFallbackValue(_FakeScriptureCard());
    registerFallbackValue(const ScriptureFilterState());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthTokenStore.instance.resetForTesting();
  });

  // =========================================================================
  // 1. SHORTS: Published community-clipped Short is unplayable
  // =========================================================================
  test(
      'BUG 1 (Shorts): Published 11-char YouTube Short must start at 0s, not source sermon offset',
      () {
    final short = Short.fromJson({
      'id': 'dQw4w9WgXcQ', // 11-char uploaded YouTube Short ID
      'title': 'Clipped Sermon Highlight',
      'videoUrl': 'https://youtube.com/shorts/dQw4w9WgXcQ',
      'thumbnailUrl': 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      'channelId': 'ch1',
      'channelTitle': 'Grace Channel',
      'publishedAt': '2026-11-20T00:00:00Z',
      'duration': '1:00',
      'type': 'SHORT',
      'sourceVideoId': 'origSermon1',
      'clipStartTime': 720.0,
      'clipEndTime': 780.0,
      'cropOffsetX': 0.25,
    });

    expect(short.playableVideoId, 'dQw4w9WgXcQ');
    expect(short.playableStartSeconds, 0);
    expect(short.playableEndSeconds, isNull);
    expect(short.isClippedSermon, isFalse);
  });

  // =========================================================================
  // 2. AUDIO: Sleep Timer "End of current track" fails and skips to Track 2
  // =========================================================================
  test(
      'BUG 2 (Audio): Sleep timer stopAtEndOfTrack must pause and NOT auto-skip to track 2',
      () async {
    final fakePlayback = _FakeAudioPlaybackService();
    final storage = AudioStorageService();
    final mockSync = _MockAudioSyncService();
    when(() => mockSync.pushPlayback(
          track: any(named: 'track'),
          positionSeconds: any(named: 'positionSeconds'),
          durationSeconds: any(named: 'durationSeconds'),
          force: any(named: 'force'),
          updatedAt: any(named: 'updatedAt'),
        )).thenAnswer((_) async {});
    when(() => mockSync.pullPlayback()).thenAnswer((_) async => null);

    final controller = AudioPlayerController(
      playbackService: fakePlayback,
      storageService: storage,
      syncService: mockSync,
    );
    final t1 = _makeTrack('t1', 'Track 1');
    final t2 = _makeTrack('t2', 'Track 2');

    await controller.playTrack(t1, queue: [t1, t2]);
    controller.setSleepTimer(null, stopAtEndOfTrack: true);

    fakePlayback.emitCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(controller.state.currentTrack?.id, 't1',
        reason: 'Sleep timer at end of track must NOT advance to Track 2');
    expect(fakePlayback.loadedTrackIds, ['t1'],
        reason: 'Track 2 must never be loaded when stopAtEndOfTrack is active');

    controller.dispose();
    await fakePlayback.dispose();
  });

  // =========================================================================
  // 3. AUDIO: Cross-device cloud sync plays old Track A when tapping Play
  // =========================================================================
  test(
      'BUG 3 (Audio): Tapping Play after cross-device cloud sync must load synced Track B, not resume stale Track A',
      () async {
    final fakePlayback = _FakeAudioPlaybackService();
    final storage = AudioStorageService();
    final mockSync = _MockAudioSyncService();
    final tA = _makeTrack('trackA', 'Old Phone Track');
    final tB = _makeTrack('trackB', 'New Web Track');

    when(() => mockSync.pushPlayback(
          track: any(named: 'track'),
          positionSeconds: any(named: 'positionSeconds'),
          durationSeconds: any(named: 'durationSeconds'),
          force: any(named: 'force'),
          updatedAt: any(named: 'updatedAt'),
        )).thenAnswer((_) async {});
    when(() => mockSync.pullPlayback()).thenAnswer(
      (_) async => RemotePlaybackRecord(
        track: tB,
        positionSeconds: 90,
        durationSeconds: 180,
        updatedAt: DateTime.utc(2027, 1, 1),
      ),
    );

    final controller = AudioPlayerController(
      playbackService: fakePlayback,
      storageService: storage,
      syncService: mockSync,
    );

    await controller.playTrack(tA, queue: [tA]);
    await controller.pause();
    expect(fakePlayback.processingState, ProcessingState.ready);

    await controller.syncWithCloud();
    expect(controller.state.currentTrack?.id, 'trackB');

    await controller.togglePlayPause();

    expect(fakePlayback.loadedTrackIds.last, 'trackB',
        reason:
            'Audio engine must load synced Track B instead of resuming Track A');
    expect(fakePlayback.loadedStartPositions.last, 90);

    controller.dispose();
    await fakePlayback.dispose();
  });

  // =========================================================================
  // 4. AUDIO: Trailing space in search query silently drops backend search results
  // =========================================================================
  test(
      'BUG 4 (Audio): Trailing space in search query must not discard backend search results',
      () async {
    final mockCatalog = _MockAudioCatalogService();
    final storage = AudioStorageService();
    final mockChannels = _MockChannelService();
    final langCtrl = LibraryLanguagesController();

    const matchedSeries = AudioSeries(
      id: 's1',
      title: 'Sermons on Grace',
      description: '',
      speaker: 'Speaker',
      coverUrl: '',
      trackCount: 3,
      category: 'Foundations',
      language: 'English',
    );

    when(() => mockChannels.subscribedChannelIds).thenReturn({});
    when(() => mockChannels.subscribedChannelNames).thenReturn({});
    when(() => mockChannels.addListener(any())).thenReturn(null);
    when(() => mockChannels.removeListener(any())).thenReturn(null);
    final mockLocal = _MockSqliteAudioCatalogAdapter();
    when(() => mockLocal.fetchCatalog()).thenAnswer((_) async => []);
    when(() => mockCatalog.localAdapter).thenReturn(mockLocal);
    when(() => mockCatalog.getCatalog()).thenAnswer((_) async => []);
    when(() => mockCatalog.search('grace'))
        .thenAnswer((_) async => [matchedSeries]);

    final controller = AudioLibraryController(
      catalogService: mockCatalog,
      storageService: storage,
      langController: langCtrl,
      channelService: mockChannels,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    controller.setSearchQuery('grace ');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(controller.state.asyncSearchResults, isNotNull,
        reason:
            'Backend search results must not be discarded due to trailing space');
    expect(controller.state.asyncSearchResults?.length, 1);

    controller.dispose();
    langCtrl.dispose();
  });

  // =========================================================================
  // 5. AUDIO DOWNLOADS: syncFromDisk wipes active downloading/queued status
  // =========================================================================
  test(
      'BUG 5 (Audio Downloads): syncFromDisk must preserve in-flight downloading/queued entries',
      () async {
    final mockLib = _MockAudioLocalLibrary();
    when(() => mockLib.localUriFor(any())).thenAnswer((_) async => null);
    when(() => mockLib.pathFor(any())).thenAnswer((_) async => '/tmp/fake.mp3');
    when(() => mockLib.registerDownloaded(any())).thenAnswer((_) async {});

    final service = AudioDownloadService(library: mockLib);
    final t1 = _makeTrack('dl1', 'Sermon 1');
    final t2 = _makeTrack('dl2', 'Sermon 2');

    unawaited(service.downloadTracks([t1, t2]));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(service.isDownloading('dl2'), isTrue);

    await service.syncFromDisk([t1, t2]);

    expect(service.isDownloading('dl2'), isTrue,
        reason:
            'syncFromDisk must not overwrite queued/downloading tracks with idle');

    service.cancelDownload('dl1');
    service.cancelDownload('dl2');
  });

  // =========================================================================
  // 6. BOOKS & ARTICLES: Signed-in highlights lose startOffset/endOffset -> 0..0
  // =========================================================================
  test(
      'BUG 6 (Books/Articles): UserItem.copyWith and toMap/fromMap must preserve startOffset & endOffset for highlights',
      () {
    final item = UserItem(
      userId: 'u1',
      id: 'book_range_1_1',
      itemType: UserItem.typeTextRange,
      feature: UserItem.featureBook,
      targetId: 'book-1',
      chapter: 1,
      verseStart: 3,
      verseEnd: 3,
      startOffset: 5,
      endOffset: 16,
      text: 'hello world',
      createdAt: DateTime.utc(2026, 11, 26),
      updatedAt: DateTime.utc(2026, 11, 26),
    );

    final copied = item.copyWith(userId: 'u1');
    expect(copied.startOffset, 5, reason: 'copyWith must preserve startOffset');
    expect(copied.endOffset, 16, reason: 'copyWith must preserve endOffset');

    final roundTripped = UserItem.fromMap(item.toMap());
    expect(roundTripped.startOffset, 5,
        reason: 'SQLite map must preserve startOffset');
    expect(roundTripped.endOffset, 16,
        reason: 'SQLite map must preserve endOffset');

    const line = BookLine(
      bookId: 'book-1',
      pageNumber: 1,
      lineNumber: 1,
      chapterIndex: 1,
      text: '01234hello world6789',
    );
    final projected = BookHighlightRanges.project(
      '01234hello world6789',
      [line],
      [
        BookHighlight(
          id: roundTripped.id,
          bookId: 'book-1',
          chapterIndex: 1,
          pageNumber: 1,
          startChar: roundTripped.startOffset,
          endChar: roundTripped.endOffset,
          text: 'hello world',
          createdAt: '2026-11-26T00:00:00Z',
        ),
      ],
    );
    expect(projected, isNotEmpty);
  });

  // =========================================================================
  // 7. BOOKS: "Start Over" in Resume Reading dialog is ignored
  // =========================================================================
  test(
      'BUG 7 (Books): Navigating to /books/:id?page=1 (Start Over) must start at page 1, not resume page 10',
      () async {
    final mockBookService = _MockBookService();
    const book = Book(
      id: 'b1',
      title: 'Test Book',
      author: 'Author',
      description: 'Desc',
      coverFile: 'cover.jpg',
      language: 'en',
      totalPages: 20,
      totalLines: 400,
      createdAt: '2026-01-01T00:00:00Z',
    );
    when(() => mockBookService.getBook('b1')).thenAnswer((_) async => book);
    when(() => mockBookService.getChapters('b1')).thenAnswer((_) async => [
          const BookChapter(
            bookId: 'b1',
            chapterIndex: 1,
            chapterTitle: 'Ch 1',
            startPage: 1,
            startLine: 1,
            endPage: 20,
            endLine: 50,
          ),
        ]);
    when(() => mockBookService.getProgress('b1')).thenAnswer(
      (_) async => const UserReadingProgress(
        bookId: 'b1',
        currentPage: 10,
        currentLine: 40,
        completionPercent: 0.5,
        lastReadAt: '2026-11-25T00:00:00Z',
      ),
    );
    when(() => mockBookService.getPageLines('b1', any())).thenAnswer(
      (_) async => [
        const BookLine(
          bookId: 'b1',
          pageNumber: 1,
          lineNumber: 1,
          chapterIndex: 1,
          text: 'Line 1',
        ),
      ],
    );
    when(() => mockBookService.getHighlightsForBook('b1'))
        .thenAnswer((_) async => []);
    when(() => mockBookService.saveProgress(any(), any(), any(), any()))
        .thenAnswer((_) async {});

    final controller = BookReaderController(
      mockBookService,
      'b1',
      initialPage: 1,
      initialLine: null,
    );
    await controller.load();

    expect(controller.state.currentPage, 1,
        reason:
            'Start Over (?page=1) must open page 1 instead of resuming saved page 10');

    controller.dispose();
  });

  // =========================================================================
  // 8. DOWNLOADS: All 6 Language Offline Packs never show as installed/Ready
  // =========================================================================
  test(
      'BUG 8 (Downloads): Language Offline Packs must recognize uppercase Bible IDs as installed',
      () async {
    final mockBible = _MockBibleDownloadManager();
    final mockDict = _MockDictionaryDownloadManager();
    final mockBook = _MockBookService();
    final mockSongs = _MockSongsDownloadManager();
    final mockArticles = _MockArticlesDownloadManager();
    final mockAudioLib = _MockAudioLocalLibrary();
    final mockStorage = _MockStorageCalculatorService();

    when(() => mockBible.addListener(any())).thenReturn(null);
    when(() => mockBible.removeListener(any())).thenReturn(null);
    when(() => mockBible.refreshInstalledList()).thenAnswer((_) async {});
    when(() => mockBible.installedIds).thenReturn({'TAOBVSI'});
    when(() => mockBible.downloadingIds).thenReturn({});
    when(() => mockBible.isInstalled(any())).thenAnswer(
      (inv) => const {'TAOBVSI'}.contains(inv.positionalArguments[0] as String),
    );
    when(() => mockBible.isDownloading(any())).thenReturn(false);

    when(() => mockDict.addListener(any())).thenReturn(null);
    when(() => mockDict.removeListener(any())).thenReturn(null);
    when(() => mockDict.initialize()).thenAnswer((_) async {});
    when(() => mockDict.installedIds).thenReturn({'ta_glossary'});
    when(() => mockDict.downloadingIds).thenReturn({});
    when(() => mockDict.isInstalled('ta_glossary')).thenReturn(true);
    when(() => mockDict.isDownloading(any())).thenReturn(false);

    when(() => mockArticles.addListener(any())).thenReturn(null);
    when(() => mockArticles.removeListener(any())).thenReturn(null);
    when(() => mockArticles.initialize()).thenAnswer((_) async {});
    when(() => mockArticles.installedLanguages).thenReturn({'ta'});
    when(() => mockArticles.downloadingLanguages).thenReturn({});
    when(() => mockArticles.isInstalled('ta')).thenReturn(true);
    when(() => mockArticles.isDownloading(any())).thenReturn(false);

    when(() => mockBook.addListener(any())).thenReturn(null);
    when(() => mockBook.removeListener(any())).thenReturn(null);
    when(() => mockBook.initialize()).thenAnswer((_) async {});
    when(() => mockBook.isInstalled()).thenAnswer((_) async => false);
    when(() => mockBook.isDownloading).thenReturn(false);
    when(() => mockBook.downloadProgress).thenReturn(0.0);
    when(() => mockBook.getInstalledBookIds()).thenAnswer((_) async => {});
    when(() => mockBook.getCatalogFromAsset()).thenAnswer((_) async => []);

    when(() => mockSongs.addListener(any())).thenReturn(null);
    when(() => mockSongs.removeListener(any())).thenReturn(null);
    when(() => mockSongs.initialize()).thenAnswer((_) async {});
    when(() => mockSongs.isInstalled).thenReturn(false);
    when(() => mockSongs.isDownloading).thenReturn(false);
    when(() => mockSongs.downloadProgress).thenReturn(0.0);

    when(() => mockStorage.calculateBreakdown(
          bibleManager: any(named: 'bibleManager'),
          dictManager: any(named: 'dictManager'),
          bookService: any(named: 'bookService'),
          songsManager: any(named: 'songsManager'),
          articlesManager: any(named: 'articlesManager'),
        )).thenAnswer((_) async => const StorageBreakdown());
    when(() => mockStorage.scanDownloadedAudioSeries())
        .thenAnswer((_) async => []);

    final controller = DownloadsController(
      bibleManager: mockBible,
      dictManager: mockDict,
      bookService: mockBook,
      songsManager: mockSongs,
      articlesManager: mockArticles,
      audioLibrary: mockAudioLib,
      storageService: mockStorage,
    );

    expect(controller.isLanguagePackInstalled('ta'), isTrue,
        reason:
            'Tamil pack has TAOBVSI + ta_glossary + ta articles installed and must report Ready');

    controller.dispose();
  });

  // =========================================================================
  // 9. SYNC: UserSyncService stays permanently frozen after transient 401
  // =========================================================================
  test(
      'BUG 9 (Sync): UserSyncService.pullAndFlush(force: true) must recover after transient 401',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.com'));
    final adapter = _MockHttpClientAdapter();
    dio.httpClientAdapter = adapter;

    int callCount = 0;
    when(() => adapter.fetch(any(), any(), any())).thenAnswer((inv) async {
      callCount++;
      if (callCount == 1) {
        return ResponseBody.fromString('{"message":"Unauthorized"}', 401,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            });
      }
      return ResponseBody.fromString(
        jsonEncode({
          'serverTime': DateTime.now().millisecondsSinceEpoch,
          'preferences': {'defaultPage': 'bible'},
          'subscriptions': [],
          'subscriptionTombstones': [],
          'watchLater': [],
          'videoHistory': [],
          'videoPlayheads': [],
          'audioPlayback': [],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    final sync = UserSyncService.forTesting(dio: dio, canSyncCheck: () => true);
    sync.setActiveUserForTesting('user-1');

    await sync.pullAndFlush(force: true);
    expect(callCount, 1);

    await sync.pullAndFlush(force: true);

    expect(callCount, 2,
        reason:
            'pullAndFlush(force: true) must resume syncing once auth recovers instead of staying permanently frozen');
  });

  // =========================================================================
  // 10. AUTH/STARTUP: Unauthenticated 401 falsely marks signed-out user sessionExpired
  // =========================================================================
  test(
      'BUG 10 (Auth): 401 on an unauthenticated request must NOT mark signed-out user as sessionExpired',
      () async {
    final store = AuthTokenStore.instance;
    final mockSessionClient = _MockAuthSessionClient();
    final coordinator = RefreshCoordinator.forTesting(
      store: store,
      client: mockSessionClient,
    );

    bool? listenerExpired;
    coordinator.addSessionListener(({required bool expired}) {
      listenerExpired = expired;
    });

    final apiClient = ApiClient(
      tokenStore: store,
      refreshCoordinator: coordinator,
    );
    final adapter = _MockHttpClientAdapter();
    apiClient.dio.httpClientAdapter = adapter;
    when(() => adapter.fetch(any(), any(), any())).thenAnswer(
      (_) async => ResponseBody.fromString('{"message":"Unauthorized"}', 401,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          }),
    );

    try {
      await apiClient.dio.get('/user/playlists');
    } on DioException catch (_) {}

    expect(await store.readSessionExpired(), isFalse,
        reason:
            'Signed-out user with no token must NOT be flagged sessionExpired=true');
    expect(listenerExpired, isNull);
  });

  // =========================================================================
  // 11. PREFERENCES: Following a channel drops sync when channelSelectionsConfigured == false
  // =========================================================================
  test(
      'BUG 11 (Preferences): syncChannelFollowState must enqueue channel list even when channelSelectionsConfigured was false',
      () async {
    final prefService = UserPreferenceService.forTesting(
      initial: const UserPreference(
        channelSelectionsConfigured: false,
        videoChannelIds: [],
      ),
    );
    UserSyncService.instance.setActiveUserForTesting('user-1');

    await prefService.syncChannelFollowState('ch-grace', true);

    final hasVideoChannelOp = UserSyncService.instance.pendingOps.values.any(
      (op) => op.kind == 'preference' && op.prefField == 'videoChannelIds',
    );
    expect(hasVideoChannelOp, isTrue,
        reason: 'Following a channel must sync videoChannelIds to backend');
  });

  // =========================================================================
  // 12. LOCKSCREEN: Recursive rotateNextWord deadlocks on empty-bookmarks fallback
  // =========================================================================
  test(
      'BUG 12 (Lockscreen): rotateNextWord empty-bookmarks fallback must not deadlock on _isRotating guard',
      () async {
    final mockNotifs = _MockFlutterLocalNotificationsPlugin();
    final mockScripture = _MockScriptureService();
    final mockBookmarks = _MockBibleBookmarkService();

    final fallbackCard = ScriptureCard(
      id: 'card-1',
      bookNumber: 43,
      bookName: 'John',
      chapter: 3,
      startVerse: 16,
      endVerse: 16,
      referenceLabel: 'John 3:16',
      category: 'Love',
      resolvedText: 'For God so loved the world...',
    );

    when(() => mockScripture.initialize()).thenAnswer((_) async {});
    when(() => mockScripture.resolveCardText(any(), any()))
        .thenAnswer((_) async => 'For God so loved the world...');
    when(() => mockScripture.fetchCards(
          activeVersionId: any(named: 'activeVersionId'),
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          bookFilter: any(named: 'bookFilter'),
          testamentFilter: any(named: 'testamentFilter'),
          categories: any(named: 'categories'),
          tags: any(named: 'tags'),
          order: any(named: 'order'),
        )).thenAnswer((inv) async {
      final order = inv.namedArguments[#order] as String?;
      if (order == 'bookmarked') return [];
      return [fallbackCard];
    });
    when(() => mockBookmarks.isBookmarked(any(), any(), any(), any()))
        .thenAnswer((_) async => false);

    final service = LockScreenWordFeedService.forTesting(
      notificationsPlugin: mockNotifs,
      scriptureService: mockScripture,
      bookmarkService: mockBookmarks,
    );

    await service
        .rotateNextWord(const ScriptureFilterState(readingOrder: 'bookmarked'));

    expect(service.currentCard?.id, 'card-1',
        reason:
            'Fallback to random card must succeed instead of hitting _isRotating deadlock');
  });

  // =========================================================================
  // 13. UPDATE SERVICE: Non-Dio FileSystemException crashes with uncaught TypeError
  // =========================================================================
  test(
      'BUG 13 (Updates): Non-Dio FileSystemException during APK download must invoke onError, not throw TypeError',
      () async {
    final mockDio = _MockDio();
    when(() => mockDio.download(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
          deleteOnError: any(named: 'deleteOnError'),
          onReceiveProgress: any(named: 'onReceiveProgress'),
        )).thenThrow(const FileSystemException('No space left on device'));

    String? reportedError;
    Object? uncaught;
    try {
      await UpdateService.downloadAndInstallApkWithProgress(
        downloadUrl: 'https://example.com/app.apk',
        onProgress: (_, __) {},
        onComplete: (_) {},
        onError: (err) => reportedError = err,
        maxRetryDuration: const Duration(milliseconds: 50),
        retryDelay: const Duration(milliseconds: 10),
        dioOverride: mockDio,
      );
    } catch (e) {
      uncaught = e;
    }

    expect(uncaught, isNull,
        reason:
            'CancelToken.isCancel(e as dynamic) must not throw TypeError on FileSystemException');
    expect(reportedError, isNotNull);
  });

  // =========================================================================
  // 14. NAVIGATION: Pushing /profile corrupts NavigationHistoryService & traps Back
  // =========================================================================
  testWidgets(
      'BUG 14 (Navigation): Pushing /profile from /feed and pressing Back twice must exit from /feed, not bounce back to /profile',
      (tester) async {
    NavigationHistoryService.instance.reset();
    NavigationHistoryService.instance.setInitialTab('/feed');

    final mockAuth = _MockAuthService();
    when(() => mockAuth.currentUser).thenReturn(null);
    when(() => mockAuth.isAuthenticated).thenReturn(false);
    when(() => mockAuth.sessionExpired).thenReturn(false);
    when(() => mockAuth.addListener(any())).thenReturn(null);
    when(() => mockAuth.removeListener(any())).thenReturn(null);

    final router = GoRouter(
      initialLocation: '/feed',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              MainLayoutScreen(authService: mockAuth, child: child),
          routes: [
            GoRoute(
              path: '/feed',
              builder: (_, __) =>
                  const Scaffold(body: Center(child: Text('FEED'))),
            ),
            GoRoute(
              path: '/profile',
              builder: (_, __) =>
                  const Scaffold(body: Center(child: Text('PROFILE'))),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        theme: ThemeData(extensions: const [AppTokens.light]),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('FEED'), findsOneWidget);

    // Push /profile (exact call made by AccountSyncPanel "Profile & Settings")
    router.push('/profile');
    await tester.pumpAndSettle();
    expect(find.text('PROFILE'), findsOneWidget);

    // Back #1: pops /profile -> returns to /feed
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('FEED'), findsOneWidget);

    // Back #2 on /feed: should stay on /feed with exit prompt, NOT jump back to /profile!
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('FEED'), findsOneWidget,
        reason:
            'Second back press on /feed must stay on /feed with exit prompt, not ping-pong to /profile');
    expect(find.text('PROFILE'), findsNothing);
  });

  // =========================================================================
  // 15. WATCH HISTORY: clearHistory() never enqueues tombstones -> resurrects
  // =========================================================================
  test(
      'BUG 15 (Watch History): clearHistory() must enqueue video_history tombstones so cleared videos do not resurrect on sync',
      () async {
    UserSyncService.instance.setActiveUserForTesting('user-1');
    final userService = UserService();
    await userService.addToHistory(
      Video.fromJson({
        'id': 'vid-1',
        'title': 'Sermon 1',
        'thumbnailUrl': 'https://img.youtube.com/vi/vid-1/hqdefault.jpg',
        'channelId': 'ch1',
        'channelTitle': 'Grace',
        'publishedAt': '2026-11-20T00:00:00Z',
      }),
    );

    await userService.clearHistory();

    final hasTombstone = UserSyncService.instance.pendingOps.values.any(
      (op) =>
          op.kind == 'watch_item' &&
          op.itemType == 'video_history' &&
          op.itemId == 'vid-1' &&
          op.isDeleted == true,
    );
    expect(hasTombstone, isTrue,
        reason:
            'clearHistory() must enqueue isDeleted=true tombstones instead of calling non-existent DELETE /user/history');
  });

  // =========================================================================
  // 16. ARTICLES (WEB): ArticleSyncService.getArticle() throws before CDN when filesystem unavailable
  // =========================================================================
  test(
      'BUG 16 (Articles): ArticleSyncService.getArticle() must not throw MissingPluginException before reaching CDN when filesystem is unavailable',
      () async {
    Object? thrown;
    try {
      await ArticleSyncService().getArticle('art-1', lang: 'en');
    } catch (e) {
      thrown = e;
    }
    expect(thrown, isNot(isA<MissingPluginException>()),
        reason:
            'getArticle() must guard _getCacheDirectory() on Web / unavailable path_provider instead of throwing MissingPluginException');
  });
}
