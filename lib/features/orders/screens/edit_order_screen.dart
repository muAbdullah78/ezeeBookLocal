import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/snackbar_helper.dart';

/// Correct an order after it has been placed.
///
/// Everything here is something a tailor gets wrong at the counter with a
/// customer waiting: the delivery date, the price, how much was taken in
/// advance, the number of suits, the colours, a special instruction. Until now
/// none of it could be changed — a mistyped date or amount was permanent for
/// the life of the order, and the only workaround was to place the order again.
///
/// Measurements are deliberately NOT edited here. They belong to the
/// measurement form, which knows the linked options (waistband, dupatta) that a
/// flat edit screen would quietly break.
class EditOrderScreen extends StatefulWidget {
  final Map<String, dynamic> order;

  const EditOrderScreen({super.key, required this.order});

  @override
  State<EditOrderScreen> createState() => _EditOrderScreenState();
}

class _EditOrderScreenState extends State<EditOrderScreen> {
  final _sync = SyncService();

  final _totalController = TextEditingController();
  final _advanceController = TextEditingController();
  late List<TextEditingController> _colorControllers;
  late List<Map<String, dynamic>> _instructions;

  int _quantity = 1;
  DateTime? _deliveryDate;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final o = widget.order;

    _totalController.text = _moneyText(o['total_amount']);
    _advanceController.text = _moneyText(o['advance_payment']);
    _quantity = int.tryParse(o['quantity']?.toString() ?? '1') ?? 1;
    if (_quantity < 1) _quantity = 1;

    final colors = _decodeColors(o['colors']);
    _colorControllers = [
      for (var i = 0; i < _quantity; i++)
        TextEditingController(text: i < colors.length ? colors[i] : ''),
    ];

    _instructions = _decodeInstructions(o['special_instructions']);

    final raw = o['delivery_date']?.toString() ?? '';
    _deliveryDate = DateTime.tryParse(raw);
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

  /// Money round-trips as a REAL, so 1500.0 would show as "1500.0" in an input
  /// the tailor then has to clear. Render whole rupees without the decimal.
  static String _moneyText(Object? v) {
    final d = v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
    if (d == null) return '';
    return d == d.roundToDouble()
        ? d.toStringAsFixed(0)
        : d.toString();
  }

  static List<String> _decodeColors(Object? raw) {
    if (raw == null) return [];
    try {
      final decoded = json.decode(raw.toString());
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {
      // Not JSON — treat a bare string as a single colour.
    }
    final s = raw.toString();
    return s.isEmpty ? [] : [s];
  }

  static List<Map<String, dynamic>> _decodeInstructions(Object? raw) {
    if (raw == null || raw.toString().isEmpty) return [];
    try {
      final decoded = json.decode(raw.toString());
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {
      // Ignore an unreadable blob rather than losing the whole edit screen.
    }
    return [];
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _updateQuantity(int next) {
    if (next < 1 || next > 10) return;
    setState(() {
      _quantity = next;
      while (_colorControllers.length < next) {
        _colorControllers.add(TextEditingController());
      }
      while (_colorControllers.length > next) {
        _colorControllers.removeLast().dispose();
      }
      _dirty = true;
    });
  }

  Future<void> _pickDeliveryDate() async {
    final now = DateTime.now();
    final initial = _deliveryDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      // An order being corrected may legitimately have a delivery date in the
      // past (it was placed last week and is late), so the range has to reach
      // back — a firstDate of "today" would make such an order uneditable.
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    setState(() {
      _deliveryDate = picked;
      _dirty = true;
    });
  }

  bool _validate() {
    if (_deliveryDate == null) {
      SnackbarHelper.showError(context, 'error_select_delivery'.tr());
      return false;
    }
    final total = double.tryParse(_totalController.text.trim());
    if (total == null || total <= 0) {
      SnackbarHelper.showError(context, 'error_enter_amount'.tr());
      return false;
    }
    final advance = double.tryParse(_advanceController.text.trim()) ?? 0;
    if (advance < 0) {
      SnackbarHelper.showError(context, 'error_enter_amount'.tr());
      return false;
    }
    if (advance > total) {
      SnackbarHelper.showError(context, 'advance_exceeds_total'.tr());
      return false;
    }
    for (var i = 0; i < _quantity; i++) {
      if (_colorControllers[i].text.trim().isEmpty) {
        SnackbarHelper.showError(context, 'error_enter_colors'.tr());
        return false;
      }
    }
    return true;
  }

  Future<void> _save() async {
    if (_saving || !_validate()) return;
    setState(() => _saving = true);

    try {
      final colors = [
        for (var i = 0; i < _quantity; i++) _colorControllers[i].text.trim(),
      ];
      final changes = <String, dynamic>{
        'quantity': _quantity,
        'colors': json.encode(colors),
        'total_amount': double.parse(_totalController.text.trim()),
        'advance_payment':
            double.tryParse(_advanceController.text.trim()) ?? 0,
        'delivery_date': _deliveryDate!.toIso8601String().substring(0, 10),
        'special_instructions':
            _instructions.isEmpty ? null : json.encode(_instructions),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      await _sync.updateOrder(widget.order['id'].toString(), changes);
      if (!mounted) return;
      // Hand the merged row back so the order screen shows the new values
      // without a reload.
      Navigator.of(context).pop({...widget.order, ...changes});
    } catch (e, st) {
      AppLogger.error('EditOrder', 'save failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() => _saving = false);
      SnackbarHelper.showError(context, friendlyError(e));
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
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

  double get _remaining {
    final total = double.tryParse(_totalController.text.trim()) ?? 0;
    final advance = double.tryParse(_advanceController.text.trim()) ?? 0;
    return total > advance ? total - advance : 0;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: Text('edit_order'.tr())),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _card(
              title: 'delivery_date'.tr(),
              icon: Icons.event_outlined,
              child: InkWell(
                onTap: _pickDeliveryDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Text(
                        _deliveryDate == null
                            ? 'select_date'.tr()
                            : _formatDate(_deliveryDate!),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _card(
              title: 'how_many_suits'.tr(),
              icon: Icons.format_list_numbered,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _qtyButton(Icons.remove, () => _updateQuantity(_quantity - 1)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          '$_quantity',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      _qtyButton(Icons.add, () => _updateQuantity(_quantity + 1)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'suit_color'.tr(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _quantity; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _input(
                        _colorControllers[i],
                        hint: _quantity > 1
                            ? '${'suit_color'.tr()} ${i + 1}'
                            : 'suit_color'.tr(),
                        onChanged: (_) => _markDirty(),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _card(
              title: 'payment'.tr(),
              icon: Icons.payments_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('total_amount'.tr(), style: _labelStyle),
                  const SizedBox(height: 6),
                  _input(
                    _totalController,
                    hint: '0',
                    numeric: true,
                    onChanged: (_) => setState(() => _dirty = true),
                  ),
                  const SizedBox(height: 12),
                  Text('advance_payment'.tr(), style: _labelStyle),
                  const SizedBox(height: 6),
                  _input(
                    _advanceController,
                    hint: '0',
                    numeric: true,
                    onChanged: (_) => setState(() => _dirty = true),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('remaining_balance'.tr(), style: _labelStyle),
                      Text(
                        'Rs. ${_remaining.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _remaining > 0
                              ? AppColors.error
                              : AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _card(
              title: 'special_instructions'.tr(),
              icon: Icons.notes_outlined,
              child: _instructions.isEmpty
                  ? Text(
                      'no_instructions'.tr(),
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < _instructions.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    (_instructions[i]['text'] ?? '').toString(),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => setState(() {
                                    _instructions.removeAt(i);
                                    _dirty = true;
                                  }),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.close,
                                        size: 18, color: AppColors.error),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primaryLight,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        'save_changes'.tr(),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _labelStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: AppColors.dashboardAccent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
      ),
    );
  }

  Widget _card({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _input(
    TextEditingController controller, {
    String? hint,
    bool numeric = false,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      // Explicit colour: the global input theme paints a near-white fill, on
      // which the default light text would be invisible.
      style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: AppColors.textHint),
        prefixText: numeric ? 'Rs. ' : null,
        prefixStyle: const TextStyle(
            fontSize: 15, color: AppColors.textSecondary),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}
