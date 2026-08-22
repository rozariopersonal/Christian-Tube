class Channel {
  final String id;
  final String title;
  final String? description;
  final String avatarUrl;
  final String? bannerUrl;
  final int subscriberCount;
  final int videoCount;
  final bool isSubscribed;

  const Channel({
    required this.id,
    required this.title,
    this.description,
    required this.avatarUrl,
    this.bannerUrl,
    this.subscriberCount = 0,
    this.videoCount = 0,
    this.isSubscribed = false,
  });

  Channel copyWith({
    String? id,
    String? title,
    String? description,
    String? avatarUrl,
    String? bannerUrl,
    int? subscriberCount,
    int? videoCount,
    bool? isSubscribed,
  }) {
    return Channel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      subscriberCount: subscriberCount ?? this.subscriberCount,
      videoCount: videoCount ?? this.videoCount,
      isSubscribed: isSubscribed ?? this.isSubscribed,
    );
  }

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      id: json['id'] ?? json['channelId'] ?? json['_id'] ?? '',
      title: json['title'] ?? json['channelTitle'] ?? 'Channel',
      description: json['description'],
      avatarUrl: json['avatarUrl'] ?? json['avatar_url'] ?? json['thumbnailUrl'] ?? '',
      bannerUrl: json['bannerUrl'] ?? json['banner_url'],
      subscriberCount: json['subscriberCount'] ?? json['subscriber_count'] ?? 0,
      videoCount: json['videoCount'] ?? json['video_count'] ?? 0,
      isSubscribed: json['isSubscribed'] ?? json['is_subscribed'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'avatarUrl': avatarUrl,
      'bannerUrl': bannerUrl,
      'subscriberCount': subscriberCount,
      'videoCount': videoCount,
      'isSubscribed': isSubscribed,
    };
  }
}
