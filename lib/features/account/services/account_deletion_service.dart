import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/utils/app_logger.dart';
import '../../../services/error_reporter.dart';
import '../models/account_deletion_result.dart';

/// Calls the server-side `delete-account` Edge Function to permanently and
/// irrevocably delete the current user's account and all associated data.
///
/// Order of operations on success is critical:
///   1. Server deletes ALL cloud data + the auth user (Edge Function).
///   2. Only then do we wipe the local SQLite database.
///   3. Finally we sign out of Supabase.
///
/// On any failure we do NOT touch local data or the session, so the user
/// stays logged in and can safely retry.
class AccountDeletionService {
  AccountDeletionService({
    SupabaseClient? client,
    DatabaseHelper? db,
  })  : _client = client ?? Supabase.instance.client,
        _db = db ?? DatabaseHelper();

  final SupabaseClient _client;
  final DatabaseHelper _db;

  static const _timeout = Duration(seconds: 30);

  /// Deletes the account. [reason] is an optional free-text/canonical reason
  /// captured from the "Why are you leaving?" dropdown.
  Future<AccountDeletionResult> deleteAccount({String? reason}) async {
    try {
      final response = await _client.functions
          .invoke(
            'delete-account',
            body: reason != null ? {'reason': reason} : null,
          )
          .timeout(_timeout);

      if (response.status == 200) {
        return await _finishSuccessfulDeletion();
      }

      // Non-2xx that did not throw — treat by status code.
      return _failureForStatus(response.status, response.data);
    } on FunctionException catch (e, st) {
      // supabase_flutter throws FunctionException for non-2xx responses.
      AppLogger.error('AccountDeletion',
          'Edge Function returned ${e.status}', error: e, stackTrace: st);
      await ErrorReporter.reportError(e, st, hint: 'account_deletion');
      return _failureForStatus(e.status, e.details);
    } on TimeoutException catch (e, st) {
      AppLogger.error('AccountDeletion', 'Deletion request timed out',
          error: e, stackTrace: st);
      await ErrorReporter.reportError(e, st, hint: 'account_deletion');
      return AccountDeletionResult.failure('del_err_timeout'.tr());
    } catch (e, st) {
      AppLogger.error('AccountDeletion', 'Deletion failed',
          error: e, stackTrace: st);
      await ErrorReporter.reportError(e, st, hint: 'account_deletion');
      return AccountDeletionResult.failure('del_err_server'.tr());
    }
  }

  /// Clears local data and signs out after the server confirmed deletion.
  Future<AccountDeletionResult> _finishSuccessfulDeletion() async {
    // Wipe local SQLite BEFORE signing out (task requirement). Even if this
    // throws, the cloud account is already gone, so we still sign out and
    // report success — the local file will be recreated fresh on next login.
    try {
      await _db.clearAllData();
    } catch (e, st) {
      AppLogger.error(
          'AccountDeletion', 'Local data clear failed after cloud delete',
          error: e, stackTrace: st);
      await ErrorReporter.reportError(e, st, hint: 'account_deletion');
    }

    await _client.auth.signOut();
    return AccountDeletionResult.success();
  }

  /// Maps an HTTP status code (and any server-provided detail) to a
  /// user-friendly, localized failure result.
  AccountDeletionResult _failureForStatus(int status, dynamic details) {
    if (status == 401) {
      return AccountDeletionResult.failure('del_err_session_expired'.tr());
    }
    if (status >= 500) {
      return AccountDeletionResult.failure('del_err_server'.tr());
    }
    // Other 4xx — prefer the server's message if it gave one.
    final serverMessage = _extractMessage(details);
    return AccountDeletionResult.failure(
      serverMessage ?? 'del_err_failed'.tr(),
    );
  }

  /// Best-effort extraction of a human-readable message from the Edge
  /// Function's error payload (may be a Map, a JSON string, or plain text).
  String? _extractMessage(dynamic details) {
    if (details == null) return null;
    if (details is Map) {
      final msg = details['error'] ?? details['message'];
      if (msg is String && msg.trim().isNotEmpty) return msg;
      return null;
    }
    if (details is String && details.trim().isNotEmpty) {
      return details;
    }
    return null;
  }
}
