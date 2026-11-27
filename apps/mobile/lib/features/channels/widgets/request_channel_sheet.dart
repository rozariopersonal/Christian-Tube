import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/ui/channel_follow_tile.dart';

typedef ChannelSubmitCallback = Future<({bool ok, String? error})> Function(
  String url,
  String name,
);
typedef ChannelSearchCallback = Future<List<Map<String, dynamic>>> Function(
  String query,
);

class RequestChannelBottomSheet extends StatefulWidget {
  final ChannelSubmitCallback onSubmitRequest;
  final ChannelSearchCallback onSearch;
  final String? Function()? getLastSearchError;
  final String? initialQuery;

  const RequestChannelBottomSheet({
    super.key,
    required this.onSubmitRequest,
    required this.onSearch,
    this.getLastSearchError,
    this.initialQuery,
  });

  @override
  State<RequestChannelBottomSheet> createState() =>
      _RequestChannelBottomSheetState();
}

class _RequestChannelBottomSheetState extends State<RequestChannelBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  String? _searchError;
  String? _submitError;
  String? _submittingId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _searchController.text = initial;
      if (initial.length >= 2) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _search(initial);
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
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
      _hasSearched = true;
      _searchError = widget.getLastSearchError?.call();
    });
  }

  Future<void> _submit(String idKey, String url, String name) async {
    if (_submittingId != null) return;
    setState(() {
      _submittingId = idKey;
      _submitError = null;
    });
    final res = await widget.onSubmitRequest(url, name);
    if (!mounted) return;
    if (res.ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _submittingId = null;
        _submitError = res.error ?? 'Failed to submit request';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final queryText = _searchController.text.trim();
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
                    'Request Channel',
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
            const SizedBox(height: 6),
            Text(
              'Search YouTube or paste a channel URL to request it for admin review:',
              style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _searchController,
              enabled: !isBusy,
              decoration: InputDecoration(
                hintText: 'Search YouTube channel or paste URL...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: isBusy ? null : () => _search(_searchController.text),
                ),
                filled: true,
                fillColor: tokens.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: _search,
            ),
            if (_submitError != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            if (queryText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.28),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.send_rounded,
                      color: theme.colorScheme.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Request "$queryText" directly',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 34),
                      ),
                      onPressed: isBusy
                          ? null
                          : () => _submit('__direct__', queryText, queryText),
                      child: _submittingId == '__direct__'
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                          : const Text('Submit', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
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
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _searchError!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    : _searchResults.isEmpty
                        ? Center(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.search,
                                    size: 44,
                                    color: tokens.onSurfaceDisabled,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _hasSearched
                                        ? 'No matching channels found. Use "Submit" above to request by URL.'
                                        : 'Search for a YouTube channel above',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: tokens.onSurfaceMuted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(top: 6),
                            itemCount: _searchResults.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
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
                                            : () => _submit(id, id, name),
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
                                                'Request',
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
