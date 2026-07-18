import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchEmail(String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _launchPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('about'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 20),
          // Logo & App Name
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.dashboardAccent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.content_cut, size: 40, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: RichText(
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
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              '${'version'.tr()} $kAppVersion',
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'tailor_shop_management'.tr(),
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 32),

          // Publisher
          _buildInfoCard(
            icon: Icons.business,
            title: 'publisher'.tr(),
            value: 'Usconnect Solutions',
          ),
          const SizedBox(height: 12),

          // Support Email
          _buildInfoCard(
            icon: Icons.email_outlined,
            title: 'support_email'.tr(),
            value: kSupportEmail,
            onTap: () => _launchEmail(kSupportEmail),
          ),
          const SizedBox(height: 12),

          // Support Phone
          _buildInfoCard(
            icon: Icons.phone_outlined,
            title: 'support_phone'.tr(),
            value: kSupportPhone,
            onTap: () => _launchPhone(kSupportPhone),
          ),
          const SizedBox(height: 24),

          // Links
          _buildLinkTile(
            icon: Icons.privacy_tip_outlined,
            title: 'privacy_policy'.tr(),
            onTap: () => _launchUrl(kPrivacyPolicyUrl),
          ),
          const SizedBox(height: 8),
          _buildLinkTile(
            icon: Icons.description_outlined,
            title: 'terms_of_service'.tr(),
            onTap: () => _launchUrl(kTermsOfServiceUrl),
          ),

          const SizedBox(height: 32),
          Center(
            child: Text(
              'made_in_pakistan'.tr(),
              style: const TextStyle(fontSize: 13, color: AppColors.textHint),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
    VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(
          title,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        subtitle: Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: onTap != null ? AppColors.info : AppColors.textPrimary,
          ),
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildLinkTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        trailing: const Icon(Icons.open_in_new, color: AppColors.textHint, size: 20),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
