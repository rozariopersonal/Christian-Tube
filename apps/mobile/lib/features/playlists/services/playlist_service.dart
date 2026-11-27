import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/playlist.dart';
import '../../../core/models/video.dart';
import '../../../core/services/user_sync_service.dart';

class PlaylistService extends ChangeNotifier {
  static final PlaylistService instance = PlaylistService._internal();
  factory PlaylistService() => instance;

  static const String _storagePrefix = 'playlists_v1_';
  static const Uuid _uuid = Uuid();

  final UserSyncService _sync;
  final String? _userIdOverride;
  final String Function() _idGenerator;

  List<Playlist> _playlists = [];
  bool _isLoading = false;
  bool _initialized = false;
  String? _loadedUserId;

  PlaylistService._internal()
      : _sync = UserSyncService.instance,
        _userIdOverride = null,
        _idGenerator = _uuid.v4;

  @visibleForTesting
  PlaylistService.forTesting({
    UserSyncService? syncService,
    String? userId,
    String Function()? idGenerator,
  })  : _sync = syncService ?? UserSyncService.instance,
        _userIdOverride = userId,
        _idGenerator = idGenerator ?? _uuid.v4;

  List<Playlist> get playlists => List.unmodifiable(_playlists);
  bool get isLoading => _isLoading;

  String get _effectiveUserId {
    final override = _userIdOverride;
    if (override != null && override.isNotEmpty) return override;
    final active = _sync.activeUserId;
    if (active != null && active.isNotEmpty) return active;
    return 'guest';
  }

  String _storageKey(String userId) => '$_storagePrefix$userId';

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _sync.addListener(_onSyncStateChanged);
    await reloadForCurrentUser();
  }

  Future<void> reloadForCurrentUser() async {
    final userId = _effectiveUserId;
    _loadedUserId = userId;
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey(userId));
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _playlists = decoded
            .whereType<Map>()
            .map((m) => Playlist.fromJson(Map<String, dynamic>.from(m)))
            .where((p) => p.id.isNotEmpty)
            .toList();
      } else {
        _playlists = [];
      }

      if (userId != 'guest') {
        final guestRaw = prefs.getString(_storageKey('guest'));
        if (guestRaw != null && guestRaw.isNotEmpty) {
          final guestList = (jsonDecode(guestRaw) as List<dynamic>)
              .whereType<Map>()
              .map((m) => Playlist.fromJson(Map<String, dynamic>.from(m)))
              .where((p) => p.id.isNotEmpty)
              .toList();
          final existingIds = _playlists.map((p) => p.id).toSet();
          final migrated = guestList
              .where((p) => existingIds.add(p.id))
              .toList();
          if (migrated.isNotEmpty) {
            _playlists = [...migrated, ..._playlists];
            await prefs.setString(
              _storageKey(userId),
              jsonEncode(_playlists.map((p) => p.toJson()).toList()),
            );
            for (final pl in migrated) {
              await _sync.enqueuePlaylistOp(
                opType: 'create',
                playlistId: pl.id,
                payload: {
                  'title': pl.title,
                  if (pl.description != null) 'description': pl.description,
                },
              );
              for (final video in pl.videos) {
                await _sync.enqueuePlaylistOp(
                  opType: 'add_item',
                  playlistId: pl.id,
                  payload: {'videoId': video.id},
                );
              }
            }
          }
          await prefs.remove(_storageKey('guest'));
        }
      }
    } catch (e) {
      debugPrint('PlaylistService load warning: $e');
      _playlists = [];
    } finally {
      _isLoading = false;
    }

    _mergeRemoteState(persist: true);
    notifyListeners();
  }

  Future<void> clearLocalState() async {
    _playlists = [];
    _loadedUserId = null;
    notifyListeners();
  }

  Playlist? getById(String id) {
    if (id.isEmpty) return null;
    for (final p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<Playlist> playlistsContainingVideo(String videoId) {
    if (videoId.isEmpty) return const [];
    return _playlists
        .where((p) => p.videos.any((v) => v.id == videoId))
        .toList(growable: false);
  }

  bool isVideoInAnyPlaylist(String videoId) {
    if (videoId.isEmpty) return false;
    return _playlists.any((p) => p.videos.any((v) => v.id == videoId));
  }

  Future<Playlist> createPlaylist(
    String title, {
    String? description,
    Video? initialVideo,
  }) async {
    final trimmedTitle = title.trim();
    final trimmedDesc = description?.trim();
    final id = _idGenerator();
    final now = DateTime.now();
    final ts = _sync.nowServerAligned();
    final initialVideos = initialVideo != null ? [initialVideo] : const <Video>[];

    final created = Playlist(
      id: id,
      title: trimmedTitle,
      description: (trimmedDesc != null && trimmedDesc.isNotEmpty) ? trimmedDesc : null,
      thumbnailUrl: initialVideo?.thumbnailUrl,
      videoCount: initialVideos.length,
      videos: initialVideos,
      createdAt: now,
      updatedAt: now,
      clientUpdatedAt: ts,
    );

    _playlists = [created, ..._playlists];
    notifyListeners();
    await _persist();

    await _sync.enqueuePlaylistOp(
      opType: 'create',
      playlistId: id,
      payload: {
        'title': created.title,
        if (created.description != null) 'description': created.description,
      },
    );

    if (initialVideo != null) {
      await _sync.enqueuePlaylistOp(
        opType: 'add_item',
        playlistId: id,
        payload: {'videoId': initialVideo.id},
      );
    }

    return created;
  }

  Future<void> updatePlaylist(
    String id, {
    required String title,
    String? description,
  }) async {
    final idx = _playlists.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final trimmedTitle = title.trim();
    final trimmedDesc = description?.trim();
    final now = DateTime.now();
    final ts = _sync.nowServerAligned();

    final updated = _playlists[idx].copyWith(
      title: trimmedTitle,
      description: trimmedDesc != null && trimmedDesc.isNotEmpty ? trimmedDesc : null,
      clearDescription: trimmedDesc == null || trimmedDesc.isEmpty,
      updatedAt: now,
      clientUpdatedAt: ts,
    );

    final next = List<Playlist>.from(_playlists);
    next[idx] = updated;
    _playlists = next;
    notifyListeners();
    await _persist();

    await _sync.enqueuePlaylistOp(
      opType: 'update',
      playlistId: id,
      payload: {
        'title': updated.title,
        'description': updated.description,
      },
    );
  }

  Future<void> deletePlaylist(String id) async {
    final exists = _playlists.any((p) => p.id == id);
    if (!exists) return;
    _playlists = _playlists.where((p) => p.id != id).toList();
    notifyListeners();
    await _persist();

    await _sync.enqueuePlaylistOp(
      opType: 'delete',
      playlistId: id,
    );
  }

  Future<void> addVideoToPlaylist(String playlistId, Video video) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1 || video.id.isEmpty) return;
    final current = _playlists[idx];
    if (current.videos.any((v) => v.id == video.id)) return;

    final updatedVideos = [...current.videos, video];
    final updated = current.copyWith(
      videos: updatedVideos,
      videoCount: updatedVideos.length,
      thumbnailUrl: current.thumbnailUrl ?? video.thumbnailUrl,
      updatedAt: DateTime.now(),
      clientUpdatedAt: _sync.nowServerAligned(),
    );

    final next = List<Playlist>.from(_playlists);
    next[idx] = updated;
    _playlists = next;
    notifyListeners();
    await _persist();

    await _sync.enqueuePlaylistOp(
      opType: 'add_item',
      playlistId: playlistId,
      payload: {'videoId': video.id},
    );
  }

  Future<void> removeVideoFromPlaylist(String playlistId, String videoId) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1 || videoId.isEmpty) return;
    final current = _playlists[idx];
    if (!current.videos.any((v) => v.id == videoId)) return;

    final updatedVideos = current.videos.where((v) => v.id != videoId).toList();
    final nextThumb = updatedVideos.isNotEmpty ? updatedVideos.first.thumbnailUrl : null;
    final updated = current.copyWith(
      videos: updatedVideos,
      videoCount: updatedVideos.length,
      thumbnailUrl: nextThumb,
      clearThumbnailUrl: nextThumb == null,
      updatedAt: DateTime.now(),
      clientUpdatedAt: _sync.nowServerAligned(),
    );

    final next = List<Playlist>.from(_playlists);
    next[idx] = updated;
    _playlists = next;
    notifyListeners();
    await _persist();

    await _sync.enqueuePlaylistOp(
      opType: 'remove_item',
      playlistId: playlistId,
      payload: {'videoId': videoId},
    );
  }

  Future<void> reorderVideos(String playlistId, int oldIndex, int newIndex) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1) return;
    final current = _playlists[idx];
    if (oldIndex < 0 ||
        oldIndex >= current.videos.length ||
        newIndex < 0 ||
        newIndex >= current.videos.length ||
        oldIndex == newIndex) {
      return;
    }

    final updatedVideos = List<Video>.from(current.videos);
    final moved = updatedVideos.removeAt(oldIndex);
    updatedVideos.insert(newIndex, moved);

    final updated = current.copyWith(
      videos: updatedVideos,
      videoCount: updatedVideos.length,
      thumbnailUrl: updatedVideos.first.thumbnailUrl,
      updatedAt: DateTime.now(),
      clientUpdatedAt: _sync.nowServerAligned(),
    );

    final next = List<Playlist>.from(_playlists);
    next[idx] = updated;
    _playlists = next;
    notifyListeners();
    await _persist();

    await _sync.enqueuePlaylistOp(
      opType: 'reorder',
      playlistId: playlistId,
      payload: {
        'videoIds': updatedVideos.map((v) => v.id).toList(),
      },
    );
  }

  void _onSyncStateChanged() {
    if (_userIdOverride == null) {
      final active = _sync.activeUserId;
      if (active == null) {
        if (_loadedUserId != null && _loadedUserId != 'guest') {
          unawaited(clearLocalState());
        }
        return;
      }
      if (_loadedUserId != active) {
        unawaited(reloadForCurrentUser());
        return;
      }
    }
    final changed = _mergeRemoteState(persist: true);
    if (changed) {
      notifyListeners();
    }
  }

  bool _mergeRemoteState({required bool persist}) {
    final remote = _sync.remoteState;
    if (remote == null) return false;

    final remoteList = remote['playlists'];
    if (remoteList is! List) return false;

    final tombstones = (remote['playlistTombstones'] as Map?) ?? const {};
    final localById = {for (final p in _playlists) p.id: p};

    final merged = <Playlist>[];
    final seen = <String>{};

    // Preserve local optimistic copies for playlists with pending ops.
    for (final local in _playlists) {
      if (_sync.hasPendingPlaylistOps(local.id)) {
        seen.add(local.id);
        merged.add(local);
      }
    }

    for (final raw in remoteList.whereType<Map>()) {
      final parsed = Playlist.fromJson(Map<String, dynamic>.from(raw));
      if (parsed.id.isEmpty || seen.contains(parsed.id)) continue;

      // If there are pending ops (e.g., pending delete) for this playlist,
      // skip remote version so local optimistic delete isn't resurrected.
      if (_sync.hasPendingPlaylistOps(parsed.id)) continue;
      if (tombstones.containsKey(parsed.id)) continue;

      seen.add(parsed.id);
      merged.add(parsed);
    }

    final changed = !_samePlaylists(merged, _playlists, localById);
    if (changed) {
      _playlists = merged;
      if (persist) {
        unawaited(_persist());
      }
    }
    return changed;
  }

  bool _samePlaylists(
    List<Playlist> next,
    List<Playlist> prev,
    Map<String, Playlist> prevById,
  ) {
    if (next.length != prev.length) return false;
    for (var i = 0; i < next.length; i++) {
      final a = next[i];
      final b = prev[i];
      if (a.id != b.id ||
          a.title != b.title ||
          a.description != b.description ||
          a.videoCount != b.videoCount ||
          a.videos.length != b.videos.length) {
        return false;
      }
      for (var j = 0; j < a.videos.length; j++) {
        if (a.videos[j].id != b.videos[j].id) return false;
      }
    }
    return true;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _loadedUserId ?? _effectiveUserId;
      await prefs.setString(
        _storageKey(userId),
        jsonEncode(_playlists.map((p) => p.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('PlaylistService persist warning: $e');
    }
  }

  @override
  void dispose() {
    if (_initialized) {
      _sync.removeListener(_onSyncStateChanged);
    }
    super.dispose();
  }
}
