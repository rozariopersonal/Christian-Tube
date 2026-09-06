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
  final List<AudioTrack> tracks;

  const AudioSeries({
    required this.id,
    required this.title,
    required this.description,
    required this.speaker,
    this.coverUrl,
    required this.trackCount,
    required this.category,
    this.language = 'English',
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
      tracks: tracks,
    );
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
      tracks: tracks ?? this.tracks,
    );
  }
}
