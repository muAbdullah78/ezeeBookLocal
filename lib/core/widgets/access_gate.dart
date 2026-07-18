import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/subscription_service.dart';
import '../services/time_service.dart';
import '../utils/app_logger.dart';
import '../../features/auth/screens/subscription_lock_screen.dart';
import '../../features/dashboard/screens/main_shell.dart';

enum AccessDecision {
  evaluating,
  granted,
  trialExpired,
  subscriptionExpired,
  timeUnverified,
}

/// Central subscription access gate. Wraps MainShell and authoritatively
/// decides whether the user sees the dashboard or the lock screen.
///
/// Re-evaluates on:
///   - mount (initial)
///   - Supabase auth state changes (signedIn / signedOut / tokenRefreshed)
///   - app lifecycle resume (returning from background)
///   - 60-second periodic timer (catches trial expiry mid-session)
class AccessGate extends StatefulWidget {
  const AccessGate({super.key});

  @override
  State<AccessGate> createState() => _AccessGateState();
}

class _AccessGateState extends State<AccessGate>
    with WidgetsBindingObserver {
  AccessDecision _state = AccessDecision.evaluating;
  Timer? _periodicCheck;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.signedOut ||
          event.event == AuthChangeEvent.tokenRefreshed) {
        _evaluate();
      }
    });

    _periodicCheck = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _evaluate(),
    );

    _evaluate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _evaluate();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicCheck?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _evaluate() async {
    if (!mounted) return;

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        // No session — main.dart's auth router handles this case.
        // Defensive: we shouldn't be mounted without a session.
        return;
      }

      // Repopulate time cache if it was wiped (e.g. by login flow's
      // _wipeLocalState). Idempotent — no-ops on failure, falls back
      // to cached value in trustedNow() below.
      await TimeService().refreshIfPossible();

      final trustedNow = await TimeService().trustedNow();
      if (trustedNow == null) {
        if (mounted) {
          setState(() => _state = AccessDecision.timeUnverified);
        }
        return;
      }

      final hasActive = await SubscriptionService().hasActiveSubscription();
      if (hasActive) {
        if (mounted) {
          setState(() => _state = AccessDecision.granted);
        }
        return;
      }

      final trialActive = await SubscriptionService().isWithinFreeTrial();
      if (trialActive) {
        if (mounted) {
          setState(() => _state = AccessDecision.granted);
        }
        return;
      }

      // Trial expired AND no active subscription. Determine reason:
      // did the user ever have a subscription before?
      final hasHistory =
          await SubscriptionService().hasAnySubscriptionHistory();
      if (mounted) {
        setState(() => _state = hasHistory
            ? AccessDecision.subscriptionExpired
            : AccessDecision.trialExpired);
      }
    } catch (e, st) {
      AppLogger.error('AccessGate', 'evaluate failed',
          error: e, stackTrace: st);
      // On error, fail OPEN (granted). Trade-off: brief access during
      // error states is acceptable for v1. The next periodic check retries.
      if (mounted) {
        setState(() => _state = AccessDecision.granted);
      }
    }
  }

  LockReason _lockReasonFor(AccessDecision decision) {
    switch (decision) {
      case AccessDecision.trialExpired:
        return LockReason.trialExpired;
      case AccessDecision.subscriptionExpired:
        return LockReason.subscriptionExpired;
      case AccessDecision.timeUnverified:
        return LockReason.timeUnverified;
      case AccessDecision.granted:
      case AccessDecision.evaluating:
        return LockReason.trialExpired;
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case AccessDecision.evaluating:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case AccessDecision.granted:
        return const MainShell();
      case AccessDecision.trialExpired:
      case AccessDecision.subscriptionExpired:
      case AccessDecision.timeUnverified:
        return SubscriptionLockScreen(reason: _lockReasonFor(_state));
    }
  }
}
