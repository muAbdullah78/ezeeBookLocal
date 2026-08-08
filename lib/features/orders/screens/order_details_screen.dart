import 'dart:convert';
import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/services/whatsapp_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../dashboard/screens/main_shell.dart';
import '../widgets/extra_instructions_widget.dart';

class OrderDetailsScreen extends StatefulWidget {
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String customerGender;
  final int customerSerialNumber;
  final String stitchType;
  final String? shirtSubType;
  final String? bottomType;
  final String? bottomWaistband;
  final String? elasticWidth;
  final Map<String, dynamic> shirtMeasurementData;
  final Map<String, dynamic> shirtAdditionalOptions;
  final Map<String, dynamic> bottomMeasurementData;
  final Map<String, dynamic> bottomAdditionalOptions;
  final Map<String, dynamic>? dupattaDetails;
  final List<Map<String, dynamic>> extraInstructions;

  const OrderDetailsScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.customerGender,
    required this.customerSerialNumber,
    required this.stitchType,
    this.shirtSubType,
    this.bottomType,
    this.bottomWaistband,
    this.elasticWidth,
    required this.shirtMeasurementData,
    required this.shirtAdditionalOptions,
    required this.bottomMeasurementData,
    required this.bottomAdditionalOptions,
    this.dupattaDetails,
    required this.extraInstructions,
  });

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  final _sync = SyncService();
  final _totalController = TextEditingController();
  final _advanceController = TextEditingController(text: '0');

  int _quantity = 1;
  List<TextEditingController> _colorControllers = [];
  List<String?> _selectedColors = [];
  DateTime? _deliveryDate;
  List<Map<String, dynamic>> _specialInstructions = [];
  bool _isSaving = false;

  String _shopName = '';
  String _shopPhone = '';

  /// The order row as saved, kept so the confirmation message can be built
  /// from the same data the rest of the app will read back later.
  Map<String, dynamic>? _savedOrder;

  static const _presetColors = [
    {'name': 'Red', 'urdu': 'سرخ', 'color': Colors.red},
    {'name': 'Blue', 'urdu': 'نیلا', 'color': Colors.blue},
    {'name': 'Black', 'urdu': 'کالا', 'color': Colors.black},
    {'name': 'White', 'urdu': 'سفید', 'color': Colors.white},
    {'name': 'Green', 'urdu': 'سبز', 'color': Colors.green},
    {'name': 'Brown', 'urdu': 'بھورا', 'color': Color(0xFF795548)},
    {'name': 'Pink', 'urdu': 'گلابی', 'color': Colors.pink},
    {'name': 'Purple', 'urdu': 'جامنی', 'color': Colors.purple},
    {'name': 'Grey', 'urdu': 'سلیٹی', 'color': Colors.grey},
    {'name': 'Yellow', 'urdu': 'پیلا', 'color': Colors.yellow},
    {'name': 'Navy', 'urdu': 'گہرا نیلا', 'color': Color(0xFF001F3F)},
    {'name': 'Maroon', 'urdu': 'مہرون', 'color': Color(0xFF800000)},
  ];

  @override
  void initState() {
    super.initState();
    _initColorControllers();
    _loadShopInfo();
  }

  @override
  void dispose() {
    _totalController.dispose();
    _advanceController.dispose();
    for (final c in _colorControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _initColorControllers() {
    _colorControllers = [TextEditingController()];
    _selectedColors = [null];
  }

  void _updateQuantity(int newQty) {
    if (newQty < 1 || newQty > 10) return;
    if (Platform.isAndroid) {
      HapticFeedback.lightImpact();
    }
    setState(() {
      _quantity = newQty;
      while (_colorControllers.length < newQty) {
        _colorControllers.add(TextEditingController());
        _selectedColors.add(null);
      }
      while (_colorControllers.length > newQty) {
        _colorControllers.removeLast().dispose();
        _selectedColors.removeLast();
      }
    });
  }

  Future<void> _loadShopInfo() async {
    try {
      final data = await SyncService().getShopProfile();
      if (data != null && mounted) {
        setState(() {
          _shopName = data['shop_name'] ?? '';
          _shopPhone = data['phone'] ?? '';
        });
      }
    } catch (e, st) {
      AppLogger.error('OrderDetailsScreen', 'shop_profile load failed',
          error: e, stackTrace: st);
    }
  }

  double get _remaining {
    final total = double.tryParse(_totalController.text) ?? 0;
    final advance = double.tryParse(_advanceController.text) ?? 0;
    return total - advance;
  }

  /// Any input the user would lose if they left this screen now. Used to
  /// guard against an accidental back gesture discarding the order.
  bool get _hasUnsavedInput =>
      _totalController.text.trim().isNotEmpty ||
      _deliveryDate != null ||
      _specialInstructions.isNotEmpty ||
      _quantity != 1 ||
      _colorControllers.any((c) => c.text.trim().isNotEmpty);

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('discard_changes_title'.tr()),
        content: Text('discard_changes_message'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('keep_editing'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text('discard'.tr()),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String get _garmentLabel {
    final isUrdu = context.locale.languageCode == 'ur';
    String label;

    switch (widget.stitchType) {
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
        label = widget.stitchType;
    }

    final parts = <String>[];
    if (widget.shirtSubType != null) {
      parts.add(_subTypeLabel(widget.shirtSubType!));
    }
    if (widget.bottomType != null) {
      parts.add(_subTypeLabel(widget.bottomType!));
    }
    if (parts.isNotEmpty) {
      label += ' — ${parts.join(' + ')}';
    }
    return label;
  }

  String _subTypeLabel(String type) {
    final isUrdu = context.locale.languageCode == 'ur';
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

  // ==================== VALIDATION & SAVE ====================

  bool _validate() {
    if (_deliveryDate == null) {
      _showError('error_select_delivery'.tr());
      return false;
    }
    final total = double.tryParse(_totalController.text) ?? 0;
    if (total <= 0) {
      _showError('error_enter_amount'.tr());
      return false;
    }
    final advance = double.tryParse(_advanceController.text) ?? 0;
    if (advance > total) {
      _showError('advance_exceeds_total'.tr());
      return false;
    }
    for (int i = 0; i < _quantity; i++) {
      if (_colorControllers[i].text.trim().isEmpty) {
        _showError('error_enter_colors'.tr());
        return false;
      }
    }
    return true;
  }

  void _showError(String message) {
    SnackbarHelper.showError(context, message);
  }

  Future<void> _confirmOrder() async {
    if (!_validate()) return;
    // The success dialog can be dismissed with the Android back button, which
    // returns to a live Confirm button. Without this guard a second tap wrote
    // a duplicate order, duplicate measurements and a duplicate dupatta row.
    if (_savedOrder != null) {
      _showSuccessDialog();
      return;
    }
    setState(() => _isSaving = true);

    try {
      final orderId = const Uuid().v4();
      final now = DateTime.now().toUtc().toIso8601String();

      final colors = _colorControllers.map((c) => c.text.trim()).toList();

      final order = {
        'id': orderId,
        'customer_id': widget.customerId,
        'stitch_type': widget.stitchType,
        'customer_gender': widget.customerGender,
        'shirt_sub_type': widget.shirtSubType,
        'bottom_type': widget.bottomType,
        'bottom_waistband': widget.bottomWaistband,
        'elastic_width': widget.elasticWidth,
        'quantity': _quantity,
        'colors': json.encode(colors),
        'total_amount': double.tryParse(_totalController.text) ?? 0,
        'advance_payment': double.tryParse(_advanceController.text) ?? 0,
        'delivery_date': _deliveryDate!.toIso8601String().substring(0, 10),
        'status': 'pending',
        'special_instructions':
            _specialInstructions.isNotEmpty ? json.encode(_specialInstructions) : null,
        'extra_instructions':
            widget.extraInstructions.isNotEmpty ? json.encode(widget.extraInstructions) : null,
        'created_at': now,
        'updated_at': now,
      };

      await _sync.saveOrder(order);
      _savedOrder = order;

      // Save shirt measurements
      if (widget.shirtMeasurementData.isNotEmpty) {
        await _sync.saveMeasurement({
          'id': const Uuid().v4(),
          'customer_id': widget.customerId,
          'order_id': orderId,
          'garment_type': 'shirt',
          'measurement_data': json.encode(widget.shirtMeasurementData),
          'additional_options': json.encode(widget.shirtAdditionalOptions),
          'created_at': now,
          'updated_at': now,
        });
      }

      // Save bottom measurements
      if (widget.bottomMeasurementData.isNotEmpty) {
        await _sync.saveMeasurement({
          'id': const Uuid().v4(),
          'customer_id': widget.customerId,
          'order_id': orderId,
          'garment_type': 'shalwar_trouser',
          'measurement_data': json.encode(widget.bottomMeasurementData),
          'additional_options': json.encode(widget.bottomAdditionalOptions),
          'created_at': now,
          'updated_at': now,
        });
      }

      // Save dupatta details
      if (widget.dupattaDetails != null) {
        final dupatta = {
          'id': const Uuid().v4(),
          'order_id': orderId,
          'included': widget.dupattaDetails!['included'] == true ? 1 : 0,
          'finishing': widget.dupattaDetails!['finishing'],
          'pico_coverage': widget.dupattaDetails!['pico_coverage'],
          'pico_type': widget.dupattaDetails!['pico_type'],
          'piping_coverage': widget.dupattaDetails!['piping_coverage'],
          'lace_coverage': widget.dupattaDetails!['lace_coverage'],
          'lace_provided_by_customer':
              widget.dupattaDetails!['lace_provided_by_customer'] == true ? 1 : 0,
          'created_at': now,
          'updated_at': now,
        };
        await _sync.saveDupattaDetails(dupatta);
      }

      if (!mounted) return;
      setState(() => _isSaving = false);
      _showSuccessDialog();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError(friendlyError(e));
    }
  }

  // ==================== SUCCESS DIALOG & WHATSAPP ====================

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.successLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: AppColors.success, size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              'order_confirmed'.tr(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'order_for'.tr(namedArgs: {'name': widget.customerName}),
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            // WhatsApp button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF25D366), Color(0xFF128C7E)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _sendWhatsApp();
                  },
                  icon: const Icon(Icons.chat, color: Colors.white, size: 20),
                  label: Text(
                    'send_whatsapp'.tr(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Done button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _navigateToDashboard();
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'done'.tr(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
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

  /// Send the confirmation for the order that was just saved.
  ///
  /// The message is built by [WhatsAppService] from the stored order row —
  /// the same code path the order screen uses to re-send it later — so the
  /// customer never receives two differently-worded confirmations.
  Future<void> _sendWhatsApp() async {
    final order = _savedOrder;
    if (order == null) {
      _navigateToDashboard();
      return;
    }

    final message = WhatsAppService().buildOrderConfirmation(
      order: order,
      shopProfile: {'shop_name': _shopName, 'phone': _shopPhone},
      customerName: widget.customerName,
      customerSerial: widget.customerSerialNumber,
    );

    final result = await WhatsAppService().send(
      phone: widget.customerPhone,
      message: message,
    );

    if (!mounted) return;
    if (result == WhatsAppSendResult.invalidNumber) {
      SnackbarHelper.showError(context, 'whatsapp_invalid_number'.tr());
    } else if (result == WhatsAppSendResult.launchFailed) {
      SnackbarHelper.showError(context, 'whatsapp_open_failed'.tr());
    }
    _navigateToDashboard();
  }

  void _navigateToDashboard() {
    Navigator.of(context).pushAndRemoveUntil(
      SlidePageRoute(page: const MainShell()),
      (route) => false,
    );
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedInput,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldDiscard = await _confirmDiscard();
        if (shouldDiscard && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('order_details'.tr()),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOrderSummaryCard(),
                  const SizedBox(height: 20),
                  _buildQuantitySection(),
                  const SizedBox(height: 20),
                  _buildDatesSection(),
                  const SizedBox(height: 20),
                  _buildPaymentSection(),
                  const SizedBox(height: 20),
                  ExtraInstructionsWidget(
                    titleTranslationKey: 'special_instructions',
                    initialInstructions:
                        _specialInstructions.isNotEmpty ? _specialInstructions : null,
                    onChanged: (instructions) {
                      _specialInstructions = instructions;
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          _buildConfirmButton(),
        ],
      ),
      ),
    );
  }

  // ==================== ORDER SUMMARY ====================

  Widget _buildOrderSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              widget.customerGender == 'female' ? Icons.dry_cleaning : Icons.checkroom,
              color: AppColors.primary,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.customerName} (#${widget.customerSerialNumber})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _garmentLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== QUANTITY & COLORS ====================

  Widget _buildQuantitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.format_list_numbered, 'how_many_suits'.tr()),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Quantity row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildQtyButton(Icons.remove, () => _updateQuantity(_quantity - 1)),
                  Container(
                    width: 64,
                    alignment: Alignment.center,
                    child: Text(
                      '$_quantity',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  _buildQtyButton(Icons.add, () => _updateQuantity(_quantity + 1)),
                ],
              ),
              const SizedBox(height: 16),
              // Color entries
              ...List.generate(_quantity, (i) => _buildColorEntry(i)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQtyButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: AppColors.primary, size: 24),
        ),
      ),
    );
  }

  Widget _buildColorEntry(int index) {
    return Padding(
      padding: EdgeInsets.only(top: index > 0 ? 12 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'suit_number'.tr(namedArgs: {'number': '${index + 1}'}),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _colorControllers[index],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'suit_color'.tr(),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              suffixIcon: _selectedColors[index] != null
                  ? Container(
                      margin: const EdgeInsets.all(8),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _getColorByName(_selectedColors[index]!),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                    )
                  : null,
            ),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _presetColors.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, ci) {
                final preset = _presetColors[ci];
                final colorName = preset['name'] as String;
                final color = preset['color'] as Color;
                final isSelected = _selectedColors[index] == colorName;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedColors[index] = colorName;
                        final isUrdu = context.locale.languageCode == 'ur';
                        _colorControllers[index].text =
                            isUrdu ? preset['urdu'] as String : colorName;
                      });
                    },
                    customBorder: const CircleBorder(),
                    child: Ink(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.border,
                          width: isSelected ? 3 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _getColorByName(String name) {
    for (final preset in _presetColors) {
      if (preset['name'] == name) return preset['color'] as Color;
    }
    return Colors.grey;
  }

  // ==================== DATES ====================

  Widget _buildDatesSection() {
    final today = DateTime.now();
    int? daysUntilDelivery;
    if (_deliveryDate != null) {
      daysUntilDelivery = _deliveryDate!.difference(today).inDays;
      if (daysUntilDelivery < 0) daysUntilDelivery = 0;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.calendar_today, 'dates'.tr()),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Order date
              Row(
                children: [
                  const Icon(Icons.today, color: AppColors.textSecondary, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'order_date'.tr(),
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDate(today),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              // Delivery date
              InkWell(
                onTap: _pickDeliveryDate,
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    Icon(
                      Icons.event,
                      color: _deliveryDate != null ? AppColors.primary : AppColors.textHint,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'delivery_date_label'.tr(),
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _deliveryDate != null
                          ? _formatDate(_deliveryDate!)
                          : 'select_delivery_date'.tr(),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: _deliveryDate != null ? FontWeight.w600 : FontWeight.normal,
                        color: _deliveryDate != null ? AppColors.primary : AppColors.textHint,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
                  ],
                ),
              ),
              if (daysUntilDelivery != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'delivery_in_days'.tr(namedArgs: {'days': '$daysUntilDelivery'}),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickDeliveryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deliveryDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _deliveryDate = picked);
    }
  }

  // ==================== PAYMENT ====================

  Widget _buildPaymentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.payments_outlined, 'payment'.tr()),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Total
              TextField(
                controller: _totalController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'total_amount_rs'.tr(),
                  prefixText: 'Rs. ',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              // Advance
              TextField(
                controller: _advanceController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'advance_peshgi'.tr(),
                  prefixText: 'Rs. ',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 14),
              // Remaining
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _remaining <= 0
                      ? AppColors.successLight
                      : AppColors.errorLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _remaining <= 0 ? 'fully_paid'.tr() : 'remaining_baqaya'.tr(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _remaining <= 0 ? AppColors.success : AppColors.error,
                      ),
                    ),
                    Text(
                      'Rs. ${_remaining < 0 ? 0 : _remaining.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _remaining <= 0 ? AppColors.success : AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== CONFIRM BUTTON ====================

  Widget _buildConfirmButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
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
            borderRadius: BorderRadius.circular(16),
          ),
          child: ElevatedButton(
            onPressed: _isSaving ? null : _confirmOrder,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'confirm_order'.tr(),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ==================== HELPERS ====================

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
