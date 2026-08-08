import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/page_transitions.dart';
import 'select_customer_screen.dart';
import 'order_view_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _sync = SyncService();
  List<Map<String, dynamic>> _allOrders = [];
  List<Map<String, dynamic>> _filteredOrders = [];
  bool _isLoading = true;
  String? _loadError;
  String _selectedFilter = 'all';
  String _searchQuery = '';
  bool _isSearching = false;
  final _searchController = TextEditingController();

  static const _filters = ['all', 'pending', 'completed', 'delivered', 'overdue'];

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final orders = await _sync.getAllOrdersWithCustomer();
      if (mounted) {
        setState(() {
          _allOrders = orders;
          _isLoading = false;
          _loadError = null;
        });
        _applyFilters();
      }
    } catch (e, st) {
      AppLogger.error('OrdersScreen', 'getAllOrdersWithCustomer failed',
          error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'orders_load_error'.tr();
        });
      }
    }
  }

  void _applyFilters() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    var filtered = List<Map<String, dynamic>>.from(_allOrders);

    // Status filter
    if (_selectedFilter == 'overdue') {
      filtered = filtered.where((o) =>
          o['status'] == 'pending' && (o['delivery_date'] ?? '').compareTo(today) < 0).toList();
    } else if (_selectedFilter != 'all') {
      filtered = filtered.where((o) => o['status'] == _selectedFilter).toList();
    }

    // Search filter — the card shows "Name (#serial)" and the serial is the
    // tailor's primary way of identifying a customer, so both it and the
    // phone must be searchable, not just the name.
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase().replaceFirst('#', '').trim();
      filtered = filtered.where((o) {
        final name = (o['customer_name'] ?? '').toString().toLowerCase();
        final serial = (o['customer_serial'] ?? '').toString();
        final phone =
            (o['customer_phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
        return name.contains(q) ||
            serial == q ||
            (q.isNotEmpty && phone.contains(q));
      }).toList();
    }

    // Newest first. The underlying query sorts by delivery_date ASC, which
    // otherwise opens the list on last year's delivered orders and buries
    // today's work at the bottom.
    filtered.sort((a, b) => (b['created_at'] ?? '')
        .toString()
        .compareTo((a['created_at'] ?? '').toString()));

    setState(() => _filteredOrders = filtered);
  }

  String _getStatusForDisplay(Map<String, dynamic> order) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (order['status'] == 'pending' && (order['delivery_date'] ?? '').compareTo(today) < 0) {
      return 'overdue';
    }
    return order['status'] ?? 'pending';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return AppColors.warning;
      case 'completed':
        return AppColors.success;
      case 'delivered':
        return AppColors.info;
      case 'overdue':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  Color _statusBgColor(String status) {
    switch (status) {
      case 'pending':
        return AppColors.warningLight;
      case 'completed':
        return AppColors.successLight;
      case 'delivered':
        return const Color(0xFFBBDEFB);
      case 'overdue':
        return AppColors.errorLight;
      default:
        return AppColors.divider;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'order_status_pending'.tr();
      case 'completed':
        return 'order_status_completed'.tr();
      case 'delivered':
        return 'order_status_delivered'.tr();
      case 'overdue':
        return 'order_overdue'.tr();
      case 'cancelled':
        // Without this the badge printed the raw English DB value, even in
        // Urdu.
        return 'order_cancelled'.tr();
      default:
        return status;
    }
  }

  String _filterLabel(String filter) {
    switch (filter) {
      case 'all':
        return 'filter_all'.tr();
      case 'pending':
        return 'order_status_pending'.tr();
      case 'completed':
        return 'order_status_completed'.tr();
      case 'delivered':
        return 'order_status_delivered'.tr();
      case 'overdue':
        return 'order_overdue'.tr();
      default:
        return filter;
    }
  }

  String _garmentLabel(Map<String, dynamic> order) {
    final isUrdu = context.locale.languageCode == 'ur';
    String label;
    // A tailor-defined category (or a renamed built-in) carries its own name;
    // its raw stitch_type is an opaque id that must never reach the screen.
    final snapshot = order['category_name']?.toString().trim() ?? '';
    if (snapshot.isNotEmpty) {
      label = snapshot;
    } else {
      switch (order['stitch_type']) {
        case 'full_suit':
          label = isUrdu ? 'مکمل سوٹ' : 'Full Suit';
          break;
        case 'naap_suit':
          label = isUrdu ? 'ناپ سوٹ' : 'Naap Suit';
          break;
        case 'only_shirt':
          label = isUrdu ? 'صرف قمیض' : 'Only Shirt';
          break;
        case 'only_shalwar_trouser':
          label = isUrdu ? 'صرف شلوار/ٹراؤزر' : 'Only Shalwar/Trouser';
          break;
        default:
          label = order['stitch_type'] ?? '';
      }
    }
    final parts = <String>[];
    if (order['shirt_sub_type'] != null) parts.add(_subTypeLabel(order['shirt_sub_type'], isUrdu));
    if (order['bottom_type'] != null) parts.add(_subTypeLabel(order['bottom_type'], isUrdu));
    if (parts.isNotEmpty) label += ' — ${parts.join(' + ')}';
    return label;
  }

  String _subTypeLabel(String type, bool isUrdu) {
    switch (type) {
      case 'kameez':
        return isUrdu ? 'قمیض' : 'Kameez';
      case 'kurti':
        return isUrdu ? 'کرتی' : 'Kurti';
      case 'short_shirt':
        return isUrdu ? 'شارٹ شرٹ' : 'Short Shirt';
      case 'choli':
        return isUrdu ? 'چولی' : 'Choli';
      case 'shalwar':
        return isUrdu ? 'شلوار' : 'Shalwar';
      case 'trouser':
        return isUrdu ? 'ٹراؤزر' : 'Trouser';
      case 'pajama':
        return isUrdu ? 'پاجامہ' : 'Pajama';
      case 'sharara':
        return isUrdu ? 'شرارہ' : 'Sharara';
      case 'gharara':
        return isUrdu ? 'غرارہ' : 'Gharara';
      default:
        return type;
    }
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '';
    try {
      final date = DateTime.parse(isoDate);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (_) {
      return isoDate;
    }
  }

  String _colorsText(Map<String, dynamic> order) {
    try {
      final decoded = json.decode(order['colors'] ?? '[]');
      if (decoded is List) return decoded.join(', ');
    } catch (_) {}
    return order['colors'] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'search_orders'.tr(),
                  border: InputBorder.none,
                  hintStyle: const TextStyle(color: AppColors.textHint),
                ),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
                onChanged: (val) {
                  _searchQuery = val;
                  _applyFilters();
                },
              )
            : Text('orders'.tr()),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchController.clear();
                  _applyFilters();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Breathing room so the chips don't sit flush against the app bar.
          const SizedBox(height: 16),
          // Filter tabs
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final f = _filters[i];
                final isSelected = _selectedFilter == f;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() => _selectedFilter = f);
                      _applyFilters();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Ink(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.border,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _filterLabel(f),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          // Orders list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _loadError != null
                    ? _buildErrorState()
                    : _filteredOrders.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            color: AppColors.primary,
                            onRefresh: _loadOrders,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                              itemCount: _filteredOrders.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) => _buildOrderCard(_filteredOrders[i]),
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            SlidePageRoute(page: const SelectCustomerScreen()),
          );
          _loadOrders();
        },
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        icon: const Icon(Icons.add),
        label: Text('place_new_order'.tr()),
      ),
    );
  }

  Widget _buildEmptyState() {
    // Distinguish "this shop has no orders" from "your search/filter matched
    // nothing" — telling a tailor with 200 orders that they have none reads
    // as data loss.
    final isNarrowed = _searchQuery.isNotEmpty || _selectedFilter != 'all';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.orderAccent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                isNarrowed
                    ? Icons.search_off_rounded
                    : Icons.receipt_long_outlined,
                size: 40,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isNarrowed ? 'no_results_found'.tr() : 'no_orders_yet'.tr(),
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.error_outline,
                size: 40,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _loadError ?? 'orders_load_error'.tr(),
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadOrders,
              icon: const Icon(Icons.refresh),
              label: Text('retry'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = _getStatusForDisplay(order);
    final quantity = order['quantity'] ?? 1;
    final colors = _colorsText(order);
    final total = (order['total_amount'] ?? 0).toDouble();
    final advance = (order['advance_payment'] ?? 0).toDouble();
    final remaining = total - advance;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(
            SlidePageRoute(page: OrderViewScreen(order: order)),
          );
          _loadOrders();
        },
        borderRadius: BorderRadius.circular(16),
        splashColor: AppColors.primary.withValues(alpha: 0.08),
        child: Ink(
        padding: const EdgeInsets.all(16),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Customer name + status badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${order['customer_name']} (#${order['customer_serial']})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusBgColor(status),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _statusColor(status),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Row 2: Garment type
            Text(
              _garmentLabel(order),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            // Row 3: Details row
            Row(
              children: [
                _buildDetailChip(Icons.format_list_numbered, '$quantity'),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildDetailChip(Icons.palette_outlined, colors),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Row 4: Delivery date + amount
            Row(
              children: [
                Icon(Icons.event, size: 14, color: _statusColor(status)),
                const SizedBox(width: 4),
                Text(
                  _formatDate(order['delivery_date']),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _statusColor(status),
                  ),
                ),
                const Spacer(),
                Text(
                  'Rs. ${total.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (remaining > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '(${'remaining_baqaya'.tr()} ${remaining.toStringAsFixed(0)})',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildDetailChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
