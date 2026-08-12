import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/measurement_keys.dart';
import '../../../models/measurement.dart';
import '../../../models/stitch_category.dart';

/// Holds the live values for a list of tailor-defined category fields.
///
/// Shared by the two places custom fields appear: the whole measurement form of
/// a tailor-created category, and the "extra fields" section appended to a
/// built-in category's hand-tuned form. Keeping the state and the
/// collect/prefill rules in one place means those two paths cannot drift into
/// saving the same field two different ways.
class CategoryFieldValues {
  final List<CategoryField> fields;

  /// Number and text fields.
  final Map<String, TextEditingController> controllers = {};

  /// Yes/No fields.
  final Map<String, bool> toggles = {};

  /// Pick-one fields; null means nothing chosen.
  final Map<String, String?> choices = {};

  CategoryFieldValues(this.fields) {
    for (final f in fields) {
      switch (f.type) {
        case CategoryFieldType.number:
        case CategoryFieldType.text:
          controllers[f.fieldKey] = TextEditingController();
          break;
        case CategoryFieldType.toggle:
          toggles[f.fieldKey] = false;
          break;
        case CategoryFieldType.choice:
          choices[f.fieldKey] = null;
          break;
      }
    }
  }

  bool get isEmpty => fields.isEmpty;

  /// Restore a previous visit's values.
  ///
  /// Has to tolerate a schema the tailor has edited since the order was placed:
  /// keys that no longer exist are ignored, a choice whose option was renamed
  /// is left unset, and an unreadable options blob is skipped rather than
  /// taking the measurement screen down on open.
  void prefillFrom(Measurement? saved) {
    if (saved == null) return;

    for (final entry in saved.measurements.entries) {
      final c = controllers[entry.key];
      if (c != null) c.text = entry.value?.toString() ?? '';
    }

    final raw = saved.additionalOptions;
    if (raw == null || raw.isEmpty) return;
    Map<String, dynamic> options;
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      options = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }

    for (final entry in options.entries) {
      if (MeasurementMetaKeys.isMeta(entry.key)) continue;
      final key = entry.key;
      if (toggles.containsKey(key)) {
        toggles[key] = _asBool(entry.value);
      } else if (choices.containsKey(key)) {
        final value = entry.value?.toString();
        final field = _fieldFor(key);
        if (value != null && field != null && field.options.contains(value)) {
          choices[key] = value;
        }
      } else if (controllers.containsKey(key)) {
        controllers[key]!.text = entry.value?.toString() ?? '';
      }
    }
  }

  /// Numeric values only — what the worker reads off in inches.
  Map<String, dynamic> collectMeasurements() {
    final data = <String, dynamic>{};
    for (final f in fields) {
      if (f.type != CategoryFieldType.number) continue;
      final raw = controllers[f.fieldKey]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      data[f.fieldKey] = double.tryParse(raw) ?? raw;
    }
    return data;
  }

  /// Text, switches and choices, plus a snapshot of every field's label.
  ///
  /// The snapshot is what lets a receipt printed today still name its fields
  /// correctly after the tailor renames them next month, and lets the PDF
  /// render a form it knows nothing about.
  Map<String, dynamic> collectOptions({required String sectionName}) {
    final opts = <String, dynamic>{};
    for (final f in fields) {
      switch (f.type) {
        case CategoryFieldType.text:
          final raw = controllers[f.fieldKey]?.text.trim() ?? '';
          if (raw.isNotEmpty) opts[f.fieldKey] = raw;
          break;
        case CategoryFieldType.toggle:
          // Recorded either way: "no lining" is an instruction, not an absence.
          opts[f.fieldKey] = toggles[f.fieldKey] ?? false;
          break;
        case CategoryFieldType.choice:
          final v = choices[f.fieldKey];
          if (v != null && v.isNotEmpty) opts[f.fieldKey] = v;
          break;
        case CategoryFieldType.number:
          break;
      }
    }
    if (opts.isEmpty) return opts;
    opts.addAll(_labelSnapshot(sectionName));
    return opts;
  }

  /// Label snapshot for a group that has numeric measurements but no options —
  /// without it the receipt would print raw storage keys.
  Map<String, dynamic> labelOnlyOptions({required String sectionName}) =>
      _labelSnapshot(sectionName);

  /// Both spellings of every field name, so the receipt can print whichever the
  /// tailor entered — or both, when they entered both.
  Map<String, dynamic> _labelSnapshot(String sectionName) {
    final urdu = <String, String>{};
    for (final f in fields) {
      final u = f.labelUrdu?.trim() ?? '';
      if (u.isNotEmpty) urdu[f.fieldKey] = u;
    }
    return {
      MeasurementMetaKeys.labels: <String, String>{
        for (final f in fields) f.fieldKey: f.label,
      },
      if (urdu.isNotEmpty) MeasurementMetaKeys.labelsUrdu: urdu,
      MeasurementMetaKeys.section: sectionName,
    };
  }

  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
  }

  CategoryField? _fieldFor(String key) {
    for (final f in fields) {
      if (f.fieldKey == key) return f;
    }
    return null;
  }

  static bool _asBool(Object? v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v?.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }
}

/// Renders one section of tailor-defined fields.
///
/// Numeric fields go in a two-up grid so they read like the built-in
/// measurement form; switches, choices and text notes stack underneath.
class CategoryFieldsGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<CategoryField> fields;
  final CategoryFieldValues values;

  /// Called after any switch or choice changes, so the host can `setState`.
  final VoidCallback onChanged;

  const CategoryFieldsGroup({
    super.key,
    required this.title,
    required this.icon,
    required this.fields,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final numbers =
        fields.where((f) => f.type == CategoryFieldType.number).toList();
    final others =
        fields.where((f) => f.type != CategoryFieldType.number).toList();

    return Container(
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
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: AppColors.primary, width: 4),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.dashboardAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 22, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              children: [
                if (numbers.isNotEmpty) _numberGrid(numbers),
                if (numbers.isNotEmpty && others.isNotEmpty)
                  const SizedBox(height: 16),
                for (var i = 0; i < others.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _otherField(others[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberGrid(List<CategoryField> numbers) {
    final rows = <Widget>[];
    for (var i = 0; i < numbers.length; i += 2) {
      final first = numbers[i];
      final second = i + 1 < numbers.length ? numbers[i + 1] : null;
      rows.add(Row(
        children: [
          Expanded(child: _numberField(first)),
          const SizedBox(width: 10),
          Expanded(
            child: second != null ? _numberField(second) : const SizedBox(),
          ),
        ],
      ));
      if (i + 2 < numbers.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }

  Widget _numberField(CategoryField field) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: values.controllers[field.fieldKey],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: field.labelUrdu ?? '',
              hintStyle: const TextStyle(
                fontSize: 13,
                fontFamily: 'NotoNaskhArabic',
                color: AppColors.textHint,
              ),
              suffixText: 'inches'.tr(),
              suffixStyle: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
              border: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }

  Widget _otherField(CategoryField field) {
    switch (field.type) {
      case CategoryFieldType.toggle:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _labelWithUrdu(field),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Switch(
              value: values.toggles[field.fieldKey] ?? false,
              onChanged: (v) {
                values.toggles[field.fieldKey] = v;
                onChanged();
              },
              activeThumbColor: AppColors.primary,
              activeTrackColor: AppColors.primaryLight,
            ),
          ],
        );

      case CategoryFieldType.choice:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _labelWithUrdu(field),
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
                for (final option in field.options)
                  _chip(
                    label: option,
                    selected: values.choices[field.fieldKey] == option,
                    onTap: () {
                      // Tapping the selected chip clears it; a wrong choice
                      // would otherwise be impossible to undo.
                      values.choices[field.fieldKey] =
                          values.choices[field.fieldKey] == option
                              ? null
                              : option;
                      onChanged();
                    },
                  ),
              ],
            ),
          ],
        );

      case CategoryFieldType.text:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _labelWithUrdu(field),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: values.controllers[field.fieldKey],
              textCapitalization: TextCapitalization.sentences,
              style:
                  const TextStyle(fontSize: 15, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: field.labelUrdu ?? '',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'NotoNaskhArabic',
                  color: AppColors.textHint,
                ),
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
            ),
          ],
        );

      case CategoryFieldType.number:
        // Rendered by the grid above.
        return const SizedBox.shrink();
    }
  }

  String _labelWithUrdu(CategoryField field) {
    final urdu = field.labelUrdu?.trim() ?? '';
    return urdu.isEmpty ? field.label : '${field.label} ($urdu)';
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
}
