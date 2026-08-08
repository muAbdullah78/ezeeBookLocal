import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../models/customer.dart';
import 'add_customer_screen.dart';
import 'customer_profile_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _sync = SyncService();
  List<Customer> _customers = [];
  List<Customer> _filteredCustomers = [];
  bool _isLoading = true;
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    final data = await _sync.getAllCustomers();
    if (mounted) {
      setState(() {
        _customers = data.map((m) => Customer.fromMap(m)).toList();
        _filteredCustomers = _customers;
        _isLoading = false;
      });
    }
  }

  void _filterCustomers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCustomers = _customers;
      } else {
        _filteredCustomers = _customers
            .where((c) =>
                c.name.toLowerCase().contains(query.toLowerCase()) ||
                c.phone.contains(query))
            .toList();
      }
    });
  }

  Future<void> _navigateToAdd() async {
    final result = await Navigator.of(context).push(
      SlidePageRoute(page: const AddCustomerScreen()),
    );
    if (result == true) _loadCustomers();
  }

  Future<void> _openProfile(Customer customer) async {
    await Navigator.of(context).push(
      SlidePageRoute(page: CustomerProfileScreen(customer: customer)),
    );
    if (mounted) _loadCustomers();
  }

  Future<void> _navigateToEdit(Customer customer) async {
    final result = await Navigator.of(context).push(
      SlidePageRoute(page: AddCustomerScreen(customer: customer)),
    );
    if (result == true) _loadCustomers();
  }

  Future<void> _deleteCustomer(Customer customer) async {
    final orderCount = await _sync.getOrderCountForCustomer(customer.id);
    if (!mounted) return;

    final body = orderCount > 0
        ? 'delete_customer_confirm_with_orders'.tr(namedArgs: {
            'name': customer.name,
            'orders': '$orderCount',
          })
        : 'delete_customer_confirm_no_orders'.tr(namedArgs: {
            'name': customer.name,
          });

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('delete'.tr()),
        content: Text(body),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            child: Text('delete'.tr()),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _sync.deleteCustomer(customer.id);
      _loadCustomers();
      if (mounted) {
        SnackbarHelper.showInfo(context, 'customer_deleted'.tr());
      }
    }
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
                // The global inputDecorationTheme fills this field with a
                // near-white background, so the text and hint must be dark —
                // white-on-white made the query invisible while typing.
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'search_customers'.tr(),
                  hintStyle: const TextStyle(color: AppColors.textHint),
                  border: InputBorder.none,
                ),
                onChanged: _filterCustomers,
              )
            : Text('customers'.tr()),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _filteredCustomers = _customers;
                }
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadCustomers,
              color: AppColors.primary,
              child: _filteredCustomers.isEmpty
                  ? _buildEmptyState()
                  : _buildCustomerList(),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAdd,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.person_add_rounded, size: 26),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        Padding(
        padding: const EdgeInsets.only(top: 120, left: 32, right: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.customerAccent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.people_outline,
                  size: 40, color: Color(0xFF1E88E5)),
            ),
            const SizedBox(height: 20),
            Text(
              _isSearching
                  ? 'no_results_found'.tr()
                  : 'no_customers_yet'.tr(),
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      ],
    );
  }

  Widget _buildCustomerList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: _filteredCustomers.length,
      itemBuilder: (context, index) {
        final customer = _filteredCustomers[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
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
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: customer.gender == 'female'
                    ? const Color(0xFFFCE4EC)
                    : AppColors.customerAccent,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                customer.gender == 'female' ? Icons.female : Icons.male,
                color: customer.gender == 'female'
                    ? const Color(0xFFE91E63)
                    : const Color(0xFF1E88E5),
                size: 24,
              ),
            ),
            title: Text(
              customer.name,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: Text(
             '#${customer.serialNumber} • ${customer.phone}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            trailing: PopupMenuButton(
              icon: const Icon(Icons.more_vert, color: AppColors.textHint),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  child: Row(
                    children: [
                      const Icon(Icons.edit_outlined,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text('edit'.tr()),
                    ],
                  ),
                  onTap: () =>
                      Future.delayed(Duration.zero, () => _navigateToEdit(customer)),
                ),
                PopupMenuItem(
                  child: Row(
                    children: [
                      const Icon(Icons.delete_outline,
                          size: 18, color: AppColors.error),
                      const SizedBox(width: 8),
                      Text('delete'.tr(),
                          style: const TextStyle(color: AppColors.error)),
                    ],
                  ),
                  onTap: () =>
                      Future.delayed(Duration.zero, () => _deleteCustomer(customer)),
                ),
              ],
            ),
            // Tapping a customer shows their profile (measurements + order
            // history); editing stays available in the ⋮ menu.
            onTap: () => _openProfile(customer),
          ),
        );
      },
    );
  }
}