import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/category_icons.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../models/measurement.dart';
import '../../../models/stitch_category.dart';
import '../widgets/category_fields_form.dart';
import '../widgets/extra_instructions_widget.dart';
import 'order_details_screen.dart';

/// Measurement form for a tailor-defined stitching category.
///
/// Everything on screen comes from the category's own field list, so the form
/// is whatever the tailor built — numeric measurements, free-text notes, Yes/No
/// switches and pick-one choices, grouped under their own section headings.
class CustomMeasurementScreen extends StatefulWidget {
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String customerGender;
  final int customerSerialNumber;
  final StitchCategory category;

  /// Most recent saved measurement for this category, when the tailor chose to
  /// reuse it.
  final Measurement? savedMeasurement;

  const CustomMeasurementScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.customerGender,
    required this.customerSerialNumber,
    required this.category,
    this.savedMeasurement,
  });

  @override
  State<CustomMeasurementScreen> createState() =>
      _CustomMeasurementScreenState();
}

class _CustomMeasurementScreenState extends State<CustomMeasurementScreen> {
  final _formKey = GlobalKey<FormState>();

  late final CategoryFieldValues _values;
  List<Map<String, dynamic>> _extraInstructions = [];
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    _values = CategoryFieldValues(widget.category.fields);
    _values.prefillFrom(widget.savedMeasurement);
  }

  @override
  void dispose() {
    _values.dispose();
    super.dispose();
  }

  void _onNext() {
    final measurements = _values.collectMeasurements();
    var options = _values.collectOptions(sectionName: widget.category.name);
    // A category of pure measurements produces no options, but the receipt
    // still needs the label snapshot or it prints raw storage keys.
    if (options.isEmpty && measurements.isNotEmpty) {
      options = _values.labelOnlyOptions(sectionName: widget.category.name);
    }

    Navigator.of(context).push(
      SlidePageRoute(
        page: OrderDetailsScreen(
          customerId: widget.customerId,
          customerName: widget.customerName,
          customerPhone: widget.customerPhone,
          customerGender: widget.customerGender,
          customerSerialNumber: widget.customerSerialNumber,
          // A tailor-created category has no built-in stitch string, so the
          // category id is the stitch type and its name is snapshotted with it.
          stitchType: widget.category.id,
          categoryId: widget.category.id,
          categoryName: widget.category.name,
          shirtMeasurementData: const {},
          shirtAdditionalOptions: const {},
          bottomMeasurementData: const {},
          bottomAdditionalOptions: const {},
          customMeasurementData: measurements,
          customAdditionalOptions: options,
          extraInstructions: _extraInstructions,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.category.fieldsByGroup;
    final icon = CategoryIcons.resolve(widget.category.iconKey);

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.category.name,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${widget.customerName} (#${widget.customerSerialNumber})',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
              ),
            ],
          ),
        ),
        body: Form(
          key: _formKey,
          onChanged: () {
            if (!_isDirty) setState(() => _isDirty = true);
          },
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  child: Column(
                    children: [
                      if (_values.isEmpty) _buildNoFieldsCard(),
                      for (final entry in groups.entries) ...[
                        CategoryFieldsGroup(
                          title: entry.key.isEmpty
                              ? 'measurements'.tr()
                              : entry.key,
                          icon: icon,
                          fields: entry.value,
                          values: _values,
                          onChanged: () => setState(() => _isDirty = true),
                        ),
                        const SizedBox(height: 16),
                      ],
                      ExtraInstructionsWidget(
                        titleTranslationKey: 'extra_instructions',
                        initialInstructions: _extraInstructions.isNotEmpty
                            ? _extraInstructions
                            : null,
                        onChanged: (instructions) {
                          _extraInstructions = instructions;
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              _buildNextButton(),
            ],
          ),
        ),
      ),
    );
  }

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

  /// A category with no fields is legitimate — "Alteration" or "Repair" only
  /// needs an instruction and a price — so this explains rather than blocks.
  Widget _buildNoFieldsCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.straighten, color: AppColors.textHint, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'category_has_no_fields'.tr(),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextButton() {
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
            onPressed: _onNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              'next'.tr(),
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
}
