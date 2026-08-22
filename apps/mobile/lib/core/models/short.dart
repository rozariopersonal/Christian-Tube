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

  factory Short.fromJson(Map<String, dynamic> json) {
    final videoId = json['id'] ?? json['shortId'] ?? json['videoId'] ?? '';
    return Short(
      id: videoId,
      title: json['title'] ?? '',
      description: json['description'],
      videoUrl: json['videoUrl'] ?? 'https://www.youtube.com/shorts/$videoId',
      thumbnailUrl: json['thumbnailUrl'] ?? json['thumbnail_url'] ?? 'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
      channelId: json['channelId'] ?? json['channel_id'] ?? '',
      channelTitle: json['channelTitle'] ?? json['channel_title'] ?? json['channelName'] ?? json['channel_name'] ?? 'Creator',
      channelAvatarUrl: json['channelAvatarUrl'] ?? json['channel_avatar_url'] ?? json['channelThumbnail'],
      viewCount: json['viewCount'] ?? json['view_count'] ?? 0,
      likeCount: json['likeCount'] ?? json['like_count'] ?? 0,
      publishedAt: json['publishedAt'] != null 
          ? DateTime.tryParse(json['publishedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      directStreamUrl: json['directStreamUrl'] ?? json['stream_url'],
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
