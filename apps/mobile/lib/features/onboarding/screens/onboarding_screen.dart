import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/config/app_config.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/models/user_preference.dart';
import '../../../core/services/user_preference_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_service.dart';
import '../../../shared/ui/language_meta.dart';
import '../../../shared/ui/bible_version_native_names.dart';
import '../../auth/auth_service.dart';
import '../../channels/channel_service.dart';
import '../../engines/scripture/models/bible_version_meta.dart';
import '../../engines/scripture/services/bible_download_manager.dart';

class OnboardingScreen extends StatefulWidget {
  final AuthService authService;
  final ThemeService themeService;

  const OnboardingScreen({
    super.key,
    required this.authService,
    required this.themeService,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final ChannelService _channelService = ChannelService();
  final UserPreferenceService _preferenceService = UserPreferenceService();

  int _currentStep = 0;
  static const int _totalSteps = 6;

  // Step 1: Languages
  final Set<String> _selectedLanguages = {'en'};
  String _languageSearch = '';

  // Step 2 & 3: Channels
  final Set<String> _selectedVideoChannels = {};
  final Set<String> _selectedShortsChannels = {};
  String _channelSearch = '';

  // Step 4: Bible Versions
  String _primaryBibleVersion = 'NASB';
  final Set<String> _selectedBibleVersions = {'NASB'};

  // Step 5: Personalization
  AppColorTheme _selectedColorTheme = AppColorTheme.blue;
  ThemeMode _selectedThemeMode = ThemeMode.system;
  bool _isAmoled = false;
  bool _dailyReminderEnabled = true;
  String _dailyReminderTime = '07:00';

  bool _isSaving = false;
  bool _channelsLoaded = false;
  bool _hasRestoredExisting = false;

  @override
  void initState() {
    super.initState();
    _selectedColorTheme = widget.themeService.colorTheme;
    _selectedThemeMode = widget.themeService.themeMode;
    _isAmoled = widget.themeService.isAmoled;

    // Load available channels for step 2 & 3
    _loadChannels();

    // Check if user is already authenticated and has preferences
    if (widget.authService.isAuthenticated) {
      _checkExistingPreferences();
    }
    widget.authService.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    widget.authService.removeListener(_onAuthChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (widget.authService.isAuthenticated && !_hasRestoredExisting) {
      _checkExistingPreferences();
    }
  }

  Future<void> _loadChannels() async {
    await _channelService.fetchChannels();
    if (mounted) {
      setState(() {
        _channelsLoaded = true;
        // Pre-select popular channels if empty
        if (_selectedVideoChannels.isEmpty && _channelService.channels.isNotEmpty) {
          final topChannels = _channelService.channels.take(4).map((c) => c.id).toSet();
          _selectedVideoChannels.addAll(topChannels);
          _selectedShortsChannels.addAll(topChannels);
        }
      });
    }
  }

  Future<void> _checkExistingPreferences() async {
    final pref = await _preferenceService.fetchPreferences(auth: widget.authService);
    if (pref.hasCompletedOnboarding && mounted) {
      setState(() {
        _hasRestoredExisting = true;
      });
    }
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
      );
      setState(() => _currentStep++);
    } else {
      _finishOnboarding();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
      );
      setState(() => _currentStep--);
    }
  }

  Future<void> _finishOnboarding() async {
    setState(() => _isSaving = true);

    try {
      // 1. Construct final preference object
      final finalPref = UserPreference(
        languages: _selectedLanguages.toList(),
        videoChannelIds: _selectedVideoChannels.toList(),
        shortsChannelIds: _selectedShortsChannels.toList(),
        primaryBibleVersionId: _primaryBibleVersion,
        bibleVersionIds: _selectedBibleVersions.toList(),
        themeMode: _selectedThemeMode == ThemeMode.dark
            ? 'dark'
            : _selectedThemeMode == ThemeMode.light
                ? 'light'
                : 'system',
        accentColor: _selectedColorTheme.name.toLowerCase(),
        dailyReminderEnabled: _dailyReminderEnabled,
        dailyReminderTime: _dailyReminderTime,
        hasCompletedOnboarding: true,
      );

      // 2. Apply theme options
      await widget.themeService.setColorTheme(_selectedColorTheme);
      await widget.themeService.setThemeMode(_selectedThemeMode);
      await widget.themeService.setAmoled(_isAmoled);

      // 3. Save preferences locally & to cloud database
      await _preferenceService.savePreferences(
        finalPref,
        auth: widget.authService,
        syncWithBackend: widget.authService.isAuthenticated,
      );

      // 4. Mark completion and proceed to feed
      if (mounted) {
        context.go('/feed');
      }
    } catch (e) {
      debugPrint('Error finishing onboarding: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preferences saved with offline notice: $e')),
        );
        context.go('/feed');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return PopScope(
      canPop: _currentStep == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _currentStep > 0) {
          _previousStep();
        }
      },
      child: Scaffold(
        backgroundColor: tokens.background,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          elevation: 0,
          backgroundColor: tokens.background,
          titleSpacing: 16,
          title: Row(
            children: [
              Image.asset(
                'assets/logo.png',
                height: 26,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.menu_book_rounded, color: context.primary),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  AppConfig.appName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          actions: [
            if (_currentStep > 0)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    'Step ${_currentStep + 1} of $_totalSteps',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: tokens.onSurfaceMuted,
                    ),
                  ),
                ),
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / _totalSteps,
              backgroundColor: tokens.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(context.accent),
              minHeight: 3,
            ),
          ),
        ),
        body: MaxWidthBox(
          maxWidth: 640,
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildStep0Auth(context),
                    _buildStep1Languages(context),
                    _buildStep2VideoChannels(context),
                    _buildStep3ShortsChannels(context),
                    _buildStep4BibleVersions(context),
                    _buildStep5Personalization(context),
                  ],
                ),
              ),
              _buildBottomActionBar(context),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // STEP 0: Authentication (Google Sign-In)
  // -------------------------------------------------------------
  Widget _buildStep0Auth(BuildContext context) {
    final tokens = context.tokens;
    final isAuth = widget.authService.isAuthenticated;
    final user = widget.authService.currentUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: context.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                Icons.church_rounded,
                size: 46,
                color: context.primary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Welcome to ${AppConfig.appName}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Your sanctified, ad-free sanctuary for scripture study, sermons, and sacred music.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: tokens.onSurfaceMuted),
          ),
          const SizedBox(height: 24),

          // Features highlight list
          _buildValueCard(
            context,
            icon: Icons.translate_rounded,
            title: 'Multi-Lingual Content',
            subtitle: 'Personalize books, hymns, audio, and sermons in your languages.',
          ),
          const SizedBox(height: 10),
          _buildValueCard(
            context,
            icon: Icons.video_collection_outlined,
            title: 'Curated Video & Shorts Feeds',
            subtitle: 'Tailored channels with edifying teachings and biblical shorts.',
          ),
          const SizedBox(height: 10),
          _buildValueCard(
            context,
            icon: Icons.menu_book_rounded,
            title: 'Offline & Cloud Sync',
            subtitle: 'Read scriptures anywhere; restore preferences on any device.',
          ),
          const SizedBox(height: 28),

          // Existing User Detected Banner
          if (_hasRestoredExisting) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.accent.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: context.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Welcome back, ${user?.displayName ?? 'Friend'}!',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your preferences are already safely saved in the cloud. You can jump directly to your feed or review them.',
                    style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => context.go('/feed'),
                      child: const Text('Go Directly to Feed'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Sign In Buttons
          if (!isAuth) ...[
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: tokens.surfaceVariant,
                  foregroundColor: tokens.onSurface,
                  elevation: 0,
                  side: BorderSide(color: tokens.surfaceBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: widget.authService.isLoading
                    ? null
                    : () async {
                        final signedIn = await widget.authService.signInWithGoogle();
                        if (signedIn != null) {
                          await _checkExistingPreferences();
                          if (!_hasRestoredExisting) {
                            _nextStep();
                          }
                        }
                      },
                child: widget.authService.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.account_circle, color: context.primary),
                          const SizedBox(width: 8),
                          const Flexible(
                            child: Text(
                              'Sign in with Google',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                await widget.authService.signInAsGuest();
                _nextStep();
              },
              child: Text(
                'Continue as Guest (Setup Offline)',
                style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: tokens.surfaceVariant,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Builder(
                    builder: (context) {
                      final name = user?.displayName ?? '';
                      final initial = name.isNotEmpty ? name[0] : 'U';
                      return CircleAvatar(
                        backgroundImage: user?.photoUrl != null
                            ? CachedNetworkImageProvider(user!.photoUrl!)
                            : null,
                        child: user?.photoUrl == null ? Text(initial) : null,
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? 'Signed In',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          user?.email ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildValueCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: context.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: tokens.onSurfaceMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // STEP 1: Languages (Library & Audio)
  // -------------------------------------------------------------
  Widget _buildStep1Languages(BuildContext context) {
    final tokens = context.tokens;
    final allLanguages = LanguageMeta.supportedLanguages.values
        .where((l) => l.code.toLowerCase() != 'all')
        .toList();

    final query = _languageSearch.trim().toLowerCase();
    final filteredLanguages = query.isEmpty
        ? allLanguages
        : allLanguages.where((l) {
            return l.englishName.toLowerCase().contains(query) ||
                l.nativeName.toLowerCase().contains(query) ||
                l.code.toLowerCase().contains(query);
          }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Content Languages',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose the languages you want for your books, sermons, articles, and songs.',
            style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search languages (e.g. Tamil, Hindi, English)...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: tokens.surfaceVariant,
            ),
            onChanged: (val) => setState(() => _languageSearch = val),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: filteredLanguages.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final lang = filteredLanguages[index];
                final isSelected = _selectedLanguages.contains(lang.code);

                return InkWell(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        if (_selectedLanguages.length > 1) {
                          _selectedLanguages.remove(lang.code);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('At least one language is required')),
                          );
                        }
                      } else {
                        _selectedLanguages.add(lang.code);
                      }
                      _updateBibleVersionsForLanguages();
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? context.primary.withValues(alpha: 0.12)
                          : tokens.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? context.primary : tokens.surfaceBorder,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lang.englishName,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 14,
                                ),
                              ),
                              if (lang.nativeName.isNotEmpty &&
                                  lang.nativeName != lang.englishName)
                                Text(
                                  lang.nativeName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isSelected ? context.primary : tokens.onSurfaceMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Checkbox(
                          value: isSelected,
                          activeColor: context.primary,
                          onChanged: (_) {
                            setState(() {
                              if (isSelected) {
                                if (_selectedLanguages.length > 1) {
                                  _selectedLanguages.remove(lang.code);
                                }
                              } else {
                                _selectedLanguages.add(lang.code);
                              }
                              _updateBibleVersionsForLanguages();
                            });
                          },
                        ),
                      ],
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

  void _updateBibleVersionsForLanguages() {
    // When languages change, check if current primary Bible version is still valid
    final available = BibleDownloadManager.catalog.where((b) {
      final code = b.languageCode.toLowerCase();
      return _selectedLanguages.contains(code);
    }).toList();

    if (available.isNotEmpty) {
      if (!available.any((b) => b.id.toUpperCase() == _primaryBibleVersion.toUpperCase())) {
        _primaryBibleVersion = available.first.id;
        _selectedBibleVersions
          ..clear()
          ..add(available.first.id);
      }
    }
  }

  // -------------------------------------------------------------
  // STEP 2: YouTube Channels for Videos
  // -------------------------------------------------------------
  Widget _buildStep2VideoChannels(BuildContext context) {
    return _buildChannelSelectionStep(
      context,
      title: 'Follow Video Channels',
      subtitle: 'Pick YouTube channels to populate your main sermons & teachings feed.',
      selectedIds: _selectedVideoChannels,
      onToggle: (id) {
        setState(() {
          if (_selectedVideoChannels.contains(id)) {
            _selectedVideoChannels.remove(id);
          } else {
            _selectedVideoChannels.add(id);
          }
        });
      },
      onSelectAll: () {
        setState(() {
          _selectedVideoChannels.addAll(_channelService.channels.map((c) => c.id));
        });
      },
      onClearAll: () {
        setState(() {
          _selectedVideoChannels.clear();
        });
      },
    );
  }

  // -------------------------------------------------------------
  // STEP 3: Shorts Channels
  // -------------------------------------------------------------
  Widget _buildStep3ShortsChannels(BuildContext context) {
    return _buildChannelSelectionStep(
      context,
      title: 'Follow Shorts Channels',
      subtitle: 'Choose creators for short, inspiring devotionals and scripture clips.',
      selectedIds: _selectedShortsChannels,
      isShorts: true,
      onToggle: (id) {
        setState(() {
          if (_selectedShortsChannels.contains(id)) {
            _selectedShortsChannels.remove(id);
          } else {
            _selectedShortsChannels.add(id);
          }
        });
      },
      onSelectAll: () {
        setState(() {
          _selectedShortsChannels.addAll(_channelService.channels.map((c) => c.id));
        });
      },
      onClearAll: () {
        setState(() {
          _selectedShortsChannels.clear();
        });
      },
    );
  }

  Widget _buildChannelSelectionStep(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Set<String> selectedIds,
    required void Function(String id) onToggle,
    required VoidCallback onSelectAll,
    required VoidCallback onClearAll,
    bool isShorts = false,
  }) {
    final tokens = context.tokens;
    final channels = _channelService.channels;

    final query = _channelSearch.trim().toLowerCase();
    final filtered = query.isEmpty
        ? channels
        : channels.where((c) {
            return c.name.toLowerCase().contains(query) ||
                (c.description ?? '').toLowerCase().contains(query);
          }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search channels...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: tokens.surfaceVariant,
                  ),
                  onChanged: (val) => setState(() => _channelSearch = val),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onSelectAll,
                child: const Text('All'),
              ),
              TextButton(
                onPressed: onClearAll,
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!_channelsLoaded && channels.isEmpty)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filtered.isEmpty)
            Expanded(
              child: Center(
                child: Text('No channels found', style: TextStyle(color: tokens.onSurfaceMuted)),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final ch = filtered[index];
                  final isFollowed = selectedIds.contains(ch.id);

                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isFollowed ? context.accent : tokens.surfaceBorder,
                        width: isFollowed ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundImage: ch.avatarUrl.isNotEmpty
                              ? CachedNetworkImageProvider(ch.avatarUrl)
                              : null,
                          child: ch.avatarUrl.isEmpty
                              ? Text(ch.name.substring(0, 1))
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      ch.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ),
                                  if (isShorts) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'SHORTS',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${ch.subscriberCount} subscribers • ${ch.videoCount} videos',
                                style: TextStyle(fontSize: 12, color: tokens.onSurfaceMuted),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isFollowed
                                ? context.accent
                                : tokens.surfaceVariant,
                            foregroundColor: isFollowed
                                ? Colors.white
                                : tokens.onSurface,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          onPressed: () => onToggle(ch.id),
                          child: Text(
                            isFollowed ? 'Following' : 'Follow',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
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
  // STEP 4: Preferred Bible Versions
  // -------------------------------------------------------------
  Widget _buildStep4BibleVersions(BuildContext context) {
    final tokens = context.tokens;

    // Filter catalog based on chosen languages
    final candidateBibles = BibleDownloadManager.catalog.where((b) {
      final code = b.languageCode.toLowerCase();
      return _selectedLanguages.contains(code);
    }).toList();

    // Group bibles by language
    final Map<String, List<BibleVersionMeta>> grouped = {};
    for (final b in candidateBibles) {
      grouped.putIfAbsent(b.language, () => []).add(b);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Preferred Bible Translations',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Select your primary reading translation, tailored to your selected languages.',
            style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
          ),
          const SizedBox(height: 12),
          if (candidateBibles.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'No Bible translations found for your selected languages. Please go back and select English or other supported languages.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tokens.onSurfaceMuted),
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                children: grouped.entries.map((entry) {
                  final langName = entry.key;
                  final bibles = entry.value;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          langName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: context.primary,
                          ),
                        ),
                      ),
                      ...bibles.map((b) {
                        final isPrimary = _primaryBibleVersion.toUpperCase() == b.id.toUpperCase();
                        final isChecked = _selectedBibleVersions.contains(b.id) || isPrimary;
                        final nativeScript = BibleVersionNativeNames.getNativeScript(
                          b.id,
                          language: b.language,
                          languageCode: b.languageCode,
                        );

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Material(
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
                              setState(() {
                                _primaryBibleVersion = b.id;
                                _selectedBibleVersions.add(b.id);
                              });
                            },
                            title: Row(
                              children: [
                                Text(
                                  b.id,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                                    nativeScript,
                                    style: TextStyle(fontSize: 11, color: tokens.onSurfaceMuted),
                                  )
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isPrimary)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: context.primary,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'PRIMARY',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                else
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _primaryBibleVersion = b.id;
                                        _selectedBibleVersions.add(b.id);
                                      });
                                    },
                                    child: const Text('Set Primary', style: TextStyle(fontSize: 12)),
                                  ),
                                Checkbox(
                                  value: isChecked,
                                  activeColor: context.primary,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedBibleVersions.add(b.id);
                                      } else if (!isPrimary) {
                                        _selectedBibleVersions.remove(b.id);
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                      const SizedBox(height: 10),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // STEP 5: App Personalization & Daily Reminder
  // -------------------------------------------------------------
  Widget _buildStep5Personalization(BuildContext context) {
    final tokens = context.tokens;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Personalize Your App',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Customize appearance themes and set daily scripture reminders.',
            style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
          ),
          const SizedBox(height: 16),

          // Theme Mode
          const Text('Theme Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildChoiceChip(
                label: 'System',
                icon: Icons.settings_brightness,
                selected: _selectedThemeMode == ThemeMode.system,
                onSelected: () => setState(() => _selectedThemeMode = ThemeMode.system),
              ),
              const SizedBox(width: 8),
              _buildChoiceChip(
                label: 'Dark',
                icon: Icons.dark_mode_outlined,
                selected: _selectedThemeMode == ThemeMode.dark,
                onSelected: () => setState(() => _selectedThemeMode = ThemeMode.dark),
              ),
              const SizedBox(width: 8),
              _buildChoiceChip(
                label: 'Light',
                icon: Icons.light_mode_outlined,
                selected: _selectedThemeMode == ThemeMode.light,
                onSelected: () => setState(() => _selectedThemeMode = ThemeMode.light),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.brightness_2_outlined),
            title: const Text('OLED Pure Black', style: TextStyle(fontSize: 14)),
            subtitle: Text('Deep black background in dark mode', style: TextStyle(fontSize: 12, color: tokens.onSurfaceMuted)),
            value: _isAmoled,
            activeThumbColor: context.accent,
            onChanged: (val) => setState(() => _isAmoled = val),
          ),
          const Divider(height: 24),

          // Accent Color
          const Text('Interface Accent Color', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: AppColorTheme.values.map((colTheme) {
              final isSelected = _selectedColorTheme == colTheme;
              return InkWell(
                onTap: () => setState(() => _selectedColorTheme = colTheme),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colTheme.color.withValues(alpha: 0.15)
                        : tokens.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? colTheme.color : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(radius: 8, backgroundColor: colTheme.color),
                      const SizedBox(width: 8),
                      Text(
                        colTheme.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? colTheme.color : null,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const Divider(height: 28),

          // Daily Scripture Notification
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(Icons.notifications_active_outlined, color: context.accent),
            title: const Text('Daily Scripture Reminder', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            subtitle: Text(
              'Receive an edifying scripture verse notification each morning',
              style: TextStyle(fontSize: 12, color: tokens.onSurfaceMuted),
            ),
            value: _dailyReminderEnabled,
            activeThumbColor: context.accent,
            onChanged: (val) => setState(() => _dailyReminderEnabled = val),
          ),
          if (_dailyReminderEnabled) ...[
            const SizedBox(height: 6),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time_rounded),
              title: const Text('Reminder Time', style: TextStyle(fontSize: 13)),
              trailing: Text(
                _dailyReminderTime,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: context.accent,
                ),
              ),
              onTap: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime: const TimeOfDay(hour: 7, minute: 0),
                );
                if (time != null && mounted) {
                  setState(() {
                    final h = time.hour.toString().padLeft(2, '0');
                    final m = time.minute.toString().padLeft(2, '0');
                    _dailyReminderTime = '$h:$m';
                  });
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    final tokens = context.tokens;
    return Expanded(
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? context.accent.withValues(alpha: 0.15) : tokens.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? context.accent : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: selected ? context.accent : tokens.onSurface),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? context.accent : tokens.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Bottom Action Bar
  // -------------------------------------------------------------
  Widget _buildBottomActionBar(BuildContext context) {
    final tokens = context.tokens;
    final isLastStep = _currentStep == _totalSteps - 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.surfaceBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_currentStep > 0)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: tokens.surfaceBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onPressed: _previousStep,
                child: const Text('Back'),
              ),
            if (_currentStep > 0) const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _isSaving
                    ? null
                    : () {
                        if (_currentStep == 0 && !widget.authService.isAuthenticated) {
                          // Allow continue as guest
                          widget.authService.signInAsGuest();
                          _nextStep();
                        } else {
                          _nextStep();
                        }
                      },
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        isLastStep
                            ? 'Complete & Start Exploring'
                            : _currentStep == 0
                                ? (widget.authService.isAuthenticated
                                    ? 'Continue'
                                    : 'Continue as Guest')
                                : 'Continue',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
