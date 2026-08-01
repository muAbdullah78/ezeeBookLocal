import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional local app-lock PIN.
///
/// The app has no accounts and no cloud, so this is a purely on-device
/// convenience lock that keeps a lost/shared phone from exposing customer
/// data. The PIN is never stored in plain text: we keep a random salt and a
/// SHA-256 hash of (salt + pin). A 4-digit PIN is a deterrent, not strong
/// cryptography — there is no server to rate-limit against — but it prevents
/// casual snooping and the hash prevents reading the PIN out of preferences.
class PinService {
  static const _kHashKey = 'app_lock.pin_hash';
  static const _kSaltKey = 'app_lock.pin_salt';

  /// True if a PIN has been configured.
  Future<bool> isPinSet() async {
    final prefs = await SharedPreferences.getInstance();
    final hash = prefs.getString(_kHashKey);
    final salt = prefs.getString(_kSaltKey);
    return hash != null && hash.isNotEmpty && salt != null && salt.isNotEmpty;
  }

  /// Store a new PIN (replaces any existing one).
  Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = _randomSalt();
    await prefs.setString(_kSaltKey, salt);
    await prefs.setString(_kHashKey, _hash(salt, pin));
  }

  /// Verify an entered PIN against the stored hash.
  Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(_kSaltKey);
    final hash = prefs.getString(_kHashKey);
    if (salt == null || hash == null) return false;
    return _hash(salt, pin) == hash;
  }

  /// Remove the PIN (disable the lock).
  Future<void> clearPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kHashKey);
    await prefs.remove(_kSaltKey);
  }

  String _hash(String salt, String pin) {
    return sha256.convert(utf8.encode('$salt::$pin')).toString();
  }

  String _randomSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes);
  }
}
