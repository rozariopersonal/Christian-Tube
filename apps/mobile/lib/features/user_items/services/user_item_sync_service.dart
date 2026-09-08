import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile/core/api/api_client.dart';
import 'package:mobile/features/auth/auth_service.dart';
import 'package:mobile/features/bible/models/bible_bookmark.dart';
import 'package:mobile/features/bible/models/bible_highlight.dart';
import 'package:mobile/features/bible/services/bible_bookmark_service.dart';
import 'package:mobile/features/bible/services/bible_highlight_service.dart';
import 'package:mobile/shared/annotations/user_item.dart';
import 'package:mobile/shared/annotations/user_item_repository.dart';
import 'package:mobile/shared/models/note.dart';
import 'package:mobile/shared/services/note_service.dart';

/// Orchestrates per-user annotation persistence: the authenticated tier of the
/// highlights / bookmarks / notes stores and sync with the backend database.
///
/// **Two-tier storage rule** (AGENTS.md-compatible, user contract):
/// - Pre-auth: device-local only (never uploaded — highlights live in the
///   bible SQLite/prefs store, bookmarks and notes in their device stores).
/// - Authenticated: every item becomes a [UserItem] row scoped by `user_id` in
///   the local `user_items` database AND is synchronized to the backend
///   (`POST/GET /user/items`). On sign-in, device-local data is re-homed into
///   the account (UUIDs/createdAt preserved, `updatedAt` bumped so it wins),
///   pushed, then the device stores are cleared.
///
/// Sync contract: items mutate `updated_at` (LWW conflict key). Writes are
/// pushed when `updated_at > lastSyncedAt` (per-user cursor in prefs). Pulls
/// use `after=<cursor>` and merge by [DateTime]-LWW; soft-deleted (`deleted`)
/// notes are tombstoned through push, then purged locally after ack. All
/// network failures degrade silently — the local user tier stays fully usable
/// offline and sync resumes on the next trigger.
class UserItemSyncService {
  UserItemSyncService._();

  static final UserItemSyncService instance = UserItemSyncService._();

  final ApiClient _apiClient = ApiClient();
  final UserItemRepository _repository = UserItemRepository.instance;

  AuthService? _auth;
  String? _currentUserId;
  bool _attached = false;
  bool _pushing = false;
  Timer? _pushDebounce;
  final Set<String> _rehomeLock = <String>{};

  /// The signed-in account id, or null when in the pre-auth device tier.
  String? get currentUserId => _currentUserId;

  /// Whether facades should route through the per-user `user_items` store.
  bool get isUserTierActive => _currentUserId != null && _currentUserId!.isNotEmpty;

  @visibleForTesting
  void setUserIdForTest(String? userId) => _currentUserId =
      (userId == null || userId.isEmpty) ? null : userId;

  /// Subscribes to [auth] so sign-in/out drives re-home + sync. Call once from
  /// app bootstrap. Safe to call repeatedly.
  void attachTo(AuthService auth) {
    _auth = auth;
    if (_attached) return;
    _attached = true;
    auth.addListener(_onAuthChanged);
    // Late-bound so AuthService's async storage restore is captured too.
    Future<void>.microtask(_onAuthChanged);
  }

  Future<void> _onAuthChanged() async {
    final user = _auth?.currentUser;
    final userId = user?.id ?? '';
    if (userId == _currentUserId && userId.isNotEmpty) return;

    // Snapshot the device tier BEFORE routing flips to the user tier.
    var deviceHighlights = <BibleHighlight>[];
    var deviceBookmarks = <BibleBookmark>[];
    var deviceNotes = <Note>[];
    try {
      deviceHighlights = await BibleHighlightService().loadDeviceHighlights();
      deviceBookmarks = await BibleBookmarkService().loadDeviceBookmarks();
      deviceNotes = await NoteService.instance.loadAllDeviceNotes();
    } catch (e) {
      debugPrint('UserItemSyncService device snapshot warning: $e');
    }

    _currentUserId = (userId.isEmpty) ? null : userId;
    if (_currentUserId == null) return;

    unawaited(_rehomeAndSync(userId, deviceHighlights, deviceBookmarks, deviceNotes));
  }

  Future<void> _rehomeAndSync(
    String userId,
    List<BibleHighlight> deviceHighlights,
    List<BibleBookmark> deviceBookmarks,
    List<Note> deviceNotes,
  ) async {
    if (!_rehomeLock.add(userId)) return;
    try {
      final items = <UserItem>[
        ...deviceHighlights.map((h) => UserItem.fromBibleHighlight(h, userId)),
        ...deviceBookmarks.map((b) => UserItem.fromBibleBookmark(b, userId)),
        ...deviceNotes.map((n) => UserItem.fromNote(n, userId)),
      ];
      if (items.isNotEmpty) {
        final now = DateTime.now().toUtc();
        await _repository.insertOrReplace(
            userId, items.map((i) => i.copyWith(updatedAt: now)).toList());
        await BibleHighlightService().clearDeviceHighlights();
        await BibleBookmarkService().clearDeviceBookmarks();
        await NoteService.instance.clearDeviceNotes();
      }
      await _pushDirty(userId);
      await _pullAndMerge(userId);
    } catch (e) {
      debugPrint('UserItemSyncService re-home warning: $e');
    } finally {
      _rehomeLock.remove(userId);
    }
  }

  /// Debounced hook for facades after any user-tier write.
  void schedulePush() {
    if (!isUserTierActive) return;
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(seconds: 4), () {
      final userId = _currentUserId;
      if (userId == null) return;
      unawaited(_pushDirty(userId));
    });
  }

  Future<String?> _loadCursor(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_items_cursor_v1_$userId');
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  Future<void> _saveCursor(String userId, DateTime cursor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'user_items_cursor_v1_$userId', cursor.toUtc().toIso8601String());
  }

  Future<void> _pushDirty(String userId) async {
    if (_pushing) return;
    _pushing = true;
    try {
      final rawCursor = await _loadCursor(userId);
      final since = DateTime.tryParse(rawCursor ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final dirty = await _repository.loadDirtySince(userId, since);
      if (dirty.isEmpty) return;

      await _apiClient.dio.post('/user/items', data: {
        'userId': userId,
        'userEmail': _auth?.currentUser?.email,
        'items': dirty.map((i) => i.toJson()).toList(),
      });

      DateTime maxTs = since;
      for (final i in dirty) {
        if (i.updatedAt.isAfter(maxTs)) maxTs = i.updatedAt;
      }
      await _saveCursor(userId, maxTs);
      await _repository.purgeTombstones(userId);
    } catch (e) {
      debugPrint('UserItemSyncService push non-blocking warning: $e');
    } finally {
      _pushing = false;
    }
  }

  Future<void> _pullAndMerge(String userId) async {
    final rawCursor = await _loadCursor(userId);
    try {
      final response = await _apiClient.dio.get('/user/items', queryParameters: {
        'userId': userId,
        if (rawCursor != null) 'after': rawCursor,
      });
      if (response.statusCode != 200 || response.data == null) return;
      final data = response.data as Map<String, dynamic>;
      final rawItems = data['items'] as List<dynamic>? ?? const [];
      final remote = rawItems
          .map((e) => UserItem.fromJson(e as Map<String, dynamic>))
          .where((i) => i.userId == userId)
          .toList();
      if (remote.isEmpty) return;

      final local = await _repository.loadAll(userId);
      final localById = <String, UserItem>{for (final i in local) i.id: i};

      final toUpsert = <UserItem>[];
      final toDelete = <String>[];
      for (final r in remote) {
        if (r.deleted) {
          toDelete.add(r.id);
          continue;
        }
        final l = localById[r.id];
        if (l == null || !r.updatedAt.isBefore(l.updatedAt)) {
          toUpsert.add(r.copyWith(userId: userId));
        }
      }
      for (final id in toDelete) {
        await _repository.remove(userId, id);
      }
      if (toUpsert.isNotEmpty) {
        await _repository.insertOrReplace(userId, toUpsert);
      }

      final cursorRaw = data['updatedAt'] as String?;
      final cursor = DateTime.tryParse(cursorRaw ?? '');
      if (cursor != null) {
        final current = DateTime.tryParse(rawCursor ?? '');
        if (current == null || cursor.isAfter(current)) {
          await _saveCursor(userId, cursor);
        }
      }
    } catch (e) {
      debugPrint('UserItemSyncService pull non-blocking warning: $e');
    }
  }
}