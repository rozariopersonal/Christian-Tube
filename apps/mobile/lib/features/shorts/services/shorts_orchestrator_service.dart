import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/local_short_item.dart';
import 'local_shorts_storage.dart';
import 'shorts_render_engine.dart';

class ShortsOrchestratorService extends ChangeNotifier {
  static final ShortsOrchestratorService _instance =
      ShortsOrchestratorService._internal();
  factory ShortsOrchestratorService() => _instance;

  final ApiClient _apiClient = ApiClient();
  final ShortsRenderEngine _renderEngine = ShortsRenderEngine();
  final Uuid _uuid = const Uuid();

  List<LocalShortItem> _localShorts = [];
  bool _isInitialized = false;

  List<LocalShortItem> get localShorts => List.unmodifiable(_localShorts);
  int get activeJobsCount => _localShorts
      .where((s) =>
          s.status == ShortCreationStatus.downloading ||
          s.status == ShortCreationStatus.trimming ||
          s.status == ShortCreationStatus.uploading ||
          s.status == ShortCreationStatus.processing)
      .length;

  ShortsOrchestratorService._internal() {
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    _localShorts = await LocalShortsStorage.loadShorts();
    _isInitialized = true;
    notifyListeners();
  }

  Future<String> createShort({
    required String sourceVideoId,
    required String sourceVideoTitle,
    String? sourceVideoThumbnail,
    required String title,
    required String creatorName,
    required String creatorEmail,
    required double clipStartTime,
    required double clipEndTime,
    double cropOffsetX = 0.0,
    ShortsFramingMode framingMode = ShortsFramingMode.portrait9x16,
  }) async {
    final shortId = _uuid.v4();
    final duration = clipEndTime - clipStartTime;

    var item = LocalShortItem(
      id: shortId,
      sourceVideoId: sourceVideoId,
      sourceVideoTitle: sourceVideoTitle,
      sourceVideoThumbnail: sourceVideoThumbnail,
      title: title,
      creatorName: creatorName,
      creatorEmail: creatorEmail,
      clipStartTime: clipStartTime,
      clipEndTime: clipEndTime,
      duration: duration,
      cropOffsetX: cropOffsetX,
      framingMode: framingMode,
      status: ShortCreationStatus.downloading,
      progress: 0.1,
      createdAt: DateTime.now(),
    );

    _localShorts.insert(0, item);
    await LocalShortsStorage.saveShorts(_localShorts);
    notifyListeners();

    // Launch async background pipeline
    _processShortPipeline(item);

    return shortId;
  }

  Future<void> _processShortPipeline(LocalShortItem initialItem) async {
    String currentId = initialItem.id;

    try {
      // 1. Stage: DOWNLOADING & TRIMMING (720p Rendering)
      _updateItemStatus(
        currentId,
        status: ShortCreationStatus.trimming,
        progress: 0.2,
      );

      final renderResult = await _renderEngine.render720pShort(
        sourceVideoId: initialItem.sourceVideoId,
        startSeconds: initialItem.clipStartTime,
        endSeconds: initialItem.clipEndTime,
        creatorName: initialItem.creatorName,
        cropOffsetX: initialItem.cropOffsetX,
        framingMode: initialItem.framingMode,
        onProgress: (prog, stage) {
          _updateItemStatus(
            currentId,
            status: prog < 0.3
                ? ShortCreationStatus.downloading
                : ShortCreationStatus.trimming,
            progress: prog,
          );
        },
      );

      if (!renderResult.isSuccess) {
        _updateItemStatus(
          currentId,
          status: ShortCreationStatus.failed,
          errorMessage: renderResult.errorMessage ?? 'Render failed',
        );
        return;
      }

      // 2. Stage: LOCAL_READY
      _updateItemStatus(
        currentId,
        status: ShortCreationStatus.readyLocal,
        localVideoPath: renderResult.outputPath,
        progress: 1.0,
      );

      // 3. Stage: CHECK YOUTUBE QUOTA & INITIATE UPLOAD
      await _uploadShortToYouTube(currentId);
    } catch (e) {
      debugPrint('Error in shorts creation pipeline: $e');
      _updateItemStatus(
        currentId,
        status: ShortCreationStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _uploadShortToYouTube(String shortId) async {
    final item = _localShorts.firstWhere((i) => i.id == shortId);

    try {
      _updateItemStatus(
        shortId,
        status: ShortCreationStatus.uploading,
        progress: 0.1,
      );

      // Query quota status from backend
      final quotaRes = await _apiClient.dio.get('/shorts/quota-status');
      final bool uploadAllowed = quotaRes.data?['uploadAllowed'] ?? true;

      if (!uploadAllowed) {
        final retryHours = quotaRes.data?['nextRetryAfterHours'] ?? 5;
        final retryAt = quotaRes.data?['retryAt'] != null
            ? DateTime.tryParse(quotaRes.data['retryAt'])
            : DateTime.now().add(Duration(hours: retryHours));

        _updateItemStatus(
          shortId,
          status: ShortCreationStatus.scheduledUpload,
          scheduledRetryAt: retryAt,
          errorMessage: 'YouTube quota limit reached. Auto-scheduled for later.',
        );
        return;
      }

      // Initiate Resumable Upload Session
      final initRes = await _apiClient.dio.post('/shorts/initiate-upload', data: {
        'title': item.title,
        'sourceVideoId': item.sourceVideoId,
        'clipStartTime': item.clipStartTime,
        'clipEndTime': item.clipEndTime,
        'cropOffsetX': item.cropOffsetX,
        'creatorName': item.creatorName,
        'creatorEmail': item.creatorEmail,
      });

      if (initRes.data?['allowed'] == false) {
        final retryHours = initRes.data?['nextRetryAfterHours'] ?? 5;
        _updateItemStatus(
          shortId,
          status: ShortCreationStatus.scheduledUpload,
          scheduledRetryAt: DateTime.now().add(Duration(hours: retryHours)),
          errorMessage: initRes.data?['message'] ?? 'Upload scheduled for later',
        );
        return;
      }

      final String? uploadUrl = initRes.data?['uploadUrl'];
      if (uploadUrl == null || !uploadUrl.startsWith('http')) {
        throw 'YouTube upload session not available. Backend must be authorized with YOUTUBE_REFRESH_TOKEN.';
      }

      String actualYtId = '';

      // Upload binary video stream to YouTube
      try {
        dynamic postData;
        int? fileSize;
        if (item.localVideoPath != null && !kIsWeb) {
          final file = io.File(item.localVideoPath!);
          if (await file.exists()) {
            fileSize = await file.length();
            postData = file.openRead();
          }
        }

        final ytRes = await Dio().put(
          uploadUrl,
          data: postData,
          options: Options(
            headers: {
              'Content-Type': 'video/mp4',
              if (fileSize != null) 'Content-Length': fileSize.toString(),
            },
          ),
          onSendProgress: (sent, total) {
            final effectiveTotal = (total > 0) ? total : (fileSize ?? 0);
            if (effectiveTotal > 0) {
              final p = 0.2 + ((sent / effectiveTotal) * 0.75);
              _updateItemStatus(
                shortId,
                status: ShortCreationStatus.uploading,
                progress: p.clamp(0.2, 0.95),
              );
            }
          },
        );

        if (ytRes.data is Map && ytRes.data['id'] != null) {
          actualYtId = ytRes.data['id'].toString();
        } else if (ytRes.data is String) {
          final parsed = jsonDecode(ytRes.data as String);
          actualYtId = parsed['id']?.toString() ?? '';
        }
      } catch (uploadErr) {
        debugPrint('YouTube direct binary upload failed: $uploadErr');
        throw 'YouTube upload failed: $uploadErr';
      }

      if (actualYtId.isEmpty) {
        throw 'YouTube did not return a valid Short ID. Please check channel upload authorization.';
      }

      // 4. Stage: PROCESSING & SYNC TO BACKEND
      _updateItemStatus(
        shortId,
        status: ShortCreationStatus.processing,
        youtubeVideoId: actualYtId,
        progress: 1.0,
      );

      // Record creation in backend database mapping user and YouTube Short ID
      try {
        await _apiClient.dio.post('/shorts/record-creation', data: {
          'userEmail': item.creatorEmail,
          'creatorName': item.creatorName,
          'youtubeVideoId': actualYtId,
          'sourceVideoId': item.sourceVideoId,
          'title': item.title,
          'thumbnail': item.sourceVideoThumbnail,
          'clipStartTime': item.clipStartTime,
          'clipEndTime': item.clipEndTime,
          'cropOffsetX': item.cropOffsetX,
        });
      } catch (recErr) {
        debugPrint('Record creation notice: $recErr');
      }

      // Trigger backend channel & video sync from YouTube
      try {
        await _apiClient.dio.post('/sync/video/$actualYtId');
      } catch (syncErr) {
        debugPrint('Direct video sync notice (will sync via channel sweep): $syncErr');
      }

      // Auto-delete local temporary MP4 file to save device storage
      if (item.localVideoPath != null && !kIsWeb) {
        try {
          final file = io.File(item.localVideoPath!);
          if (await file.exists()) {
            await file.delete();
            debugPrint('✅ Local temporary short video file auto-deleted: ${item.localVideoPath}');
          }
        } catch (delErr) {
          debugPrint('Notice deleting local short file: $delErr');
        }
      }

      // 5. Stage: PUBLISHED
      _updateItemStatus(
        shortId,
        status: ShortCreationStatus.published,
        youtubeVideoId: actualYtId,
        progress: 1.0,
      );
    } catch (e) {
      debugPrint('Error uploading short to YouTube: $e');
      _updateItemStatus(
        shortId,
        status: ShortCreationStatus.failed,
        errorMessage: 'Upload error: $e',
      );
    }
  }

  Future<void> retryUpload(String shortId) async {
    final index = _localShorts.indexWhere((i) => i.id == shortId);
    if (index < 0) return;

    final item = _localShorts[index];
    if (item.localVideoPath == null) {
      // Re-run full pipeline
      _processShortPipeline(item);
    } else {
      // Direct upload
      _uploadShortToYouTube(shortId);
    }
  }

  Future<void> deleteShort(String shortId) async {
    final idx = _localShorts.indexWhere((i) => i.id == shortId);
    if (idx != -1) {
      final path = _localShorts[idx].localVideoPath;
      if (path != null && !kIsWeb) {
        try {
          final file = io.File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
      _localShorts.removeAt(idx);
      await LocalShortsStorage.saveShorts(_localShorts);
      notifyListeners();
    }
  }

  Future<void> fetchCloudCreations({String? email, String? userId}) async {
    try {
      final res = await _apiClient.dio.get(
        '/shorts/my-creations',
        queryParameters: {
          if (email != null && email.isNotEmpty) 'email': email,
          if (userId != null && userId.isNotEmpty) 'userId': userId,
        },
      );

      if (res.data is List) {
        final List list = res.data;
        final cloudItems = list.map((json) {
          final ytId = json['id']?.toString() ?? '';
          return LocalShortItem(
            id: 'cloud_$ytId',
            youtubeVideoId: ytId,
            sourceVideoId: json['sourceVideoId']?.toString() ?? '',
            sourceVideoTitle: json['title']?.toString() ?? 'Christian Short',
            sourceVideoThumbnail: json['thumbnailUrl']?.toString(),
            title: json['title']?.toString() ?? 'Christian Short',
            creatorName: json['creatorName']?.toString() ?? 'Believer',
            creatorEmail: json['creatorEmail']?.toString() ?? '',
            clipStartTime: (json['clipStartTime'] as num?)?.toDouble() ?? 0.0,
            clipEndTime: (json['clipEndTime'] as num?)?.toDouble() ?? 60.0,
            duration: (json['durationSeconds'] as num?)?.toDouble() ?? 60.0,
            cropOffsetX: (json['cropOffsetX'] as num?)?.toDouble() ?? 0.0,
            status: ShortCreationStatus.published,
            progress: 1.0,
            createdAt: json['publishedAt'] != null
                ? DateTime.tryParse(json['publishedAt']) ?? DateTime.now()
                : DateTime.now(),
          );
        }).toList();

        // Merge active local jobs and cloud creations
        final Map<String, LocalShortItem> merged = {};
        for (final item in _localShorts) {
          final key = item.youtubeVideoId ?? item.id;
          merged[key] = item;
        }
        for (final cloud in cloudItems) {
          final key = cloud.youtubeVideoId ?? cloud.id;
          if (!merged.containsKey(key)) {
            merged[key] = cloud;
          }
        }

        _localShorts = merged.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        await LocalShortsStorage.saveShorts(_localShorts);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching cloud creations: $e');
    }
  }

  void _updateItemStatus(
    String id, {
    ShortCreationStatus? status,
    double? progress,
    String? localVideoPath,
    String? youtubeVideoId,
    DateTime? scheduledRetryAt,
    String? errorMessage,
  }) {
    final index = _localShorts.indexWhere((i) => i.id == id);
    if (index >= 0) {
      _localShorts[index] = _localShorts[index].copyWith(
        status: status,
        progress: progress,
        localVideoPath: localVideoPath,
        youtubeVideoId: youtubeVideoId,
        scheduledRetryAt: scheduledRetryAt,
        errorMessage: errorMessage,
      );
      LocalShortsStorage.saveShorts(_localShorts);
      notifyListeners();
    }
  }
}
