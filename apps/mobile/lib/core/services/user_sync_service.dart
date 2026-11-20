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
  static final UserSyncService instance = UserSyncService._internal();
  factory UserSyncService() => instance;

  final Dio _dio;

  UserSyncService._internal({Dio? dio}) : _dio = dio ?? ApiClient().dio {
    _loadClockOffset();
  }

  @visibleForTesting
  UserSyncService.forTesting({Dio? dio}) : _dio = dio ?? ApiClient().dio;

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
  Map<String, SyncOp> _pendingOps = {};

  Map<String, dynamic>? get remoteState => _remoteState;
  Map<String, SyncOp> get pendingOps => Map.unmodifiable(_pendingOps);
  String? get activeUserId => _activeUserId;

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
      _pendingOps = await _readPendingMap(prefs, userId);
      _remoteState = null;
      notifyListeners();
      unawaited(pullAndFlush(force: true));
    }
  }

  Future<void> enqueueSubscription(String channelId, bool isActive) async {
    final userId = _activeUserId;
    if (userId == null || userId.isEmpty || channelId.isEmpty) return;
    final key = 'sub:$channelId';
    final op = SyncOp(
      opId: '$key:${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      kind: 'subscription',
      itemId: channelId,
      isActive: isActive,
      clientUpdatedAt: nowServerAligned(),
    );
    await _saveOp(userId, key, op);
    unawaited(flushOutbox());
  }

  Future<void> enqueuePreference(String field, dynamic value) async {
    final userId = _activeUserId;
    if (userId == null || userId.isEmpty || field.isEmpty) return;
    final key = 'pref:$field';
    final op = SyncOp(
      opId: '$key:${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      kind: 'preference',
      itemId: field,
      prefField: field,
      prefValue: value,
      clientUpdatedAt: nowServerAligned(),
    );
    await _saveOp(userId, key, op);
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
          if (_activeUserId == userId) {
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

  Future<void> flushOutbox() async {
    final userId = _activeUserId;
    if (userId == null || userId.isEmpty || _authPaused) return;

    final prefs = await SharedPreferences.getInstance();
    final currentMap = await _readPendingMap(prefs, userId);
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
        await _dio.patch('/api/user/preferences', data: body);
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

    if (keysToRemove.isNotEmpty) {
      final latestMap = await _readPendingMap(prefs, userId);
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

    final guestOps = await _readPendingMap(prefs, guestId);
    if (guestOps.isNotEmpty) {
      final targetOps = await _readPendingMap(prefs, newUserId);
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
    final map = await _readPendingMap(prefs, userId);
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

  Future<Map<String, SyncOp>> _readPendingMap(
    SharedPreferences prefs,
    String userId,
  ) async {
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
    if (_activeUserId == userId) {
      _pendingOps = Map<String, SyncOp>.from(map);
      notifyListeners();
    }
    try {
      await prefs.setString(
        '$_keyPendingPrefix$userId',
        jsonEncode(map.map((k, v) => MapEntry(k, v.toJson()))),
      );
    } catch (_) {}
  }
}
