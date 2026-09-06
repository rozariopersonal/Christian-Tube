/// Represents a single audio sermon or teaching track.
class AudioTrack {
  final String id;
  final String title;
  final String seriesId;
  final String seriesTitle;
  final String speaker;
  final int durationSeconds;
  final String audioUrl;
  final String? fallbackUrl;
  final String? coverUrl;
  final String? scriptureBook;
  final int? scriptureChapter;
  final int? scriptureVerse;

  const AudioTrack({
    required this.id,
    required this.title,
    required this.seriesId,
    required this.seriesTitle,
    required this.speaker,
    required this.durationSeconds,
    required this.audioUrl,
    this.fallbackUrl,
    this.coverUrl,
    this.scriptureBook,
    this.scriptureChapter,
    this.scriptureVerse,
  });

  String get formattedDuration {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  bool get hasScripture =>
      scriptureBook != null && scriptureChapter != null && scriptureChapter! > 0;

  String get scriptureRefText {
    if (!hasScripture) return '';
    if (scriptureVerse != null && scriptureVerse! > 0) {
      return '$scriptureBook $scriptureChapter:$scriptureVerse';
    }
    return '$scriptureBook $scriptureChapter';
  }

  factory AudioTrack.fromJson(Map<String, dynamic> json) {
    return AudioTrack(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      seriesId: json['seriesId'] as String? ?? '',
      seriesTitle: json['seriesTitle'] as String? ?? '',
      speaker: json['speaker'] as String? ?? 'Zac Poonen',
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      audioUrl: json['audioUrl'] as String? ?? '',
      fallbackUrl: json['fallbackUrl'] as String?,
      coverUrl: json['coverUrl'] as String?,
      scriptureBook: json['scriptureBook'] as String?,
      scriptureChapter: json['scriptureChapter'] as int?,
      scriptureVerse: json['scriptureVerse'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'seriesId': seriesId,
        'seriesTitle': seriesTitle,
        'speaker': speaker,
        'durationSeconds': durationSeconds,
        'audioUrl': audioUrl,
        if (fallbackUrl != null) 'fallbackUrl': fallbackUrl,
        if (coverUrl != null) 'coverUrl': coverUrl,
        if (scriptureBook != null) 'scriptureBook': scriptureBook,
        if (scriptureChapter != null) 'scriptureChapter': scriptureChapter,
        if (scriptureVerse != null) 'scriptureVerse': scriptureVerse,
      };
}
