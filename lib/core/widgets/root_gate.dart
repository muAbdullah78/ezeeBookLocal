import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_colors.dart';
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
/// All state is local (SharedPreferences + local PIN). There is no account
/// and no network.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _loading = true;
  bool _disclaimerAccepted = false;
  bool _shopSetupDone = false;
  bool _pinSet = false;
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final pinSet = await PinService().isPinSet();
    if (!mounted) return;
    setState(() {
      _disclaimerAccepted = prefs.getBool('disclaimer_accepted') ?? false;
      _shopSetupDone = prefs.getBool('shop_setup_done') ?? false;
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
