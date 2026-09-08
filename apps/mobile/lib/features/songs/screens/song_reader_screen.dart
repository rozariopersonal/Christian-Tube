import 'package:flutter/material.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../models/song.dart';
import '../services/song_transliteration_controller.dart';

/// Full lyrics reader for a single song.
///
/// Language-agnostic: primary lyrics render in the system font, which supports
/// the song's script. For songs carrying a Latin transliteration ([Song]
/// `titleRoman`/`versesRoman`), an optional toggle switches the visible lyric
/// text to the transliteration — a persisted, app-wide preference.
class SongReaderScreen extends StatefulWidget {
  final Song song;

  const SongReaderScreen({super.key, required this.song});

  @override
  State<SongReaderScreen> createState() => _SongReaderScreenState();
}

class _SongReaderScreenState extends State<SongReaderScreen> {
  late final SongTransliterationController _translit;

  @override
  void initState() {
    super.initState();
    _translit = SongTransliterationController()..addListener(_onChanged);
    _translit.load();
  }

  @override
  void dispose() {
    _translit.removeListener(_onChanged);
    _translit.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  bool get _showTranslit => _translit.showTransliteration;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final song = widget.song;
    final translitAvailable = song.hasTransliteration;

    if (song.id.isEmpty) {
      return Scaffold(
        backgroundColor: tokens.background,
        appBar: AppBar(
          backgroundColor: tokens.background,
          elevation: 0,
          title: Text(
            'Song',
            style: TextStyle(color: tokens.onSurface, fontWeight: FontWeight.bold),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.music_off_outlined,
                    size: 48, color: tokens.onSurfaceMuted),
                const SizedBox(height: 16),
                Text(
                  'Song not found',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This song could not be loaded. It may have been removed or the link is invalid.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.onSurfaceMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // The Latin view shows the transliterated title; the primary view keeps
    // the true title. Fall back to the available one when a view is missing.
    final title =
        _showTranslit && (song.titleRoman?.isNotEmpty ?? false)
            ? song.titleRoman!
            : song.title;
    final author = song.author;

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        elevation: 0,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: tokens.onSurface, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (translitAvailable)
            IconButton(
              tooltip: _showTranslit ? 'Show original script' : 'Show transliteration',
              icon: Icon(
                _showTranslit ? Icons.translate : Icons.translate_rounded,
                color: tokens.onSurfaceMuted,
                size: 21,
              ),
              onPressed: () {
                _translit.showTransliteration = !_showTranslit;
              },
            ),
        ],
      ),
      body: MaxWidthBox(
        maxWidth: kReadingMaxWidth,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: tokens.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (author != null || song.collection != null) ...[
                const SizedBox(height: 8),
                Text(
                  [if (author != null) author, if (song.collection != null) song.collection!]
                      .join(' • '),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.onSurfaceMuted,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              for (var i = 0; i < song.verses.length; i++) ...[
                _VerseBlock(
                  number: i + 1,
                  primaryText: song.verses[i],
                  romanText: _showTranslit ? _romanAt(i) : null,
                  showRoman: _showTranslit,
                  textColor: tokens.onSurface,
                  romanColor: tokens.onSurfaceMuted,
                ),
                if (i != song.verses.length - 1) const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Resolves the transliteration for verse [i], tolerating a short/mismatched
  /// [Song.versesRoman] list by treating missing entries as empty.
  String _romanAt(int i) {
    if (i < 0 || i >= widget.song.versesRoman.length) return '';
    return widget.song.versesRoman[i];
  }
}

class _VerseBlock extends StatelessWidget {
  final int number;
  final String primaryText;
  final String? romanText;
  final bool showRoman;
  final Color textColor;
  final Color romanColor;

  const _VerseBlock({
    required this.number,
    required this.primaryText,
    this.romanText,
    required this.showRoman,
    required this.textColor,
    required this.romanColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Verse $number',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          primaryText,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: textColor,
            height: 1.7,
          ),
        ),
        if (showRoman && (romanText?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 6),
          Text(
            romanText!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: romanColor,
              height: 1.55,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}
