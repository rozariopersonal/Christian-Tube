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
  final String? directStreamUrl;

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
    this.directStreamUrl,
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

    // RULE 1: If duration is known and > 60 seconds, it is DEFINITELY a regular video, NOT a Short!
    if (durationSeconds > 60) {
      return false;
    }

    // RULE 2: Video URL explicitly contains /shorts/
    final videoUrl =
        (json['videoUrl'] ?? json['video_url'] ?? '').toString().toLowerCase();
    if (videoUrl.contains('/shorts/')) {
      return true;
    }

    // RULE 3: Title or description has dedicated #shorts / #short tag AND duration is <= 60s
    final title = (json['title'] ?? '').toString().toLowerCase();
    final description = (json['description'] ?? '').toString().toLowerCase();
    final hasShortsTag = title.contains('#shorts') ||
        title.contains('#short') ||
        description.contains('#shorts') ||
        description.contains('#short');

    if (hasShortsTag && (durationSeconds == 0 || durationSeconds <= 60)) {
      return true;
    }

    // RULE 4: Valid duration between 1 and 60 seconds
    if (durationSeconds > 0 && durationSeconds <= 60) {
      return true;
    }

    // RULE 5: Explicit type == 'SHORT' ONLY IF duration is <= 60s
    final type = (json['type'] ?? '').toString().toUpperCase();
    if (type == 'SHORT' && (durationSeconds == 0 || durationSeconds <= 60)) {
      return true;
    }

    return false;
  }

  factory Short.fromJson(Map<String, dynamic> json) {
    final videoId = json['id'] ?? json['shortId'] ?? json['videoId'] ?? '';
    return Short(
      id: videoId,
      title: json['title'] ?? '',
      description: json['description'],
      videoUrl: json['videoUrl'] ?? 'https://www.youtube.com/shorts/$videoId',
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
      directStreamUrl: json['directStreamUrl'] ?? json['stream_url'],
    );
  }

  factory Short.fromVideo(Video video) {
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
      directStreamUrl: video.streamUrl,
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
