import 'dart:async';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/supabase_config.dart';
import 'core/database/sync_service.dart';
import 'core/services/billing_service.dart';
import 'core/services/time_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/connectivity_helper.dart';
import 'core/widgets/access_gate.dart';
import 'features/auth/screens/consent_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Enable SQLite on Windows/Linux for testing
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await EasyLocalization.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  // Initialize billing — safe on Windows (returns early if not Android)
  try {
    await BillingService().initialize();
  } catch (_) {}

  // Warm the trusted-time cache so AccessGate's first evaluation can
  // resolve without waiting on the network.
  await TimeService().refreshIfPossible();

  final prefs = await SharedPreferences.getInstance();
  final consentGiven = prefs.getBool('consent_given') ?? false;

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'lib/l10n',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      child: EzeeBookApp(showConsent: !consentGiven),
    ),
  );
}

class EzeeBookApp extends StatefulWidget {
  final bool showConsent;

  const EzeeBookApp({
    super.key,
    required this.showConsent,
  });

  @override
  State<EzeeBookApp> createState() => _EzeeBookAppState();
}

class _EzeeBookAppState extends State<EzeeBookApp> {
  StreamSubscription<bool>? _connSub;
  StreamSubscription<AuthState>? _authSub;
  bool _wasOnline = true;

  @override
  void initState() {
    super.initState();
    _connSub = ConnectivityHelper().onConnectivityChanged.listen((online) {
      if (online && !_wasOnline) {
        // Just reconnected — push local changes if signed in
        if (Supabase.instance.client.auth.currentSession == null) {
          _wasOnline = online;
          return;
        }
        // Fire and forget; errors are logged internally
        SyncService().uploadAllData();
      }
      _wasOnline = online;
    });

    // Auth state listener drives routing: when the user signs out (e.g.
    // from the lock screen's logout button) we rebuild and the build()
    // method routes to LoginScreen. When they sign in we route into the
    // AccessGate, which then decides MainShell vs lock screen.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.signedOut) {
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EzeeBook',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: child!,
        );
      },
      home: _getHomeScreen(),
    );
  }

  Widget _getHomeScreen() {
    if (widget.showConsent) return const ConsentScreen();
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return const LoginScreen();
    // Authenticated — let AccessGate decide subscription state.
    return const AccessGate();
  }
}
