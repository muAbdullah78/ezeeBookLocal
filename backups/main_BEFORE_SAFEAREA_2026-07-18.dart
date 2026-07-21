import 'dart:async';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:sentry_flutter/sentry_flutter.dart';
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

Future<void> main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn =
          'https://dce69db402f945b6a2033883ddfdf850@o4511506775670784.ingest.us.sentry.io/4511506786877440';
      options.tracesSampleRate = 0.2; // 20% of transactions traced
      options.profilesSampleRate = 0.1; // 10% profiling
      options.environment = kReleaseMode ? 'production' : 'development';
      options.release = 'ezeebook-flutter@1.0.0+4'; // Update on each release
      options.attachScreenshot = false; // Privacy: don't capture screenshots
      options.attachViewHierarchy = false; // Privacy: don't capture UI tree
      options.sendDefaultPii = false; // Privacy: don't auto-send PII
      options.maxBreadcrumbs = 50;
      options.beforeSend = (event, hint) {
        // Sanitize: remove any potential PII before sending.
        // For now just return as-is; can add filtering later if needed.
        return event;
      };
    },
    appRunner: () async {
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

      // Attribute crashes to a restored session's user. The auth listener
      // in EzeeBookApp only fires on sign-in/out, so set it here for the
      // already-authenticated case at cold start.
      final restoredUser = Supabase.instance.client.auth.currentUser;
      if (restoredUser != null) {
        await Sentry.configureScope((scope) {
          scope.setUser(SentryUser(
            id: restoredUser.id,
            email: restoredUser.email,
            ipAddress: '{{auto}}',
          ));
        });
      }

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
    },
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
        // Tie crash reports to the signed-in user (cleared on sign-out).
        // Fire and forget — must not block UI routing.
        _updateSentryUser(event.session?.user);
        if (mounted) setState(() {});
      }
    });
  }

  /// Sets (or clears) the Sentry user scope so crashes are attributed to a
  /// specific account. Called whenever Supabase auth state changes.
  Future<void> _updateSentryUser(User? user) async {
    if (user == null) {
      await Sentry.configureScope((scope) => scope.setUser(null));
      return;
    }
    await Sentry.configureScope((scope) {
      scope.setUser(SentryUser(
        id: user.id,
        email: user.email,
        ipAddress: '{{auto}}',
      ));
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
