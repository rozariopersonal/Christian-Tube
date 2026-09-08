import '../../../shared/ui/language_meta.dart';

/// Backwards-compatible name for [LanguageMeta].
///
/// Kept so existing imports of `book_language_meta.dart` continue to work
/// during the migration to the shared `LanguageMeta` registry. New code should
/// import `package:mobile/shared/ui/language_meta.dart` directly.
typedef BookLanguageMeta = LanguageMeta;
