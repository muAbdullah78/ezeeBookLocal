import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../providers/auth_service.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';
import '../../../core/widgets/access_gate.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/services/billing_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = await _authService.login(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;

      if (result['success']) {
        SnackbarHelper.showSuccess(context, 'login_syncing_message'.tr());

        // Download data from cloud to local DB (for new device)
        await SyncService().downloadAllData();
        // Push any local-only writes (queued during offline use)
        await SyncService().uploadAllData();

        // Restore any Google Play purchases (handles device switch / reinstall)
        BillingService().restorePurchases();

        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          SlidePageRoute(page: const AccessGate()),
          (route) => false,
        );
      } else {
        final msg = (result['message'] ?? '').toString().toLowerCase();
        if (msg.contains('not confirmed')) {
          SnackbarHelper.showError(
            context,
            'auth_email_not_confirmed_guidance'.tr(),
          );
        } else {
          SnackbarHelper.showError(context, result['message']);
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 60),

                // Header
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.content_cut,
                    size: 45,
                    color: AppColors.textOnPrimary,
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  'EzeeBook',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  'login_subtitle'.tr(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: 40),

                // Email Field
                Align(
                  alignment: Alignment.centerLeft,
                  child: _buildLabel('email'.tr()),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'example@email.com',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'error_required_field'.tr();
                    }
                    if (!value.contains('@') || !value.contains('.')) {
                      return 'error_invalid_email'.tr();
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Password Field
                Align(
                  alignment: Alignment.centerLeft,
                  child: _buildLabel('password'.tr()),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    hintText: 'password'.tr(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        setState(
                            () => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'error_required_field'.tr();
                    }
                    return null;
                  },
                ),

                // Forgot Password
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        SlidePageRoute(page: const ForgotPasswordScreen()),
                      );
                    },
                    child: Text(
                      'forgot_password'.tr(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Login Button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: AppColors.textOnPrimary,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            'login'.tr(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                // Don't have account
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      SlidePageRoute(page: const SignupScreen()),
                    );
                  },
                  child: Text(
                    'dont_have_account'.tr(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }
}