import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../security/screens/set_pin_screen.dart';

/// First-run shop profile setup. Collects the shop details that appear on
/// order receipts. Stored locally only — no account, no email, no password.
class ShopSetupScreen extends StatefulWidget {
  /// Called once setup (and the optional PIN step) is complete.
  final VoidCallback onDone;

  /// Shown as a back arrow when the tailor reached this from the first-launch
  /// choice, so picking "new shop" by mistake is not a dead end.
  final VoidCallback? onBack;

  const ShopSetupScreen({super.key, required this.onDone, this.onBack});

  @override
  State<ShopSetupScreen> createState() => _ShopSetupScreenState();
}

class _ShopSetupScreenState extends State<ShopSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _shopNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _shopNameController.dispose();
    _ownerNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final now = DateTime.now().toIso8601String();
      await SyncService().saveShopProfile({
        'owner_name': _ownerNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'shop_name': _shopNameController.text.trim(),
        'address': _addressController.text.trim(),
        'email': '',
        'created_at': now,
        'updated_at': now,
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('shop_setup_done', true);
      if (!mounted) return;

      await offerPinSetup(context);
      if (!mounted) return;
      widget.onDone();
    } catch (e, st) {
      AppLogger.error('ShopSetupScreen', 'save failed', error: e, stackTrace: st);
      if (mounted) {
        setState(() => _saving = false);
        SnackbarHelper.showError(context, 'auth_profile_save_failed'.tr());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('shop_setup_title'.tr()),
        automaticallyImplyLeading: false,
        leading: widget.onBack == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _saving ? null : widget.onBack,
              ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'shop_setup_subtitle'.tr(),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              _field(
                controller: _shopNameController,
                label: 'shop_name'.tr(),
                icon: Icons.store_outlined,
              ),
              const SizedBox(height: 14),
              _field(
                controller: _ownerNameController,
                label: 'owner_name'.tr(),
                icon: Icons.person_outline,
                required: false,
              ),
              const SizedBox(height: 14),
              _field(
                controller: _phoneController,
                label: 'phone_number'.tr(),
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                required: false,
              ),
              const SizedBox(height: 14),
              _field(
                controller: _addressController,
                label: 'shop_address'.tr(),
                icon: Icons.location_on_outlined,
                required: false,
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          'shop_setup_save'.tr(),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool required = true,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: required
          ? (v) =>
              (v == null || v.trim().isEmpty) ? 'error_required_field'.tr() : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
