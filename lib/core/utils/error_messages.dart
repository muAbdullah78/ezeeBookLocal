import 'package:easy_localization/easy_localization.dart';

/// Maps a caught exception to a short, localized, user-friendly message.
/// Never surface raw exception strings (e.g. sqflite DatabaseException(...))
/// to end users — route everything through here.
///
/// The app is fully offline now, so the only errors we expect come from the
/// local SQLite database. The most common recoverable one is a UNIQUE
/// constraint violation (duplicate id / serial), which we surface distinctly.
String friendlyError(Object? e) {
  final msg = e?.toString().toLowerCase() ?? '';
  if (msg.contains('unique constraint') ||
      msg.contains('code 2067') ||
      msg.contains('code 1555')) {
    return 'err_duplicate_record'.tr();
  }
  return 'err_generic_friendly'.tr();
}
