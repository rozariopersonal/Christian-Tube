import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/theme/app_tokens.dart';
import '../models/verse_concept.dart';

class VerseConceptCard extends StatefulWidget {
  final VerseConcept concept;
  final double baseFontSize;

  const VerseConceptCard({
    Key? key,
    required this.concept,
    this.baseFontSize = 16.0,
  }) : super(key: key);

  @override
  State<VerseConceptCard> createState() => _VerseConceptCardState();
}

class _VerseConceptCardState extends State<VerseConceptCard> {
  bool _isExpanded = false;

  void _copyToClipboard() {
    final text = '${widget.concept.conceptName}: ${widget.concept.definition}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Concept copied to clipboard'),
        backgroundColor: context.tokens.surfaceVariant,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (Original Language)
          if (widget.concept.originalLanguage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                color: tokens.surfaceVariant.withOpacity(0.5),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          widget.concept.originalLanguage!.originalWord.isNotEmpty 
                              ? widget.concept.originalLanguage!.originalWord 
                              : widget.concept.originalLanguage!.lemma,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'serif',
                            color: tokens.onSurface,
                            height: 1.2,
                          ),
                          textDirection: TextDirection.rtl, // Hebrew reads RTL
                        ),
                      ),
                      if (widget.concept.originalLanguage!.strongs.isNotEmpty || 
                          widget.concept.originalLanguage!.transliteration.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: tokens.background.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            [
                              widget.concept.originalLanguage!.strongs,
                              widget.concept.originalLanguage!.transliteration
                            ].where((s) => s.isNotEmpty).join(' | '),
                            style: TextStyle(
                              color: tokens.onSurfaceMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

          // Body Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Definition (Word Meaning First)
                Text(
                  'Word Meaning (Definition)',
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.concept.definition,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontSize: (widget.baseFontSize * 1.1).clamp(16.0, 24.0),
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),

                // 2. Concept Title
                Text(
                  'Concept Title',
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Concept: ${widget.concept.conceptName}',
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontSize: widget.baseFontSize.clamp(14.0, 20.0),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),

          // Deep Dive Accordion & Footer
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: tokens.surfaceBorder)),
            ),
            child: Column(
              children: [
                if (_isExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.concept.biblicalMeaning.isNotEmpty) ...[
                          Text('Biblical Meaning', style: _getSubtitleStyle(tokens)),
                          const SizedBox(height: 6),
                          MarkdownBody(data: widget.concept.biblicalMeaning, styleSheet: _getMarkdownStyle(tokens)),
                          const SizedBox(height: 16),
                        ],
                        if (widget.concept.historicalContext.isNotEmpty) ...[
                          Text('Historical Context', style: _getSubtitleStyle(tokens)),
                          const SizedBox(height: 6),
                          MarkdownBody(data: widget.concept.historicalContext, styleSheet: _getMarkdownStyle(tokens)),
                          const SizedBox(height: 16),
                        ],
                        if (widget.concept.culturalContext.isNotEmpty) ...[
                          Text('Cultural Context', style: _getSubtitleStyle(tokens)),
                          const SizedBox(height: 6),
                          MarkdownBody(data: widget.concept.culturalContext, styleSheet: _getMarkdownStyle(tokens)),
                          const SizedBox(height: 16),
                        ],
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                
                // Footer Buttons
                InkWell(
                  onTap: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Deep Dive (Biblical & Historical Context)',
                              style: TextStyle(
                                color: tokens.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                              color: tokens.accent,
                              size: 16,
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: _copyToClipboard,
                          icon: Icon(Icons.content_copy_outlined, size: 18, color: tokens.accent),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          style: IconButton.styleFrom(
                            backgroundColor: tokens.accent.withOpacity(0.1),
                            padding: const EdgeInsets.all(8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _getSubtitleStyle(AppTokens tokens) {
    return TextStyle(
      color: tokens.onSurface,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
  }

  MarkdownStyleSheet _getMarkdownStyle(AppTokens tokens) {
    return MarkdownStyleSheet(
      p: TextStyle(
        color: tokens.onSurfaceMuted,
        fontSize: (widget.baseFontSize * 0.95).clamp(14.0, 18.0),
        height: 1.5,
      ),
    );
  }
}
