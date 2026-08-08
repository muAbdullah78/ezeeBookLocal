import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../database/database_helper.dart';
import '../utils/app_logger.dart';

/// Outcome of a restore attempt.
class BackupImportResult {
  final bool success;

  /// A localization key describing what happened (success or the failure
  /// reason), resolved by the calling screen.
  final String messageKey;

  /// Counts of the top-level records restored (for the success message).
  final int customers;
  final int orders;

  const BackupImportResult({
    required this.success,
    required this.messageKey,
    this.customers = 0,
    this.orders = 0,
  });
}

/// Handles offline backup (export) and restore (import) of all app data so a
/// tailor can move to a new phone without a cloud account.
///
/// A backup is a single JSON file containing every row of every table plus a
/// small header. It can be shared via WhatsApp/Drive/email/file manager and
/// later imported on the new device.
class BackupService {
  static const _magic = 'ezeebook_backup';

  /// 2 adds the tailor's stitching categories and their fields. Version 1 files
  /// still restore — `importAllData` re-seeds the built-in categories when a
  /// backup carries none.
  static const _backupVersion = 2;

  final _db = DatabaseHelper();

  /// Build the backup file on disk and return it.
  Future<File> _writeBackupFile() async {
    final data = await _db.exportAllData();
    final payload = <String, dynamic>{
      'app': _magic,
      'backup_version': _backupVersion,
      'app_version': kAppVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'data': data,
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final file = File('${dir.path}/ezeebook_backup_$stamp.json');
    await file.writeAsString(jsonStr);
    return file;
  }

  /// Create a backup file and open the system share sheet so the tailor can
  /// save it to Drive / send it on WhatsApp / etc.
  Future<void> exportAndShare() async {
    final file = await _writeBackupFile();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'EzeeBook backup — keep this file safe to restore your data.',
      ),
    );
    await _recordBackupTaken();
  }

  // ==================== backup reminders ====================
  //
  // The only copy of a shop's data is the phone in the tailor's pocket. That is
  // the deliberate trade for having no cloud and no account, but it means a
  // lost or broken phone is a total loss unless somebody actually exports a
  // file. Nobody remembers to. So the app keeps track and asks.

  static const String _kLastBackupKey = 'last_backup_at';

  /// How long a shop can go without a backup before the dashboard says so.
  static const Duration overdueAfter = Duration(days: 14);

  Future<void> _recordBackupTaken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kLastBackupKey, DateTime.now().toIso8601String());
    } catch (e, st) {
      // A reminder timestamp is never worth failing a completed backup over.
      AppLogger.error('BackupService', 'could not record backup time',
          error: e, stackTrace: st);
    }
  }

  /// When the last backup was shared, or null if there has never been one.
  Future<DateTime?> lastBackupAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kLastBackupKey);
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  /// True when the shop has data worth losing and no recent backup.
  ///
  /// [hasData] is passed in rather than queried here so a brand-new install
  /// with an empty register is never nagged.
  Future<bool> isBackupOverdue({required bool hasData}) async {
    if (!hasData) return false;
    final last = await lastBackupAt();
    if (last == null) return true;
    return DateTime.now().difference(last) >= overdueAfter;
  }

  /// Parse and validate a picked backup file, then REPLACE all local data
  /// with its contents. On any validation failure nothing is changed.
  Future<BackupImportResult> importFromFile(String path) async {
    try {
      final raw = await File(path).readAsString();
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        return const BackupImportResult(
            success: false, messageKey: 'restore_invalid_file');
      }

      // If the file carries an app tag, it must be ours. (Bare table maps with
      // no tag are still accepted for resilience.)
      final appTag = decoded['app'];
      if (appTag != null && appTag != _magic) {
        return const BackupImportResult(
            success: false, messageKey: 'restore_invalid_file');
      }

      // Accept either the full envelope ({app, data:{...}}) or a bare table
      // map ({customers:[...], ...}) for resilience.
      final Map<String, dynamic> tables;
      if (decoded['data'] is Map) {
        tables = Map<String, dynamic>.from(decoded['data'] as Map);
      } else if (decoded['customers'] is List || decoded['orders'] is List) {
        tables = Map<String, dynamic>.from(decoded);
      } else {
        return const BackupImportResult(
            success: false, messageKey: 'restore_invalid_file');
      }

      // Sanity check: must have at least the customers key as a list.
      if (tables['customers'] is! List) {
        return const BackupImportResult(
            success: false, messageKey: 'restore_invalid_file');
      }

      await _db.importAllData(tables);

      final customers = (tables['customers'] as List).length;
      final orders = (tables['orders'] is List)
          ? (tables['orders'] as List).length
          : 0;
      return BackupImportResult(
        success: true,
        messageKey: 'restore_success',
        customers: customers,
        orders: orders,
      );
    } catch (e, st) {
      AppLogger.error('BackupService', 'importFromFile failed',
          error: e, stackTrace: st);
      return const BackupImportResult(
          success: false, messageKey: 'restore_failed');
    }
  }
}
