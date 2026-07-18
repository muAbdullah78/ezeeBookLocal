import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import '../constants/supabase_config.dart';

class ConnectivityHelper {
  static final ConnectivityHelper _instance = ConnectivityHelper._internal();
  factory ConnectivityHelper() => _instance;
  ConnectivityHelper._internal();

  final Connectivity _connectivity = Connectivity();

  Future<bool> hasInternet() async {
    // 1. Quick interface check — if no network interface at all,
    //    don't waste time on an HTTP probe
    final result = await _connectivity.checkConnectivity();
    if (result.contains(ConnectivityResult.none) || result.isEmpty) {
      return false;
    }

    // 2. Real reachability — HEAD request to Supabase REST root
    try {
      final response = await http
          .head(Uri.parse('${SupabaseConfig.url}/rest/v1/'))
          .timeout(const Duration(seconds: 3));
      // Any response (even 401) means we reached Supabase
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  /// Stream of interface-level connectivity changes. NOTE: this does
  /// NOT verify actual internet reachability; use hasInternet() for
  /// authoritative checks. This stream is suitable for triggering
  /// best-effort retries.
  Stream<bool> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged.map(
      (results) => !results.contains(ConnectivityResult.none),
    );
  }
}
