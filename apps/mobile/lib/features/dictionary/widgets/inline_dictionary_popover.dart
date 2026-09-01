import 'package:flutter/material.dart';
import '../../../../core/layout/adaptivity.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/dictionary_entry.dart';
import '../services/dictionary_download_manager.dart';
import '../services/dictionary_service.dart';

/// Modal bottom sheet or dialog displaying inline dictionary definitions for a selected word.
class InlineDictionaryPopover extends StatefulWidget {
  final String word;
  final String? preferredLanguageCode;

  const InlineDictionaryPopover({
    super.key,
    required this.word,
    this.preferredLanguageCode,
  });

  static Future<void> show(
    BuildContext context, {
    required String word,
    String? preferredLanguageCode,
  }) async {
    final screen = ScreenClass.of(context);
    if (screen.isCompact) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => InlineDictionaryPopover(
          word: word,
          preferredLanguageCode: preferredLanguageCode,
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 580),
            child: InlineDictionaryPopover(
              word: word,
              preferredLanguageCode: preferredLanguageCode,
            ),
          ),
        ),
      );
    }
  }

  @override
  State<InlineDictionaryPopover> createState() => _InlineDictionaryPopoverState();
}

class _InlineDictionaryPopoverState extends State<InlineDictionaryPopover> {
  final DictionaryService _service = DictionaryService();
  final DictionaryDownloadManager _downloadManager = DictionaryDownloadManager();

  List<DictionaryEntry> _entries = [];
  bool _isLoading = true;
  bool _hasAnyDictionary = false;
  late TextEditingController _searchCtrl;
  bool _showSearchBar = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: _service.cleanWord(widget.word));
    _showSearchBar = _searchCtrl.text.trim().isEmpty;
    _downloadManager.addListener(_onManagerUpdate);
    _lookup(_searchCtrl.text);
  }

  @override
  void dispose() {
    _downloadManager.removeListener(_onManagerUpdate);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onManagerUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _lookup([String? wordToQuery]) async {
    final query = (wordToQuery ?? _searchCtrl.text).trim();
    setState(() => _isLoading = true);
    await _downloadManager.initialize();

    final hasAny = _downloadManager.installedIds.isNotEmpty;
    final entries = query.isNotEmpty
        ? await _service.lookupWord(
            query,
            preferredLangCode: widget.preferredLanguageCode,
          )
        : <DictionaryEntry>[];

    if (mounted) {
      setState(() {
        _hasAnyDictionary = hasAny;
        _entries = entries;
        _isLoading = false;
      });
    }
  }

  String get _targetLang =>
      widget.preferredLanguageCode ??
      DictionaryService.detectLanguageCode(_searchCtrl.text) ??
      'en';

  DictionaryMeta get _targetMeta =>
      DictionaryDownloadManager.catalog.firstWhere(
        (c) => c.id == _targetLang,
        orElse: () => DictionaryDownloadManager.catalog.first,
      );

  Future<void> _downloadTargetDict() async {
    await _downloadManager.downloadDictionary(_targetLang);
    await _lookup();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final cleanWord = _service.cleanWord(_searchCtrl.text);
    final targetLangNotInstalled =
        !_downloadManager.installedIds.contains(_targetLang);

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: tokens.surfaceBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          if (_showSearchBar || cleanWord.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: cleanWord.isEmpty,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (val) => _lookup(val),
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Type a word to define…',
                        hintStyle: TextStyle(color: tokens.onSurfaceMuted, fontSize: 14),
                        prefixIcon: Icon(Icons.search, color: tokens.accent, size: 20),
                        isDense: true,
                        filled: true,
                        fillColor: tokens.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: tokens.surfaceBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: tokens.surfaceBorder),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.close, color: tokens.onSurfaceMuted, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cleanWord,
                        style: TextStyle(
                          color: tokens.onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'serif',
                        ),
                      ),
                      if (_entries.isNotEmpty && _entries.first.phonetic.isNotEmpty)
                        Text(
                          _entries.first.phonetic,
                          style: TextStyle(
                            color: tokens.accent,
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.search, color: tokens.onSurfaceMuted, size: 20),
                  tooltip: 'Search another word',
                  onPressed: () => setState(() => _showSearchBar = true),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: tokens.onSurfaceMuted, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Divider(color: tokens.surfaceBorder, height: 1),
          const SizedBox(height: 12),

          // Content
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: tokens.accent),
                  )
                : (!_hasAnyDictionary || targetLangNotInstalled && _entries.isEmpty)
                    ? _buildDownloadDictionaryCard(tokens)
                    : _entries.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.menu_book_outlined, size: 40, color: tokens.onSurfaceMuted),
                                  const SizedBox(height: 10),
                                  Text(
                                    cleanWord.isEmpty
                                        ? 'Enter a word to view definitions'
                                        : 'No definition found for "$cleanWord"',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 14),
                                  ),
                                  const SizedBox(height: 14),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      Navigator.of(context).pushNamed('/downloads');
                                    },
                                    icon: const Icon(Icons.download_for_offline_rounded, size: 16),
                                    label: const Text('Manage Offline Dictionaries'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _entries.length,
                            separatorBuilder: (_, __) => Divider(color: tokens.surfaceBorder, height: 20),
                            itemBuilder: (context, index) {
                              final entry = _entries[index];
                              return _buildEntryItem(entry, tokens);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadDictionaryCard(AppTokens tokens) {
    final meta = _targetMeta;
    final isDownloading = _downloadManager.isDownloading(meta.id);
    final progress = _downloadManager.getProgress(meta.id);

    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tokens.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.surfaceBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_for_offline_rounded, size: 36, color: tokens.accent),
            const SizedBox(height: 10),
            Text(
              '${meta.name} Not Downloaded',
              style: TextStyle(
                color: tokens.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Download the offline ${meta.name} (${meta.sizeDisplay}) for instant word definitions in Scripture and Books.',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            if (isDownloading) ...[
              LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                color: tokens.accent,
                backgroundColor: tokens.surface,
              ),
              const SizedBox(height: 8),
              Text(
                'Downloading ${(progress * 100).toInt()}%...',
                style: TextStyle(color: tokens.accent, fontSize: 12),
              ),
            ] else
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: tokens.accent),
                onPressed: _downloadTargetDict,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text('Download ${meta.name} (${meta.sizeDisplay})'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryItem(DictionaryEntry entry, AppTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (entry.partOfSpeech.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: tokens.surfaceVariant,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: tokens.surfaceBorder),
                ),
                child: Text(
                  entry.partOfSpeech.toLowerCase(),
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Text(
              entry.source,
              style: TextStyle(
                color: tokens.onSurfaceMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          entry.definition,
          style: TextStyle(
            color: tokens.onSurface,
            fontSize: 14.5,
            height: 1.45,
          ),
        ),
        if (entry.examples.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '“${entry.examples}”',
            style: TextStyle(
              color: tokens.onSurfaceMuted,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}
