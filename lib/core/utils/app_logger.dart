import 'dart:developer' as developer;

/// Lightweight logger for sync, auth, and other backend interactions.
/// Uses dart:developer so logs appear in `adb logcat` even in release
/// builds. Filter by tag name when debugging.
class AppLogger {
  AppLogger._();

  /// Informational log — sync progress, non-error events.
  static void info(String tag, String message) {
    developer.log(message, name: tag);
  }

  /// Error log — caught exceptions in cloud calls. Includes optional
  /// error and stack trace. Never log user-identifying data; log table
  /// names and error messages only.
  static void error(String tag, String message,
      {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: tag,
      level: 1000, // SEVERE
      error: error,
      stackTrace: stackTrace,
    );
  }
}
