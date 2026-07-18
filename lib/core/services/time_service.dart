import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_logger.dart';
import '../utils/connectivity_helper.dart';

/// Trusted-time service. Fetches server time from Supabase via the
/// get_server_time() RPC and caches it locally so we can detect
/// device-clock spoofing offline.
///
/// Usage:
///   await TimeService().refreshIfPossible();
///   final now = await TimeService().trustedNow();
///
/// Returns null from trustedNow() if we cannot establish a trusted
/// time AND no valid cache exists. Callers must treat null as "block
/// until online."
class TimeService {
  static final TimeService _instance = TimeService._internal();
  factory TimeService() => _instance;
  TimeService._internal();

  static const _kServerTimeKey = 'time_service.last_server_time_iso';
  static const _kDeviceTimeKey = 'time_service.last_device_time_iso';
  static const _kOfflineGraceMinutes = 24 * 60;

  final _supabase = Supabase.instance.client;
  final Stopwatch _monotonic = Stopwatch();

  /// Try to fetch and cache server time. Silently no-ops if offline
  /// or if the RPC fails. Returns true on success, false on any
  /// failure (caller can still call trustedNow() to use cache).
  Future<bool> refreshIfPossible() async {
    try {
      final hasNet = await ConnectivityHelper().hasInternet();
      if (!hasNet) {
        AppLogger.info('TimeService', 'refreshIfPossible: offline, skipping');
        return false;
      }
      final result = await _supabase.rpc('get_server_time').timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          AppLogger.info('TimeService', 'get_server_time timed out');
          return null;
        },
      );
      if (result == null) {
        AppLogger.error('TimeService', 'get_server_time returned null');
        return false;
      }
      final serverTime = DateTime.parse(result.toString()).toUtc();
      final deviceTime = DateTime.now().toUtc();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kServerTimeKey, serverTime.toIso8601String());
      await prefs.setString(_kDeviceTimeKey, deviceTime.toIso8601String());
      _monotonic.reset();
      _monotonic.start();
      AppLogger.info('TimeService',
          'refresh OK: cachedServer=$serverTime, monotonic reset');
      return true;
    } catch (e, st) {
      AppLogger.error('TimeService', 'refreshIfPossible failed',
          error: e, stackTrace: st);
      return false;
    }
  }

  /// Returns the trusted current time, or null if no trustworthy
  /// source is available.
  ///
  /// Resolution:
  ///   - If we have a cached server time AND device clock has not
  ///     been rolled back AND we are within the offline grace window,
  ///     return cachedServerTime + (deviceNow - cachedDeviceNow).
  ///   - If device clock appears rolled back (deviceNow < cached
  ///     deviceNow), return cachedServerTime directly (no progress
  ///     credited).
  ///   - If no cache at all, return null.
  ///   - If beyond offline grace window, return null.
  Future<DateTime?> trustedNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serverIso = prefs.getString(_kServerTimeKey);
      final deviceIso = prefs.getString(_kDeviceTimeKey);
      if (serverIso == null || deviceIso == null) {
        return null;
      }
      final cachedServer = DateTime.parse(serverIso).toUtc();
      final cachedDevice = DateTime.parse(deviceIso).toUtc();
      final nowDevice = DateTime.now().toUtc();

      // Rollback detection: device clock moved backward
      if (nowDevice.isBefore(cachedDevice)) {
        AppLogger.error('TimeService',
            'device clock rollback detected; refusing to verify');
        return null;
      }

      final delta = nowDevice.difference(cachedDevice);

      // Offline grace cap: if it's been too long since we last verified,
      // we cannot trust the elapsed device time anymore.
      if (delta.inMinutes >= _kOfflineGraceMinutes) {
        AppLogger.info('TimeService',
            'cached time is stale (>=${_kOfflineGraceMinutes}m); returning null');
        return null;
      }

      // Monotonic cross-check: device clock advancement should match
      // monotonic clock advancement within tolerance. If they diverge,
      // the device clock is frozen/manipulated (frozen-time bypass attack).
      if (_monotonic.isRunning) {
        final monotonicElapsed = _monotonic.elapsed;
        final discrepancy = (delta - monotonicElapsed).abs();
        // 30-minute tolerance covers normal Android process suspension.
        // Longer suspensions are handled by AccessGate's resume-triggered refresh.
        if (discrepancy.inMinutes >= 30) {
          AppLogger.error('TimeService',
              'Time tampering detected: device delta=${delta.inSeconds}s, '
              'monotonic elapsed=${monotonicElapsed.inSeconds}s, '
              'discrepancy=${discrepancy.inSeconds}s');
          return null;
        }
      }
      // If monotonic isn't running (before any successful refresh), skip the
      // check — existing 24h cap and rollback detection still apply.

      return cachedServer.add(delta);
    } catch (e, st) {
      AppLogger.error('TimeService', 'trustedNow failed',
          error: e, stackTrace: st);
      return null;
    }
  }

  /// Wipe cache. Call this on signOut / account deletion so a future
  /// user on the same device starts clean.
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kServerTimeKey);
      await prefs.remove(_kDeviceTimeKey);
      _monotonic.reset();
      _monotonic.stop();
    } catch (e, st) {
      AppLogger.error('TimeService', 'clearCache failed',
          error: e, stackTrace: st);
    }
  }
}
