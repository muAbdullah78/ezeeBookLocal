import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/stitch_category.dart';

/// Add or edit one field on a stitching category.
///
/// Returns the edited [CategoryField], or null if the tailor backed out.
/// [existingKeys] must contain the storage keys already used by the category
/// (excluding the field being edited) so a new field cannot silently overwrite
/// another one's value.
Future<CategoryField?> showFieldEditorSheet({
  required BuildContext context,
  required String categoryId,
  required Set<String> existingKeys,
  required List<String> knownGroups,
  CategoryField? field,
}) {
  return showModalBottomSheet<CategoryField>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FieldEditorSheet(
      categoryId: categoryId,
      existingKeys: existingKeys,
      knownGroups: knownGroups,
      field: field,
    ),
  );
}

class _FieldEditorSheet extends StatefulWidget {
  final String categoryId;
  final Set<String> existingKeys;
  final List<String> knownGroups;
  final CategoryField? field;

  const _FieldEditorSheet({
    required this.categoryId,
    required this.existingKeys,
    required this.knownGroups,
    this.field,
  });

  @override
  State<_FieldEditorSheet> createState() => _FieldEditorSheetState();
}

class _FieldEditorSheetState extends State<_FieldEditorSheet> {
  late final TextEditingController _label;
  late final TextEditingController _labelUrdu;
  late final TextEditingController _group;
  late CategoryFieldType _type;
  late List<TextEditingController> _options;
  String? _error;

  bool get _isEdit => widget.field != null;

  @override
  void initState() {
    super.initState();
    final f = widget.field;
    _label = TextEditingController(text: f?.label ?? '');
    _labelUrdu = TextEditingController(text: f?.labelUrdu ?? '');
    _group = TextEditingController(text: f?.groupLabel ?? '');
    _type = f?.type ?? CategoryFieldType.number;
    _options = [
      for (final o in (f?.options ?? const <String>[]))
        TextEditingController(text: o),
    ];
    if (_options.isEmpty) {
      _options = [TextEditingController(), TextEditingController()];
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _labelUrdu.dispose();
    _group.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final label = _label.text.trim();
    if (label.isEmpty) {
      setState(() => _error = 'field_name_required'.tr());
      return;
    }

    List<String> options = const [];
    if (_type == CategoryFieldType.choice) {
      options = _options
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (options.length < 2) {
        setState(() => _error = 'choice_needs_two_options'.tr());
        return;
      }
    }

    final urdu = _labelUrdu.text.trim();
    final group = _group.text.trim();

    if (_isEdit) {
      // Keep the existing storage key: changing it would orphan every value
      // already recorded against this field on past orders.
      Navigator.of(context).pop(widget.field!.copyWith(
        label: label,
        labelUrdu: urdu.isEmpty ? null : urdu,
        clearLabelUrdu: urdu.isEmpty,
        groupLabel: group,
        type: _type,
        options: options,
      ));
      return;
    }

    Navigator.of(context).pop(CategoryField(
      categoryId: widget.categoryId,
      groupLabel: group,
      fieldKey: CategoryField.buildFieldKey(label, widget.existingKeys),
      label: label,
      labelUrdu: urdu.isEmpty ? null : urdu,
      type: _type,
      options: options,
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Sits above the keyboard: these are all text inputs and the sheet would
    // otherwise put the Save button under it.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textHint,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isEdit ? 'edit_field'.tr() : 'add_field'.tr(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),

              _labelled(
                'field_name'.tr(),
                _input(_label, hint: 'field_name_hint'.tr()),
              ),
              const SizedBox(height: 12),
              _labelled(
                'field_name_urdu'.tr(),
                _input(_labelUrdu,
                    hint: 'optional'.tr(), fontFamily: 'NotoNastaliqUrdu'),
              ),
              const SizedBox(height: 12),
              _labelled(
                'field_section'.tr(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _input(_group, hint: 'field_section_hint'.tr()),
                    if (widget.knownGroups.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final g in widget.knownGroups)
                            _chip(
                              label: g,
                              selected: _group.text.trim() == g,
                              onTap: () => setState(() {
                                _group.text = g;
                              }),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'field_type'.tr(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in CategoryFieldType.values)
                    _chip(
                      label: _typeLabel(t),
                      selected: _type == t,
                      onTap: () => setState(() => _type = t),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _typeHint(_type),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),

              if (_type == CategoryFieldType.choice) ...[
                const SizedBox(height: 16),
                Text(
                  'choices'.tr(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _options.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: _input(_options[i],
                              hint: '${'choice'.tr()} ${i + 1}'),
                        ),
                        if (_options.length > 2)
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                color: AppColors.error),
                            tooltip: 'remove'.tr(),
                            onPressed: () => setState(() {
                              _options.removeAt(i).dispose();
                            }),
                          ),
                      ],
                    ),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => setState(
                        () => _options.add(TextEditingController())),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text('add_choice'.tr()),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary),
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 13, color: AppColors.error),
                ),
              ],

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text('cancel'.tr()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text('save'.tr()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── small builders ──

  Widget _labelled(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _input(
    TextEditingController controller, {
    String? hint,
    String? fontFamily,
  }) {
    return TextField(
      controller: controller,
      // The global input theme fills fields with a near-white background, so
      // the text colour has to be set explicitly or it disappears.
      style: TextStyle(
        fontSize: 15,
        color: AppColors.textPrimary,
        fontFamily: fontFamily,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: AppColors.textHint),
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

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  String _typeLabel(CategoryFieldType t) {
    switch (t) {
      case CategoryFieldType.number:
        return 'field_type_number'.tr();
      case CategoryFieldType.text:
        return 'field_type_text'.tr();
      case CategoryFieldType.toggle:
        return 'field_type_toggle'.tr();
      case CategoryFieldType.choice:
        return 'field_type_choice'.tr();
    }
  }

  String _typeHint(CategoryFieldType t) {
    switch (t) {
      case CategoryFieldType.number:
        return 'field_type_number_hint'.tr();
      case CategoryFieldType.text:
        return 'field_type_text_hint'.tr();
      case CategoryFieldType.toggle:
        return 'field_type_toggle_hint'.tr();
      case CategoryFieldType.choice:
        return 'field_type_choice_hint'.tr();
    }
  }
}
