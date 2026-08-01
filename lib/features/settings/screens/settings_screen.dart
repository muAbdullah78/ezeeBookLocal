import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/pin_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../core/widgets/root_gate.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../security/screens/set_pin_screen.dart';
import 'about_screen.dart';
import 'edit_profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _shopName = '';
  String _ownerName = '';
  String _phone = '';
  bool _profileLoading = true;
  bool _pinSet = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadPinState();
  }

  Future<void> _loadPinState() async {
    final pinSet = await PinService().isPinSet();
    if (mounted) setState(() => _pinSet = pinSet);
  }

  Future<void> _loadProfile() async {
    try {
      final data = await SyncService().getShopProfile();
      if (data != null && mounted) {
        setState(() {
          _shopName = data['shop_name'] ?? '';
          _ownerName = data['owner_name'] ?? '';
          _phone = data['phone'] ?? '';
          _profileLoading = false;
        });
      } else if (mounted) {
        setState(() => _profileLoading = false);
      }
    } catch (e, st) {
      AppLogger.error('Settings', 'profile load failed', error: e, stackTrace: st);
      if (mounted) setState(() => _profileLoading = false);
    }
  }

  // ==================== BACKUP / RESTORE ====================

  Future<void> _backupData() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await BackupService().exportAndShare();
    } catch (e, st) {
      AppLogger.error('Settings', 'backup failed', error: e, stackTrace: st);
      if (mounted) SnackbarHelper.showError(context, 'backup_failed'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreData() async {
    if (_busy) return;

    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(type: FileType.any);
    } catch (e, st) {
      AppLogger.error('Settings', 'file pick failed', error: e, stackTrace: st);
    }
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('restore_confirm_title'.tr()),
        content: Text('restore_confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text('restore_replace'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final result = await BackupService().importFromFile(path);
    if (!mounted) return;
    setState(() => _busy = false);

    if (result.success) {
      SnackbarHelper.showSuccess(context, 'restore_success'.tr());
      // Rebuild through the gate so every tab reloads the restored data and
      // the app-lock lifecycle observer stays active. startUnlocked avoids
      // re-prompting for the PIN we already passed this session.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RootGate(startUnlocked: true)),
        (route) => false,
      );
    } else {
      SnackbarHelper.showError(context, result.messageKey.tr());
    }
  }

  // ==================== APP LOCK (PIN) ====================

  Future<void> _setOrChangePin() async {
    await Navigator.of(context).push(
      SlidePageRoute(page: const SetPinScreen()),
    );
    await _loadPinState();
  }

  Future<void> _removePin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('remove_pin_confirm_title'.tr()),
        content: Text('remove_pin_confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text('remove_pin'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await PinService().clearPin();
    await _loadPinState();
    if (mounted) SnackbarHelper.showSuccess(context, 'pin_removed'.tr());
  }

  // ==================== ERASE ALL DATA ====================

  Future<void> _eraseAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('erase_confirm_title'.tr()),
        content: Text('erase_confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text('erase_confirm_button'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await DatabaseHelper().clearAllData();
    await PinService().clearPin();
    // Reset first-run flags so the app returns to disclaimer + setup.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('disclaimer_accepted');
    await prefs.remove('shop_setup_done');
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RootGate()),
      (route) => false,
    );
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
          const SizedBox(height: 12),

          // Data section — backup & restore
          _sectionLabel('section_data'.tr()),
          _card([
            _buildSettingsItem(
              icon: Icons.backup_outlined,
              title: 'backup_data'.tr(),
              subtitle: 'backup_data_subtitle'.tr(),
              onTap: _backupData,
            ),
            _divider(),
            _buildSettingsItem(
              icon: Icons.restore_outlined,
              title: 'restore_data'.tr(),
              subtitle: 'restore_data_subtitle'.tr(),
              onTap: _restoreData,
            ),
          ]),
          const SizedBox(height: 12),

          // Security section — app lock
          _sectionLabel('section_security'.tr()),
          _card([
            _buildSettingsItem(
              icon: Icons.lock_outline,
              title: _pinSet ? 'change_pin'.tr() : 'set_pin'.tr(),
              subtitle: 'app_lock'.tr(),
              onTap: _setOrChangePin,
            ),
            if (_pinSet) ...[
              _divider(),
              _buildSettingsItem(
                icon: Icons.lock_open_outlined,
                title: 'remove_pin'.tr(),
                onTap: _removePin,
              ),
            ],
          ]),
          const SizedBox(height: 12),

          // App section — about
          _sectionLabel('section_app'.tr()),
          _card([
            _buildSettingsItem(
              icon: Icons.info_outline,
              title: 'about'.tr(),
              onTap: () {
                Navigator.of(context).push(
                  SlidePageRoute(page: const AboutScreen()),
                );
              },
            ),
          ]),
          const SizedBox(height: 12),

          // Legal section
          _sectionLabel('section_legal'.tr()),
          _card([
            _buildSettingsItem(
              icon: Icons.privacy_tip_outlined,
              title: 'privacy_policy'.tr(),
              onTap: () => _launchUrl(kPrivacyPolicyUrl),
            ),
            _divider(),
            _buildSettingsItem(
              icon: Icons.description_outlined,
              title: 'terms_of_service'.tr(),
              onTap: () => _launchUrl(kTermsOfServiceUrl),
            ),
          ]),
          const SizedBox(height: 12),

          // Danger zone — erase all data
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
            child: Text(
              'danger_zone'.tr(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE53935),
              ),
            ),
          ),
          _card([
            _buildSettingsItem(
              icon: Icons.delete_forever,
              title: 'erase_all_data'.tr(),
              subtitle: 'erase_all_data_subtitle'.tr(),
              onTap: _eraseAllData,
              isDestructive: true,
            ),
          ]),

          // Version footer
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Text(
                  'EzeeBook v$kAppVersion',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Made with ❤️ for tailors',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Color(0xFFB0BEC5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6B7280),
          ),
        ),
      );

  Widget _card(List<Widget> children) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Card(
          elevation: 2,
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(children: children),
        ),
      );

  Widget _divider() => const Divider(
        height: 1,
        color: Color(0xFFE5E7EB),
        indent: 72,
        endIndent: 16,
      );

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            if (_phone.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _phone,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  SlidePageRoute(page: const EditProfileScreen()),
                );
                _loadProfile();
              },
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text('edit_profile'.tr(), style: const TextStyle(fontSize: 14)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF26A69A),
                side: const BorderSide(color: Color(0xFF26A69A), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
  }) {
    return ListTile(
      onTap: _busy ? null : onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDestructive ? const Color(0xFFFFEBEE) : const Color(0xFFE0F2F1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 20,
          color: isDestructive ? const Color(0xFFE53935) : const Color(0xFF26A69A),
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: isDestructive ? const Color(0xFFE53935) : const Color(0xFF1A1A1A),
        ),
      ),
      subtitle: subtitle != null && subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            )
          : null,
      trailing: const Icon(Icons.chevron_right, color: Color(0xFF6B7280), size: 20),
    );
  }
}
