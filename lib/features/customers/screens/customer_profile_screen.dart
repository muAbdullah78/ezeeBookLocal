import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/utils/garment_labels.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../models/customer.dart';
import '../../../models/measurement.dart';
import '../../orders/screens/order_view_screen.dart';
import '../../orders/screens/select_garment_screen.dart';

/// Profile for a single customer: their saved measurements and past orders.
///
/// Returning customers expect the shop to still have their measurements, but
/// the app previously offered no way to see what was on file — the only hint
/// was a prompt buried after picking a category. This screen surfaces that
/// history up front so the tailor can reuse it instead of re-measuring.
class CustomerProfileScreen extends StatefulWidget {
  final Customer customer;

  /// True when reached from the place-order flow, where continuing to the
  /// order is the expected next step.
  final bool orderFlow;

  const CustomerProfileScreen({
    super.key,
    required this.customer,
    this.orderFlow = false,
  });

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  final _sync = SyncService();

  List<Map<String, dynamic>> _orders = [];
  List<Measurement> _measurements = [];
  bool _loading = true;
  String? _expandedMeasurementId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final orders = await _sync.getOrdersForCustomer(widget.customer.id);
    final measRows = await _sync.getMeasurementsForCustomer(widget.customer.id);
    if (!mounted) return;
    setState(() {
      _orders = orders;
      _measurements = measRows.map((m) => Measurement.fromMap(m)).toList();
      _loading = false;
    });
  }

  /// Most recent saved measurement per garment type — older revisions of the
  /// same garment would only add noise.
  List<Measurement> get _latestPerGarment {
    final byType = <String, Measurement>{};
    for (final m in _measurements) {
      final existing = byType[m.garmentType];
      if (existing == null || m.updatedAt.isAfter(existing.updatedAt)) {
        byType[m.garmentType] = m;
      }
    }
    final list = byType.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Future<void> _startNewOrder() async {
    await Navigator.of(context).push(
      SlidePageRoute(page: SelectGarmentScreen(customer: widget.customer)),
    );
    if (mounted) _load();
  }

  Future<void> _openOrder(Map<String, dynamic> order) async {
    // Orders fetched by customer id carry no customer columns; the order view
    // needs them for the header, WhatsApp and the PDF.
    final enriched = Map<String, dynamic>.from(order)
      ..['customer_name'] = widget.customer.name
      ..['customer_phone'] = widget.customer.phone
      ..['customer_serial'] = widget.customer.serialNumber;
    await Navigator.of(context).push(
      SlidePageRoute(page: OrderViewScreen(order: enriched)),
    );
    if (mounted) _load();
  }

  String _formatDate(Object? value) {
    if (value == null) return '-';
    try {
      final d = value is DateTime ? value : DateTime.parse(value.toString());
      return '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('${c.name} (#${c.serialNumber})')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                _buildHeaderCard(),
                const SizedBox(height: 14),
                _buildMeasurementsSection(),
                const SizedBox(height: 14),
                _buildOrdersSection(),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _startNewOrder,
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
              label: Text(
                // Coming from the place-order flow the tailor is already
                // mid-order, so the button continues rather than restarts.
                widget.orderFlow
                    ? 'continue_to_order'.tr()
                    : 'place_new_order'.tr(),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final c = widget.customer;
    final pending = _orders.where((o) => o['status'] == 'pending').length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.dashboardAccent,
            child: Icon(
              c.gender == 'female' ? Icons.woman : Icons.man,
              color: AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (c.phone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    c.phone,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    _chip('${_orders.length}', 'total_orders'.tr()),
                    const SizedBox(width: 8),
                    if (pending > 0)
                      _chip('$pending', 'order_status_pending'.tr()),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.dashboardAccent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$value $label',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildMeasurementsSection() {
    final latest = _latestPerGarment;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.straighten, 'saved_measurements'.tr()),
          const SizedBox(height: 10),
          if (latest.isEmpty)
            Text(
              'no_saved_measurements'.tr(),
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            )
          else
            ...latest.map(_buildMeasurementTile),
        ],
      ),
    );
  }

  Widget _buildMeasurementTile(Measurement m) {
    final isExpanded = _expandedMeasurementId == m.id;
    final values = m.measurements.entries
        .where((e) => e.value != null && e.value.toString().isNotEmpty)
        .toList();
    final rawOptions = _decodeOptions(m.additionalOptions);
    // Tailor-defined fields are named by the snapshot saved with the order; the
    // reserved bookkeeping entries must not be listed as instructions.
    final labels = GarmentLabels.labelSnapshot(rawOptions);
    final options = GarmentLabels.visibleOptions(rawOptions);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(
                () => _expandedMeasurementId = isExpanded ? null : m.id),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          GarmentLabels.groupLabel(m.garmentType, rawOptions),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${'last_updated'.tr()}: ${_formatDate(m.updatedAt)}'
                          '  •  ${values.length}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: values
                        .map((e) => SizedBox(
                              width:
                                  (MediaQuery.of(context).size.width - 96) / 2,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      GarmentLabels.fieldLabel(e.key, labels),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    e.value.toString(),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                  if (options.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...options.entries.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '${GarmentLabels.fieldLabel(e.key, labels)}: '
                            '${_optionValue(e.value)}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        )),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrdersSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.receipt_long, 'order_history'.tr()),
          const SizedBox(height: 10),
          if (_orders.isEmpty)
            Text(
              'no_orders_for_customer'.tr(),
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            )
          else
            ..._orders.map(_buildOrderTile),
        ],
      ),
    );
  }

  Widget _buildOrderTile(Map<String, dynamic> order) {
    final status = (order['status'] ?? 'pending').toString();
    final garment = GarmentLabels.describe(
      stitchTypeValue: order['stitch_type']?.toString(),
      categoryName: order['category_name']?.toString(),
      shirtSubType: order['shirt_sub_type']?.toString(),
      bottomType: order['bottom_type']?.toString(),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openOrder(order),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      garment,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${'order_date'.tr()}: '
                      '${_formatDate(order['created_at'])}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusBg(status),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _statusLabel(status),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _statusColor(status),
                  ),
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 20, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== helpers ====================

  Widget _sectionTitle(IconData icon, String title) => Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      );

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      );

  Map<String, dynamic> _decodeOptions(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = json.decode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {};
  }

  String _optionValue(Object? v) {
    if (v is bool) return v ? 'Yes' : 'No';
    if (v is num && (v == 0 || v == 1)) return v == 1 ? 'Yes' : 'No';
    return GarmentLabels.titleCase(v?.toString() ?? '');
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'order_status_pending'.tr();
      case 'completed':
        return 'order_status_completed'.tr();
      case 'delivered':
        return 'order_status_delivered'.tr();
      case 'cancelled':
        return 'order_cancelled'.tr();
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return AppColors.warning;
      case 'completed':
        return AppColors.success;
      case 'delivered':
        return AppColors.info;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  Color _statusBg(String status) {
    switch (status) {
      case 'pending':
        return AppColors.warningLight;
      case 'completed':
        return AppColors.successLight;
      case 'delivered':
        return const Color(0xFFBBDEFB);
      case 'cancelled':
        return AppColors.errorLight;
      default:
        return AppColors.divider;
    }
  }
}
