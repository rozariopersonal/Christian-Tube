import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/app_config.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/link/deep_link_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/services/reader_appearance.dart';
import '../../../shared/ui/reader_appearance_sheet.dart';
import '../models/song.dart';
import '../services/songs_catalog_service.dart';
import '../services/song_transliteration_controller.dart';

/// Full lyrics reader for a single song.
///
/// Language-agnostic: primary lyrics render in the system font, which supports
/// the song's script. For songs carrying a Latin transliteration ([Song]
/// `titleRoman`/`versesRoman`), an optional toggle switches the visible lyric
/// text to the transliteration — a persisted, app-wide preference.
class SongReaderScreen extends StatefulWidget {
  final String? songId;
  final Song? initialSong;

  const SongReaderScreen({super.key, this.songId, this.initialSong});

  @override
  State<SongReaderScreen> createState() => _SongReaderScreenState();
}

class _SongReaderScreenState extends State<SongReaderScreen> {
  late final SongTransliterationController _translit;
  final ReaderAppearance _appearance = ReaderAppearance();
  Song? _song;
  bool _loading = false;

  String get _effectiveId => widget.songId ?? widget.initialSong?.id ?? '';

  @override
  void initState() {
    super.initState();
    _appearance.addListener(_onAppearanceChanged);
    _appearance.loadFromPrefs();
    _translit = SongTransliterationController()..addListener(_onChanged);
    _translit.load();
    _song = widget.initialSong;
    if (_song == null && _effectiveId.isNotEmpty) {
      _loadSong();
    }
  }

  Future<void> _loadSong() async {
    setState(() => _loading = true);
    try {
      final loaded = await SongsCatalogService().getSong(_effectiveId);
      if (mounted) setState(() => _song = loaded);
    } catch (_) {
      if (mounted) setState(() => _song = const Song.empty());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _appearance.removeListener(_onAppearanceChanged);
    _translit.removeListener(_onChanged);
    _translit.dispose();
    super.dispose();
  }

  void _onAppearanceChanged() {
    if (mounted) setState(() {});
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  bool get _showTranslit => _translit.showTransliteration;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final song = _song;
    final translitAvailable = song?.hasTransliteration ?? false;

    if (_loading) {
      return Scaffold(
        backgroundColor: tokens.background,
        body: Center(child: CircularProgressIndicator(color: tokens.accent)),
      );
    }

    if (song == null || song.id.isEmpty) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop(result);
          } else {
            context.go('/songs');
          }
        },
        child: Scaffold(
          backgroundColor: tokens.background,
          appBar: AppBar(
            automaticallyImplyLeading: false,
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
        ),
      );
    }

    final s = song;
    // The Latin view shows the transliterated title; the primary view keeps
    // the true title. Fall back to the available one when a view is missing.
    final title =
        _showTranslit && (s.titleRoman?.isNotEmpty ?? false)
            ? s.titleRoman!
            : s.title;
    final author = s.author;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(result);
        } else {
          context.go('/songs');
        }
      },
      child: Scaffold(
        backgroundColor: _appearance.background(tokens),
        appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: _appearance.surface(tokens),
        elevation: 0,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _appearance.textColor(tokens),
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Reading settings',
            icon: Text(
              'Aa',
              style: TextStyle(
                color: _appearance.textColor(tokens),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            onPressed: () => showReaderAppearanceSheet(context, _appearance),
          ),
          IconButton(
            tooltip: 'Share',
            icon: Icon(Icons.share_outlined, color: _appearance.mutedTextColor(tokens), size: 21),
            onPressed: () {
              final link = DeepLinkService.song(s.id);
              Share.share(
                '$title — ${s.author ?? s.collection ?? AppConfig.appName}\n$link',
                subject: title,
              );
            },
          ),
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
      body: Scrollbar(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(
            24,
            20,
            24,
            MediaQuery.paddingOf(context).bottom + 32,
          ),
          child: MaxWidthBox(
            maxWidth: kReadingMaxWidth,
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
                if (author != null || s.collection != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    [if (author != null) author, if (s.collection != null) s.collection!]
                        .join(' • '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.onSurfaceMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                for (var i = 0; i < s.verses.length; i++) ...[
                  _VerseBlock(
                    number: i + 1,
                    primaryText: s.verses[i],
                    romanText: _showTranslit ? _romanAt(i) : null,
                    showRoman: _showTranslit,
                    textColor: _appearance.textColor(tokens),
                    romanColor: _appearance.mutedTextColor(tokens),
                    fontSize: _appearance.fontSize,
                    lineHeight: _appearance.lineHeight,
                    fontFamily: _appearance.fontFamily,
                  ),
                  if (i != s.verses.length - 1) const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

  /// Resolves the transliteration for verse [i], tolerating a short/mismatched
  /// [Song.versesRoman] list by treating missing entries as empty.
  String _romanAt(int i) {
    final versesRoman = _song?.versesRoman ?? const <String>[];
    if (i < 0 || i >= versesRoman.length) return '';
    return versesRoman[i];
  }
}

class _VerseBlock extends StatelessWidget {
  final int number;
  final String primaryText;
  final String? romanText;
  final bool showRoman;
  final Color textColor;
  final Color romanColor;
  final double fontSize;
  final double lineHeight;
  final String? fontFamily;

  const _VerseBlock({
    required this.number,
    required this.primaryText,
    this.romanText,
    required this.showRoman,
    required this.textColor,
    required this.romanColor,
    required this.fontSize,
    required this.lineHeight,
    this.fontFamily,
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
          style: TextStyle(
            color: textColor,
            fontSize: fontSize,
            height: lineHeight,
            fontFamily: fontFamily,
          ),
        ),
        if (showRoman && (romanText?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 6),
          Text(
            romanText!,
            style: TextStyle(
              color: romanColor,
              fontSize: fontSize * 0.9,
              height: lineHeight * 0.95,
              fontStyle: FontStyle.italic,
              fontFamily: fontFamily,
            ),
          ),
        ],
      ],
    );
  }
}
