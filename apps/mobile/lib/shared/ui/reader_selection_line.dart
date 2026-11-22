import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Reports the selection offsets within one reader text block.
class ReaderSelectionLine extends StatefulWidget {
  const ReaderSelectionLine(
      {super.key, required this.onSelection, required this.child});

  final ValueChanged<SelectedContentRange?> onSelection;
  final Widget child;

  @override
  State<ReaderSelectionLine> createState() => _ReaderSelectionLineState();
}

class _ReaderSelectionLineState extends State<ReaderSelectionLine> {
  final SelectionListenerNotifier _notifier = SelectionListenerNotifier();

  @override
  void initState() {
    super.initState();
    _notifier.addListener(_changed);
  }

  void _changed() {
    widget.onSelection(_notifier.registered ? _notifier.selection.range : null);
  }

  @override
  void dispose() {
    widget.onSelection(null);
    _notifier.removeListener(_changed);
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SelectionListener(
        selectionNotifier: _notifier,
        child: widget.child,
      );
}
