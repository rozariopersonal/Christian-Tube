import 'song.dart';

/// A named grouping (album, author, or collection catalog) of songs.
///
/// Groupings are computed by the songs controller; this model is a plain
/// view-model describing one group and its songs.
class SongCollection {
  final String label;
  final String? subtitle;
  final List<Song> songs;

  const SongCollection({
    required this.label,
    this.subtitle,
    required this.songs,
  });

  Song? get firstSong => songs.isEmpty ? null : songs.first;
}
