import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/page_transitions.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _agreed = false;
  late final TapGestureRecognizer _privacyRecognizer;
  late final TapGestureRecognizer _termsRecognizer;

  @override
  void initState() {
    super.initState();
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => _launchUrl(kPrivacyPolicyUrl);
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => _launchUrl(kTermsOfServiceUrl);
  }

  @override
  void dispose() {
    _privacyRecognizer.dispose();
    _termsRecognizer.dispose();
    super.dispose();
  }

  Future<void> _onContinue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('consent_given', true);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        SlidePageRoute(page: const SignupScreen()),
      );
    }
  }

  Future<void> _onLoginTap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('consent_given', true);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        SlidePageRoute(page: const LoginScreen()),
      );
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 1),
              // Logo — always centered, no directionality needed
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.dashboardAccent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.content_cut, size: 40, color: AppColors.primary),
              ),
              const SizedBox(height: 16),
              RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: 'Ezee',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w300,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    TextSpan(
                      text: 'Book',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'welcome_to_ezeebook'.tr(),
                style: const TextStyle(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              // Info card
              Expanded(
                flex: 4,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'consent_your_data'.tr(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildPoint(Icons.email_outlined, 'consent_email_phone'.tr()),
                        const SizedBox(height: 12),
                        _buildPoint(Icons.lock_outline, 'consent_data_secure'.tr()),
                        const SizedBox(height: 12),
                        _buildPoint(Icons.cloud_outlined, 'consent_cloud_backup'.tr()),
                        const SizedBox(height: 12),
                        _buildPoint(Icons.delete_outline, 'consent_delete_anytime'.tr()),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Checkbox row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _agreed,
                      onChanged: (v) => setState(() => _agreed = v ?? false),
                      activeColor: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                        children: [
                          TextSpan(text: 'consent_agree_prefix'.tr()),
                          TextSpan(
                            text: 'privacy_policy'.tr(),
                            style: const TextStyle(
                              color: AppColors.info,
                              fontWeight: FontWeight.w500,
                            ),
                            recognizer: _privacyRecognizer,
                          ),
                          TextSpan(text: 'consent_agree_and'.tr()),
                          TextSpan(
                            text: 'terms_of_service'.tr(),
                            style: const TextStyle(
                              color: AppColors.info,
                              fontWeight: FontWeight.w500,
                            ),
                            recognizer: _termsRecognizer,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Get Started button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _agreed ? _onContinue : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.textHint,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'consent_get_started'.tr(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Already have an account? Login
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'consent_already_account'.tr(),
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  TextButton(
                    onPressed: _agreed ? _onLoginTap : null,
                    child: Text(
                      'consent_login_link'.tr(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _agreed ? AppColors.primary : AppColors.textHint,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPoint(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.dashboardAccent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
