import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/subscription_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../account/screens/delete_account_screen.dart';
import '../../auth/providers/auth_service.dart';
import '../../auth/screens/login_screen.dart';
import 'about_screen.dart';
import 'edit_profile_screen.dart';
import 'change_password_screen.dart';
import 'subscription_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _client = Supabase.instance.client;
  String _shopName = '';
  String _ownerName = '';
  String _email = '';
  String _phone = '';
  bool _profileLoading = true;
  String _subscriptionStatus = '';
  bool _isSubscriptionExpired = false;
  String? _subscriptionPaymentMethod;
  bool _isFetchingPaymentMethod = false;
  final _subscriptionService = SubscriptionService();

  static const _manageSubscriptionUrl =
      'https://play.google.com/store/account/subscriptions'
      '?package=com.usconnect.ezeebook';

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadSubscriptionStatus();
  }

  Future<void> _loadSubscriptionStatus() async {
    final sub = await _subscriptionService.getCurrentSubscription();
    if (!mounted) return;

    if (sub != null) {
      final days = _subscriptionService.getDaysRemaining(sub['end_date']);
      setState(() {
        _subscriptionStatus = 'days_remaining'.tr(namedArgs: {'days': days.toString()});
        _isSubscriptionExpired = false;
      });
      _fetchSubscriptionPaymentMethod();
      return;
    }

    // No active subscription — check if still in free trial
    final inTrial = await _subscriptionService.isWithinFreeTrial();
    if (!mounted) return;

    if (inTrial) {
      setState(() {
        _subscriptionStatus = 'trial_active'.tr();
        _isSubscriptionExpired = false;
      });
    } else {
      setState(() {
        _subscriptionStatus = 'subscription_expired'.tr();
        _isSubscriptionExpired = true;
      });
    }
  }

  Future<void> _loadProfile() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;
      final data = await _client
          .from('shop_profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (data != null && mounted) {
        setState(() {
          _shopName = data['shop_name'] ?? '';
          _ownerName = data['owner_name'] ?? '';
          _email = data['email'] ?? '';
          _phone = data['phone'] ?? '';
          _profileLoading = false;
        });
      } else if (mounted) {
        setState(() {
          _email = _client.auth.currentUser?.email ?? '';
          _profileLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _profileLoading = false);
    }
  }

  void _handleLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('logout'.tr()),
        content: Text('logout_confirm'.tr()),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('no'.tr()),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await AuthService().signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  SlidePageRoute(page: const LoginScreen()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text('yes'.tr()),
          ),
        ],
      ),
    );
  }

  void _handleDeleteAccount(BuildContext context) {
    Navigator.of(context).push(
      SlidePageRoute(page: const DeleteAccountScreen()),
    );
  }

  Future<void> _fetchSubscriptionPaymentMethod() async {
    if (_isFetchingPaymentMethod) return;
    _isFetchingPaymentMethod = true;
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;
      final response = await _client
          .from('user_subscriptions')
          .select('payment_method')
          .eq('user_id', userId)
          .eq('status', 'active')
          .order('end_date', ascending: false)
          .limit(1)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      if (mounted) {
        setState(() {
          _subscriptionPaymentMethod = response?['payment_method'] as String?;
        });
      }
    } catch (e) {
      AppLogger.info('Settings', 'Failed to fetch payment_method: $e');
      // Leave _subscriptionPaymentMethod null — button stays hidden
    } finally {
      _isFetchingPaymentMethod = false;
    }
  }

  bool _isPlayBillingActive() {
    return !_isSubscriptionExpired && _subscriptionPaymentMethod == 'play_billing';
  }

  Future<void> _openManageSubscription() async {
    final uri = Uri.parse(_manageSubscriptionUrl);
    try {
      final canLaunch = await canLaunchUrl(uri);
      if (canLaunch) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        SnackbarHelper.showError(context, 'manage_subscription_failed'.tr());
      }
    } catch (e) {
      AppLogger.error('Settings', 'Failed to launch manage subscription URL: $e');
      if (mounted) {
        SnackbarHelper.showError(context, 'manage_subscription_failed'.tr());
      }
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
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(
          'settings'.tr(),
          style: const TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          _buildProfileCard(),
          const SizedBox(height: 8),

          // Subscription — individual card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              elevation: 2,
              color: Colors.white,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: _buildSettingsItem(
                icon: Icons.card_membership,
                title: 'subscription'.tr(),
                subtitle: _subscriptionStatus,
                isSubscription: true,
                onTap: () async {
                  await Navigator.of(context).push(
                    SlidePageRoute(page: const SubscriptionScreen()),
                  );
                  _loadSubscriptionStatus();
                },
              ),
            ),
          ),
          if (_isPlayBillingActive())
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: OutlinedButton.icon(
                onPressed: _openManageSubscription,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: Text('manage_subscription'.tr()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF26A69A),
                  side: const BorderSide(color: Color(0xFF26A69A), width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  minimumSize: const Size(double.infinity, 44),
                ),
              ),
            ),
          const SizedBox(height: 12),

          // Account section
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 16, 8),
            child: Text(
              'Account',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              elevation: 2,
              color: Colors.white,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _buildSettingsItem(
                    icon: Icons.lock_outline,
                    title: 'change_password'.tr(),
                    onTap: () {
                      Navigator.of(context).push(
                        SlidePageRoute(page: const ChangePasswordScreen()),
                      );
                    },
                  ),
                  const Divider(
                    height: 1,
                    color: Color(0xFFE5E7EB),
                    indent: 72,
                    endIndent: 16,
                  ),
                  _buildSettingsItem(
                    icon: Icons.info_outline,
                    title: 'about'.tr(),
                    onTap: () {
                      Navigator.of(context).push(
                        SlidePageRoute(page: const AboutScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Legal section
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 16, 8),
            child: Text(
              'Legal',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              elevation: 2,
              color: Colors.white,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _buildSettingsItem(
                    icon: Icons.privacy_tip_outlined,
                    title: 'privacy_policy'.tr(),
                    onTap: () => _launchUrl('https://muabdullah78.github.io/ezeebook/privacy-policy.html'),
                  ),
                  const Divider(
                    height: 1,
                    color: Color(0xFFE5E7EB),
                    indent: 72,
                    endIndent: 16,
                  ),
                  _buildSettingsItem(
                    icon: Icons.description_outlined,
                    title: 'terms_of_service'.tr(),
                    onTap: () => _launchUrl('https://muabdullah78.github.io/ezeebook/terms-of-service.html'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Danger Zone section
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 16, 8),
            child: Text(
              'Danger Zone',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE53935),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              elevation: 2,
              color: Colors.white,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _buildSettingsItem(
                    icon: Icons.logout,
                    title: 'logout'.tr(),
                    onTap: () => _handleLogout(context),
                    isDestructive: true,
                  ),
                  const Divider(
                    height: 1,
                    color: Color(0xFFE5E7EB),
                    indent: 72,
                    endIndent: 16,
                  ),
                  _buildSettingsItem(
                    icon: Icons.delete_forever,
                    title: 'delete_account'.tr(),
                    onTap: () => _handleDeleteAccount(context),
                    isDestructive: true,
                  ),
                ],
              ),
            ),
          ),

          // Version footer
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Text(
                  'EzeeBook v1.0.0',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Made with ❤️ for tailors',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFFB0BEC5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    if (_profileLoading) return const ShimmerProfileCard();

    final String displayName = _shopName.isNotEmpty ? _shopName : _ownerName;
    final String initials;
    if (displayName.isEmpty) {
      initials = '?';
    } else {
      final words = displayName.trim().split(RegExp(r'\s+'));
      if (words.length >= 2) {
        initials = '${words[0][0]}${words[1][0]}'.toUpperCase();
      } else {
        initials = words[0][0].toUpperCase();
      }
    }

    return Card(
      elevation: 2,
      color: Colors.white,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: const Color(0xFF26A69A),
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              displayName.isNotEmpty ? displayName : 'shop_name'.tr(),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              _phone.isNotEmpty ? _phone : _email,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  SlidePageRoute(page: const EditProfileScreen()),
                );
                _loadProfile();
              },
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(
                'edit_profile'.tr(),
                style: const TextStyle(fontSize: 14),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF26A69A),
                side: const BorderSide(color: Color(0xFF26A69A), width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    bool isDestructive = false,
    bool isSubscription = false,
  }) {
    final isExpired = isSubscription && _isSubscriptionExpired;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDestructive
              ? const Color(0xFFFFEBEE)
              : const Color(0xFFE0F2F1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 20,
          color: isDestructive
              ? const Color(0xFFE53935)
              : const Color(0xFF26A69A),
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: isDestructive
              ? const Color(0xFFE53935)
              : const Color(0xFF1A1A1A),
        ),
      ),
      subtitle: subtitle != null && subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isExpired
                    ? const Color(0xFFE53935)
                    : const Color(0xFF6B7280),
              ),
            )
          : null,
      trailing: isSubscription
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isExpired
                    ? const Color(0xFFFFEBEE)
                    : const Color(0xFFE0F2F1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isExpired ? 'expired'.tr() : 'active'.tr(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isExpired
                      ? const Color(0xFFE53935)
                      : const Color(0xFF26A69A),
                ),
              ),
            )
          : const Icon(
              Icons.chevron_right,
              color: Color(0xFF6B7280),
              size: 20,
            ),
    );
  }
}
