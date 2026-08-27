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

  /// Client-side decision logic to classify whether any video payload is a Short
  static bool isShort(Map<String, dynamic> json) {
    // 1. Explicit type field from backend
    final type = (json['type'] ?? '').toString().toUpperCase();
    if (type == 'SHORT') return true;

    // 2. Video URL format (e.g. youtube.com/shorts/...)
    final videoUrl =
        (json['videoUrl'] ?? json['video_url'] ?? '').toString().toLowerCase();
    if (videoUrl.contains('/shorts/')) return true;

    // 3. Title or Description hashtags (#shorts, #short, #reels)
    final title = (json['title'] ?? '').toString().toLowerCase();
    final description = (json['description'] ?? '').toString().toLowerCase();
    if (title.contains('#short') ||
        description.contains('#short') ||
        title.contains('#reels') ||
        description.contains('#reels')) {
      return true;
    }

    // 4. Duration check (<= 60 seconds)
    final duration = (json['duration'] ?? '').toString().trim();
    if (duration.isNotEmpty) {
      final parts = duration.split(':');
      if (parts.length == 2) {
        final m = int.tryParse(parts[0]) ?? 0;
        final s = int.tryParse(parts[1]) ?? 0;
        final totalSeconds = m * 60 + s;
        if (totalSeconds > 0 && totalSeconds <= 60) return true;
      }
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
