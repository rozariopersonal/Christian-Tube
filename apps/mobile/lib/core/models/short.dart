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
  final String? directStreamUrl;
  final bool isVertical;
  final double aspectRatio;

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
    this.directStreamUrl,
    this.isVertical = true,
    this.aspectRatio = 9 / 16,
  });

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

  /// Strict validation: A video is ONLY a Short if duration <= 60s or contains explicit #shorts tag
  static bool isShort(Map<String, dynamic> json) {
    final durationStr = (json['duration'] ?? '').toString().trim();
    final durationSeconds = parseDurationInSeconds(durationStr);

    if (durationSeconds > 60) {
      return false;
    }

    final videoUrl =
        (json['videoUrl'] ?? json['video_url'] ?? '').toString().toLowerCase();
    if (videoUrl.contains('/shorts/')) {
      return true;
    }

    final title = (json['title'] ?? '').toString().toLowerCase();
    final description = (json['description'] ?? '').toString().toLowerCase();
    final hasShortsTag = title.contains('#shorts') ||
        title.contains('#short') ||
        description.contains('#shorts') ||
        description.contains('#short');

    if (hasShortsTag && (durationSeconds == 0 || durationSeconds <= 60)) {
      return true;
    }

    if (durationSeconds > 0 && durationSeconds <= 60) {
      return true;
    }

    final type = (json['type'] ?? '').toString().toUpperCase();
    if (type == 'SHORT' && (durationSeconds == 0 || durationSeconds <= 60)) {
      return true;
    }

    return false;
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
        (durationSec > 0 && durationSec <= 60);

    final double calculatedAspectRatio = isVerticalVideo ? (9 / 16) : (16 / 9);

    return Short(
      id: videoId,
      title: title,
      description: description.isNotEmpty ? description : null,
      videoUrl: videoUrl,
      thumbnailUrl: json['thumbnailUrl'] ??
          json['thumbnail_url'] ??
          'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
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
      directStreamUrl: json['directStreamUrl'] ?? json['stream_url'],
      isVertical: isVerticalVideo,
      aspectRatio: calculatedAspectRatio,
    );
  }

  factory Short.fromVideo(Video video) {
    final durationSec = parseDurationInSeconds(video.duration);
    final isShortUrl = video.id.contains('/shorts/');
    final titleLower = video.title.toLowerCase();
    final descLower = (video.description ?? '').toLowerCase();
    final hasShortTag =
        titleLower.contains('#short') || descLower.contains('#short');
    final isVerticalVideo = isShortUrl ||
        hasShortTag ||
        (durationSec > 0 && durationSec <= 60);

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
