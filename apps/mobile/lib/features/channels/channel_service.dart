import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api/api_client.dart';
import '../../core/models/channel.dart';
import '../../core/models/channel_request.dart';
import '../auth/auth_service.dart';
import '../../core/services/user_sync_service.dart';

class ChannelService extends ChangeNotifier {
  static final ChannelService _instance = ChannelService._internal();
  factory ChannelService() => _instance;

  AuthService? _authService;
  AuthService? get authService => _authService;

  late final Dio _dio;
  late final UserSyncService _syncService;

  ChannelService._internal({Dio? dio, UserSyncService? syncService})
      : _dio = dio ?? ApiClient().dio,
        _syncService = syncService ?? UserSyncService.instance {
    _loadFromPrefs();
    _syncService.addListener(_onSyncStateChanged);
  }

  void _onSyncStateChanged() {
    if (_syncService.activeUserId == null) {
      if (_subscribedIds.isNotEmpty) {
        _subscribedIds.clear();
        _syncSubscriptionStatus();
        notifyListeners();
      }
      return;
    }
    final remote = _syncService.remoteState;
    final subs = remote?['subscriptions'];
    if (subs is! List) return;
    final serverIds = subs.whereType<String>().toSet();
    final projected = _projectWithPendingOps(serverIds);
    if (!setEquals(projected, _subscribedIds)) {
      _subscribedIds = projected;
      _saveToPrefs();
      _syncSubscriptionStatus();
      notifyListeners();
    }
  }

  Set<String> _projectWithPendingOps(Set<String> serverIds) {
    final result = Set<String>.from(serverIds);
    for (final op in _syncService.pendingOps.values) {
      if (op.kind != 'subscription') continue;
      if (op.isActive == true) {
        result.add(op.itemId);
      } else {
        result.remove(op.itemId);
      }
    }
    return result;
  }

  @visibleForTesting
  ChannelService.forTesting({
    Dio? dio,
    AuthService? authService,
    UserSyncService? syncService,
  })  : _dio = dio ?? ApiClient().dio,
        _syncService = syncService ?? UserSyncService.instance {
    attachToAuth(authService);
    _syncService.addListener(_onSyncStateChanged);
  }

  @override
  void dispose() {
    _authService?.removeListener(_onAuthChanged);
    _syncService.removeListener(_onSyncStateChanged);
    super.dispose();
  }

  @visibleForTesting
  void setChannelsForTesting(List<Channel> channels) {
    _channels = channels;
    for (final ch in channels) {
      _rememberChannelName(ch.id, ch.name);
    }
    _syncSubscriptionStatus();
    notifyListeners();
  }

  void attachToAuth(AuthService? authService) {
    _authService = authService;
    authService?.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    loadSubscriptions();
  }

  bool get _isAuthenticated => _authService?.isAuthenticated ?? false;
  List<Channel> _channels = [];
  List<Map<String, dynamic>> _channelRequests = [];
  bool _isLoading = false;
  bool _isLoadingRequests = false;
  Set<String> _subscribedIds = {};
  final Map<String, String> _channelNamesById = {};
  int _subscriptionMutationVersion = 0;
  Future<void>? _inFlightSubscriptionsSync;

  List<Channel> get channels => _channels;
  List<Channel> get shortsChannels =>
      _channels.where((c) => c.hasShorts).toList();
  List<Map<String, dynamic>> get channelRequests => _channelRequests;
  bool get isLoading => _isLoading;
  bool get isLoadingRequests => _isLoadingRequests;
  Set<String> get subscribedChannelIds => _subscribedIds;
  Set<String> get followedChannelIds => _subscribedIds;

  bool isSubscribed(String channelId) => _subscribedIds.contains(channelId);
  bool isFollowing(String channelId) => isSubscribed(channelId);
  bool isFollowed(String channelId) => isFollowing(channelId);

  /// Names of the currently subscribed/followed channels (trimmed). Other features
  /// (audio YouTube tab) bridge channel subscriptions to their own data by
  /// name, so names are remembered whenever they are learned — from the
  /// backend subscription payload, the channel list, or persisted prefs.
  Set<String> get subscribedChannelNames {
    final names = <String>{};
    for (final id in _subscribedIds) {
      final name = _channelNamesById[id];
      if (name != null && name.isNotEmpty) names.add(name);
    }
    return names;
  }
  Set<String> get followedChannelNames => subscribedChannelNames;

  void toggleFollow(String channelId) => toggleSubscribe(channelId);
  Future<void> loadFollowing() => loadSubscriptions();

  /// Seeds initial followed channel IDs (e.g. from onboarding).
  void seedSubscribedIds(Set<String> ids) {
    if (ids.isEmpty) return;
    _subscriptionMutationVersion++;
    final newIds = ids.difference(_subscribedIds);
    final merged = {..._subscribedIds, ...ids};
    if (merged.length != _subscribedIds.length) {
      _subscribedIds = merged;
      _syncSubscriptionStatus();
      _saveToPrefs();
      notifyListeners();
    }
    if (_isAuthenticated && _syncService.activeUserId != null) {
      unawaited(_syncService.enqueueSubscriptions({
        for (final id in newIds) id: true,
      }));
    }
  }

  void _rememberChannelName(String? id, String? name) {
    if (id == null || id.isEmpty) return;
    final clean = (name ?? '').trim();
    if (clean.isEmpty) return;
    _channelNamesById[id] = clean;
  }

  Future<void> loadSubscriptions() async {
    if (_inFlightSubscriptionsSync != null) {
      return _inFlightSubscriptionsSync!;
    }
    final future = _performLoadSubscriptions();
    _inFlightSubscriptionsSync = future;
    try {
      await future;
    } finally {
      if (identical(_inFlightSubscriptionsSync, future)) {
        _inFlightSubscriptionsSync = null;
      }
    }
  }

  Future<void> _performLoadSubscriptions() async {
    if (_isAuthenticated) {
      if (_subscribedIds.isEmpty) {
        await _loadFromPrefs();
      }
      await _loadFromBackend();
    } else {
      await _loadFromPrefs();
    }
    notifyListeners();
  }

  Future<void> _loadFromBackend() async {
    final versionBefore = _subscriptionMutationVersion;
    final acknowledgementVersion = _syncService.acknowledgementVersion;
    final userId = _authService?.currentUser?.id;
    try {
      dynamic response;
      try {
        response = await _dio.get('/api/channels/subscriptions');
      } catch (_) {
        response = await _dio.get('/channels/subscriptions');
      }

      if (versionBefore != _subscriptionMutationVersion ||
          acknowledgementVersion != _syncService.acknowledgementVersion ||
          userId != _authService?.currentUser?.id) {
        return;
      }

      if (response.statusCode == 200 && response.data != null) {
        final channelIds = (response.data['channelIds'] as List?)
                ?.whereType<String>()
                .toSet() ??
            const <String>{};
        _subscribedIds = _projectWithPendingOps(channelIds);

        final subscribedChannels = response.data['channels'];
        if (subscribedChannels is List) {
          for (final entry in subscribedChannels.whereType<Map>()) {
            final id = entry['id'];
            if (id is String && _subscribedIds.contains(id)) {
              _rememberChannelName(id, entry['name'] as String?);
            }
          }
        }

        await _saveToPrefs();
        _syncSubscriptionStatus();
      }
    } catch (e) {
      debugPrint('Error loading subscriptions from backend: $e');
      if (versionBefore == _subscriptionMutationVersion &&
          acknowledgementVersion == _syncService.acknowledgementVersion &&
          userId == _authService?.currentUser?.id) {
        await _loadFromPrefs();
      }
    }
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('subscribed_channel_ids') ?? [];
      _subscribedIds = list.toSet();

      final namesJson = prefs.getString('subscribed_channel_names');
      if (namesJson != null && namesJson.isNotEmpty) {
        final decoded = jsonDecode(namesJson);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.key is String) {
              _rememberChannelName(entry.key as String, entry.value as String?);
            }
          }
        }
      }
      _syncSubscriptionStatus();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('subscribed_channel_ids', _subscribedIds.toList());

      // Persist names only for the currently subscribed ids so the map does
      // not retain stale entries across accounts or sign-outs.
      final subscribedNamesJson = jsonEncode({
        for (final id in _subscribedIds)
          if (_channelNamesById[id] != null) id: _channelNamesById[id],
      });
      await prefs.setString('subscribed_channel_names', subscribedNamesJson);
    } catch (_) {}
  }

  void _syncSubscriptionStatus() {
    for (int i = 0; i < _channels.length; i++) {
      final ch = _channels[i];
      if (_subscribedIds.contains(ch.id) != ch.isSubscribed) {
        _channels[i] = ch.copyWith(isSubscribed: _subscribedIds.contains(ch.id));
      }
    }
  }

  Future<void> fetchChannels() async {
    _isLoading = true;
    notifyListeners();

    try {
      dynamic response;
      try {
        response = await _dio.get('/api/channels');
      } catch (_) {
        response = await _dio.get('/channels');
      }

      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data;
        final List<dynamic> list = raw is List ? raw : (raw['channels'] ?? raw['data'] ?? []);
        _channels = list
            .whereType<Map>()
            .map((c) => Channel.fromJson(Map<String, dynamic>.from(c)))
            .toList();

        for (final ch in _channels) {
          _rememberChannelName(ch.id, ch.name);
        }

        _syncSubscriptionStatus();
      }
    } catch (e) {
      debugPrint('Error fetching channels: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchRequests() async {
    _isLoadingRequests = true;
    notifyListeners();

    try {
      final response = await _dio.get('/channels/requests');
      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> list = response.data is List ? response.data : [];
        _channelRequests = list.whereType<Map<String, dynamic>>().toList();
      }
    } catch (e) {
      debugPrint('Error fetching channel requests: $e');
    } finally {
      _isLoadingRequests = false;
      notifyListeners();
    }
  }

  Future<Channel?> fetchChannelDetails(String channelId) async {
    try {
      dynamic response;
      try {
        response = await _dio.get('/api/channels/$channelId');
      } catch (_) {
        response = await _dio.get('/channels/$channelId');
      }

      if (response.statusCode == 200 && response.data != null) {
        final ch = Channel.fromJson(response.data);
        _rememberChannelName(ch.id, ch.name);
        return ch.copyWith(isSubscribed: _subscribedIds.contains(ch.id));
      }
    } catch (e) {
      debugPrint('Error fetching channel details for $channelId: $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> searchYouTubeChannels(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      dynamic response;
      try {
        response = await _dio.get(
          '/api/channels/search-youtube',
          queryParameters: {'q': query},
        );
      } catch (_) {
        response = await _dio.get(
          '/channels/search-youtube',
          queryParameters: {'q': query},
        );
      }

      if (response.statusCode == 200 && response.data != null) {
        final dynamic list = response.data is List ? response.data : [];
        return list.whereType<Map<String, dynamic>>().toList();
      }
    } catch (e) {
      debugPrint('Error searching YouTube channels: $e');
    }
    return [];
  }

  Future<bool> addChannel({
    required String channelUrl,
    String? name,
    String? category,
    String? language,
    String? adminEmail,
  }) async {
    try {
      final data = {
        'channelUrl': channelUrl,
        'name': name,
        'category': category,
        'language': language,
        'adminEmail': adminEmail,
      };

      dynamic response;
      try {
        response = await _dio.post('/api/channels', data: data);
      } catch (_) {
        response = await _dio.post('/channels', data: data);
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchChannels();
        return true;
      }
    } catch (e) {
      debugPrint('Error adding channel: $e');
    }
    return false;
  }

  Future<bool> toggleChannelActive(Channel ch) async {
    final action = ch.isActive ? 'suspend' : 'activate';
    try {
      dynamic response;
      try {
        response = await _dio.post('/api/channels/${ch.id}/$action');
      } catch (_) {
        response = await _dio.post('/channels/${ch.id}/$action');
      }
      if (response.statusCode == 200 || response.statusCode == 201) {
        final idx = _channels.indexWhere((c) => c.id == ch.id);
        if (idx != -1) {
          _channels[idx] = _channels[idx].copyWith(isActive: !ch.isActive);
          notifyListeners();
        }
        return true;
      }
    } catch (e) {
      debugPrint('Error toggling channel active status: $e');
    }
    return false;
  }

  Future<void> fetchAdminChannels() async {
    _isLoading = true;
    notifyListeners();
    try {
      dynamic response;
      try {
        response = await _dio.get('/api/channels/admin/all');
      } catch (_) {
        response = await _dio.get('/channels/admin/all');
      }
      if (response.statusCode == 200 && response.data is List) {
        _channels = (response.data as List)
            .whereType<Map<String, dynamic>>()
            .map((j) {
              final ch = Channel.fromJson(j);
              _rememberChannelName(ch.id, ch.name);
              return ch.copyWith(isSubscribed: _subscribedIds.contains(ch.id));
            })
            .toList();
      }
    } catch (e) {
      debugPrint('Error fetching admin channels: $e');
      await fetchChannels();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> removeChannel(String channelId) async {
    try {
      final response = await _dio.delete('/channels/$channelId');
      if (response.statusCode == 200 || response.statusCode == 204) {
        _channels.removeWhere((c) => c.id == channelId);
        _subscribedIds.remove(channelId);
        _channelNamesById.remove(channelId);
        await _saveToPrefs();
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Error removing channel: $e');
    }
    return false;
  }

  Future<bool> submitChannelRequest(ChannelRequest request) async {
    try {
      final response = await _dio.post(
        '/channels/request',
        data: request.toJson(),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchRequests();
        return true;
      }
    } catch (e) {
      debugPrint('Error submitting channel request: $e');
    }
    return false;
  }

  Future<bool> approveRequest(String requestId, [String? adminEmail]) async {
    try {
      final response = await _dio.post(
        '/channels/requests/$requestId/approve',
        data: {'adminEmail': adminEmail},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchChannels();
        await fetchRequests();
        return true;
      }
    } catch (e) {
      debugPrint('Error approving channel request: $e');
    }
    return false;
  }

  Future<bool> rejectRequest(String requestId, [String? reason]) async {
    try {
      final response = await _dio.post(
        '/channels/requests/$requestId/reject',
        data: {'reason': reason},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchRequests();
        return true;
      }
    } catch (e) {
      debugPrint('Error rejecting channel request: $e');
    }
    return false;
  }

  void toggleSubscribe(String channelId) {
    _subscriptionMutationVersion++;
    final wasSubscribed = _subscribedIds.contains(channelId);
    final willSubscribe = !wasSubscribed;

    _applySubscriptionState(channelId, willSubscribe);
    _saveToPrefs();
    notifyListeners();

    unawaited(_persistFollowChange(
      channelId,
      willSubscribe,
      wasSubscribed,
    ));
  }

  Future<void> _persistFollowChange(
    String channelId,
    bool followed,
    bool wasFollowed,
  ) async {
    if (!_isAuthenticated) return;
    if (_syncService.activeUserId != null &&
        (_authService?.currentUser == null ||
            _authService!.currentUser!.id == _syncService.activeUserId)) {
      await _syncService.enqueueSubscription(channelId, followed);
    } else {
      try {
        if (followed) {
          await _dio.post('/api/channels/$channelId/subscribe');
        } else {
          await _dio.delete('/api/channels/$channelId/subscribe');
        }
      } catch (error) {
        debugPrint('Subscription backend sync failed, reverting: $error');
        _applySubscriptionState(channelId, wasFollowed);
        await _saveToPrefs();
        notifyListeners();
      }
    }
  }

  /// Applies the difference between two explicit sets of channel selections.
  Future<void> saveChannelSelections(
    Set<String> previous,
    Set<String> selected,
  ) async {
    final changes = {
      for (final id in previous.difference(selected)) id: false,
      for (final id in selected.difference(previous)) id: true,
    };
    if (changes.isEmpty) return;
    _subscriptionMutationVersion++;
    for (final change in changes.entries) {
      _applySubscriptionState(change.key, change.value);
    }
    notifyListeners();
    await _saveToPrefs();
    if (_syncService.activeUserId != null &&
        (_authService?.currentUser == null ||
            _authService!.currentUser!.id == _syncService.activeUserId)) {
      await _syncService.enqueueSubscriptions(changes);
    }
  }

  void _applySubscriptionState(String channelId, bool subscribed) {
    if (subscribed) {
      _subscribedIds.add(channelId);
    } else {
      _subscribedIds.remove(channelId);
    }

    final index = _channels.indexWhere((c) => c.id == channelId);
    if (index != -1) {
      final ch = _channels[index];
      _channels[index] = ch.copyWith(isSubscribed: subscribed);
    }
  }
}
