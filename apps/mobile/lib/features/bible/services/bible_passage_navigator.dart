import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import '../models/bible_reference.dart';

/// A Bible reader that can accept a [BibleReference] and move to it in place.
typedef BiblePassageReceiver = void Function(BibleReference reference);

class _BibleReaderRegistration {
  final BuildContext context;
  final BiblePassageReceiver receiver;
  _BibleReaderRegistration(this.context, this.receiver);
}

/// Application-wide entry point for "go to Bible passage X".
///
/// Any feature (words feed, cross-references, book reader, the in-reader
/// selector, search, bookmarks) can hand the navigator a [BibleReference] and
/// the Bible reader moves there — scrolling to and highlighting the verse.
///
/// Behavior:
///  * If a Bible reader is currently visible on screen it navigates in place.
///  * Otherwise it opens the `/bible` route so a fresh reader starts at the
///    reference (the reader's own load-and-scroll pipeline takes over).
class BiblePassageNavigator {
  BiblePassageNavigator._();
  static final BiblePassageNavigator instance = BiblePassageNavigator._();

  final List<_BibleReaderRegistration> _registrations = [];
  GoRouter? _router;

  /// Stores the app router so [navigateTo] can open the reader from anywhere
  /// without call sites needing a [BuildContext].
  void init(GoRouter router) => _router = router;

  /// Clears router and registrations (used by tests).
  @visibleForTesting
  void reset() {
    _router = null;
    _registrations.clear();
  }

  /// Registers a Bible reader screen so in-place navigation can target it.
  void attach(BuildContext context, BiblePassageReceiver receiver) {
    detach(context, receiver);
    _registrations.add(_BibleReaderRegistration(context, receiver));
  }

  void detach(BuildContext context, BiblePassageReceiver receiver) {
    _registrations.removeWhere(
      (r) => identical(r.context, context) && identical(r.receiver, receiver),
    );
  }

  /// Moves the Bible reader to [reference]: in place when a reader is
  /// currently visible, otherwise by opening the `/bible` route.
  void navigateTo(BibleReference reference, {BuildContext? context}) {
    for (final registration in _registrations.reversed) {
      if (registration.context.mounted &&
          (ModalRoute.of(registration.context)?.isCurrent ?? false)) {
        registration.receiver(reference);
        return;
      }
    }
    final uri = _routeUri(reference);
    final router = _router;
    if (router != null) {
      router.push(uri);
      return;
    }
    final ctx = context;
    if (ctx != null && ctx.mounted) {
      ctx.push(uri);
      return;
    }
    assert(false, 'BiblePassageNavigator: no router or context available');
  }

  String _routeUri(BibleReference reference) {
    final verse = reference.verse;
    final versionId = reference.versionId;
    final params = <String, String>{
      'book': reference.bookName,
      'chapter': '${reference.chapter}',
    };
    if (verse != null) params['verse'] = '$verse';
    if (versionId != null) params['version'] = versionId;
    return '/bible?${Uri(queryParameters: params).query}';
  }
}