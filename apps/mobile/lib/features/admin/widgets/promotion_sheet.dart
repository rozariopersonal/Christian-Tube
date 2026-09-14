import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/promotion_status.dart';
import '../services/release_promotion_service.dart';

class PromotionSheet extends StatefulWidget {
  final ReleasePromotionService? service;

  const PromotionSheet({super.key, this.service});

  static Future<void> show(BuildContext context,
      {ReleasePromotionService? service}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PromotionSheet(service: service),
    );
  }

  @override
  State<PromotionSheet> createState() => _PromotionSheetState();
}

class _PromotionSheetState extends State<PromotionSheet> {
  late final ReleasePromotionService _service;
  PromotionStatus? _status;
  bool _isLoading = true;
  bool _isPromoting = false;
  String? _errorMessage;
  String? _successMessage;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ReleasePromotionService();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final status = await _service.fetchStatus();
      if (mounted) {
        setState(() {
          _status = status;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handlePromote() async {
    setState(() {
      _isPromoting = true;
      _errorMessage = null;
    });

    try {
      final message = await _service.promoteToProduction();
      if (mounted) {
        setState(() {
          _isPromoting = false;
          _successMessage = message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPromoting = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isExpanded = screenWidth >= 600;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isExpanded ? 640 : double.infinity,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: tokens.surfaceBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.onSurfaceDisabled.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: tokens.accent.withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.rocket_launch_rounded,
                        color: tokens.accent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Promote to Production',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: tokens.onSurface,
                            ),
                          ),
                          Text(
                            'Deploy Beta integration channel to all users',
                            style: TextStyle(
                              fontSize: 12,
                              color: tokens.onSurfaceMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: tokens.onSurfaceMuted),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Body content
              Flexible(
                child: _buildBody(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final tokens = context.tokens;

    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: tokens.accent),
              const SizedBox(height: 16),
              Text(
                'Checking branch differences and build status...',
                style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
              ),
            ],
          ),
        ),
      );
    }

    if (_successMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Colors.green, size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              'Production Release Initiated!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: tokens.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _successMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: tokens.accent),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null && _status == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                color: tokens.onSurfaceDisabled, size: 48),
            const SizedBox(height: 12),
            Text(
              'Unable to Check Status',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: tokens.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _loadStatus,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final status = _status!;

    return ListView(
      padding: const EdgeInsets.all(20),
      shrinkWrap: true,
      children: [
        // Status overview card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surfaceVariant,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tokens.surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Integration Channel Status',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tokens.onSurfaceMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusChip(context, status),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Source (Beta)',
                            style: TextStyle(
                                fontSize: 11, color: tokens.onSurfaceMuted)),
                        const SizedBox(height: 2),
                        Text('develop',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: tokens.onSurface)),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_rounded,
                      color: tokens.onSurfaceDisabled, size: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Target (Production)',
                            style: TextStyle(
                                fontSize: 11, color: tokens.onSurfaceMuted)),
                        const SizedBox(height: 2),
                        Text(
                          status.latestProductionTag.isNotEmpty
                              ? status.latestProductionTag
                              : 'main',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: tokens.onSurface),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (status.message != null && status.message!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Text(
                  status.message!,
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.onSurfaceMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Commits Section
        if (status.commits.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Commits to Promote (${status.aheadCount})',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: tokens.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (status.aheadCount > status.commits.length) ...[
                const SizedBox(width: 8),
                Text(
                  'showing first ${status.commits.length}',
                  style: TextStyle(fontSize: 11, color: tokens.onSurfaceMuted),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: tokens.surfaceVariant.withAlpha(80),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tokens.surfaceBorder),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: status.commits.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: tokens.surfaceBorder),
              itemBuilder: (context, index) {
                final commit = status.commits[index];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: tokens.surface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: tokens.surfaceBorder),
                        ),
                        child: Text(
                          commit.sha,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: tokens.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              commit.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: tokens.onSurface,
                              ),
                            ),
                            Text(
                              commit.author,
                              style: TextStyle(
                                fontSize: 10,
                                color: tokens.onSurfaceMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Error message if promotion failed
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withAlpha(80)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Confirmation section
        if (status.canPromote) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.accent.withAlpha(15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tokens.accent.withAlpha(40)),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: _confirmed,
                  activeColor: tokens.accent,
                  onChanged: (val) {
                    setState(() {
                      _confirmed = val == true;
                    });
                  },
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _confirmed = !_confirmed;
                      });
                    },
                    child: Text(
                      'I have verified these Beta changes and approve releasing them to Production.',
                      style:
                          TextStyle(fontSize: 12, color: tokens.onSurface),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: tokens.accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed:
                  (_confirmed && !_isPromoting) ? _handlePromote : null,
              icon: _isPromoting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: tokens.surface,
                      ),
                    )
                  : const Icon(Icons.rocket_launch_rounded),
              label: Text(
                _isPromoting
                    ? 'Initiating Release...'
                    : 'Confirm & Release to Production',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ] else if (status.isBuilding) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withAlpha(80)),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.amber),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'A production build is currently in flight on GitHub Actions.',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Center(
            child: Text(
              'No action needed. Production is already current.',
              style: TextStyle(fontSize: 12, color: tokens.onSurfaceMuted),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatusChip(BuildContext context, PromotionStatus status) {
    final tokens = context.tokens;
    String label;
    Color chipColor;

    if (status.isBuilding) {
      label = 'Build in Progress';
      chipColor = Colors.amber;
    } else if (status.aheadCount > 0) {
      label = '${status.aheadCount} New Commit(s)';
      chipColor = tokens.accent;
    } else {
      label = 'Up to Date';
      chipColor = Colors.green;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: chipColor.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: chipColor,
        ),
      ),
    );
  }
}
