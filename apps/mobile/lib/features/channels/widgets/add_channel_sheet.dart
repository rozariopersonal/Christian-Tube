import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/ui/channel_follow_tile.dart';
import 'request_channel_sheet.dart';

class AddChannelBottomSheet extends StatefulWidget {
  final ChannelSubmitCallback onAddDirect;
  final ChannelSearchCallback onSearch;
  final String? Function()? getLastSearchError;
  final String? initialQuery;

  const AddChannelBottomSheet({
    super.key,
    required this.onAddDirect,
    required this.onSearch,
    this.getLastSearchError,
    this.initialQuery,
  });

  @override
  State<AddChannelBottomSheet> createState() => _AddChannelBottomSheetState();
}

class _AddChannelBottomSheetState extends State<AddChannelBottomSheet> {
  final TextEditingController _queryController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;
  String? _submitError;
  String? _submittingId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _queryController.text = initial;
      if (initial.length >= 2) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _performSearch(initial);
        });
      }
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String q) async {
    final trimmed = q.trim();
    if (trimmed.length < 2) {
      setState(() {
        _submitError = 'Enter at least 2 characters to search YouTube.';
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _searchError = null;
      _submitError = null;
    });
    final results = await widget.onSearch(trimmed);
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _isSearching = false;
      _searchError = widget.getLastSearchError?.call();
    });
  }

  Future<void> _add(String idKey, String url, String name) async {
    if (_submittingId != null) return;
    setState(() {
      _submittingId = idKey;
      _submitError = null;
    });
    final res = await widget.onAddDirect(url, name);
    if (!mounted) return;
    if (res.ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _submittingId = null;
        _submitError = res.error ?? 'Failed to add channel';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final queryText = _queryController.text.trim();
    final isBusy = _submittingId != null;

    return PopScope(
      canPop: !isBusy,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: tokens.surfaceBorder,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Add Channel (Admin)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: isBusy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _queryController,
              enabled: !isBusy,
              decoration: InputDecoration(
                hintText: 'Search YouTube channel or paste URL...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed:
                      isBusy ? null : () => _performSearch(_queryController.text),
                ),
                filled: true,
                fillColor: tokens.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: _performSearch,
            ),
            if (_submitError != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.error.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  _submitError!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (queryText.isNotEmpty) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.flash_on_rounded,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ingest "$queryText" directly',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: isBusy
                          ? null
                          : () => _add('__direct__', queryText, queryText),
                      child: _submittingId == '__direct__'
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                          : const Text('Add Now'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_isSearching)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              Flexible(
                child: _searchError != null
                    ? Center(
                        child: Text(
                          _searchError!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : _searchResults.isEmpty
                        ? Center(
                            child: Text(
                              'Search YouTube to directly ingest channels into the instance',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: tokens.onSurfaceMuted,
                                fontSize: 13,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(top: 8),
                            itemCount: _searchResults.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, idx) {
                              final r = _searchResults[idx];
                              final id = (r['id'] ?? '').toString();
                              final name =
                                  (r['name'] ?? 'Unknown Channel').toString();
                              final isExisting = r['isExisting'] == true;
                              final subs = r['subscriberCount'] != null
                                  ? int.tryParse(
                                          r['subscriberCount'].toString()) ??
                                      0
                                  : 0;

                              final isThisSubmitting = _submittingId == id;

                              return ChannelFollowTile(
                                channelId: id,
                                title: name,
                                avatarUrl: (r['thumbnail'] ?? '').toString(),
                                subscriberCount: subs,
                                subtitle: r['isSynthetic'] == true
                                    ? 'Unverified handle · ${r['handle'] ?? id}'
                                    : (subs > 0
                                        ? null
                                        : (r['handle']?.toString() ??
                                            r['description']?.toString() ??
                                            'YouTube Channel')),
                                actionButton: isExisting
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: tokens.surfaceVariant,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                            color: tokens.surfaceBorder,
                                          ),
                                        ),
                                        child: Text(
                                          'Added',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: tokens.onSurfaceMuted,
                                          ),
                                        ),
                                      )
                                    : ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              theme.colorScheme.primary,
                                          foregroundColor:
                                              theme.colorScheme.onPrimary,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          minimumSize: const Size(0, 34),
                                        ),
                                        onPressed: isBusy
                                            ? null
                                            : () => _add(id, id, name),
                                        child: isThisSubmitting
                                            ? SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: theme
                                                      .colorScheme.onPrimary,
                                                ),
                                              )
                                            : const Text(
                                                'Add',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                      ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
