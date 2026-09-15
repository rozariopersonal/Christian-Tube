import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../controllers/feedback_controller.dart';
import '../services/feedback_context_service.dart';

class VoiceFeedbackSheet extends StatefulWidget {
  final FeedbackController controller;

  static final ValueNotifier<bool> isSheetOpen = ValueNotifier<bool>(false);

  const VoiceFeedbackSheet({
    super.key,
    required this.controller,
  });

  static Future<void> show(BuildContext context) async {
    final routeState = GoRouterState.of(context);
    const contextService = FeedbackContextService();
    final screenContext = contextService.resolveScreenContext(
      routePath: routeState.uri.path,
      queryParams: routeState.uri.queryParameters,
      context: context,
    );
    final diagnostics = contextService.collectDiagnostics(context);

    final controller = FeedbackController();
    controller.initializeContext(
      screenContext: screenContext,
      route: routeState.uri.toString(),
      diagnostics: diagnostics,
    );

    controller.startListening();

    isSheetOpen.value = true;
    bool? result;
    String? issueUrl;
    String? issueNumber;
    try {
      result = await showAdaptiveBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => VoiceFeedbackSheet(controller: controller),
      );
      issueUrl = controller.submittedIssueUrl;
      issueNumber = controller.submittedIssueNumber;
    } finally {
      isSheetOpen.value = false;
      controller.dispose();
    }

    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  issueUrl != null
                      ? 'Feedback submitted as issue #$issueNumber'
                      : 'Thank you! Your feedback has been submitted.',
                ),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          action: issueUrl != null
              ? SnackBarAction(
                  label: 'View',
                  textColor: Colors.white,
                  onPressed: () => launchGitHubIssue(issueUrl!),
                )
              : null,
        ),
      );
    }
  }

  static Future<void> launchGitHubIssue(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  State<VoiceFeedbackSheet> createState() => _VoiceFeedbackSheetState();
}

class _VoiceFeedbackSheetState extends State<VoiceFeedbackSheet> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.controller.text);
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (_textController.text != widget.controller.text) {
      final oldSelection = _textController.selection;
      _textController.text = widget.controller.text;
      if (oldSelection.start <= _textController.text.length) {
        _textController.selection = oldSelection;
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final editorHeight = screenHeight * 0.60;

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final isListening = widget.controller.isListening;
        final isSubmitting =
            widget.controller.submitState == FeedbackSubmitState.submitting;
        final isError =
            widget.controller.submitState == FeedbackSubmitState.error;

        return MaxWidthBox(
          maxWidth: 640,
          child: Container(
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: tokens.surfaceBorder, width: 1),
              boxShadow: [
                BoxShadow(
                  color: tokens.scrim.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
                  left: 16,
                  right: 16,
                  top: 10,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag Handle
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: tokens.onSurfaceDisabled
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Context Chip & Listening Indicator
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: tokens.surfaceVariant,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: tokens.surfaceBorder,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.location_on,
                                    size: 15, color: tokens.accent),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    widget.controller.screenContext,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: tokens.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        InkWell(
                          onTap: isSubmitting
                              ? null
                              : () => widget.controller.toggleListening(),
                          borderRadius: BorderRadius.circular(20),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isListening
                                  ? tokens.accent.withValues(alpha: 0.2)
                                  : tokens.surfaceVariant,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isListening
                                    ? tokens.accent
                                    : tokens.surfaceBorder,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isListening ? Icons.mic : Icons.mic_none,
                                  size: 16,
                                  color: isListening
                                      ? tokens.accent
                                      : tokens.onSurfaceMuted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isListening ? 'Listening...' : 'Tap to speak',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isListening
                                        ? tokens.accent
                                        : tokens.onSurfaceMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Editor
                    Container(
                      height: editorHeight,
                      decoration: BoxDecoration(
                        color: tokens.surfaceVariant,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isListening
                              ? tokens.accent.withValues(alpha: 0.6)
                              : tokens.surfaceBorder,
                          width: isListening ? 1.5 : 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(14),
                      child: TextField(
                        controller: _textController,
                        onChanged: (val) =>
                            widget.controller.updateText(val),
                        enabled: !isSubmitting,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.45,
                          color: tokens.onSurface,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Speak or type your feedback here...\n\nTell us what happened, what went wrong, or what you would love to see.',
                          hintStyle: TextStyle(
                            fontSize: 14,
                            color: tokens.onSurfaceMuted,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),

                    // Error Banner
                    if (isError && widget.controller.errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .error
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .error
                                .withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                size: 18,
                                color:
                                    Theme.of(context).colorScheme.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.controller.errorMessage!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),

                    // Action Buttons
                    Row(
                      children: [
                        TextButton(
                          onPressed: isSubmitting
                              ? null
                              : () {
                                  widget.controller.stopListening();
                                  Navigator.pop(context, false);
                                },
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: tokens.onSurfaceMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (isError)
                          OutlinedButton.icon(
                            onPressed: () {
                              widget.controller.resetToIdle();
                            },
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Retry'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: tokens.onSurface,
                              side: BorderSide(color: tokens.surfaceBorder),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                          )
                        else
                          ElevatedButton(
                            onPressed:
                                (widget.controller.canSubmit && !isSubmitting)
                                    ? () async {
                                        final ok =
                                            await widget.controller.submit();
                                        if (ok && context.mounted) {
                                          Navigator.pop(context, true);
                                        }
                                      }
                                    : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: tokens.accent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 28, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              elevation: 0,
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black,
                                    ),
                                  )
                                : const Text(
                                    'Submit',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
