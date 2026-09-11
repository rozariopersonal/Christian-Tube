import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';

/// "Explore Topics" grid on the Audio Library home view. Selecting a topic
/// switches the active category filter via [onTopicSelected].
class AudioTopicsGrid extends StatelessWidget {
  final ValueChanged<String> onTopicSelected;

  const AudioTopicsGrid({
    super.key,
    required this.onTopicSelected,
  });

  static const _topics = [
    {
      'title': 'Overcoming Sin',
      'category': 'Christian Living',
      'icon': Icons.shield_outlined
    },
    {
      'title': 'Holy Spirit',
      'category': 'Christian Living',
      'icon': Icons.local_fire_department_outlined
    },
    {
      'title': 'Family & Home',
      'category': 'Family & Home',
      'icon': Icons.home_outlined
    },
    {
      'title': 'Faith & Victory',
      'category': 'Foundations',
      'icon': Icons.emoji_events_outlined
    },
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Explore Topics',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: tokens.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _topics.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 340,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.2,
                ),
                itemBuilder: (context, index) {
                  final topic = _topics[index];
                  return Material(
                    color: tokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onTopicSelected(topic['category'] as String),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            Icon(
                              topic['icon'] as IconData,
                              color: theme.colorScheme.primary,
                              size: 24,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                topic['title'] as String,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: tokens.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
