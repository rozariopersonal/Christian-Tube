import 'package:flutter/material.dart';

/// Base class for all engine filter / setting states.
abstract class BaseFeedFilterState {
  const BaseFeedFilterState();
}

/// Abstract base contract that all domain-specific feed engines must implement.
abstract class BaseFeedEngine<T, F extends BaseFeedFilterState> {
  /// Unique identifier of the engine (e.g., 'scripture', 'flashcard', 'recipe').
  String get engineType;

  /// Default title for the bottom navigation destination tab (e.g., 'Words', 'Formulas').
  String get defaultTabTitle;

  /// Default icon for the bottom navigation destination tab.
  IconData get defaultTabIcon;

  /// One-time async initialization for the engine (e.g. initializing local SQLite databases).
  Future<void> initialize();

  /// The default initial filter / settings state.
  F get initialFilterState;

  /// Fetches a page of feed items based on the active filter state.
  Future<List<T>> fetchItems({required F filterState, int page = 0, int limit = 20});

  /// Builds the Top Control Bar slot (e.g., Version picker, Font size adjuster).
  Widget? buildTopControls(
    BuildContext context,
    F filterState,
    ValueChanged<F> onFilterChanged,
    VoidCallback onOpenManager,
  );

  /// Builds the main visual card canvas slot inside the vertical PageView.
  Widget buildCard(
    BuildContext context,
    T item,
    F filterState,
    bool isActive,
    GlobalKey repaintBoundaryKey,
  );

  /// Builds the Right Side Action Column slot (e.g., Share, Style, Copy, Bookmark).
  List<Widget> buildSideActions(
    BuildContext context,
    T item,
    F filterState,
    GlobalKey repaintBoundaryKey,
    VoidCallback onRefreshCard,
    ValueChanged<F> onFilterChanged,
  );

  /// Builds the Bottom Context Bar slot (optional contextual deep link or metadata).
  Widget? buildBottomBar(
    BuildContext context,
    T item,
  );

  /// Handles high-resolution canvas capture and native sharing.
  Future<void> shareCard(
    BuildContext context,
    T item,
    GlobalKey repaintBoundaryKey,
  );
}
