class Video {
  final String id;
  final String title;
  final String? description;
  final String thumbnailUrl;
  final String channelId;
  final String channelTitle;
  final String? channelAvatarUrl;
  final int viewCount;
  final DateTime publishedAt;
  final String? duration;
  final String? streamUrl;
  final bool isLive;

  const Video({
    required this.id,
    required this.title,
    this.description,
    required this.thumbnailUrl,
    required this.channelId,
    required this.channelTitle,
    this.channelAvatarUrl,
    this.viewCount = 0,
    required this.publishedAt,
    this.duration,
    this.streamUrl,
    this.isLive = false,
  });

  factory Video.fromJson(Map<String, dynamic> json) {
    final videoId = json['id'] ?? json['videoId'] ?? json['_id'] ?? '';
    final defaultThumb = videoId.isNotEmpty 
        ? 'https://img.youtube.com/vi/$videoId/hqdefault.jpg'
        : 'https://images.unsplash.com/photo-1516321318423-f06f85e504b3?w=800';

    return Video(
      id: videoId,
      title: json['title'] ?? '',
      description: json['description'],
      thumbnailUrl: json['thumbnailUrl'] ?? json['thumbnail_url'] ?? json['thumbnail'] ?? defaultThumb,
      channelId: json['channelId'] ?? json['channel_id'] ?? '',
      channelTitle: json['channelTitle'] ?? json['channel_title'] ?? json['channelName'] ?? json['channel_name'] ?? 'Channel',
      channelAvatarUrl: json['channelAvatarUrl'] ?? json['channel_avatar_url'] ?? json['channelThumbnail'],
      viewCount: json['viewCount'] ?? json['view_count'] ?? 0,
      publishedAt: json['publishedAt'] != null 
          ? DateTime.tryParse(json['publishedAt'].toString()) ?? DateTime.now()
          : (json['published_at'] != null ? DateTime.tryParse(json['published_at'].toString()) ?? DateTime.now() : DateTime.now()),
      duration: json['duration'] ?? '0:00',
      streamUrl: json['streamUrl'] ?? json['stream_url'],
      isLive: json['isLive'] ?? json['is_live'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'thumbnailUrl': thumbnailUrl,
      'channelId': channelId,
      'channelTitle': channelTitle,
      'channelAvatarUrl': channelAvatarUrl,
      'viewCount': viewCount,
      'publishedAt': publishedAt.toIso8601String(),
      'duration': duration,
      'streamUrl': streamUrl,
      'isLive': isLive,
    };
  }
}
