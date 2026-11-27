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
  final int clientUpdatedAt;

  const Playlist({
    required this.id,
    required this.title,
    this.description,
    this.thumbnailUrl,
    this.videoCount = 0,
    this.videos = const [],
    required this.createdAt,
    required this.updatedAt,
    this.clientUpdatedAt = 0,
  });

  static int _parseClientUpdatedAt(dynamic raw) {
    if (raw == null) return 0;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    final str = raw.toString().trim();
    if (str.isEmpty) return 0;
    final asInt = int.tryParse(str);
    if (asInt != null) return asInt;
    return DateTime.tryParse(str)?.millisecondsSinceEpoch ?? 0;
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final rawVideos =
        (json['videos'] as List<dynamic>?) ?? (json['items'] as List<dynamic>?) ?? const [];
    final parsedVideos = <Video>[];
    for (final entry in rawVideos.whereType<Map>()) {
      final map = Map<String, dynamic>.from(entry);
      final videoMap = map['video'] is Map
          ? Map<String, dynamic>.from(map['video'] as Map)
          : map;
      final video = Video.fromJson(videoMap);
      if (video.id.isNotEmpty) {
        parsedVideos.add(video);
      }
    }

    final rawCount = json['videoCount'] ?? json['video_count'];
    final resolvedCount = rawCount is num ? rawCount.toInt() : parsedVideos.length;

    return Playlist(
      id: (json['id'] ?? json['_id'] ?? json['playlistId'] ?? '').toString(),
      title: (json['title'] ?? 'Playlist').toString(),
      description: json['description'] as String?,
      thumbnailUrl: (json['thumbnailUrl'] ?? json['thumbnail_url']) as String?,
      videoCount: resolvedCount,
      videos: parsedVideos,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      clientUpdatedAt: _parseClientUpdatedAt(
        json['clientUpdatedAt'] ?? json['client_updated_at'],
      ),
    );
  }

  Playlist copyWith({
    String? id,
    String? title,
    String? description,
    bool clearDescription = false,
    String? thumbnailUrl,
    bool clearThumbnailUrl = false,
    int? videoCount,
    List<Video>? videos,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? clientUpdatedAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      title: title ?? this.title,
      description: clearDescription ? null : (description ?? this.description),
      thumbnailUrl: clearThumbnailUrl ? null : (thumbnailUrl ?? this.thumbnailUrl),
      videoCount: videoCount ?? this.videoCount,
      videos: videos ?? this.videos,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
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
      'clientUpdatedAt': clientUpdatedAt,
    };
  }
}
