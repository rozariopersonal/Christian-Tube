import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

class SyncOp {
  final String opId;
  final String userId;
  final String kind; // 'watch_item' | 'subscription' | 'preference'
  final String? itemType;
  final String itemId;
  final int? positionSeconds;
  final int? durationSeconds;
  final String? payloadJson;
  final bool isDeleted;
  final bool? isActive;
  final String? prefField;
  final dynamic prefValue;
  final int clientUpdatedAt;

  const SyncOp({
    required this.opId,
    required this.userId,
    required this.kind,
    this.itemType,
    required this.itemId,
    this.positionSeconds,
    this.durationSeconds,
    this.payloadJson,
    this.isDeleted = false,
    this.isActive,
    this.prefField,
    this.prefValue,
    required this.clientUpdatedAt,
  });

  Map<String, dynamic> toJson() => {
        'opId': opId,
        'userId': userId,
        'kind': kind,
        if (itemType != null) 'itemType': itemType,
        'itemId': itemId,
        if (positionSeconds != null) 'positionSeconds': positionSeconds,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
        if (payloadJson != null) 'payloadJson': payloadJson,
        'isDeleted': isDeleted,
        if (isActive != null) 'isActive': isActive,
        if (prefField != null) 'prefField': prefField,
        if (prefValue != null) 'prefValue': prefValue,
        'clientUpdatedAt': clientUpdatedAt,
      };

  factory SyncOp.fromJson(Map<String, dynamic> json) => SyncOp(
        opId: json['opId'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
        kind: json['kind'] as String? ?? 'watch_item',
        itemType: json['itemType'] as String?,
        itemId: json['itemId'] as String? ?? '',
        positionSeconds: (json['positionSeconds'] as num?)?.toInt(),
        durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
        payloadJson: json['payloadJson'] as String?,
        isDeleted: json['isDeleted'] == true,
        isActive: json['isActive'] as bool?,
        prefField: json['prefField'] as String?,
        prefValue: json['prefValue'],
        clientUpdatedAt: (json['clientUpdatedAt'] as num?)?.toInt() ?? 0,
      );
}

class UserSyncService extends ChangeNotifier {
  static const String likedVideoType = 'liked_video';
  static const String likedShortType = 'liked_short';
  static final UserSyncService instance = UserSyncService._internal();
  factory UserSyncService() => instance;

  final Dio _dio;

  UserSyncService._internal({Dio? dio}) : _dio = dio ?? ApiClient().dio {
    _loadClockOffset();
  }

  @visibleForTesting
  UserSyncService.forTesting({Dio? dio}) : _dio = dio ?? ApiClient().dio;

  @visibleForTesting
  void setActiveUserForTesting(String userId) {
    _activeUserId = userId;
    _authPaused = false;
  }

  static const String _keyClockOffset = 'mobile_clock_offset_v1';
  static const String _keyPendingPrefix = 'mobile_sync_pending_v2_';
  static const String _keyLastGuestId = 'mobile_last_guest_id_v1';

  int _clockOffsetMs = 0;
  String? _activeUserId;
  bool _authPaused = false;
  DateTime? _lastPullAt;
  Future<void>? _inFlightSync;
  Timer? _retryTimer;
  int _retryDelayMs = 2000;

  Map<String, dynamic>? _remoteState;
  int _acknowledgementVersion = 0;
  int _operationSequence = 0;
  Future<void> _outboxFlush = Future.value();
  Map<String, SyncOp> _pendingOps = {};

  Map<String, dynamic>? get remoteState => _remoteState;
  Map<String, SyncOp> get pendingOps => Map.unmodifiable(_pendingOps);
  String? get activeUserId => _activeUserId;
  int get acknowledgementVersion => _acknowledgementVersion;

  Set<String> likedIds(String itemType) {
    final ids = <String>{
      for (final item in likedItems(itemType))
        if (item['id'] is String) item['id'] as String,
    };
    final tombstoneKey = itemType == likedVideoType
        ? 'likedVideoTombstones'
        : 'likedShortTombstones';
    final tombstones = _remoteState?[tombstoneKey];
    if (tombstones is Map) {
      for (final id in tombstones.keys) { ids.remove(id.toString()); }
    }
    for (final op in _pendingOps.values) {
      if (op.kind != 'watch_item' || op.itemType != itemType) continue;
      if (op.isDeleted) {
        ids.remove(op.itemId);
      } else {
        ids.add(op.itemId);
      }
    }
    return ids;
  }

  List<Map<String, dynamic>> likedItems(String itemType) {
    final itemsById = <String, Map<String, dynamic>>{};
    final itemsKey = itemType == likedVideoType ? 'likedVideos' : 'likedShorts';
    final tombstoneKey = itemType == likedVideoType
        ? 'likedVideoTombstones'
        : 'likedShortTombstones';
    final rows = _remoteState?[itemsKey];
    if (rows is List) {
      for (final row in rows.whereType<Map>()) {
        final video = row['video'];
        if (video is Map && video['id'] != null) {
          final id = video['id'].toString();
          itemsById[id] = Map<String, dynamic>.from(video)..['id'] = id;
        }
      }
    }
    final tombstones = _remoteState?[tombstoneKey];
    if (tombstones is Map) {
      for (final id in tombstones.keys) {
        itemsById.remove(id.toString());
      }
    }
    for (final op in _pendingOps.values) {
      if (op.kind != 'watch_item' || op.itemType != itemType) continue;
      if (op.isDeleted) {
        itemsById.remove(op.itemId);
      } else {
        itemsById.putIfAbsent(op.itemId, () => {'id': op.itemId});
      }
    }
    return itemsById.values.toList(growable: false);
  }

  bool isLiked(String itemType, String itemId) =>
      itemId.isNotEmpty && likedIds(itemType).contains(itemId);

  Future<void> setLiked({
    required String itemType,
    required String itemId,
    required bool liked,
  }) async {
    final state = _remoteState;
    if (state != null) {
      final isVideo = itemType == likedVideoType;
      final itemsKey = isVideo ? 'likedVideos' : 'likedShorts';
      final tombstonesKey =
          isVideo ? 'likedVideoTombstones' : 'likedShortTombstones';
      final rows = ((state[itemsKey] as List?) ?? const [])
          .whereType<Map>()
          .where((row) => (row['video'] as Map?)?['id']?.toString() != itemId)
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final tombstones = Map<String, dynamic>.from(
        (state[tombstonesKey] as Map?) ?? const {},
      );
      final timestamp = nowServerAligned();
      if (liked) {
        tombstones.remove(itemId);
        rows.insert(0, {'video': {'id': itemId}, 'likedAt': timestamp});
      } else {
        tombstones[itemId] = timestamp;
      }
      _remoteState = {...state, itemsKey: rows, tombstonesKey: tombstones};
      notifyListeners();
    }
    await enqueueWatchItem(
      itemType: itemType,
      itemId: itemId,
      isDeleted: !liked,
    );
    unawaited(pullAndFlush(force: true));
  }

  int nowServerAligned() => DateTime.now().millisecondsSinceEpoch + _clockOffsetMs;

  Future<void> _loadClockOffset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _clockOffsetMs = prefs.getInt(_keyClockOffset) ?? 0;
    } catch (_) {}
  }

  Future<void> clearAllDeviceData() async {
    await onUserChanged(null);
    try {
      final prefs = await SharedPreferences.getInstance();
      const exactKeys = [
        _keyClockOffset,
        _keyLastGuestId,
        'subscribed_channel_ids',
        'user_watch_history_v1',
        'video_playheads_map_v1',
      ];
      for (final k in exactKeys) {
        await prefs.remove(k);
      }
      final allKeys = prefs.getKeys().toList();
      for (final k in allKeys) {
        if (k.startsWith(_keyPendingPrefix) || k.startsWith('video_playhead_')) {
          await prefs.remove(k);
        }
      }
    } catch (_) {}
  }

  Future<void> onUserChanged(String? userId) async {
    if (userId == null || userId.isEmpty) {
      _activeUserId = null;
      _authPaused = false;
      _remoteState = null;
      _pendingOps = {};
      _retryTimer?.cancel();
      _retryTimer = null;
      notifyListeners();
      return;
    }

    final changed = _activeUserId != userId;
    _activeUserId = userId;
    _authPaused = false;

    final prefs = await SharedPreferences.getInstance();
    if (userId.startsWith('user_') || userId.startsWith('guest_')) {
      await prefs.setString(_keyLastGuestId, userId);
    } else {
      await _handoffGuestPendingOps(prefs, userId);
    }

    if (changed) {
      _pendingOps = _readPendingMap(prefs, userId);
      _remoteState = null;
      notifyListeners();
      unawaited(pullAndFlush(force: true));
    }
  }

  Future<void> enqueueSubscription(String channelId, bool isActive) =>
      enqueueSubscriptions({channelId: isActive});

  Future<void> enqueueSubscriptions(Map<String, bool> changes) async {
    final userId = _activeUserId;
    if (userId == null || changes.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (_activeUserId != userId) return;
    final pending = _readPendingMap(prefs, userId);
    for (final entry in changes.entries) {
      if (entry.key.isEmpty) continue;
      final key = 'sub:${entry.key}';
      pending[key] = SyncOp(
        opId: '$key:${DateTime.now().microsecondsSinceEpoch}:${_operationSequence++}',
        userId: userId,
        kind: 'subscription',
        itemId: entry.key,
        isActive: entry.value,
        clientUpdatedAt: nowServerAligned(),
      );
    }
    await _writePendingMap(prefs, userId, pending);
    unawaited(flushOutbox());
  }

  Future<void> enqueuePreference(String field, dynamic value) =>
      enqueuePreferences({field: value});

  Future<void> enqueuePreferences(Map<String, dynamic> fields) async {
    final userId = _activeUserId;
    if (userId == null || fields.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (_activeUserId != userId) return;
    final pending = _readPendingMap(prefs, userId);
    final timestamp = nowServerAligned();
    for (final entry in fields.entries) {
      final field = entry.key;
      if (field.isEmpty) continue;
      final key = 'pref:$field';
      pending[key] = SyncOp(
        opId: '$key:${DateTime.now().microsecondsSinceEpoch}:${_operationSequence++}',
        userId: userId,
        kind: 'preference',
        itemId: field,
        prefField: field,
        prefValue: entry.value,
        clientUpdatedAt: timestamp,
      );
    }
    await _writePendingMap(prefs, userId, pending);
    unawaited(flushOutbox());
  }

  Future<void> enqueueWatchItem({
    required String itemType,
    required String itemId,
    int positionSeconds = 0,
    int durationSeconds = 0,
    String? payloadJson,
    bool isDeleted = false,
  }) async {
    final userId = _activeUserId;
    if (userId == null || userId.isEmpty || itemId.isEmpty) return;
    final key = '$itemType:$itemId';
    final op = SyncOp(
      opId: '$key:${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      kind: 'watch_item',
      itemType: itemType,
      itemId: itemId,
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      payloadJson: payloadJson,
      isDeleted: isDeleted,
      clientUpdatedAt: nowServerAligned(),
    );
    await _saveOp(userId, key, op);
    unawaited(flushOutbox());
  }

  Future<void> pullAndFlush({bool force = false}) async {
    final userId = _activeUserId;
    if (userId == null || userId.isEmpty) return;

    final now = DateTime.now();
    if (!force &&
        _lastPullAt != null &&
        now.difference(_lastPullAt!).inSeconds < 15) {
      return;
    }
    if (_inFlightSync != null) return _inFlightSync!;

    _lastPullAt = now;
    final future = () async {
      try {
        await flushOutbox();
        if (_authPaused) return;
        final version = _acknowledgementVersion;
        final res = await _dio.get('/api/user/state');
        if (res.statusCode == 200 && res.data is Map) {
          final data = Map<String, dynamic>.from(res.data as Map);
          final serverTime = (data['serverTime'] as num?)?.toInt();
          if (serverTime != null && serverTime > 0) {
            _clockOffsetMs =
                serverTime - DateTime.now().millisecondsSinceEpoch;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt(_keyClockOffset, _clockOffsetMs);
          }
          if (_activeUserId == userId && version == _acknowledgementVersion) {
            _remoteState = data;
            notifyListeners();
          }
          _retryDelayMs = 2000;
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          _authPaused = true;
        }
      } catch (e) {
        debugPrint('UserSyncService pullAndFlush warning: $e');
      } finally {
        _inFlightSync = null;
      }
    }();
    _inFlightSync = future;
    return future;
  }

  Future<void> flushOutbox() {
    final userId = _activeUserId;
    if (userId == null) return Future.value();
    _outboxFlush = _outboxFlush.then((_) async {
      if (_activeUserId != userId || _authPaused) return;
      try {
        await _flushOutbox(userId);
      } catch (error) {
        debugPrint('UserSyncService outbox warning: $error');
        _scheduleRetry();
      }
    });
    return _outboxFlush;
  }

  Future<void> _flushOutbox(String userId) async {

    final prefs = await SharedPreferences.getInstance();
    final currentMap = _readPendingMap(prefs, userId);
    if (currentMap.isEmpty) return;

    final watchOps = <MapEntry<String, SyncOp>>[];
    final prefOps = <MapEntry<String, SyncOp>>[];
    final subOps = <MapEntry<String, SyncOp>>[];

    for (final entry in currentMap.entries) {
      if (entry.value.userId != userId) continue;
      if (entry.value.kind == 'watch_item') watchOps.add(entry);
      if (entry.value.kind == 'preference') prefOps.add(entry);
      if (entry.value.kind == 'subscription') subOps.add(entry);
    }

    final keysToRemove = <String>{};
    final acknowledgedSubscriptions = <SyncOp>[];
    Map<String, dynamic>? acknowledgedPreferences;
    var shouldRetry = false;

    if (watchOps.isNotEmpty) {
      try {
        final res = await _dio.post('/api/user/watch-items/batch', data: {
          'items': watchOps
              .map((e) => {
                    'opId': e.value.opId,
                    'itemType': e.value.itemType,
                    'itemId': e.value.itemId,
                    'positionSeconds': e.value.positionSeconds ?? 0,
                    'durationSeconds': e.value.durationSeconds ?? 0,
                    'payloadJson': e.value.payloadJson,
                    'isDeleted': e.value.isDeleted,
                    'clientUpdatedAt': e.value.clientUpdatedAt,
                  })
              .toList(),
        });
        final results = (res.data is Map ? res.data['results'] : null) as List?;
        final statusByOpId = <String, String>{};
        if (results != null) {
          for (final r in results.whereType<Map>()) {
            final id = r['opId'] as String?;
            final st = r['status'] as String?;
            if (id != null && st != null) statusByOpId[id] = st;
          }
        }
        for (final entry in watchOps) {
          final st = statusByOpId[entry.value.opId];
          if (st == 'ok' || st == 'rejected') {
            keysToRemove.add(entry.key);
          } else {
            shouldRetry = true;
          }
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          _authPaused = true;
          return;
        }
        if (_isPermanentClientError(e.response?.statusCode)) {
          for (final entry in watchOps) {
            keysToRemove.add(entry.key);
          }
        } else {
          shouldRetry = true;
        }
      }
    }

    if (_activeUserId != userId) return;
    if (prefOps.isNotEmpty) {
      final body = <String, dynamic>{};
      final fieldTimestamps = <String, int>{};
      for (final entry in prefOps) {
        final f = entry.value.prefField;
        if (f != null && f.isNotEmpty) {
          body[f] = entry.value.prefValue;
          fieldTimestamps[f] = entry.value.clientUpdatedAt;
        }
      }
      body['fieldTimestamps'] = fieldTimestamps;

      try {
        final response = await _dio.patch('/api/user/preferences', data: body);
        if (response.data is Map) {
          acknowledgedPreferences = Map<String, dynamic>.from(response.data as Map);
        }
        for (final entry in prefOps) {
          keysToRemove.add(entry.key);
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          _authPaused = true;
          return;
        }
        if (_isPermanentClientError(e.response?.statusCode)) {
          for (final entry in prefOps) {
            keysToRemove.add(entry.key);
          }
        } else {
          shouldRetry = true;
        }
      }
    }

    for (final entry in subOps) {
      if (_activeUserId != userId) return;
      try {
        final op = entry.value;
        if (op.isActive == true) {
          await _dio.post('/api/channels/${op.itemId}/subscribe', data: {
            'clientUpdatedAt': op.clientUpdatedAt,
          });
        } else {
          await _dio.delete(
            '/api/channels/${op.itemId}/subscribe',
            queryParameters: {'clientUpdatedAt': op.clientUpdatedAt},
          );
        }
        acknowledgedSubscriptions.add(op);
        keysToRemove.add(entry.key);
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          _authPaused = true;
          return;
        }
        if (_isPermanentClientError(e.response?.statusCode)) {
          keysToRemove.add(entry.key);
        } else {
          shouldRetry = true;
        }
      }
    }

    if (_activeUserId == userId && keysToRemove.isNotEmpty) {
      final latestMap = _readPendingMap(prefs, userId);
      if (_activeUserId == userId &&
          (acknowledgedSubscriptions.isNotEmpty || acknowledgedPreferences != null)) {
        _acknowledgementVersion++;
        final remote = _remoteState;
        if (remote != null) {
          final ids = (remote['subscriptions'] as List?)?.whereType<String>().toSet();
          if (ids != null) {
            for (final op in acknowledgedSubscriptions) {
              if (op.isActive == true) {
                ids.add(op.itemId);
              } else {
                ids.remove(op.itemId);
              }
            }
          }
          _remoteState = {
            ...remote,
            if (ids != null) 'subscriptions': ids.toList(),
            if (acknowledgedPreferences != null)
              'preferences': acknowledgedPreferences,
          };
        }
      }
      for (final key in keysToRemove) {
        final sent = currentMap[key];
        final latest = latestMap[key];
        if (latest == null || (sent != null && latest.opId == sent.opId)) {
          latestMap.remove(key);
        }
      }
      await _writePendingMap(prefs, userId, latestMap);
    }

    if (shouldRetry) {
      _scheduleRetry();
    }
  }

  Future<void> _handoffGuestPendingOps(
    SharedPreferences prefs,
    String newUserId,
  ) async {
    final guestId = prefs.getString(_keyLastGuestId);
    if (guestId == null || guestId.isEmpty || guestId == newUserId) return;

    final guestOps = _readPendingMap(prefs, guestId);
    if (guestOps.isNotEmpty) {
      final targetOps = _readPendingMap(prefs, newUserId);
      for (final entry in guestOps.entries) {
        targetOps.putIfAbsent(
          entry.key,
          () => SyncOp(
            opId: entry.value.opId,
            userId: newUserId,
            kind: entry.value.kind,
            itemType: entry.value.itemType,
            itemId: entry.value.itemId,
            positionSeconds: entry.value.positionSeconds,
            durationSeconds: entry.value.durationSeconds,
            payloadJson: entry.value.payloadJson,
            isDeleted: entry.value.isDeleted,
            isActive: entry.value.isActive,
            prefField: entry.value.prefField,
            prefValue: entry.value.prefValue,
            clientUpdatedAt: entry.value.clientUpdatedAt,
          ),
        );
      }
      await _writePendingMap(prefs, newUserId, targetOps);
    }
    await prefs.remove('$_keyPendingPrefix$guestId');
    await prefs.remove(_keyLastGuestId);
  }

  Future<void> _saveOp(String userId, String key, SyncOp op) async {
    final prefs = await SharedPreferences.getInstance();
    if (_activeUserId != userId) return;
    final map = _readPendingMap(prefs, userId);
    map[key] = op;
    await _writePendingMap(prefs, userId, map);
  }

  void _scheduleRetry() {
    if (_retryTimer != null || _authPaused) return;
    final delay = _retryDelayMs;
    _retryDelayMs = (_retryDelayMs * 2).clamp(2000, 60000);
    _retryTimer = Timer(Duration(milliseconds: delay), () {
      _retryTimer = null;
      unawaited(flushOutbox());
    });
  }

  bool _isPermanentClientError(int? status) =>
      status == 400 || status == 404 || status == 422;

  Map<String, SyncOp> _readPendingMap(
    SharedPreferences prefs,
    String userId,
  ) {
    try {
      final raw = prefs.getString('$_keyPendingPrefix$userId');
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (k, v) => MapEntry(k, SyncOp.fromJson(Map<String, dynamic>.from(v as Map))),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _writePendingMap(
    SharedPreferences prefs,
    String userId,
    Map<String, SyncOp> map,
  ) async {
    final write = prefs.setString(
      '$_keyPendingPrefix$userId',
      jsonEncode(map.map((k, v) => MapEntry(k, v.toJson()))),
    );
    if (_activeUserId == userId) {
      _pendingOps = Map<String, SyncOp>.from(map);
      notifyListeners();
    }
    if (!await write) {
      throw StateError('Could not save pending user changes');
    }
  }
}
