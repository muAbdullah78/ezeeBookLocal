import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/snackbar_helper.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _ownerNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _shopNameController = TextEditingController();
  final _addressController = TextEditingController();
  String _email = '';
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _ownerNameController.dispose();
    _phoneController.dispose();
    _shopNameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await SyncService().getShopProfile();
      if (profile != null && mounted) {
        _ownerNameController.text = profile['owner_name'] ?? '';
        _phoneController.text = profile['phone'] ?? '';
        _shopNameController.text = profile['shop_name'] ?? '';
        _addressController.text = profile['address'] ?? '';
        _email = profile['email'] ?? '';
      } else if (mounted) {
        _email = _client.auth.currentUser?.email ?? '';
      }
    } catch (e, st) {
      AppLogger.error('EditProfileScreen', 'profile load failed',
          error: e, stackTrace: st);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      final saved = await SyncService().saveShopProfile({
        'id': userId,
        'owner_name': _ownerNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'shop_name': _shopNameController.text.trim(),
        'address': _addressController.text.trim(),
        'email': _email,
        'updated_at': DateTime.now().toIso8601String(),
      });
      if (!saved) {
        throw Exception('save failed');
      }

      if (mounted) {
        SnackbarHelper.showSuccess(context, 'profile_updated'.tr());
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'auth_profile_save_failed'.tr());
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('edit_profile'.tr()),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildField(
                      controller: _ownerNameController,
                      label: 'owner_name'.tr(),
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _phoneController,
                      label: 'phone_number'.tr(),
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _shopNameController,
                      label: 'shop_name'.tr(),
                      icon: Icons.store_outlined,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _addressController,
                      label: 'shop_address'.tr(),
                      icon: Icons.location_on_outlined,
                      required: false,
                    ),
                    const SizedBox(height: 14),
                    // Email (read-only)
                    TextFormField(
                      initialValue: _email,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'email'.tr(),
                        prefixIcon: const Icon(Icons.email_outlined),
                        helperText: 'email_cannot_change'.tr(),
                        helperStyle: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textHint,
                        ),
                        filled: true,
                        fillColor: AppColors.divider,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 28),
                    // Save button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'save'.tr(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildField({
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
          ? (v) => (v == null || v.trim().isEmpty) ? 'error_required_field'.tr() : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
