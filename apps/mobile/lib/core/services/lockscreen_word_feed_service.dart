import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../../features/bible/services/bible_bookmark_service.dart';
import '../../features/engines/scripture/models/scripture_card.dart';
import '../../features/engines/scripture/models/scripture_filter_state.dart';
import '../../features/engines/scripture/scripture_engine.dart';
import '../../features/engines/scripture/services/book_name_service.dart';
import '../../features/engines/scripture/services/saved_scripture_service.dart';
import '../../features/engines/scripture/services/scripture_service.dart';
import 'notification_service.dart';

/// Manages the Lock Screen Word Feed notification.
///
/// Displays an ongoing public notification card directly on the Android lock screen,
/// automatically mirroring active filters (version, category, books, testament)
/// selected in the Word Feed (/words) page.
///
/// Provides quick action buttons right on the lock screen:
/// - ⏭️ Next Word: rotate immediately to the next card matching active filters.
/// - 📖 Read Chapter: deep links to the chapter & verse in Bible reader.
/// - ❤️ Bookmark: toggles saving the passage directly from the lock screen.
class LockScreenWordFeedService extends ChangeNotifier {
  static const int notificationId = 77701;
  static const String actionNextWord = 'action_next_word';
  static const String actionReadChapter = 'action_read_chapter';
  static const String actionBookmark = 'action_bookmark';

  static const String _prefKeyEnabled = 'lockscreen_wordfeed_enabled_v1';
  static const String _prefKeyInterval = 'lockscreen_wordfeed_interval_v1';
  static const String _prefKeyCurrentCard = 'lockscreen_wordfeed_current_card_v1';
  static const String _prefKeyCanonicalOffset = 'lockscreen_wordfeed_canonical_offset_v1';

  static LockScreenWordFeedService _instance =
      LockScreenWordFeedService._internal();
  factory LockScreenWordFeedService() => _instance;
  static LockScreenWordFeedService get instance => _instance;

  @visibleForTesting
  static set instanceForTesting(LockScreenWordFeedService service) {
    _instance = service;
  }

  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  final ScriptureService _scriptureService;
  final BibleBookmarkService _bookmarkService;

  bool _isEnabled = false;
  int _intervalMinutes = 60;
  ScriptureCard? _currentCard;
  bool _isCurrentBookmarked = false;
  Timer? _refreshTimer;
  bool _isRotating = false;

  bool get isEnabled => _isEnabled;
  int get intervalMinutes => _intervalMinutes;
  ScriptureCard? get currentCard => _currentCard;
  bool get isCurrentBookmarked => _isCurrentBookmarked;

  LockScreenWordFeedService._internal({
    FlutterLocalNotificationsPlugin? notificationsPlugin,
    ScriptureService? scriptureService,
    BibleBookmarkService? bookmarkService,
  })  : _notificationsPlugin =
            notificationsPlugin ?? NotificationService().plugin,
        _scriptureService = scriptureService ?? ScriptureService(),
        _bookmarkService = bookmarkService ?? BibleBookmarkService();

  @visibleForTesting
  LockScreenWordFeedService.forTesting({
    required FlutterLocalNotificationsPlugin notificationsPlugin,
    ScriptureService? scriptureService,
    BibleBookmarkService? bookmarkService,
  })  : _notificationsPlugin = notificationsPlugin,
        _scriptureService = scriptureService ?? ScriptureService(),
        _bookmarkService = bookmarkService ?? BibleBookmarkService();

  /// Loads saved state on startup and restores the lock screen card if enabled.
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_prefKeyEnabled) ?? false;
      _intervalMinutes = prefs.getInt(_prefKeyInterval) ?? 60;

      final cardJson = prefs.getString(_prefKeyCurrentCard);
      if (cardJson != null && cardJson.isNotEmpty) {
        try {
          _currentCard = ScriptureCard.fromJson(jsonDecode(cardJson));
          if (_currentCard != null) {
            _isCurrentBookmarked = await _checkIfBookmarked(_currentCard!);
          }
        } catch (_) {}
      }

      if (_isEnabled) {
        _startPeriodicTimer();
        if (_currentCard != null) {
          await _publishNotification(_currentCard!, isBookmarked: _isCurrentBookmarked);
        } else {
          await rotateNextWord();
        }
      }
    } catch (e) {
      debugPrint('LockScreenWordFeedService initialize error: $e');
    }
    notifyListeners();
  }

  /// Enables the lock screen word feed and publishes the initial card.
  Future<void> enable({int intervalMinutes = 60}) async {
    final wasEnabled = _isEnabled;
    final prevInterval = _intervalMinutes;
    _isEnabled = true;
    _intervalMinutes = intervalMinutes;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyEnabled, true);
    await prefs.setInt(_prefKeyInterval, intervalMinutes);

    _startPeriodicTimer();
    if (!wasEnabled || prevInterval != intervalMinutes || _currentCard == null) {
      await rotateNextWord();
    }
    notifyListeners();
  }

  /// Disables the lock screen word feed and dismisses the ongoing notification.
  Future<void> disable() async {
    _isEnabled = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyEnabled, false);

    try {
      await _notificationsPlugin.cancel(notificationId);
    } catch (e) {
      debugPrint('Error cancelling lock screen notification: $e');
    }
    notifyListeners();
  }

  /// Updates the periodic rotation interval.
  Future<void> setIntervalMinutes(int minutes) async {
    _intervalMinutes = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKeyInterval, minutes);

    if (_isEnabled) {
      _startPeriodicTimer();
    }
    notifyListeners();
  }

  void _startPeriodicTimer() {
    _refreshTimer?.cancel();
    if (_intervalMinutes <= 0) return; // 0 means manual refresh only

    _refreshTimer = Timer.periodic(
      Duration(minutes: _intervalMinutes),
      (_) => rotateNextWord(),
    );
  }

  /// Fetches and displays the next scripture card based on the active filters.
  Future<void> rotateNextWord([ScriptureFilterState? filterOverride]) async {
    if (_isRotating) return;
    _isRotating = true;

    try {
      await _scriptureService.initialize();

      final filters = filterOverride ?? ScriptureEngine().initialFilterState;
      final versionId = filters.activeVersionId;

      int page = 0;
      final isCanonical = filters.readingOrder == 'canonical';
      final prefs = await SharedPreferences.getInstance();
      if (isCanonical) {
        page = prefs.getInt(_prefKeyCanonicalOffset) ?? 0;
      }

      final cards = await _scriptureService.fetchCards(
        activeVersionId: versionId,
        page: page,
        limit: 1,
        bookFilter: filters.bookFilter,
        testamentFilter: filters.testamentFilter,
        categories: filters.selectedCategories.isNotEmpty
            ? filters.selectedCategories
            : null,
        tags: filters.selectedTags.isNotEmpty ? filters.selectedTags : null,
        order: filters.readingOrder,
      );

      if (cards.isNotEmpty) {
        final card = cards.first;
        await _scriptureService.resolveCardText(card, versionId);

        _currentCard = card;
        _isCurrentBookmarked = await _checkIfBookmarked(card);

        // Persist current card for crash resilience & offline viewing
        await prefs.setString(_prefKeyCurrentCard, jsonEncode(card.toJson()));
        if (isCanonical) {
          await prefs.setInt(_prefKeyCanonicalOffset, page + 1);
        }

        if (_isEnabled) {
          await _publishNotification(card, isBookmarked: _isCurrentBookmarked);
        }
      } else if (isCanonical && page > 0) {
        await prefs.setInt(_prefKeyCanonicalOffset, 0);
        await rotateNextWord(filterOverride);
        return;
      }
    } catch (e) {
      debugPrint('LockScreenWordFeedService rotateNextWord error: $e');
    } finally {
      _isRotating = false;
      notifyListeners();
    }
  }

  /// Toggles the bookmark status of the currently displayed word directly.
  Future<void> toggleBookmarkCurrentWord() async {
    if (_currentCard == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cardJson = prefs.getString(_prefKeyCurrentCard);
        if (cardJson != null && cardJson.isNotEmpty) {
          _currentCard = ScriptureCard.fromJson(jsonDecode(cardJson));
        }
      } catch (_) {}
    }
    final card = _currentCard;
    if (card == null) return;

    try {
      final versionId = card.resolvedVersion ??
          ScriptureEngine().initialFilterState.activeVersionId;

      final isBookmarked = await _bookmarkService.toggle(
        versionId: versionId,
        book: card.bookName,
        chapter: card.chapter,
        verse: card.startVerse,
        text: card.resolvedText ?? '',
      );

      try {
        final savedService = SavedScriptureService();
        await savedService.initialize();
        if (isBookmarked) {
          if (!savedService.isSaved(card.id)) {
            await savedService.toggleSave(card, versionId);
          }
        } else {
          if (savedService.isSaved(card.id)) {
            await savedService.removeCard(card.id);
          }
        }
      } catch (_) {}

      _isCurrentBookmarked = isBookmarked;
      card.isSaved = isBookmarked;

      if (_isEnabled) {
        await _publishNotification(card, isBookmarked: isBookmarked);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error toggling lock screen bookmark: $e');
    }
  }

  /// Called whenever Word Feed filters change to immediately synchronize the lock screen card.
  Future<void> onFilterStateChanged(ScriptureFilterState newFilters) async {
    if (!_isEnabled) return;
    await rotateNextWord(newFilters);
  }

  Future<bool> _checkIfBookmarked(ScriptureCard card) async {
    try {
      final savedService = SavedScriptureService();
      await savedService.initialize();
      if (savedService.isSaved(card.id)) return true;

      final versionId = card.resolvedVersion ??
          ScriptureEngine().initialFilterState.activeVersionId;
      return await _bookmarkService.isBookmarked(
        versionId,
        card.bookName,
        card.chapter,
        card.startVerse,
      );
    } catch (_) {
      return false;
    }
  }

  /// Publishes the rich ongoing public notification visible on the Android lock screen.
  Future<void> _publishNotification(
    ScriptureCard card, {
    required bool isBookmarked,
  }) async {
    final versionId = card.resolvedVersion ??
        ScriptureEngine().initialFilterState.activeVersionId;
    final title = '${card.referenceLabel} • $versionId';
    final text = card.resolvedText ?? '';
    final category = card.category.isNotEmpty ? card.category : 'Daily Bread';

    int bookNumber = card.bookNumber;
    int chapter = card.chapter;
    int verse = card.startVerse;
    String bookName = card.bookName;

    final mapping = card.verseMappings?[versionId];
    if (mapping is Map) {
      bookNumber = mapping['bookNumber'] ?? bookNumber;
      chapter = mapping['chapter'] ?? chapter;
      verse = mapping['startVerse'] ?? verse;
      bookName = mapping['bookName'] ?? BookNameService.englishNameFor(bookNumber);
    }

    // Deep link route payload into the Bible chapter & verse
    final payload =
        '/bible?book=${Uri.encodeComponent(bookName)}&chapter=$chapter&verse=$verse&version=${Uri.encodeComponent(versionId)}';

    final androidDetails = AndroidNotificationDetails(
      '${AppConfig.instanceId}_lockscreen_word_feed',
      'Lock Screen Scripture Feed',
      channelDescription:
          'Ongoing scripture feed displayed on your lock screen matching active Word Feed filters',
      importance: Importance.low,
      priority: Priority.low,
      // Public visibility ensures content is rendered on the lock screen without unlocking
      visibility: NotificationVisibility.public,
      ongoing: true,
      autoCancel: false,
      showWhen: true,
      styleInformation: BigTextStyleInformation(
        '“$text”',
        contentTitle: title,
        summaryText: category,
        htmlFormatContent: false,
        htmlFormatContentTitle: false,
      ),
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          actionNextWord,
          '⏭️ Next Word',
          showsUserInterface: false,
          cancelNotification: false,
        ),
        const AndroidNotificationAction(
          actionReadChapter,
          '📖 Read Chapter',
          showsUserInterface: true,
          cancelNotification: false,
        ),
        AndroidNotificationAction(
          actionBookmark,
          isBookmarked ? '❤️ Saved' : '🤍 Bookmark',
          showsUserInterface: false,
          cancelNotification: false,
        ),
      ],
    );

    final platformDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      notificationId,
      title,
      text,
      platformDetails,
      payload: payload,
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
