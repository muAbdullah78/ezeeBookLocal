import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/services/subscription_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../models/account_deletion_result.dart';
import '../services/account_deletion_service.dart';
import 'delete_account_success_screen.dart';

/// A single reason option for the "Why are you leaving?" dropdown.
/// [labelKey] is a localization key; [reason] is the stable canonical value
/// sent to the server (null = "Prefer not to say" / no reason).
class _ReasonOption {
  const _ReasonOption(this.labelKey, this.reason);
  final String labelKey;
  final String? reason;
}

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _emailController = TextEditingController();
  final _deletionService = AccountDeletionService();
  final _subscriptionService = SubscriptionService();

  static const _reasons = <_ReasonOption>[
    _ReasonOption('del_reason_prefer_not', null),
    _ReasonOption('del_reason_no_need', 'I don\'t need it anymore'),
    _ReasonOption('del_reason_expensive', 'Too expensive'),
    _ReasonOption('del_reason_missing_feature', 'Missing a feature I need'),
    _ReasonOption('del_reason_has_issues', 'The app has issues'),
    _ReasonOption('del_reason_other', 'Other'),
  ];

  late final String _userEmail;
  _ReasonOption _selectedReason = _reasons.first;

  bool _emailMatches = false;

  // Data counts (best effort — may be unavailable if the DB read fails).
  int? _customerCount;
  int? _orderCount;
  bool _countsAvailable = false;

  // Active subscription (null if none / offline).
  Map<String, dynamic>? _activeSubscription;
  String? _activePlanId;
  String _activePlanName = '';

  @override
  void initState() {
    super.initState();
    _userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    _emailController.addListener(_onEmailChanged);
    _loadCounts();
    _loadSubscription();
  }

  @override
  void dispose() {
    _emailController.removeListener(_onEmailChanged);
    _emailController.dispose();
    super.dispose();
  }

  void _onEmailChanged() {
    // Case-sensitive exact match — do NOT lowercase either side.
    final matches = _emailController.text == _userEmail && _userEmail.isNotEmpty;
    if (matches != _emailMatches) {
      setState(() => _emailMatches = matches);
    }
  }

  Future<void> _loadCounts() async {
    try {
      final db = DatabaseHelper();
      final customers = await db.getCustomerCount();
      final orders = (await db.getAllOrders()).length;
      if (!mounted) return;
      setState(() {
        _customerCount = customers;
        _orderCount = orders;
        _countsAvailable = true;
      });
    } catch (e) {
      AppLogger.info('DeleteAccount', 'Failed to load counts: $e');
      // Leave _countsAvailable false — the UI falls back to generic wording.
    }
  }

  Future<void> _loadSubscription() async {
    try {
      final sub = await _subscriptionService.getCurrentSubscription();
      if (sub == null || !mounted) return;

      final planId = sub['plan_id']?.toString();
      String planName = '';
      if (planId != null) {
        final plans = await _subscriptionService.getPlans();
        for (final plan in plans) {
          if (plan['id']?.toString() == planId) {
            planName = (plan['display_name'] ?? plan['name'] ?? '').toString();
            break;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _activeSubscription = sub;
        _activePlanId = planId;
        _activePlanName = planName;
      });
    } catch (e) {
      AppLogger.info('DeleteAccount', 'Failed to load subscription: $e');
    }
  }

  Future<void> _openPlaySubscriptions() async {
    final skuParam =
        _activePlanId != null ? '&sku=${Uri.encodeComponent(_activePlanId!)}' : '';
    final url =
        'https://play.google.com/store/account/subscriptions?package=com.usconnect.ezeebook$skuParam';
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        SnackbarHelper.showError(context, 'manage_subscription_failed'.tr());
      }
    } catch (e) {
      AppLogger.error('DeleteAccount', 'Failed to open Play subscriptions: $e');
      if (mounted) {
        SnackbarHelper.showError(context, 'manage_subscription_failed'.tr());
      }
    }
  }

  Future<void> _onDeletePressed() async {
    if (!_emailMatches) return;

    // Loading dialog — user cannot dismiss it mid-deletion.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 20),
              Expanded(child: Text('del_deleting'.tr())),
            ],
          ),
        ),
      ),
    );

    final AccountDeletionResult result =
        await _deletionService.deleteAccount(reason: _selectedReason.reason);

    if (!mounted) return;

    // Dismiss the loading dialog.
    Navigator.of(context).pop();

    if (result.success) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DeleteAccountSuccessScreen()),
        (route) => false,
      );
    } else {
      SnackbarHelper.showError(
        context,
        result.errorMessage ?? 'del_err_failed'.tr(),
      );
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
        iconTheme: const IconThemeData(color: AppColors.error),
        title: Text(
          'del_screen_title'.tr(),
          style: const TextStyle(
            color: AppColors.error,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildWarningCard(),
          if (_activeSubscription != null) ...[
            const SizedBox(height: 16),
            _buildSubscriptionWarning(),
          ],
          const SizedBox(height: 16),
          _buildReasonDropdown(),
          const SizedBox(height: 16),
          _buildEmailConfirmField(),
          const SizedBox(height: 24),
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildWarningCard() {
    final bullets = <String>[
      'del_item_profile'.tr(),
      _countsAvailable && _customerCount != null
          ? 'del_item_customers'
              .tr(namedArgs: {'count': _customerCount.toString()})
          : 'del_item_customers_generic'.tr(),
      _countsAvailable && _orderCount != null
          ? 'del_item_orders'.tr(namedArgs: {'count': _orderCount.toString()})
          : 'del_item_orders_generic'.tr(),
      'del_item_measurements'.tr(),
      'del_item_subscription'.tr(),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Icon(
              Icons.warning_amber_rounded,
              color: AppColors.error,
              size: 56,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'del_warning_title'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.error,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'del_will_delete'.tr(),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '•  $b',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'del_cannot_undo'.tr(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionWarning() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline,
                  color: Color(0xFFF57F17), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'del_active_sub_warning'.tr(namedArgs: {
                    'plan': _activePlanName.isNotEmpty
                        ? _activePlanName
                        : 'subscription'.tr(),
                  }),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B4E00),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openPlaySubscriptions,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text('del_open_play_subs'.tr()),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFF57F17),
                side: const BorderSide(color: Color(0xFFF57F17), width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReasonDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'del_reason_label'.tr(),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<_ReasonOption>(
              value: _selectedReason,
              isExpanded: true,
              items: _reasons
                  .map(
                    (r) => DropdownMenuItem<_ReasonOption>(
                      value: r,
                      child: Text(r.labelKey.tr()),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedReason = value);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailConfirmField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'del_type_email_confirm'.tr(namedArgs: {'email': _userEmail}),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: false,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            hintText: 'del_email_hint'.tr(),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: _emailMatches
                ? const Icon(Icons.check_circle, color: AppColors.success)
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _emailMatches ? AppColors.success : AppColors.border,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _emailMatches ? AppColors.success : AppColors.primary,
                width: 1.5,
              ),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _emailMatches ? _onDeletePressed : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.textHint,
              disabledForegroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              'del_delete_forever_btn'.tr(),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.5),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              'cancel'.tr(),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
