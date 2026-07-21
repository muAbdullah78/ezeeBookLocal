import 'dart:io';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/billing_service.dart';
import '../../../core/services/subscription_service.dart';
import '../../../core/utils/snackbar_helper.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _subscriptionService = SubscriptionService();
  List<Map<String, dynamic>> _plans = [];
  Map<String, dynamic>? _currentSub;
  bool _loading = true;
  String? _selectedPlanId;
  bool _subscribing = false;
  void Function(String, BillingEvent, String)? _previousBillingCallback;

  @override
  void initState() {
    super.initState();
    _loadData();
    _setupBillingCallback();
  }

  @override
  void dispose() {
    BillingService().onPurchaseComplete = _previousBillingCallback;
    super.dispose();
  }

  void _setupBillingCallback() {
    _previousBillingCallback = BillingService().onPurchaseComplete;
    BillingService().onPurchaseComplete = (planId, event, message) async {
      if (!mounted) return;

      switch (event) {
        case BillingEvent.success:
          // The subscription was already created with the server-verified
          // expiry inside BillingService._handlePurchase. Do NOT create it
          // again here — a second write would use a client-computed expiry.
          SnackbarHelper.showSuccess(context, 'subscription_activated'.tr());
          Navigator.of(context).pop(true);
          break;
        case BillingEvent.pending:
          SnackbarHelper.showInfo(context, message);
          // Keep the screen alive; do NOT mark as failed
          break;
        case BillingEvent.cancelled:
          // No snackbar needed; user knows they cancelled
          break;
        case BillingEvent.error:
          SnackbarHelper.showError(
            context,
            message.isEmpty ? 'subscription_failed'.tr() : message,
          );
          break;
      }

      if (!mounted) return;
      // Only stop the loading spinner for terminal states. A pending
      // purchase may still resolve to success later.
      if (event != BillingEvent.pending) {
        setState(() => _subscribing = false);
      }
    };
  }

  Future<void> _loadData() async {
    final plans = await _subscriptionService.getPlans();
    final sub = await _subscriptionService.getCurrentSubscription();
    if (mounted) {
      setState(() {
        _plans = plans;
        _currentSub = sub;
        _selectedPlanId = _plans.isNotEmpty
            ? _plans.firstWhere((p) => _isPopular(p), orElse: () => _plans.first)['id']
            : null;
        _loading = false;
      });
    }
  }

  double _getFinalPrice() {
    if (_selectedPlanId == null) return 0;
    final plan = _plans.firstWhere((p) => p['id'] == _selectedPlanId);
    return ((plan['price_pkr'] ?? 0) as num).toDouble();
  }

  Future<void> _subscribe() async {
    if (_selectedPlanId == null || _subscribing) return;

    // Promo redemption UI deferred to v1.1 — requires paired Edge Function.

    // Google Play billing path
    if (Platform.isAndroid && !BillingService().isAvailable) {
      if (!mounted) return;
      SnackbarHelper.showError(context, 'billing_unavailable_message'.tr());
      return;
    }

    setState(() => _subscribing = true);
    // Result arrives via onPurchaseComplete callback set in _setupBillingCallback
    await BillingService().purchaseSubscription(_selectedPlanId!);
  }

  String _formatNumber(double n) {
    if (n == n.truncateToDouble()) {
      return NumberFormat('#,###', 'en').format(n.toInt());
    }
    return NumberFormat('#,###', 'en').format(n);
  }

  String _getPlanDisplayName(String planId) {
    switch (planId) {
      case 'monthly':
        return 'monthly_plan'.tr();
      case 'quarterly':
        return 'quarterly_plan'.tr();
      case 'yearly':
        return 'yearly_plan'.tr();
      default:
        return planId;
    }
  }

  double _pricePerMonth(Map<String, dynamic> plan) {
    final price = ((plan['price_pkr'] ?? 0) as num).toDouble();
    final months = ((plan['duration_months'] ?? 1) as num).toInt();
    if (months <= 0) return price;
    return price / months;
  }

  int _savingsPkr(Map<String, dynamic> plan, List<Map<String, dynamic>> allPlans) {
    final months = ((plan['duration_months'] ?? 1) as num).toInt();
    if (months <= 1) return 0;
    final monthlyPrice = _monthlyBasePrice(allPlans);
    if (monthlyPrice <= 0) return 0;
    final thisPrice = ((plan['price_pkr'] ?? 0) as num).toInt();
    final saved = (monthlyPrice * months) - thisPrice;
    return saved > 0 ? saved : 0;
  }

  double _savingsPercent(Map<String, dynamic> plan, List<Map<String, dynamic>> allPlans) {
    final months = ((plan['duration_months'] ?? 1) as num).toInt();
    if (months <= 1) return 0;
    final monthlyPrice = _monthlyBasePrice(allPlans);
    if (monthlyPrice <= 0) return 0;
    final monthlyTotal = monthlyPrice * months;
    final thisPrice = ((plan['price_pkr'] ?? 0) as num).toInt();
    if (monthlyTotal <= 0) return 0;
    return ((monthlyTotal - thisPrice) / monthlyTotal) * 100;
  }

  bool _isPopular(Map<String, dynamic> plan) {
    final months = ((plan['duration_months'] ?? 0) as num).toInt();
    return months == 3;
  }

  int _monthlyBasePrice(List<Map<String, dynamic>> allPlans) {
    for (final p in allPlans) {
      final months = ((p['duration_months'] ?? 0) as num).toInt();
      if (months == 1) {
        return ((p['price_pkr'] ?? 0) as num).toInt();
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('subscription_title'.tr())),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_currentSub != null) _buildActiveCard(),
              if (_currentSub != null) const SizedBox(height: 20),
              _buildHeader(),
              const SizedBox(height: 16),
              ..._plans.map(_buildPlanCard),
              const SizedBox(height: 16),
              _buildAutoRenewalDisclosure(),
              const SizedBox(height: 80),
            ],
          ),
        ),
        _buildSubscribeButton(),
      ],
    );
  }

  // ==================== ACTIVE SUBSCRIPTION CARD ====================

  Widget _buildActiveCard() {
    final planName = _subscriptionService.getPlanName(_currentSub!['plan_id']);
    final endDate = _currentSub!['end_date'] as String;
    final daysLeft = _subscriptionService.getDaysRemaining(endDate);
    final isExpiringSoon = daysLeft <= 7;

    DateTime parsedEnd;
    try {
      parsedEnd = DateTime.parse(endDate);
    } catch (_) {
      parsedEnd = DateTime.now();
    }
    final formattedEnd = DateFormat('dd MMM yyyy').format(parsedEnd);

    final statusColor = isExpiringSoon ? AppColors.warning : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status row
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isExpiringSoon ? Icons.warning_amber_rounded : Icons.verified,
                  color: statusColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'active_plan'.tr(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      planName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              // Days badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'days_remaining'.tr(namedArgs: {'days': daysLeft.toString()}),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: statusColor.withValues(alpha: 0.15), height: 1),
          const SizedBox(height: 10),
          Text(
            '${'valid_until'.tr()}: $formattedEnd',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          if (isExpiringSoon) ...[
            const SizedBox(height: 6),
            Text(
              'expiring_soon'.tr(),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== HEADER ====================

  Widget _buildHeader() {
    return Column(
      children: [
        Text(
          'choose_plan'.tr(),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'unlock_features'.tr(),
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ==================== PLAN CARDS ====================

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final planId = plan['id'] as String;
    final isSelected = _selectedPlanId == planId;
    final isPopular = _isPopular(plan);
    final isYearly = planId == 'yearly';
    final pricePkr = ((plan['price_pkr'] ?? 0) as num).toDouble();
    final pricePerMonth = _pricePerMonth(plan);
    final savingsPkr = _savingsPkr(plan, _plans).toDouble();
    final savingsPercent = _savingsPercent(plan, _plans).toInt();
    final durationMonths = ((plan['duration_months'] ?? 1) as num).toInt();
    final originalPrice = pricePerMonth == 950.0 ? 0.0 : 950.0 * durationMonths;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPlanId = planId;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.04)
              : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: badges + radio
            Row(
              children: [
                if (isPopular)
                  _buildBadge('most_popular'.tr(), AppColors.primary),
                if (isYearly)
                  _buildBadge('best_value'.tr(), AppColors.success),
                const Spacer(),
                // Radio
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.textHint,
                      width: 2,
                    ),
                    color: isSelected ? AppColors.primary : Colors.transparent,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ],
            ),
            if (isPopular || isYearly) const SizedBox(height: 12),
            // Plan name
            Text(
              _getPlanDisplayName(planId),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            // Price row
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'Rs. ${_formatNumber(pricePkr)}',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
                if (originalPrice > 0) ...[
                  const SizedBox(width: 10),
                  Text(
                    'Rs. ${_formatNumber(originalPrice)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textHint.withValues(alpha: 0.7),
                      decoration: TextDecoration.lineThrough,
                      decorationColor: AppColors.textHint,
                    ),
                  ),
                ],
              ],
            ),
            // Per month + savings
            if (savingsPkr > 0) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Rs. ${_formatNumber(pricePerMonth)}${'per_month'.tr()} — ${'save_amount'.tr(namedArgs: {'amount': _formatNumber(savingsPkr), 'percent': savingsPercent.toString()})}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // ==================== AUTO-RENEWAL DISCLOSURE ====================

  Widget _buildAutoRenewalDisclosure() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.textHint.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: AppColors.textHint.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'auto_renewal_disclosure'.tr(),
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary.withValues(alpha: 0.8),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== SUBSCRIBE BUTTON ====================

  Widget _buildSubscribeButton() {
    final finalPrice = _getFinalPrice();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _subscribing || _selectedPlanId == null ? null : _subscribe,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.transparent,
              disabledForegroundColor: Colors.white60,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _subscribing
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    'subscribe_button'.tr(namedArgs: {'price': _formatNumber(finalPrice)}),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ),
    );
  }
}
