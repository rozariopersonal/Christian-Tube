import 'video.dart';

class Short {
  final String id;
  final String title;
  final String? description;
  final String videoUrl;
  final String thumbnailUrl;
  final String channelId;
  final String channelTitle;
  final String? channelAvatarUrl;
  final int viewCount;
  final int likeCount;
  final DateTime publishedAt;
  final String? duration;
  final int durationSeconds;
  final String? type;
  final String? directStreamUrl;
  final bool isVertical;
  final double aspectRatio;
  final String? sourceVideoId;
  final double? clipStartTime;
  final double? clipEndTime;
  final String? creatorName;
  final String? creatorEmail;
  final double cropOffsetX;

  const Short({
    required this.id,
    required this.title,
    this.description,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.channelId,
    required this.channelTitle,
    this.channelAvatarUrl,
    this.viewCount = 0,
    this.likeCount = 0,
    required this.publishedAt,
    this.duration,
    this.durationSeconds = 0,
    this.type = 'SHORT',
    this.directStreamUrl,
    this.isVertical = true,
    this.aspectRatio = 9 / 16,
    this.sourceVideoId,
    this.clipStartTime,
    this.clipEndTime,
    this.creatorName,
    this.creatorEmail,
    this.cropOffsetX = 0.0,
  });

  bool get isClippedSermon =>
      sourceVideoId != null && sourceVideoId!.trim().isNotEmpty;

  String get playableVideoId {
    if (sourceVideoId != null && sourceVideoId!.isNotEmpty) {
      if (id.startsWith('short_') || id.length != 11 || id.contains('-')) {
        return sourceVideoId!;
      }
    }
    return id.isNotEmpty ? id : (sourceVideoId ?? '');
  }

  int get playableStartSeconds {
    if (clipStartTime != null && clipStartTime! > 0) {
      return clipStartTime!.toInt();
    }
    return 0;
  }

  int? get playableEndSeconds {
    if (clipEndTime != null && clipEndTime! > 0) {
      return clipEndTime!.toInt();
    }
    return null;
  }

  static int parseDurationInSeconds(String? durationStr) {
    if (durationStr == null || durationStr.trim().isEmpty) return 0;
    final parts = durationStr.trim().split(':');
    if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2]) ?? 0;
      return h * 3600 + m * 60 + s;
    } else if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return m * 60 + s;
    }
    return 0;
  }

  /// Strict validation: A video is a Short if and only if its explicit type is 'SHORT'.
  static bool isShort(Map<String, dynamic> json) {
    final type = (json['type'] ?? '').toString().trim().toUpperCase();
    return type == 'SHORT';
  }

  factory Short.fromJson(Map<String, dynamic> json) {
    final videoId = json['id'] ?? json['shortId'] ?? json['videoId'] ?? '';
    final durationStr = json['duration']?.toString() ?? '0:00';
    final durationSec = parseDurationInSeconds(durationStr);

    final videoUrl = json['videoUrl'] ??
        json['video_url'] ??
        'https://www.youtube.com/shorts/$videoId';
    final isShortUrl = videoUrl.toString().toLowerCase().contains('/shorts/');

    final title = json['title'] ?? '';
    final description = json['description']?.toString() ?? '';
    final titleLower = title.toString().toLowerCase();
    final descLower = description.toLowerCase();
    final hasShortTag =
        titleLower.contains('#short') || descLower.contains('#short');

    final explicitShortType =
        (json['type'] ?? '').toString().toUpperCase() == 'SHORT';

    // Vertical 9:16 aspect ratio detection
    final isVerticalVideo = isShortUrl ||
        hasShortTag ||
        explicitShortType ||
        (durationSec > 0 && durationSec <= 180);

    final double calculatedAspectRatio = isVerticalVideo ? (9 / 16) : (16 / 9);

    final sourceVid = json['sourceVideoId'] as String?;
    final thumbId = (sourceVid != null && sourceVid.isNotEmpty && (videoId.startsWith('short_') || videoId.length != 11))
        ? sourceVid
        : videoId;

    return Short(
      id: videoId,
      title: title,
      description: description.isNotEmpty ? description : null,
      videoUrl: videoUrl,
      thumbnailUrl: json['thumbnailUrl'] ??
          json['thumbnail_url'] ??
          'https://img.youtube.com/vi/$thumbId/hqdefault.jpg',
      channelId: json['channelId'] ?? json['channel_id'] ?? '',
      channelTitle: json['channelTitle'] ??
          json['channel_title'] ??
          json['channelName'] ??
          json['channel_name'] ??
          'Creator',
      channelAvatarUrl: json['channelAvatarUrl'] ??
          json['channel_avatar_url'] ??
          json['channelThumbnail'],
      viewCount: json['viewCount'] ?? json['view_count'] ?? 0,
      likeCount: json['likeCount'] ?? json['like_count'] ?? 0,
      publishedAt: json['publishedAt'] != null
          ? DateTime.tryParse(json['publishedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      duration: durationStr,
      durationSeconds: durationSec,
      type: json['type']?.toString().toUpperCase() ?? 'SHORT',
      directStreamUrl: json['directStreamUrl'] ?? json['stream_url'],
      isVertical: isVerticalVideo,
      aspectRatio: calculatedAspectRatio,
      sourceVideoId: json['sourceVideoId'] as String?,
      clipStartTime: (json['clipStartTime'] as num?)?.toDouble(),
      clipEndTime: (json['clipEndTime'] as num?)?.toDouble(),
      creatorName: json['creatorName'] as String?,
      creatorEmail: json['creatorEmail'] as String?,
      cropOffsetX: (json['cropOffsetX'] as num?)?.toDouble() ?? 0.0,
    );
  }

  factory Short.fromVideo(Video video) {
    final durationSec = parseDurationInSeconds(video.duration);
    final isShortUrl = video.id.contains('/shorts/');
    final titleLower = video.title.toLowerCase();
    final descLower = (video.description ?? '').toLowerCase();
    final hasShortTag =
        titleLower.contains('#short') || descLower.contains('#short');
    final isTypeShort = video.type == 'SHORT';
    final isVerticalVideo = isTypeShort ||
        isShortUrl ||
        hasShortTag ||
        (durationSec > 0 && durationSec <= 180);

    return Short(
      id: video.id,
      title: video.title,
      description: video.description,
      videoUrl: 'https://www.youtube.com/shorts/${video.id}',
      thumbnailUrl: video.thumbnailUrl,
      channelId: video.channelId,
      channelTitle: video.channelTitle,
      channelAvatarUrl: video.channelAvatarUrl,
      viewCount: video.viewCount,
      likeCount: 0,
      publishedAt: video.publishedAt,
      duration: video.duration,
      durationSeconds: durationSec,
      directStreamUrl: video.streamUrl,
      isVertical: isVerticalVideo,
      aspectRatio: isVerticalVideo ? (9 / 16) : (16 / 9),
      type: video.type,
      sourceVideoId: video.sourceVideoId,
      clipStartTime: video.clipStartTime,
      clipEndTime: video.clipEndTime,
      cropOffsetX: video.cropOffsetX ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'videoUrl': videoUrl,
      'thumbnailUrl': thumbnailUrl,
      'channelId': channelId,
      'channelTitle': channelTitle,
      'channelAvatarUrl': channelAvatarUrl,
      'viewCount': viewCount,
      'likeCount': likeCount,
      'publishedAt': publishedAt.toIso8601String(),
      'directStreamUrl': directStreamUrl,
    };
  }
}
