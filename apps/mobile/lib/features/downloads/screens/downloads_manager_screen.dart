import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../controllers/downloads_controller.dart';
import '../widgets/audio_tab.dart';
import '../widgets/bibles_tab.dart';
import '../widgets/dictionaries_tab.dart';
import '../widgets/books_tab.dart';
import '../widgets/overview_tab.dart';
import '../widgets/songs_tab.dart';
import '../widgets/fonts_tab.dart';

/// Single unified screen managing all offline downloads for Christian Tube:
/// Bibles, Dictionaries, Books & Commentaries, Audio Sermons, and Songbooks.
class DownloadsManagerScreen extends StatefulWidget {
  final int initialTab;
  final DownloadsController? controller;

  const DownloadsManagerScreen({
    super.key,
    this.initialTab = 0,
    this.controller,
  });

  @override
  State<DownloadsManagerScreen> createState() => _DownloadsManagerScreenState();
}

class _DownloadsManagerScreenState extends State<DownloadsManagerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final DownloadsController _controller;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 7,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 6),
    );

    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = DownloadsController();
      _ownsController = true;
    }
    _controller.addListener(_onControllerChange);
  }

  void _onControllerChange() {
    final error = _controller.state.errorMessage;
    if (error != null && error.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Theme.of(context).colorScheme.error,
          action: SnackBarAction(
            label: 'OK',
            textColor: Theme.of(context).colorScheme.onError,
            onPressed: () => _controller.clearError(),
          ),
        ),
      );
      _controller.clearError();
    }
  }

  @override
  void didUpdateWidget(DownloadsManagerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _navigateToTab(widget.initialTab.clamp(0, 6));
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    _tabController.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _navigateToTab(int index) {
    if (index >= 0 && index < _tabController.length) {
      _tabController.animateTo(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        elevation: 0,
        title: Text(
          'Offline Library & Downloads',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tokens.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: tokens.onSurfaceMuted),
            tooltip: 'Recalculate Storage & Status',
            onPressed: _controller.refreshAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: tokens.accent,
          labelColor: tokens.accent,
          unselectedLabelColor: tokens.onSurfaceMuted,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Bibles & Study Tools'),
            Tab(text: 'Dictionaries'),
            Tab(text: 'Books & Commentaries'),
            Tab(text: 'Audio Sermons'),
            Tab(text: 'Songs & Hymns'),
            Tab(text: 'Reader Fonts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          OverviewTab(
            controller: _controller,
            onNavigateToTab: _navigateToTab,
          ),
          BiblesTab(controller: _controller),
          DictionariesTab(controller: _controller),
          BooksTab(controller: _controller),
          AudioTab(controller: _controller),
          SongsTab(controller: _controller),
          FontsTab(controller: _controller),
        ],
      ),
    );
  }
}
