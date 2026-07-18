import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../models/customer.dart';
import '../../customers/screens/add_customer_screen.dart';
import 'select_garment_screen.dart';

class SelectCustomerScreen extends StatefulWidget {
  const SelectCustomerScreen({super.key});

  @override
  State<SelectCustomerScreen> createState() => _SelectCustomerScreenState();
}

class _SelectCustomerScreenState extends State<SelectCustomerScreen> {
  final _sync = SyncService();
  final _searchController = TextEditingController();
  List<Customer> _allCustomers = [];
  List<Customer> _filteredCustomers = [];
  bool _isLoading = true;
  int _selectedGenderTab = 0; // 0 = Men, 1 = Women

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
        _allCustomers = data.map((m) => Customer.fromMap(m)).toList();
        _isLoading = false;
        _applyFilters();
      });
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    final gender = _selectedGenderTab == 0 ? 'male' : 'female';

    var results = _allCustomers.where((c) => c.gender == gender);

    if (query.isNotEmpty) {
      if (query.startsWith('#')) {
        final numStr = query.substring(1);
        final num = int.tryParse(numStr);
        if (num != null) {
          results = results.where((c) => c.serialNumber == num);
        }
      } else {
        results = results.where((c) =>
            c.name.toLowerCase().contains(query) ||
            c.phone.contains(query));
      }
    }

    setState(() {
      _filteredCustomers = results.toList();
    });
  }

  Future<void> _navigateToAddCustomer() async {
    final result = await Navigator.of(context).push(
      SlidePageRoute(page: const AddCustomerScreen()),
    );
    if (result == true) _loadCustomers();
  }

  void _selectCustomer(Customer customer) {
    Navigator.of(context).push(
      SlidePageRoute(page: SelectGarmentScreen(customer: customer)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('select_customer'.tr()),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSearchBar(),
                _buildGenderTabs(),
                Expanded(child: _buildBody()),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddCustomer,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.person_add_rounded, size: 26),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => _applyFilters(),
        decoration: InputDecoration(
          hintText: 'search_customer_placeholder'.tr(),
          hintStyle: const TextStyle(
            fontSize: 14,
            color: AppColors.textHint,
          ),
          prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
          filled: true,
          fillColor: AppColors.cardBackground,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildGenderTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Expanded(child: _buildGenderTab(0, Icons.male, 'men'.tr())),
          const SizedBox(width: 10),
          Expanded(child: _buildGenderTab(1, Icons.female, 'women'.tr())),
        ],
      ),
    );
  }

  Widget _buildGenderTab(int index, IconData icon, String label) {
    final isSelected = _selectedGenderTab == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedGenderTab = index;
            _applyFilters();
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: isSelected ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_allCustomers.isEmpty) {
      return _buildNoCustomersState();
    }
    if (_filteredCustomers.isEmpty) {
      return _buildEmptySearchState();
    }
    return _buildCustomerList();
  }

  Widget _buildNoCustomersState() {
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
                color: AppColors.customerAccent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.people_outline,
                  size: 40, color: Color(0xFF1E88E5)),
            ),
            const SizedBox(height: 20),
            Text(
              'add_customer_first'.tr(),
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _navigateToAddCustomer,
              icon: const Icon(Icons.person_add_rounded),
              label: Text('add_new_customer'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySearchState() {
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
                color: AppColors.customerAccent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.search_off,
                  size: 40, color: Color(0xFF1E88E5)),
            ),
            const SizedBox(height: 20),
            Text(
              'no_results_found'.tr(),
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

  Widget _buildCustomerList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
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
            trailing: const Icon(Icons.chevron_right,
                color: AppColors.textHint, size: 22),
            onTap: () => _selectCustomer(customer),
          ),
        );
      },
    );
  }
}
