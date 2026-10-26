import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/core/services/lockscreen_word_feed_service.dart';
import 'package:mobile/core/models/user_preference.dart';
import 'package:mobile/core/services/user_preference_service.dart';
import 'package:mobile/features/bible/services/bible_bookmark_service.dart';
import 'package:mobile/features/engines/scripture/models/scripture_card.dart';
import 'package:mobile/features/engines/scripture/models/scripture_filter_state.dart';
import 'package:mobile/features/engines/scripture/services/scripture_service.dart';

class FakeFlutterLocalNotificationsPlugin extends Fake
    implements FlutterLocalNotificationsPlugin {
  int? lastCancelledId;
  int? lastShownId;
  String? lastShownTitle;
  String? lastShownBody;
  NotificationDetails? lastShownDetails;
  String? lastShownPayload;

  @override
  Future<void> cancel(int id, {String? tag}) async {
    lastCancelledId = id;
  }

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails, {
    String? payload,
  }) async {
    lastShownId = id;
    lastShownTitle = title;
    lastShownBody = body;
    lastShownDetails = notificationDetails;
    lastShownPayload = payload;
  }
}

class FakeScriptureService extends Fake implements ScriptureService {
  bool returnEmpty = false;
  ScriptureCard mockCard = ScriptureCard(
    id: 'test_card_1',
    bookName: 'John',
    bookNumber: 43,
    chapter: 3,
    startVerse: 16,
    endVerse: 16,
    referenceLabel: 'John 3:16',
    category: 'Salvation & Grace',
    resolvedText: 'For God so loved the world, that He gave His only begotten Son...',
    resolvedVersion: 'NASB',
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<List<ScriptureCard>> fetchCards({
    required String activeVersionId,
    int page = 0,
    int limit = 15,
    String? category,
    String? bookFilter,
    String? testamentFilter,
    List<String>? categories,
    List<String>? tags,
    String order = 'random',
  }) async {
    if (returnEmpty) return [];
    return [mockCard];
  }

  @override
  Future<void> resolveCardText(ScriptureCard card, String versionId) async {
    card.resolvedVersion = versionId;
  }
}

class FakeBibleBookmarkService extends Fake implements BibleBookmarkService {
  bool bookmarked = false;

  @override
  Future<bool> isBookmarked(
      String versionId, String book, int chapter, int verse) async {
    return bookmarked;
  }

  @override
  Future<bool> toggle({
    required String versionId,
    required String book,
    required int chapter,
    required int verse,
    required String text,
  }) async {
    bookmarked = !bookmarked;
    return bookmarked;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFlutterLocalNotificationsPlugin fakeNotifications;
  late FakeScriptureService fakeScriptureService;
  late FakeBibleBookmarkService fakeBookmarkService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeNotifications = FakeFlutterLocalNotificationsPlugin();
    fakeScriptureService = FakeScriptureService();
    fakeBookmarkService = FakeBibleBookmarkService();
    final service = LockScreenWordFeedService.forTesting(
      notificationsPlugin: fakeNotifications,
      scriptureService: fakeScriptureService,
      bookmarkService: fakeBookmarkService,
    );
    LockScreenWordFeedService.instanceForTesting = service;
  });

  group('LockScreenWordFeedService', () {
    test('enabling service starts rotation and displays public ongoing notification', () async {
      final service = LockScreenWordFeedService.forTesting(
        notificationsPlugin: fakeNotifications,
        scriptureService: fakeScriptureService,
        bookmarkService: fakeBookmarkService,
      );

      expect(service.isEnabled, isFalse);

      await service.enable(intervalMinutes: 30);

      expect(service.isEnabled, isTrue);
      expect(service.intervalMinutes, equals(30));
      expect(service.currentCard, isNotNull);
      expect(service.currentCard?.referenceLabel, equals('John 3:16'));

      // Verify notification details
      expect(fakeNotifications.lastShownId, equals(LockScreenWordFeedService.notificationId));
      expect(fakeNotifications.lastShownTitle, contains('John 3:16'));
      expect(fakeNotifications.lastShownPayload, contains('/bible?book=John&chapter=3&verse=16'));

      final androidDetails = fakeNotifications.lastShownDetails?.android;
      expect(androidDetails, isNotNull);
      expect(androidDetails?.channelId, equals(LockScreenWordFeedService.notificationChannelId));
      expect(androidDetails?.importance, equals(Importance.defaultImportance));
      expect(androidDetails?.priority, equals(Priority.defaultPriority));
      expect(androidDetails?.playSound, isFalse);
      expect(androidDetails?.enableVibration, isFalse);
      expect(androidDetails?.channelShowBadge, isFalse);
      expect(androidDetails?.visibility, equals(NotificationVisibility.public));
      expect(androidDetails?.ongoing, isTrue);
      expect(androidDetails?.actions, isNotNull);
      expect(androidDetails?.actions?.length, equals(3));
      expect(androidDetails?.actions?[0].id, equals(LockScreenWordFeedService.actionNextWord));
      expect(androidDetails?.actions?[1].id, equals(LockScreenWordFeedService.actionReadChapter));
      expect(androidDetails?.actions?[2].id, equals(LockScreenWordFeedService.actionBookmark));
    });

    test('disabling service cancels notification and clears state', () async {
      final service = LockScreenWordFeedService.forTesting(
        notificationsPlugin: fakeNotifications,
        scriptureService: fakeScriptureService,
        bookmarkService: fakeBookmarkService,
      );

      await service.enable(intervalMinutes: 60);
      expect(service.isEnabled, isTrue);

      await service.disable();
      expect(service.isEnabled, isFalse);
      expect(fakeNotifications.lastCancelledId, equals(LockScreenWordFeedService.notificationId));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('lockscreen_wordfeed_enabled_v1'), isFalse);
    });

    test('toggleBookmarkCurrentWord updates bookmark state and notification button', () async {
      final service = LockScreenWordFeedService.forTesting(
        notificationsPlugin: fakeNotifications,
        scriptureService: fakeScriptureService,
        bookmarkService: fakeBookmarkService,
      );

      await service.enable(intervalMinutes: 60);
      expect(service.isCurrentBookmarked, isFalse);

      // Bookmark
      await service.toggleBookmarkCurrentWord();
      expect(service.isCurrentBookmarked, isTrue);
      final action = fakeNotifications.lastShownDetails?.android?.actions?[2];
      expect(action?.title, contains('Saved'));

      // Toggle again to remove
      await service.toggleBookmarkCurrentWord();
      expect(service.isCurrentBookmarked, isFalse);
      final action2 = fakeNotifications.lastShownDetails?.android?.actions?[2];
      expect(action2?.title, contains('Bookmark'));
    });

    test('onFilterStateChanged rotates word when enabled', () async {
      final service = LockScreenWordFeedService.forTesting(
        notificationsPlugin: fakeNotifications,
        scriptureService: fakeScriptureService,
        bookmarkService: fakeBookmarkService,
      );

      await service.enable(intervalMinutes: 60);
      fakeNotifications.lastShownId = null;

      const newFilters = ScriptureFilterState(
        activeVersionId: 'TAOBVSI',
        selectedCategories: ['peace'],
      );

      await service.onFilterStateChanged(newFilters);
      expect(fakeNotifications.lastShownId, equals(LockScreenWordFeedService.notificationId));
      expect(fakeNotifications.lastShownTitle, contains('TAOBVSI'));
    });

    test('setIntervalMinutes updates schedule and persists', () async {
      final service = LockScreenWordFeedService.forTesting(
        notificationsPlugin: fakeNotifications,
        scriptureService: fakeScriptureService,
        bookmarkService: fakeBookmarkService,
      );

      await service.setIntervalMinutes(120);
      expect(service.intervalMinutes, equals(120));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('lockscreen_wordfeed_interval_v1'), equals(120));
    });

    test('initialize restores previously saved card and enabled state', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('lockscreen_wordfeed_enabled_v1', true);
      await prefs.setInt('lockscreen_wordfeed_interval_v1', 45);
      await prefs.setString(
        'lockscreen_wordfeed_current_card_v1',
        jsonEncode(fakeScriptureService.mockCard.toJson()),
      );

      final service = LockScreenWordFeedService.forTesting(
        notificationsPlugin: fakeNotifications,
        scriptureService: fakeScriptureService,
        bookmarkService: fakeBookmarkService,
      );

      await service.initialize();

      expect(service.isEnabled, isTrue);
      expect(service.intervalMinutes, equals(45));
      expect(service.currentCard?.referenceLabel, equals('John 3:16'));
      expect(fakeNotifications.lastShownId, equals(LockScreenWordFeedService.notificationId));
    });

    test('publishes immediate fallback seed card when offline DB returns empty cards', () async {
      fakeScriptureService.returnEmpty = true;
      final service = LockScreenWordFeedService.forTesting(
        notificationsPlugin: fakeNotifications,
        scriptureService: fakeScriptureService,
        bookmarkService: fakeBookmarkService,
      );

      await service.enable(intervalMinutes: 60);

      expect(service.isEnabled, isTrue);
      expect(service.currentCard, isNotNull);
      expect(service.currentCard?.referenceLabel, equals('John 3:16'));
      expect(service.currentCard?.resolvedText, contains('loved the world'));
      expect(fakeNotifications.lastShownId, equals(LockScreenWordFeedService.notificationId));
      expect(fakeNotifications.lastShownTitle, contains('John 3:16'));
    });

    test('checkAndRequestPermission returns true in test environment', () async {
      final service = LockScreenWordFeedService.forTesting(
        notificationsPlugin: fakeNotifications,
        scriptureService: fakeScriptureService,
        bookmarkService: fakeBookmarkService,
      );

      final hasPermission = await service.checkAndRequestPermission();
      expect(hasPermission, isTrue);
    });
  });

  group('UserPreferenceService LockScreen Integration', () {
    test('saving preferences with lockScreenWordFeedEnabled toggles LockScreenWordFeedService', () async {
      final prefService = UserPreferenceService.forTesting();

      const pref = UserPreference(
        lockScreenWordFeedEnabled: true,
        lockScreenRefreshIntervalMinutes: 30,
      );

      await prefService.savePreferences(pref, syncWithBackend: false);

      expect(prefService.preferences.lockScreenWordFeedEnabled, isTrue);
      expect(prefService.preferences.lockScreenRefreshIntervalMinutes, equals(30));
      expect(LockScreenWordFeedService.instance.isEnabled, isTrue);

      // Disable
      final disabledPref = pref.copyWith(lockScreenWordFeedEnabled: false);
      await prefService.savePreferences(disabledPref, syncWithBackend: false);

      expect(prefService.preferences.lockScreenWordFeedEnabled, isFalse);
      expect(LockScreenWordFeedService.instance.isEnabled, isFalse);
    });
  });
}
