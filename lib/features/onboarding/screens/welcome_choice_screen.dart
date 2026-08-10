import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../security/screens/set_pin_screen.dart';
import 'shop_setup_screen.dart';

/// First launch: is this a brand-new shop, or a tailor moving to a new phone?
///
/// Without this screen the only way in was the shop-setup form, so a tailor
/// replacing their phone had to invent a shop profile, reach the dashboard, find
/// Settings, and *then* restore — which immediately overwrote everything they
/// had just typed. It looked like creating a second account, and there was no
/// obvious answer to "I already use this app, where do I put my backup file?"
///
/// There is no login here because there is nothing to log in to: the app has no
/// server and no accounts. For an offline app the backup file *is* the tailor's
/// identity, so "restore my file" is the sign-in.
class WelcomeChoiceScreen extends StatefulWidget {
  /// Called once the shop is ready — either freshly set up or restored.
  final VoidCallback onDone;

  const WelcomeChoiceScreen({super.key, required this.onDone});

  @override
  State<WelcomeChoiceScreen> createState() => _WelcomeChoiceScreenState();
}

class _WelcomeChoiceScreenState extends State<WelcomeChoiceScreen> {
  /// True once the tailor picks "set up a new shop", so the form is rendered in
  /// place rather than pushed — a pushed route would sit on top of the gate
  /// after it rebuilds and hide the dashboard behind it.
  bool _settingUpNewShop = false;
  bool _restoring = false;

  // ==================== RESTORE ====================

  Future<void> _restoreFromBackup() async {
    if (_restoring) return;

    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(type: FileType.any);
    } catch (e, st) {
      AppLogger.error('WelcomeChoice', 'file pick failed',
          error: e, stackTrace: st);
    }
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;

    setState(() => _restoring = true);
    final result = await BackupService().importFromFile(path);
    if (!mounted) return;

    if (!result.success) {
      setState(() => _restoring = false);
      SnackbarHelper.showError(context, result.messageKey.tr());
      return;
    }

    // A backup should carry the shop profile, but a hand-edited or truncated
    // file might not. Marking setup complete without one would drop the tailor
    // on a dashboard whose receipts say "My Shop", so send them through the
    // form instead — their customers and orders are already restored either way.
    Map<String, dynamic>? profile;
    try {
      profile = await SyncService().getShopProfile();
    } catch (e, st) {
      AppLogger.error('WelcomeChoice', 'profile read after restore failed',
          error: e, stackTrace: st);
    }
    if (!mounted) return;

    if (profile == null) {
      setState(() {
        _restoring = false;
        _settingUpNewShop = true;
      });
      SnackbarHelper.showInfo(context, 'restore_needs_shop_details'.tr());
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('shop_setup_done', true);
    } catch (e, st) {
      // The gate also treats an existing shop profile as setup-complete, so a
      // failed flag write is not fatal.
      AppLogger.error('WelcomeChoice', 'could not persist setup flag',
          error: e, stackTrace: st);
    }
    if (!mounted) return;

    SnackbarHelper.showSuccess(
      context,
      'restore_success_counts'.tr(namedArgs: {
        'customers': result.customers.toString(),
        'orders': result.orders.toString(),
      }),
    );

    // The PIN is not part of the backup by design, so the new phone has none
    // yet — offer one here rather than leaving the app unlocked silently.
    await offerPinSetup(context);
    if (!mounted) return;
    widget.onDone();
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    if (_settingUpNewShop) {
      return ShopSetupScreen(
        onDone: widget.onDone,
        onBack: () => setState(() => _settingUpNewShop = false),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: AppColors.dashboardAccent,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(Icons.storefront_outlined,
                      size: 38, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'welcome_title'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'welcome_subtitle'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              _choiceCard(
                icon: Icons.add_business_outlined,
                title: 'welcome_new_shop_title'.tr(),
                body: 'welcome_new_shop_body'.tr(),
                primary: true,
                onTap: _restoring
                    ? null
                    : () => setState(() => _settingUpNewShop = true),
              ),
              const SizedBox(height: 14),
              _choiceCard(
                icon: Icons.restore_outlined,
                title: 'welcome_restore_title'.tr(),
                body: 'welcome_restore_body'.tr(),
                primary: false,
                busy: _restoring,
                onTap: _restoring ? null : _restoreFromBackup,
              ),

              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'welcome_no_account_note'.tr(),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choiceCard({
    required IconData icon,
    required String title,
    required String body,
    required bool primary,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    return Material(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: primary ? AppColors.primary : AppColors.border,
              width: primary ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: primary
                      ? AppColors.dashboardAccent
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary),
                      )
                    : Icon(icon,
                        size: 24,
                        color: primary
                            ? AppColors.primary
                            : AppColors.textSecondary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      body,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}
