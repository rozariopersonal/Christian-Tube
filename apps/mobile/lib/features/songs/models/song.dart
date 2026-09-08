/// A single song in the library, language- and source-agnostic.
///
/// Lyrics are stored as a plain list of verse strings. For scripts where a
/// Latin transliteration is provided (e.g. Tamil), [versesRoman] holds an
/// optional parallel transliteration and [titleRoman] the Latin-script title —
/// both purely display/search aids, never required.
class Song {
  final String id;
  final String title;

  /// Latin-script transliteration of [title], used for search and the
  /// Tamil→Latin reader view. Null when the song has no transliteration.
  final String? titleRoman;

  final String? author;
  final String? album;
  final String? collection;
  final String language;
  final String? category;

  /// One entry per verse/chorus block. Each string may contain line breaks.
  final List<String> verses;

  /// Optional parallel transliteration of [verses] (same length and order).
  /// Entries may be empty where a given verse has no transliteration.
  final List<String> versesRoman;

  /// Optional future audio stream URL. Reserved for the lyrics-first rollout.
  final String? audioUrl;

  const Song({
    required this.id,
    required this.title,
    this.titleRoman,
    this.author,
    this.album,
    this.collection,
    required this.language,
    this.category,
    this.verses = const [],
    this.versesRoman = const [],
    this.audioUrl,
  });

  /// Whether a Latin transliteration view is available for this song.
  bool get hasTransliteration =>
      (titleRoman != null && titleRoman!.isNotEmpty) ||
      versesRoman.any((v) => v.isNotEmpty);

  String get languageCode => language.toLowerCase();

  const Song.empty({String language = 'en'})
      : this(id: '', title: '', language: language);

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      titleRoman: json['titleRoman']?.toString(),
      author: json['author']?.toString(),
      album: json['album']?.toString(),
      collection: json['collection']?.toString(),
      language: (json['language'] ?? 'en').toString(),
      category: json['category']?.toString(),
      verses: (json['verses'] as List<dynamic>? ?? const [])
          .map((v) => v.toString())
          .toList(),
      versesRoman: (json['versesRoman'] as List<dynamic>? ?? const [])
          .map((v) => v.toString())
          .toList(),
      audioUrl: json['audioUrl']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (titleRoman != null) 'titleRoman': titleRoman,
        if (author != null) 'author': author,
        if (album != null) 'album': album,
        if (collection != null) 'collection': collection,
        'language': language,
        if (category != null) 'category': category,
        'verses': verses,
        if (versesRoman.isNotEmpty) 'versesRoman': versesRoman,
        if (audioUrl != null) 'audioUrl': audioUrl,
      };
}
