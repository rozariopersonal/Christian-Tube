import 'package:flutter/material.dart';

import '../../features/dictionary/widgets/glossary_entry_sheet.dart';

/// Wraps [SelectionArea] and opens [GlossaryEntrySheet] when the user
/// double-taps or double-clicks a word, without competing in the gesture arena.
class DoubleTapDictionaryArea extends StatefulWidget {
  const DoubleTapDictionaryArea({
    super.key,
    required this.contextMenuBuilder,
    required this.child,
  });

  final SelectableRegionContextMenuBuilder contextMenuBuilder;
  final Widget child;

  @override
  State<DoubleTapDictionaryArea> createState() =>
      _DoubleTapDictionaryAreaState();
}

class _DoubleTapDictionaryAreaState extends State<DoubleTapDictionaryArea> {
  static const Duration _doubleTapTimeout = Duration(milliseconds: 350);
  static const double _maxTapSlop = 18.0;
  static const double _maxDoubleTapDistance = 28.0;

  String _selectedText = '';
  Offset? _downPos;
  Offset? _lastTapPos;
  DateTime? _lastTapUpTime;

  void _onPointerDown(PointerDownEvent event) {
    _downPos = event.position;
  }

  void _onPointerUp(PointerUpEvent event) {
    final down = _downPos;
    _downPos = null;
    if (down == null || (event.position - down).distance > _maxTapSlop) {
      _lastTapUpTime = null;
      _lastTapPos = null;
      return;
    }

    final now = DateTime.now();
    final prevTime = _lastTapUpTime;
    final prevPos = _lastTapPos;
    if (prevTime != null &&
        prevPos != null &&
        now.difference(prevTime) <= _doubleTapTimeout &&
        (event.position - prevPos).distance <= _maxDoubleTapDistance) {
      _lastTapUpTime = null;
      _lastTapPos = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final word = _extractWord(_selectedText);
        if (word.isNotEmpty) {
          GlossaryEntrySheet.show(context, word: word);
        }
      });
      return;
    }

    _lastTapUpTime = now;
    _lastTapPos = event.position;
  }

  static String _extractWord(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final words = trimmed
        .split(RegExp(r'\s+'))
        .map(
          (w) => w.replaceAll(
            RegExp(
              r'''[^\w\-\u0900-\u097F\u0B80-\u0BFF\u0C00-\u0C7F\u0C80-\u0CFF\u0D00-\u0D7F]''',
            ),
            '',
          ),
        )
        .where((w) => w.isNotEmpty)
        .toList();
    return words.isNotEmpty ? words.first : '';
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      child: SelectionArea(
        contextMenuBuilder: widget.contextMenuBuilder,
        onSelectionChanged: (content) {
          _selectedText = content?.plainText ?? '';
        },
        child: widget.child,
      ),
    );
  }
}
