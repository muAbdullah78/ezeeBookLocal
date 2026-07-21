import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps a caught exception to a short, localized, user-friendly message.
/// Never surface raw exception strings (e.g. PostgrestException(...)) to
/// end users — route everything through here.
String friendlyError(Object? e) {
  if (e is PostgrestException) {
    if (e.code == '23505') return 'err_duplicate_record'.tr();
    return 'err_server'.tr();
  }
  if (e is AuthException) return 'err_auth'.tr();
  if (e is SocketException || e is TimeoutException) {
    return 'err_no_internet'.tr();
  }
  return 'err_generic_friendly'.tr();
}
