import 'package:flutter/material.dart';

import '../../../core/layout/adaptivity.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/models/user_preference.dart';
import '../../../core/services/user_preference_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_service.dart';
import '../../../shared/ui/language_meta.dart';
import '../../../shared/ui/bible_version_native_names.dart';
import '../../auth/auth_service.dart';
import '../../channels/channel_service.dart';
import '../../engines/scripture/services/bible_download_manager.dart';
import '../../../shared/ui/channel_follow_tile.dart';

class ContentPreferencesScreen extends StatefulWidget {
  final AuthService authService;
  final ThemeService themeService;
  final UserPreferenceService? preferenceService;
  final ChannelService? channelService;

  const ContentPreferencesScreen({
    super.key,
    required this.authService,
    required this.themeService,
    this.preferenceService,
    this.channelService,
  });

  @override
  State<ContentPreferencesScreen> createState() =>
      _ContentPreferencesScreenState();
}

class _ContentPreferencesScreenState extends State<ContentPreferencesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final UserPreferenceService _preferenceService;
  late final ChannelService _channelService;

  late UserPreference _currentPref;
  bool _isSaving = false;
  String _channelSearch = '';
  String _languageSearch = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _preferenceService = widget.preferenceService ?? UserPreferenceService();
    _channelService = widget.channelService ?? ChannelService();
    _currentPref = _preferenceService.preferences;
    _channelService.addListener(_onChannelsChanged);
    if (widget.channelService == null) {
      _channelService.fetchChannels();
    }
    _preferenceService.addListener(_onPrefChanged);
  }

  @override
  void dispose() {
    _channelService.removeListener(_onChannelsChanged);
    _preferenceService.removeListener(_onPrefChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onChannelsChanged() {
    if (mounted) setState(() {});
  }

  void _onPrefChanged() {
    if (mounted) {
      setState(() {
        _currentPref = _preferenceService.preferences;
      });
    }
  }

  Future<void> _updatePreferences(UserPreference updated) async {
    setState(() {
      _currentPref = updated;
      _isSaving = true;
    });

    await _preferenceService.savePreferences(
      updated,
      auth: widget.authService,
      syncWithBackend: widget.authService.isAuthenticated,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preferences saved & synchronized!'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: tokens.background,
        titleSpacing: 16,
        title: const Text(
          'Content & Feed Preferences',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: context.accent,
          unselectedLabelColor: tokens.onSurfaceMuted,
          indicatorColor: context.accent,
          tabs: const [
            Tab(text: 'Languages', icon: Icon(Icons.translate_rounded, size: 18)),
            Tab(text: 'Channels', icon: Icon(Icons.subscriptions_outlined, size: 18)),
            Tab(text: 'Bible Version', icon: Icon(Icons.menu_book_rounded, size: 18)),
          ],
        ),
      ),
      body: MaxWidthBox(
        maxWidth: 840,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildLanguagesTab(context),
            _buildChannelsTab(context),
            _buildBibleTab(context),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 1: Content Languages
  // -------------------------------------------------------------
  Widget _buildLanguagesTab(BuildContext context) {
    final tokens = context.tokens;
    final allLanguages = LanguageMeta.supportedLanguages.values
        .where((l) => l.code.toLowerCase() != 'all')
        .toList();

    final query = _languageSearch.trim().toLowerCase();
    final filtered = query.isEmpty
        ? allLanguages
        : allLanguages.where((l) {
            return l.englishName.toLowerCase().contains(query) ||
                l.nativeName.toLowerCase().contains(query) ||
                l.code.toLowerCase().contains(query);
          }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Library & Audio Languages',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: context.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Filter books, sermons, articles, and songs by your selected languages.',
            style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search languages...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: tokens.surfaceVariant,
            ),
            onChanged: (val) => setState(() => _languageSearch = val),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final lang = filtered[index];
                final isSelected = _currentPref.languages.contains(lang.code);

                return Material(
                  color: isSelected
                      ? context.primary.withValues(alpha: 0.1)
                      : tokens.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected ? context.primary : tokens.surfaceBorder,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: CheckboxListTile(
                    value: isSelected,
                    activeColor: context.primary,
                    dense: true,
                    title: Text(
                      lang.englishName,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: lang.nativeName.isNotEmpty &&
                            lang.nativeName != lang.englishName
                        ? Text(lang.nativeName, style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted))
                        : null,
                    onChanged: (val) {
                      final newLangs = List<String>.from(_currentPref.languages);
                      if (val == true) {
                        if (!newLangs.contains(lang.code)) newLangs.add(lang.code);
                      } else {
                        if (newLangs.length > 1) {
                          newLangs.remove(lang.code);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('At least one language is required')),
                          );
                          return;
                        }
                      }
                      _updatePreferences(_currentPref.copyWith(languages: newLangs));
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 2: Followed Channels (Unified via ChannelService)
  // -------------------------------------------------------------
  Widget _buildChannelsTab(BuildContext context) {
    final tokens = context.tokens;
    final channels = _channelService.channels;
    final followedIds = _channelService.subscribedChannelIds;

    if (_channelService.isLoading && channels.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final query = _channelSearch.trim().toLowerCase();
    final filtered = query.isEmpty
        ? channels
        : channels.where((c) {
            return c.name.toLowerCase().contains(query) ||
                (c.description ?? '').toLowerCase().contains(query);
          }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Followed Channels',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: context.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Channels featured in your video and shorts feeds.',
            style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search channels...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: tokens.surfaceVariant,
                  ),
                  onChanged: (val) {
                    setState(() {
                      _channelSearch = val;
                    });
                  },
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(44, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: channels.isEmpty
                    ? null
                    : () async {
                        final allIds = channels.map((c) => c.id).toSet();
                        await _channelService.saveChannelSelections(
                          Set<String>.from(followedIds),
                          allIds,
                        );
                      },
                child: const Text('All'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(44, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: followedIds.isEmpty
                    ? null
                    : () async {
                        await _channelService.saveChannelSelections(
                          Set<String>.from(followedIds),
                          const <String>{},
                        );
                      },
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No channels found',
                      style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final ch = filtered[index];
                      final isFollowed = followedIds.contains(ch.id);

                      return ChannelFollowTile(
                        channelId: ch.id,
                        title: ch.name,
                        avatarUrl: ch.avatarUrl,
                        subscriberCount: ch.subscriberCount,
                        videoCount: ch.videoCount,
                        isFollowed: isFollowed,
                        badge: ch.hasShorts
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: ScreenClass.of(context).isCompact
                                    ? Icon(
                                        Icons.bolt_rounded,
                                        size: 12,
                                        color: Theme.of(context).colorScheme.error,
                                        semanticLabel: 'Shorts',
                                      )
                                    : Text(
                                        'SHORTS',
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.error,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              )
                            : null,
                        onToggleFollow: () => _channelService.toggleFollow(ch.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 3: Primary Bible Version
  // -------------------------------------------------------------
  Widget _buildBibleTab(BuildContext context) {
    final tokens = context.tokens;
    final selectedLanguages = _currentPref.languages
        .map((code) => code.toLowerCase())
        .toSet();

    // Filter catalog based on chosen languages
    final candidateBibles = BibleDownloadManager.catalog.where((b) {
      return selectedLanguages.contains(b.languageCode.toLowerCase());
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Primary Bible Version',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: context.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose your default Bible translation for reading and study.',
            style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: candidateBibles.isEmpty
                ? Center(
                    child: Text(
                      'No Bible versions found for your selected languages.',
                      style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
                    ),
                  )
                : ListView.separated(
                    itemCount: candidateBibles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final b = candidateBibles[index];
                      final isPrimary = _currentPref.primaryBibleVersionId.toUpperCase() ==
                          b.id.toUpperCase();

                      final nativeScript = BibleVersionNativeNames.getNativeScript(
                        b.id,
                        language: b.language,
                        languageCode: b.languageCode,
                      );

                      return Material(
                        color: isPrimary
                            ? context.primary.withValues(alpha: 0.1)
                            : tokens.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isPrimary ? context.primary : tokens.surfaceBorder,
                            width: isPrimary ? 1.5 : 1.0,
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          onTap: () {
                            if (!isPrimary) {
                              _updatePreferences(
                                _currentPref.copyWith(
                                  primaryBibleVersionId: b.id,
                                ),
                              );
                            }
                          },
                          title: Row(
                            children: [
                              Text(
                                b.id,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  b.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          subtitle: nativeScript.isNotEmpty && nativeScript != b.name
                              ? Text(
                                  '$nativeScript • ${b.language}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: tokens.onSurfaceMuted,
                                  ),
                                )
                              : Text(
                                  b.language,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: tokens.onSurfaceMuted,
                                  ),
                                ),
                          trailing: isPrimary
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    'PRIMARY',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onPrimary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : Icon(
                                  Icons.radio_button_unchecked,
                                  size: 20,
                                  color: tokens.onSurfaceMuted,
                                ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
