import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_colors.dart';
import '../database/sync_service.dart';
import '../services/pin_service.dart';
import '../../features/dashboard/screens/main_shell.dart';
import '../../features/onboarding/screens/disclaimer_screen.dart';
import '../../features/onboarding/screens/shop_setup_screen.dart';
import '../../features/security/screens/pin_lock_screen.dart';

/// Root routing widget. Decides what the tailor sees at launch:
///   1. Disclaimer (first ever launch)
///   2. Shop setup (profile not yet created)
///   3. PIN unlock (a PIN is configured and we haven't unlocked this session)
///   4. The main app (MainShell)
///
/// It also re-locks the app when it returns from the background after being
/// away longer than [_relockAfter], so a configured PIN actually protects a
/// phone that was put down — not just a cold start.
///
/// All state is local (SharedPreferences + local PIN). There is no account
/// and no network.
class RootGate extends StatefulWidget {
  /// When true, the gate starts already unlocked (used after an in-app data
  /// restore, which rebuilds the gate but should not re-prompt for the PIN).
  final bool startUnlocked;

  const RootGate({super.key, this.startUnlocked = false});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> with WidgetsBindingObserver {
  /// How long the app can be in the background before a set PIN re-locks it on
  /// resume. Long enough to survive quick in-app hops (share sheet, WhatsApp,
  /// file picker, print dialog); short enough to protect a phone left idle.
  static const Duration _relockAfter = Duration(minutes: 2);

  bool _loading = true;
  bool _disclaimerAccepted = false;
  bool _shopSetupDone = false;
  bool _pinSet = false;
  bool _unlocked = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    _unlocked = widget.startUnlocked;
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (_pinSet &&
          _unlocked &&
          since != null &&
          DateTime.now().difference(since) >= _relockAfter) {
        setState(() => _unlocked = false);
      }
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final pinSet = await PinService().isPinSet();
    var shopDone = prefs.getBool('shop_setup_done') ?? false;

    // Upgrade path: an older version may already have a saved shop profile
    // (migrated to the local id) even though the new `shop_setup_done` flag was
    // never written. Treat that as setup-complete so we don't force the tailor
    // back through onboarding and overwrite their profile.
    if (!shopDone) {
      try {
        final profile = await SyncService().getShopProfile();
        if (profile != null) {
          shopDone = true;
          await prefs.setBool('shop_setup_done', true);
        }
      } catch (_) {
        // If the DB can't be read yet, fall through to normal setup.
      }
    }

    if (!mounted) return;
    setState(() {
      _disclaimerAccepted = prefs.getBool('disclaimer_accepted') ?? false;
      _shopSetupDone = shopDone;
      _pinSet = pinSet;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (!_disclaimerAccepted) {
      return DisclaimerScreen(
        onAccepted: () => setState(() => _disclaimerAccepted = true),
      );
    }

    if (!_shopSetupDone) {
      return ShopSetupScreen(
        onDone: () async {
          final pinSet = await PinService().isPinSet();
          if (!mounted) return;
          setState(() {
            _shopSetupDone = true;
            _pinSet = pinSet;
            _unlocked = true; // just finished setup — no need to re-lock now
          });
        },
      );
    }

    if (_pinSet && !_unlocked) {
      return PinLockScreen(
        onUnlocked: () => setState(() => _unlocked = true),
        onReset: () async {
          await _load();
          if (mounted) setState(() => _unlocked = false);
        },
      );
    }

    return const MainShell();
  }
}
