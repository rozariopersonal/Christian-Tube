import 'package:flutter/material.dart';
import 'short.dart';

enum ShortCreationStatus {
  downloading,
  trimming,
  readyLocal,
  scheduledUpload,
  uploading,
  processing,
  published,
  failed,
}

enum ShortsFramingMode {
  portrait9x16,  // 9:16 Vertical Short (Direct Panning & Zero Margins)
  landscape16x9, // 16:9 Original Widescreen
}

class LocalShortItem {
  // Sentinel for copyWith: allows explicitly setting nullable fields to null.
  static const Object _unset = Object();

  final String id;
  final String sourceVideoId;
  final String sourceVideoTitle;
  final String? sourceVideoThumbnail;
  final String title;
  final String creatorName;
  final String creatorEmail;
  final double clipStartTime;
  final double clipEndTime;
  final double duration;
  final double cropOffsetX; // -1.0 (Left) to +1.0 (Right), 0.0 (Center)
  final ShortsFramingMode framingMode;
  final String? localVideoPath;
  final ShortCreationStatus status;
  final double progress; // 0.0 to 1.0
  final DateTime? scheduledRetryAt;
  final String? errorMessage;
  final String? youtubeVideoId;
  final DateTime createdAt;

  const LocalShortItem({
    required this.id,
    required this.sourceVideoId,
    required this.sourceVideoTitle,
    this.sourceVideoThumbnail,
    required this.title,
    required this.creatorName,
    required this.creatorEmail,
    required this.clipStartTime,
    required this.clipEndTime,
    required this.duration,
    this.cropOffsetX = 0.0,
    this.framingMode = ShortsFramingMode.portrait9x16,
    this.localVideoPath,
    this.status = ShortCreationStatus.downloading,
    this.progress = 0.0,
    this.scheduledRetryAt,
    this.errorMessage,
    this.youtubeVideoId,
    required this.createdAt,
  });

  LocalShortItem copyWith({
    String? id,
    String? sourceVideoId,
    String? sourceVideoTitle,
    String? sourceVideoThumbnail,
    String? title,
    String? creatorName,
    String? creatorEmail,
    double? clipStartTime,
    double? clipEndTime,
    double? duration,
    double? cropOffsetX,
    ShortsFramingMode? framingMode,
    // Use Object? + _unset sentinel so null can be passed explicitly to clear the path
    Object? localVideoPath = _unset,
    ShortCreationStatus? status,
    double? progress,
    DateTime? scheduledRetryAt,
    String? errorMessage,
    String? youtubeVideoId,
    DateTime? createdAt,
  }) {
    return LocalShortItem(
      id: id ?? this.id,
      sourceVideoId: sourceVideoId ?? this.sourceVideoId,
      sourceVideoTitle: sourceVideoTitle ?? this.sourceVideoTitle,
      sourceVideoThumbnail: sourceVideoThumbnail ?? this.sourceVideoThumbnail,
      title: title ?? this.title,
      creatorName: creatorName ?? this.creatorName,
      creatorEmail: creatorEmail ?? this.creatorEmail,
      clipStartTime: clipStartTime ?? this.clipStartTime,
      clipEndTime: clipEndTime ?? this.clipEndTime,
      duration: duration ?? this.duration,
      cropOffsetX: cropOffsetX ?? this.cropOffsetX,
      framingMode: framingMode ?? this.framingMode,
      localVideoPath: identical(localVideoPath, _unset)
          ? this.localVideoPath
          : localVideoPath as String?,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      scheduledRetryAt: scheduledRetryAt ?? this.scheduledRetryAt,
      errorMessage: errorMessage ?? this.errorMessage,
      youtubeVideoId: youtubeVideoId ?? this.youtubeVideoId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceVideoId': sourceVideoId,
      'sourceVideoTitle': sourceVideoTitle,
      'sourceVideoThumbnail': sourceVideoThumbnail,
      'title': title,
      'creatorName': creatorName,
      'creatorEmail': creatorEmail,
      'clipStartTime': clipStartTime,
      'clipEndTime': clipEndTime,
      'duration': duration,
      'cropOffsetX': cropOffsetX,
      'framingMode': framingMode.name,
      'localVideoPath': localVideoPath,
      'status': status.name,
      'progress': progress,
      'scheduledRetryAt': scheduledRetryAt?.toIso8601String(),
      'errorMessage': errorMessage,
      'youtubeVideoId': youtubeVideoId,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory LocalShortItem.fromJson(Map<String, dynamic> json) {
    return LocalShortItem(
      id: json['id'] as String,
      sourceVideoId: json['sourceVideoId'] as String,
      sourceVideoTitle: json['sourceVideoTitle'] as String? ?? 'Sermon Clip',
      sourceVideoThumbnail: json['sourceVideoThumbnail'] as String?,
      title: json['title'] as String? ?? 'Short Clip',
      creatorName: json['creatorName'] as String? ?? 'Anonymous',
      creatorEmail: json['creatorEmail'] as String? ?? '',
      clipStartTime: (json['clipStartTime'] as num?)?.toDouble() ?? 0.0,
      clipEndTime: (json['clipEndTime'] as num?)?.toDouble() ?? 60.0,
      duration: (json['duration'] as num?)?.toDouble() ?? 60.0,
      cropOffsetX: (json['cropOffsetX'] as num?)?.toDouble() ?? 0.0,
      framingMode: ShortsFramingMode.values.firstWhere(
        (e) => e.name == json['framingMode'],
        orElse: () => ShortsFramingMode.portrait9x16,
      ),
      localVideoPath: json['localVideoPath'] as String?,
      status: ShortCreationStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ShortCreationStatus.readyLocal,
      ),
      progress: (json['progress'] as num?)?.toDouble() ?? 1.0,
      scheduledRetryAt: json['scheduledRetryAt'] != null
          ? DateTime.tryParse(json['scheduledRetryAt'] as String)
          : null,
      errorMessage: json['errorMessage'] as String?,
      youtubeVideoId: json['youtubeVideoId'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Color get statusColor {
    switch (status) {
      case ShortCreationStatus.downloading:
      case ShortCreationStatus.trimming:
      case ShortCreationStatus.readyLocal:
        return const Color(0xFFF59E0B); // Amber Gold
      case ShortCreationStatus.uploading:
      case ShortCreationStatus.processing:
        return const Color(0xFF38BDF8); // Electric Sky Blue
      case ShortCreationStatus.scheduledUpload:
        return const Color(0xFFFB923C); // Warm Orange
      case ShortCreationStatus.published:
        return const Color(0xFF10B981); // Emerald Green
      case ShortCreationStatus.failed:
        return const Color(0xFFF43F5E); // Rose Red
    }
  }

  IconData get statusIcon {
    switch (status) {
      case ShortCreationStatus.downloading:
        return Icons.downloading_rounded;
      case ShortCreationStatus.trimming:
        return Icons.content_cut_rounded;
      case ShortCreationStatus.readyLocal:
        return Icons.check_circle_outline_rounded;
      case ShortCreationStatus.uploading:
        return Icons.cloud_upload_rounded;
      case ShortCreationStatus.processing:
        return Icons.sync_rounded;
      case ShortCreationStatus.scheduledUpload:
        return Icons.schedule_rounded;
      case ShortCreationStatus.published:
        return Icons.verified_rounded;
      case ShortCreationStatus.failed:
        return Icons.error_outline_rounded;
    }
  }

  String get statusStageName {
    switch (status) {
      case ShortCreationStatus.downloading:
        return 'Extracting';
      case ShortCreationStatus.trimming:
        return 'Rendering';
      case ShortCreationStatus.readyLocal:
        return 'Ready';
      case ShortCreationStatus.scheduledUpload:
        return 'Scheduled';
      case ShortCreationStatus.uploading:
        return 'Uploading';
      case ShortCreationStatus.processing:
        return 'Syncing';
      case ShortCreationStatus.published:
        return 'Live';
      case ShortCreationStatus.failed:
        return 'Failed';
    }
  }

  String get statusLabel {
    switch (status) {
      case ShortCreationStatus.downloading:
        return 'Extracting ${(progress * 100).toInt()}%';
      case ShortCreationStatus.trimming:
        return 'Rendering ${(progress * 100).toInt()}%';
      case ShortCreationStatus.readyLocal:
        return 'Ready to Upload';
      case ShortCreationStatus.scheduledUpload:
        if (scheduledRetryAt != null) {
          final diff = scheduledRetryAt!.difference(DateTime.now());
          final hours = diff.inHours;
          final mins = diff.inMinutes % 60;
          return 'Scheduled (${hours > 0 ? '${hours}h ' : ''}${mins}m)';
        }
        return 'Scheduled';
      case ShortCreationStatus.uploading:
        return 'Uploading ${(progress * 100).toInt()}%';
      case ShortCreationStatus.processing:
        return 'Syncing...';
      case ShortCreationStatus.published:
        return 'Live';
      case ShortCreationStatus.failed:
        return 'Failed';
    }
  }

  String get statusDisplay {
    switch (status) {
      case ShortCreationStatus.downloading:
        return 'Extracting stream ${(progress * 100).toInt()}%';
      case ShortCreationStatus.trimming:
        return 'Rendering 720p ${(progress * 100).toInt()}%';
      case ShortCreationStatus.readyLocal:
        return 'Rendered • Ready for upload';
      case ShortCreationStatus.scheduledUpload:
        if (scheduledRetryAt != null) {
          final diff = scheduledRetryAt!.difference(DateTime.now());
          final hours = diff.inHours;
          final mins = diff.inMinutes % 60;
          return 'Scheduled for upload (in ${hours > 0 ? '${hours}h ' : ''}${mins}m)';
        }
        return 'Scheduled for upload';
      case ShortCreationStatus.uploading:
        return 'Uploading to YouTube ${(progress * 100).toInt()}%';
      case ShortCreationStatus.processing:
        return 'Syncing with Christian-Tube...';
      case ShortCreationStatus.published:
        return 'Published & Live';
      case ShortCreationStatus.failed:
        return errorMessage ?? 'Failed • Tap to retry';
    }
  }

  bool get isPlayable =>
      status == ShortCreationStatus.published ||
      (localVideoPath != null && localVideoPath!.isNotEmpty);

  Short toShort() {
    return Short(
      id: youtubeVideoId ?? id,
      title: title,
      videoUrl: 'https://youtube.com/shorts/${youtubeVideoId ?? id}',
      thumbnailUrl: sourceVideoThumbnail ??
          'https://img.youtube.com/vi/$sourceVideoId/hqdefault.jpg',
      channelId: 'UC_ChristianTube_Local',
      channelTitle: 'Christian-Tube',
      publishedAt: createdAt,
      duration: '${duration.toInt()}s',
      durationSeconds: duration.toInt(),
      type: 'SHORT',
      sourceVideoId: sourceVideoId,
      clipStartTime: clipStartTime,
      clipEndTime: clipEndTime,
      cropOffsetX: cropOffsetX,
      creatorName: creatorName,
      creatorEmail: creatorEmail,
    );
  }
}
