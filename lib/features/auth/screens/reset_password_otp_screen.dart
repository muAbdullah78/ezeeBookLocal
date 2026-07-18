import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../providers/auth_service.dart';
import 'login_screen.dart';

class ResetPasswordOtpScreen extends StatefulWidget {
  final String email;

  const ResetPasswordOtpScreen({super.key, required this.email});

  @override
  State<ResetPasswordOtpScreen> createState() => _ResetPasswordOtpScreenState();
}

class _ResetPasswordOtpScreenState extends State<ResetPasswordOtpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _isResending = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  static const int _resendCooldownSeconds = 30;
  int _resendSecondsRemaining = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _startResendCooldown();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSecondsRemaining = _resendCooldownSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendSecondsRemaining--;
        if (_resendSecondsRemaining <= 0) {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      try {
        await Supabase.instance.client.auth.verifyOTP(
          email: widget.email,
          token: _otpController.text.trim(),
          type: OtpType.recovery,
        );
      } on AuthException catch (e) {
        if (!mounted) return;
        SnackbarHelper.showError(context, e.message);
        return;
      } catch (_) {
        if (!mounted) return;
        SnackbarHelper.showError(context, 'auth_something_wrong'.tr());
        return;
      }

      try {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(password: _newPasswordController.text),
        );
      } on AuthException catch (e) {
        if (!mounted) return;
        SnackbarHelper.showError(context, e.message);
        await Supabase.instance.client.auth.signOut();
        return;
      } catch (_) {
        if (!mounted) return;
        SnackbarHelper.showError(context, 'auth_something_wrong'.tr());
        await Supabase.instance.client.auth.signOut();
        return;
      }

      await Supabase.instance.client.auth.signOut();

      if (!mounted) return;
      SnackbarHelper.showSuccess(context, 'reset_password_success'.tr());
      Navigator.of(context).pushAndRemoveUntil(
        SlidePageRoute(page: const LoginScreen()),
        (route) => false,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleResend() async {
    if (_resendSecondsRemaining > 0 || _isResending) return;

    setState(() => _isResending = true);

    final result = await _authService.resetPassword(widget.email);

    if (!mounted) return;
    setState(() => _isResending = false);

    if (result['success'] == true) {
      SnackbarHelper.showSuccess(context, 'reset_otp_resent'.tr());
      _startResendCooldown();
    } else {
      SnackbarHelper.showError(
        context,
        result['message'] ?? 'auth_something_wrong'.tr(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResend = _resendSecondsRemaining == 0 && !_isResending;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'reset_password_title'.tr(),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),

                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.dashboardAccent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.lock_reset_outlined,
                      size: 40,
                      color: AppColors.primary,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  'reset_password_otp_subtitle'
                      .tr(namedArgs: {'email': widget.email}),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 28),

                _buildLabel('reset_password_otp_label'.tr()),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    fontFamily: 'monospace',
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '••••••',
                    hintStyle: const TextStyle(
                      fontSize: 22,
                      letterSpacing: 8,
                      color: AppColors.textHint,
                    ),
                    filled: true,
                    fillColor: AppColors.cardBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppColors.border, width: 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppColors.border, width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppColors.primary, width: 2),
                    ),
                  ),
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) {
                      return 'error_required_field'.tr();
                    }
                    if (!RegExp(r'^[0-9]+$').hasMatch(v)) {
                      return 'reset_otp_numeric_only'.tr();
                    }
                    if (v.length != 6) {
                      return 'reset_otp_invalid_length'.tr();
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 14),

                _buildLabel('reset_password_new_label'.tr()),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: _obscureNewPassword,
                  decoration: InputDecoration(
                    hintText: 'password_hint'.tr(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNewPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        setState(
                            () => _obscureNewPassword = !_obscureNewPassword);
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'error_required_field'.tr();
                    }
                    if (value.length < 6) {
                      return 'reset_password_min_length'.tr();
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 14),

                _buildLabel('reset_password_confirm_label'.tr()),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    hintText: 'reset_password_confirm_label'.tr(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        setState(() => _obscureConfirmPassword =
                            !_obscureConfirmPassword);
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'error_required_field'.tr();
                    }
                    if (value != _newPasswordController.text) {
                      return 'reset_password_mismatch'.tr();
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.textOnPrimary,
                    ),
                    onPressed: _isLoading ? null : _handleSubmit,
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
                            'reset_password_button'.tr(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 12),

                Center(
                  child: TextButton(
                    onPressed: canResend ? _handleResend : null,
                    child: _isResending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _resendSecondsRemaining > 0
                                ? 'reset_otp_resend_cooldown'.tr(namedArgs: {
                                    'seconds': '$_resendSecondsRemaining'
                                  })
                                : 'reset_otp_resend'.tr(),
                            style: TextStyle(
                              color: canResend
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 16),
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
