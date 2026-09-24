import 'audio_track.dart';

/// Represents a collection/series/album of audio sermon tracks.
class AudioSeries {
  final String id;
  final String title;
  final String description;
  final String speaker;
  final String? coverUrl;
  final int trackCount;
  final String category;
  final String language;

  /// Newest track publish time for this series, used by "Newest" channel sort.
  final DateTime? latestPublishedAt;
  final List<AudioTrack> tracks;

  /// Backing YouTube Channel this series belongs to (null for sermon
  /// collections). Set during backend sync and matched by ID to the user's
  /// channel subscriptions on the Audio Library's YouTube tab.
  final String? channelId;
  final String? channelName;
  final String? channelThumbnail;

  const AudioSeries({
    required this.id,
    required this.title,
    required this.description,
    required this.speaker,
    this.coverUrl,
    required this.trackCount,
    required this.category,
    this.language = 'English',
    this.latestPublishedAt,
    this.channelId,
    this.channelName,
    this.channelThumbnail,
    this.tracks = const [],
  });

  factory AudioSeries.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['tracks'] as List<dynamic>? ?? [];
    final tracks = rawTracks
        .map((t) => AudioTrack.fromJson(t as Map<String, dynamic>))
        .toList();

    return AudioSeries(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      speaker: json['speaker'] as String? ?? 'Zac Poonen',
      coverUrl: json['coverUrl'] as String?,
      trackCount: json['trackCount'] as int? ?? tracks.length,
      category: json['category'] as String? ?? 'Sermons',
      language: json['language'] as String? ?? 'English',
      latestPublishedAt: _parseTimestamp(json['latestPublishedAt']),
      channelId: json['channelId'] as String?,
      channelName: json['channelName'] as String?,
      channelThumbnail: json['channelThumbnail'] as String?,
      tracks: tracks,
    );
  }

  /// Accepts an ISO-8601 string (backend/worker) or epoch-millis int (legacy).
  static DateTime? _parseTimestamp(dynamic value) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      return parsed?.toUtc();
    }
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'speaker': speaker,
        if (coverUrl != null) 'coverUrl': coverUrl,
        'trackCount': trackCount,
        'category': category,
        'language': language,
        if (latestPublishedAt != null)
          'latestPublishedAt': latestPublishedAt!.toIso8601String(),
        if (channelId != null) 'channelId': channelId,
        if (channelName != null) 'channelName': channelName,
        if (channelThumbnail != null) 'channelThumbnail': channelThumbnail,
        if (tracks.isNotEmpty)
          'tracks': tracks.map((t) => t.toJson()).toList(),
      };

  AudioSeries copyWith({
    String? id,
    String? title,
    String? description,
    String? speaker,
    String? coverUrl,
    int? trackCount,
    String? category,
    String? language,
    DateTime? latestPublishedAt,
    bool clearLatestPublishedAt = false,
    String? channelId,
    String? channelName,
    String? channelThumbnail,
    List<AudioTrack>? tracks,
  }) {
    return AudioSeries(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      speaker: speaker ?? this.speaker,
      coverUrl: coverUrl ?? this.coverUrl,
      trackCount: trackCount ?? this.trackCount,
      category: category ?? this.category,
      language: language ?? this.language,
      latestPublishedAt: clearLatestPublishedAt
          ? null
          : (latestPublishedAt ?? this.latestPublishedAt),
      channelId: channelId ?? this.channelId,
      channelName: channelName ?? this.channelName,
      channelThumbnail: channelThumbnail ?? this.channelThumbnail,
      tracks: tracks ?? this.tracks,
    );
  }
}
