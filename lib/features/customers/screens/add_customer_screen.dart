import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../models/customer.dart';

class AddCustomerScreen extends StatefulWidget {
  final Customer? customer;

  const AddCustomerScreen({super.key, this.customer});

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _serialController = TextEditingController();
  final _sync = SyncService();
  String _selectedGender = 'male';
  bool _isLoading = false;
  int _nextSerialNumber = 1;

  bool get _isEditing => widget.customer != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameController.text = widget.customer!.name;
      _phoneController.text = widget.customer!.phone;
      _selectedGender = widget.customer!.gender;
      _serialController.text = widget.customer!.serialNumber.toString();
    } else {
      _loadNextSerialNumber();
    }
  }

  Future<void> _loadNextSerialNumber() async {
    _nextSerialNumber = await _sync.getNextCustomerSerial();
    if (mounted && _serialController.text.isEmpty) {
      setState(() {
        _serialController.text = '$_nextSerialNumber';
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _serialController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final serialNumber = int.parse(_serialController.text.trim());

      if (_isEditing) {
        final updated = widget.customer!.copyWith(
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          gender: _selectedGender,
          serialNumber: serialNumber,
        );
        await _sync.updateCustomer(updated.id, updated.toMap());
      } else {
        final customer = Customer(
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          gender: _selectedGender,
          serialNumber: serialNumber,
        );
        await _sync.saveCustomer(customer.toMap());
      }

      if (!mounted) return;

      SnackbarHelper.showSuccess(context, _isEditing
          ? 'customer_updated'.tr()
          : 'success_customer_added'.tr());

      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      SnackbarHelper.showError(context, 'error_generic'.tr(namedArgs: {'error': '$e'}));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEditing ? 'edit'.tr() : 'add_new_customer'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Customer Name
              _buildLabel('customer_name'.tr()),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'customer_name'.tr(),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'error_required_field'.tr();
                  }
                  return null;
                },
              ),

              const SizedBox(height: 20),

              // Phone Number
              _buildLabel('phone_number'.tr()),
              const SizedBox(height: 6),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  hintText: '03XX XXXXXXX',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'error_required_field'.tr();
                  }
                  return null;
                },
              ),

              const SizedBox(height: 20),

              // Gender
              _buildLabel('gender'.tr()),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _buildGenderButton('male', Icons.male, 'male'.tr())),
                  const SizedBox(width: 14),
                  Expanded(child: _buildGenderButton('female', Icons.female, 'female'.tr())),
                ],
              ),

              const SizedBox(height: 20),

              // Serial Number
              _buildLabel('customer_id'.tr()),
              const SizedBox(height: 6),
              TextFormField(
                controller: _serialController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  hintText: '$_nextSerialNumber',
                  prefixIcon: const Icon(Icons.tag),
                  helperText: 'serial_auto_hint'.tr(),
                  helperStyle: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'error_required_field'.tr();
                  }
                  return null;
                },
              ),

              const SizedBox(height: 32),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleSave,
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: AppColors.textOnPrimary,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          'save'.tr(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenderButton(String gender, IconData icon, String label) {
    final isSelected = _selectedGender == gender;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedGender = gender),
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? Colors.white : AppColors.textSecondary, size: 22),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }
}