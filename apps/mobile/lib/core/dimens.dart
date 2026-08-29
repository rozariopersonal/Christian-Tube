import 'package:flutter/widgets.dart';

/// Single set of spacing/radius/min-touch constants replacing scattered
/// literals. Add to this file instead of inventing ad-hoc values.
class AppDimens {
  AppDimens._();

  // Spacing scale (dp)
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  // Radii (dp)
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusPill = 20;

  // Interactive
  static const double minTouchTarget = 48;

  // Standard side padding for content lists.
  static const EdgeInsets contentPadding = EdgeInsets.symmetric(horizontal: AppDimens.lg);
}