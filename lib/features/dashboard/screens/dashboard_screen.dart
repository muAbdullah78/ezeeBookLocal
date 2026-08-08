import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/services/whatsapp_service.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../customers/screens/add_customer_screen.dart';
import '../../orders/screens/order_view_screen.dart';
import '../../orders/screens/select_customer_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _sync = SyncService();
  int _customerCount = 0;
  int _activeOrderCount = 0;
  int _overdueOrderCount = 0;
  List<Map<String, dynamic>> _todaysDeliveries = [];
  bool _statsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final customers = await _sync.getCustomerCount();
    final active = await _sync.getActiveOrderCount();
    final overdue = await _sync.getOverdueOrderCount();
    final deliveries = await _sync.getTodaysDeliveries();
    if (mounted) {
      setState(() {
        _customerCount = customers;
        _activeOrderCount = active;
        _overdueOrderCount = overdue;
        _todaysDeliveries = deliveries;
        _statsLoading = false;
      });
    }
  }

  Future<void> _confirmMarkCompleted(Map<String, dynamic> order) async {
    final orderId = order['id'] as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('mark_done_confirm_title'.tr()),
        content: Text('mark_done_confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: Text('mark_done_confirm_button'.tr()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _sync.updateOrderStatus(orderId, 'completed');
    if (!mounted) return;
    _loadStats();

    // The row leaves Today's Deliveries the moment it is completed, so this is
    // the last chance to offer the "your order is ready" message from here.
    final phone = (order['customer_phone'] ?? '').toString();
    if (phone.isEmpty) return;
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('send_order_ready'.tr()),
        content: Text('send_ready_prompt'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('not_now'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: Text('send'.tr()),
          ),
        ],
      ),
    );
    if (send == true && mounted) {
      await _sendReadyMessage({...order, 'status': 'completed'});
    }
  }

  /// Send the "your order is ready" WhatsApp message straight from the
  /// dashboard, so the tailor can notify a customer without opening the order.
  Future<void> _sendReadyMessage(Map<String, dynamic> order) async {
    final phone = (order['customer_phone'] ?? '').toString();
    if (phone.isEmpty) {
      SnackbarHelper.showInfo(context, 'no_phone_number'.tr());
      return;
    }
    final profile = await _sync.getShopProfile();
    final message = WhatsAppService().buildOrderReady(
      order: order,
      shopProfile: profile,
    );
    final result = await WhatsAppService().send(phone: phone, message: message);
    if (!mounted) return;
    if (result == WhatsAppSendResult.invalidNumber) {
      SnackbarHelper.showError(context, 'whatsapp_invalid_number'.tr());
    } else if (result == WhatsAppSendResult.launchFailed) {
      SnackbarHelper.showError(context, 'whatsapp_open_failed'.tr());
    }
  }

  Future<void> _navigateToAddCustomer() async {
    final result = await Navigator.of(context).push(
      SlidePageRoute(page: const AddCustomerScreen()),
    );
    if (result == true) _loadStats();
  }

  String _garmentLabel(Map<String, dynamic> order) {
    final isUrdu = context.locale.languageCode == 'ur';
    switch (order['stitch_type']) {
      case 'full_suit':
        return isUrdu ? 'مکمل سوٹ' : 'Full Suit';
      case 'naap_suit':
        return isUrdu ? 'ناپ سوٹ' : 'Naap Suit';
      case 'only_shirt':
        return isUrdu ? 'صرف قمیض' : 'Only Shirt';
      case 'only_shalwar_trouser':
        return isUrdu ? 'صرف شلوار/ٹراؤزر' : 'Only Shalwar/Trouser';
      default:
        return order['stitch_type'] ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatCards(),
                    const SizedBox(height: 24),
                    _buildQuickActions(context),
                    const SizedBox(height: 24),
                    _buildDeliveriesSection(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, topPadding + 14, 20, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2EC4B6), Color(0xFF1A8C7E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF26A69A).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(Icons.content_cut,
                      size: 18, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Ezee',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w300,
                    color: Colors.white,
                    letterSpacing: 1.0,
                  ),
                ),
                const Text(
                  'Book',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCards() {
    if (_statsLoading) {
      return const Row(
        children: [
          Expanded(child: ShimmerStatCard()),
          SizedBox(width: 10),
          Expanded(child: ShimmerStatCard()),
          SizedBox(width: 10),
          Expanded(child: ShimmerStatCard()),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: _StatBox(
            icon: Icons.people_rounded,
            value: '$_customerCount',
            label: 'total_customers'.tr(),
            color: const Color(0xFF1E88E5),
            bgColor: const Color(0xFFE3F2FD),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatBox(
            icon: Icons.receipt_long_rounded,
            value: '$_activeOrderCount',
            label: 'active_orders'.tr(),
            color: const Color(0xFFF57C00),
            bgColor: const Color(0xFFFFF3E0),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatBox(
            icon: Icons.warning_amber_rounded,
            value: '$_overdueOrderCount',
            label: 'overdue_orders'.tr(),
            color: const Color(0xFFE53935),
            bgColor: const Color(0xFFFFEBEE),
          ),
        ),
      ],
    );
  }

Widget _buildQuickActions(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _navigateToAddCustomer,
            borderRadius: BorderRadius.circular(18),
            splashColor: Colors.white.withValues(alpha: 0.15),
            highlightColor: Colors.white.withValues(alpha: 0.08),
            child: Ink(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2EC4B6), Color(0xFF1A8C7E)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF26A69A).withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.person_add_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'add_new_customer'.tr(),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'نیا گاہک شامل کریں',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'NotoNastaliqUrdu',
                          color: Colors.white.withValues(alpha: 0.7),
                          height: 1.8,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              await Navigator.of(context).push(
                SlidePageRoute(page: const SelectCustomerScreen()),
              );
              _loadStats();
            },
            borderRadius: BorderRadius.circular(18),
            splashColor: AppColors.primary.withValues(alpha: 0.12),
            highlightColor: AppColors.primary.withValues(alpha: 0.06),
            child: Ink(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.primary, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.dashboardAccent,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.add_shopping_cart_rounded,
                        color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'place_new_order'.tr(),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        'نیا آرڈر دیں',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'NotoNastaliqUrdu',
                          color: AppColors.primary.withValues(alpha: 0.7),
                          height: 1.8,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeliveriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'todays_deliveries'.tr(),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.dashboardAccent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_todaysDeliveries.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_todaysDeliveries.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.dashboardAccent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.event_available_rounded,
                      size: 26,
                      color: AppColors.primary.withValues(alpha: 0.5)),
                ),
                const SizedBox(height: 10),
                Text(
                  'no_deliveries_today'.tr(),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          )
        else
          ...(_todaysDeliveries.map(_buildDeliveryCard)),
      ],
    );
  }

  Widget _buildDeliveryCard(Map<String, dynamic> order) {
    final quantity = order['quantity'] ?? 1;
    String colors = '';
    try {
      final decoded = json.decode(order['colors'] ?? '[]');
      if (decoded is List) colors = decoded.join(', ');
    } catch (_) {
      colors = order['colors'] ?? '';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push(
              SlidePageRoute(page: OrderViewScreen(order: order)),
            );
            _loadStats();
          },
          borderRadius: BorderRadius.circular(16),
          splashColor: AppColors.primary.withValues(alpha: 0.08),
          child: Ink(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order['customer_name'] ?? '',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_garmentLabel(order)} x$quantity',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (colors.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          colors,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textHint,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 34,
                  child: ElevatedButton(
                    onPressed: () => _confirmMarkCompleted(order),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'mark_completed'.tr(),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final Color bgColor;

  const _StatBox({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.12),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
