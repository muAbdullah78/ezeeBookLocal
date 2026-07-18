import 'dart:async';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/constants/app_colors.dart';
import '../../auth/screens/login_screen.dart';

/// Shown briefly after a successful account deletion, then automatically
/// returns the user to the auth/login screen with the entire navigation
/// stack cleared. There is intentionally no way to navigate anywhere else.
class DeleteAccountSuccessScreen extends StatefulWidget {
  const DeleteAccountSuccessScreen({super.key});

  @override
  State<DeleteAccountSuccessScreen> createState() =>
      _DeleteAccountSuccessScreenState();
}

class _DeleteAccountSuccessScreenState
    extends State<DeleteAccountSuccessScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 3), _goToAuth);
  }

  void _goToAuth() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Block the hardware back button — there is nowhere valid to go back to.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 96,
                ),
                const SizedBox(height: 24),
                Text(
                  'del_success_title'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'del_success_subtitle'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
