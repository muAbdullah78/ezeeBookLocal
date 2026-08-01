import '../core/utils/app_logger.dart';

/// Local-only error reporter.
///
/// The app used to forward handled exceptions to Sentry. Now that EzeeBook is
/// fully offline and collects no data, this is a thin wrapper that logs to the
/// device log (`adb logcat`) via [AppLogger]. The method signatures are kept
/// so existing call sites do not need to change.
class ErrorReporter {
  /// Report a handled exception with optional context. Logs locally only —
  /// nothing leaves the device.
  static Future<void> reportError(
    dynamic error,
    StackTrace? stackTrace, {
    Map<String, dynamic>? context,
    String? hint,
  }) async {
    AppLogger.error(
      'ErrorReporter',
      'handled error${hint != null ? ' [$hint]' : ''}',
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Report a non-fatal message. Logs locally only.
  static Future<void> reportMessage(
    String message, {
    Map<String, dynamic>? context,
  }) async {
    AppLogger.info('ErrorReporter', message);
  }
}
