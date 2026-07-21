import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/billing_service.dart';
import '../../../core/utils/connectivity_helper.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../providers/auth_service.dart';
import '../../settings/screens/subscription_screen.dart';
import '../../../core/widgets/access_gate.dart';

enum LockReason { trialExpired, subscriptionExpired, timeUnverified }

class SubscriptionLockScreen extends StatefulWidget {
  final LockReason reason;
  const SubscriptionLockScreen({
    super.key,
    this.reason = LockReason.subscriptionExpired,
  });

  @override
  State<SubscriptionLockScreen> createState() => _SubscriptionLockScreenState();
}

class _SubscriptionLockScreenState extends State<SubscriptionLockScreen> {
  bool _restoring = false;
  void Function(String, BillingEvent, String)? _previousBillingCallback;

  @override
  void initState() {
    super.initState();
    _setupBillingCallback();
  }

  @override
  void dispose() {
    BillingService().onPurchaseComplete = _previousBillingCallback;
    super.dispose();
  }

  void _setupBillingCallback() {
    _previousBillingCallback = BillingService().onPurchaseComplete;
    BillingService().onPurchaseComplete = (planId, event, message) async {
      if (!mounted) return;

      switch (event) {
        case BillingEvent.success:
          // The subscription was already created with the server-verified
          // expiry inside BillingService._handlePurchase. Do NOT create it
          // again here — a second write would use a client-computed expiry.
          SnackbarHelper.showSuccess(context, 'subscription_activated'.tr());
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const _GoToAccessGate()),
            (route) => false,
          );
          break;
        case BillingEvent.pending:
          SnackbarHelper.showInfo(context, message);
          // Keep the screen alive; do NOT mark as failed
          break;
        case BillingEvent.cancelled:
          // No snackbar needed; user knows they cancelled
          break;
        case BillingEvent.error:
          SnackbarHelper.showError(
            context,
            message.isEmpty ? 'no_subscription_found'.tr() : message,
          );
          break;
      }

      if (!mounted) return;
      if (event != BillingEvent.pending) {
        setState(() => _restoring = false);
      }
    };
  }

  String get _titleKey {
    switch (widget.reason) {
      case LockReason.trialExpired:
        return 'lock_trial_expired_title';
      case LockReason.subscriptionExpired:
        return 'subscription_expired';
      case LockReason.timeUnverified:
        return 'lock_time_unverified_title';
    }
  }

  String get _bodyKey {
    switch (widget.reason) {
      case LockReason.trialExpired:
        return 'lock_trial_expired_message';
      case LockReason.subscriptionExpired:
        return 'subscription_expired_message';
      case LockReason.timeUnverified:
        return 'lock_time_unverified_message';
    }
  }

  String get _ctaKey {
    switch (widget.reason) {
      case LockReason.trialExpired:
        return 'lock_subscribe_cta';
      case LockReason.subscriptionExpired:
        return 'renew_subscription';
      case LockReason.timeUnverified:
        return 'lock_reconnect_cta';
    }
  }

  Future<void> _handleRestore() async {
    if (_restoring) return;
    setState(() => _restoring = true);

    // Pre-check connectivity — give a clear error instead of a blind timeout
    final online = await ConnectivityHelper().hasInternet();
    if (!online) {
      if (mounted) {
        setState(() => _restoring = false);
        SnackbarHelper.showError(context, 'restore_offline_error'.tr());
      }
      return;
    }

    // Trigger restore — results arrive via the purchase stream callback
    await BillingService().restorePurchases();

    // Timeout — if no purchase event fires within 10 seconds, show "not found"
    await Future.delayed(const Duration(seconds: 10));
    if (mounted && _restoring) {
      setState(() => _restoring = false);
      SnackbarHelper.showError(context, 'no_subscription_found'.tr());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.primary, AppColors.primaryDark],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),
                  // Lock icon
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      size: 50,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Title
                  Text(
                    _titleKey.tr(),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  // Message
                  Text(
                    _bodyKey.tr(),
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.85),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 36),
                  // Renew button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () async {
                        final result = await Navigator.of(context).push<bool>(
                          SlidePageRoute(page: const SubscriptionScreen()),
                        );
                        if (result == true && context.mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const _GoToAccessGate()),
                            (route) => false,
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primaryDark,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _ctaKey.tr(),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Restore purchases button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _restoring ? null : _handleRestore,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _restoring
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            )
                          : Text(
                              'restore_purchases'.tr(),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                            ),
                    ),
                  ),
                  const Spacer(flex: 3),
                  // Logout. signOut() wipes local data and fires
                  // AuthChangeEvent.signedOut; main.dart's auth listener
                  // rebuilds and routes to LoginScreen. No manual nav.
                  TextButton(
                    onPressed: () async {
                      await AuthService().signOut();
                    },
                    child: Text(
                      'logout'.tr(),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// After subscription is activated, re-enter the AccessGate so it
/// re-evaluates and routes to MainShell.
class _GoToAccessGate extends StatelessWidget {
  const _GoToAccessGate();

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AccessGate()),
        (route) => false,
      );
    });
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
