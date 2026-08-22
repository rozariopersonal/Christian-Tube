import 'video.dart';

class Playlist {
  final String id;
  final String title;
  final String? description;
  final String? thumbnailUrl;
  final int videoCount;
  final List<Video> videos;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Playlist({
    required this.id,
    required this.title,
    this.description,
    this.thumbnailUrl,
    this.videoCount = 0,
    this.videos = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    var rawVideos = json['videos'] as List<dynamic>? ?? [];
    List<Video> parsedVideos = rawVideos
        .whereType<Map<String, dynamic>>()
        .map((v) => Video.fromJson(v))
        .toList();

    return Playlist(
      id: json['id'] ?? json['_id'] ?? json['playlistId'] ?? '',
      title: json['title'] ?? 'Playlist',
      description: json['description'],
      thumbnailUrl: json['thumbnailUrl'] ?? json['thumbnail_url'],
      videoCount: json['videoCount'] ?? json['video_count'] ?? parsedVideos.length,
      videos: parsedVideos,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'thumbnailUrl': thumbnailUrl,
      'videoCount': videoCount,
      'videos': videos.map((v) => v.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
