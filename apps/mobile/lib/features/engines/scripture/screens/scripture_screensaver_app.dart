import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/theme_service.dart';
import '../models/scripture_card.dart';
import '../models/scripture_filter_state.dart';
import '../scripture_engine.dart';
import '../widgets/scripture_card_view.dart';

/// Minimalist, auto-advancing Scripture card display used by Android's
/// `DreamService` (OS Screen Saver when docked/charging).
class ScriptureScreensaverApp extends StatefulWidget {
  final List<ScriptureCard>? initialCards;

  const ScriptureScreensaverApp({super.key, this.initialCards});

  @override
  State<ScriptureScreensaverApp> createState() =>
      _ScriptureScreensaverAppState();
}

class _ScriptureScreensaverAppState extends State<ScriptureScreensaverApp> {
  final ThemeService _themeService = ThemeService();
  final ScriptureEngine _engine = ScriptureEngine();

  List<ScriptureCard> _cards = const [];
  ScriptureFilterState _filterState = const ScriptureFilterState();
  int _currentIndex = 0;
  int _page = 0;
  bool _isLoadingMore = false;
  DateTime _now = DateTime.now();

  Timer? _advanceTimer;
  Timer? _clockTimer;

  static const Duration _slideInterval = Duration(seconds: 12);

  static final List<ScriptureCard> _fallbackCards = [
    ScriptureCard(
      id: 'fallback_john_3_16',
      bookNumber: 43,
      bookName: 'John',
      chapter: 3,
      startVerse: 16,
      endVerse: 16,
      referenceLabel: 'John 3:16',
      backgroundPreset: 'mountain_dawn',
      resolvedText:
          'For God so loved the world, that He gave His only begotten Son, that whoever believes in Him shall not perish, but have eternal life.',
      resolvedVersion: 'NASB',
    ),
    ScriptureCard(
      id: 'fallback_psalm_23_1',
      bookNumber: 19,
      bookName: 'Psalms',
      chapter: 23,
      startVerse: 1,
      endVerse: 2,
      referenceLabel: 'Psalm 23:1-2',
      backgroundPreset: 'deep_ocean',
      resolvedText:
          'The Lord is my shepherd, I shall not want. He makes me lie down in green pastures; He leads me beside quiet waters.',
      resolvedVersion: 'NASB',
    ),
    ScriptureCard(
      id: 'fallback_prov_3_5',
      bookNumber: 20,
      bookName: 'Proverbs',
      chapter: 3,
      startVerse: 5,
      endVerse: 6,
      referenceLabel: 'Proverbs 3:5-6',
      backgroundPreset: 'forest_mist',
      resolvedText:
          'Trust in the Lord with all your heart and do not lean on your own understanding. In all your ways acknowledge Him, and He will make your paths straight.',
      resolvedVersion: 'NASB',
    ),
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initFeed();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  Future<void> _initFeed() async {
    if (widget.initialCards != null) {
      setState(() {
        _cards = widget.initialCards!.isNotEmpty
            ? widget.initialCards!
            : _fallbackCards;
        _currentIndex = 0;
      });
      _startAutoAdvance();
      return;
    }
    try {
      await _engine.initialize();
      final filterState = _engine.initialFilterState;
      final items = await _engine.fetchItems(
        filterState: filterState,
        page: 0,
        limit: 20,
      );
      if (!mounted) return;
      setState(() {
        _filterState = filterState;
        _cards = items.isNotEmpty ? items : _fallbackCards;
        _currentIndex = 0;
        _page = 1;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cards = _fallbackCards;
        _currentIndex = 0;
      });
    }
    _startAutoAdvance();
  }

  void _startAutoAdvance() {
    _advanceTimer?.cancel();
    _advanceTimer = Timer.periodic(_slideInterval, (_) {
      if (!mounted || _cards.isEmpty) return;
      final next = _currentIndex + 1;
      if (next >= _cards.length - 3) {
        _loadMore();
      }
      setState(() {
        _currentIndex = next % _cards.length;
      });
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    try {
      final more = await _engine.fetchItems(
        filterState: _filterState,
        page: _page,
        limit: 20,
      );
      if (mounted && more.isNotEmpty) {
        setState(() {
          _cards = [..._cards, ...more];
          _page++;
        });
      }
    } catch (_) {
      // Keep cycling existing cards on offline/transient error
    } finally {
      _isLoadingMore = false;
    }
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeService,
      builder: (context, _) {
        final theme = _themeService.darkTheme;
        final tokens = theme.extension<AppTokens>() ?? AppTokens.dark;

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: Scaffold(
            backgroundColor: tokens.scrim,
            body: _cards.isEmpty
                ? Center(
                    child: CircularProgressIndicator(color: tokens.accent),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 900),
                        switchInCurve: Curves.easeInOut,
                        switchOutCurve: Curves.easeInOut,
                        child: KeyedSubtree(
                          key: ValueKey(_cards[_currentIndex].id),
                          child: ScriptureCardView(
                            card: _cards[_currentIndex],
                            filterState: _filterState,
                            isActive: true,
                          ),
                        ),
                      ),
                      // Subtle top-right clock overlay with gentle burn-in shift
                      Positioned(
                        top: 24 + (_currentIndex % 3) * 4.0,
                        right: 24 + ((_currentIndex ~/ 3) % 3) * 4.0,
                        child: SafeArea(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.scrim.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _formatTime(_now),
                              style: TextStyle(
                                color: tokens.onScrim,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
