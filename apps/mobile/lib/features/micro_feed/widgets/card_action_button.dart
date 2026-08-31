import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';

class CardActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? iconColor;
  final bool isActive;

  const CardActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.onLongPress,
    this.iconColor,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? context.tokens.onScrim.withValues(alpha: 0.25)
                    : context.tokens.scrim.withValues(alpha: 0.4),
                border: Border.all(
                  color: isActive
                      ? context.tokens.onScrim.withValues(alpha: 0.6)
                      : context.tokens.onScrim.withValues(alpha: 0.15),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: context.tokens.scrim.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: iconColor ?? context.tokens.onScrim,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: context.tokens.onScrim.withValues(alpha: 0.9),
                fontSize: 11,
                fontWeight: FontWeight.w500,
                shadows: const [
                  Shadow(
                    color: context.tokens.scrim.withValues(alpha: 0.87),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
