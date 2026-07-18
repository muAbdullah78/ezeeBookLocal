import 'package:sentry_flutter/sentry_flutter.dart';

/// Thin wrapper around Sentry for manual (non-fatal) error reporting.
///
/// Uncaught exceptions are captured automatically by SentryFlutter.init's
/// zone guard (see main.dart). Use these helpers to report handled
/// exceptions or suspicious states with extra context.
class ErrorReporter {
  /// Manually report an exception with context.
  static Future<void> reportError(
    dynamic error,
    StackTrace? stackTrace, {
    Map<String, dynamic>? context,
    String? hint,
  }) async {
    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        if (context != null) {
          context.forEach((key, value) {
            scope.setContexts(key, value);
          });
        }
        if (hint != null) {
          scope.setTag('hint', hint);
        }
      },
    );
  }

  /// Report a non-fatal message (useful for tracking suspicious states).
  static Future<void> reportMessage(
    String message, {
    SentryLevel level = SentryLevel.warning,
    Map<String, dynamic>? context,
  }) async {
    await Sentry.captureMessage(
      message,
      level: level,
      withScope: (scope) {
        if (context != null) {
          context.forEach((key, value) {
            scope.setContexts(key, value);
          });
        }
      },
    );
  }

  /// Add a breadcrumb (debug trail leading up to a future error).
  static Breadcrumb breadcrumb({
    required String message,
    String? category,
    SentryLevel level = SentryLevel.info,
    Map<String, dynamic>? data,
  }) {
    final crumb = Breadcrumb(
      message: message,
      category: category ?? 'app',
      level: level,
      data: data,
    );
    Sentry.addBreadcrumb(crumb);
    return crumb;
  }
}
