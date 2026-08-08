import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/category_icons.dart';
import '../../../core/services/category_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../models/stitch_category.dart';
import '../widgets/field_editor_sheet.dart';

/// Create or edit one stitching category.
///
/// A built-in category keeps its hand-tuned measurement form — that form
/// encodes real tailoring logic a generic builder cannot express (choosing
/// "elastic" reveals an elastic-width question; a women's full suit reveals the
/// dupatta finishing tree). What the tailor edits here is the catalogue entry
/// (name, Urdu name, icon, which customers it is offered to) plus any *extra*
/// fields to collect on top. Categories they create are rendered entirely from
/// the fields on this screen.
class EditCategoryScreen extends StatefulWidget {
  /// Null when creating a brand-new category.
  final StitchCategory? category;

  const EditCategoryScreen({super.key, this.category});

  @override
  State<EditCategoryScreen> createState() => _EditCategoryScreenState();
}

class _EditCategoryScreenState extends State<EditCategoryScreen> {
  final _service = CategoryService();

  late final TextEditingController _name;
  late final TextEditingController _nameUrdu;
  late String _gender;
  late String _iconKey;
  late List<CategoryField> _fields;
  late String _categoryId;

  bool _dirty = false;
  bool _saving = false;

  bool get _isNew => widget.category == null;
  bool get _isBuiltin => widget.category?.isBuiltin ?? false;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    // A new category needs its id up front: fields are created against it
    // before the first save.
    _categoryId = c?.id ?? const Uuid().v4();
    _name = TextEditingController(text: c?.name ?? '');
    _nameUrdu = TextEditingController(text: c?.nameUrdu ?? '');
    _gender = c?.gender ?? 'both';
    _iconKey = c?.iconKey ?? CategoryIcons.fallbackKey;
    _fields = List<CategoryField>.from(c?.fields ?? const <CategoryField>[]);
  }

  @override
  void dispose() {
    _name.dispose();
    _nameUrdu.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Set<String> get _takenKeys => _fields.map((f) => f.fieldKey).toSet();

  List<String> get _knownGroups {
    final seen = <String>[];
    for (final f in _fields) {
      final g = f.groupLabel.trim();
      if (g.isNotEmpty && !seen.contains(g)) seen.add(g);
    }
    return seen;
  }

  // ==================== FIELD ACTIONS ====================

  Future<void> _addField() async {
    final field = await showFieldEditorSheet(
      context: context,
      categoryId: _categoryId,
      existingKeys: _takenKeys,
      knownGroups: _knownGroups,
    );
    if (field == null) return;
    setState(() {
      _fields.add(field);
      _dirty = true;
    });
  }

  Future<void> _editField(int index) async {
    final current = _fields[index];
    final updated = await showFieldEditorSheet(
      context: context,
      categoryId: _categoryId,
      // Exclude this field's own key so re-saving it unchanged is not treated
      // as a collision.
      existingKeys: _takenKeys.difference({current.fieldKey}),
      knownGroups: _knownGroups,
      field: current,
    );
    if (updated == null) return;
    setState(() {
      _fields[index] = updated;
      _dirty = true;
    });
  }

  Future<void> _removeField(int index) async {
    final field = _fields[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('remove_field_title'.tr()),
        content: Text(
          'remove_field_message'.tr(namedArgs: {'name': field.label}),
        ),
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
            child: Text('remove'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _fields.removeAt(index);
      _dirty = true;
    });
  }

  void _reorderField(int oldIndex, int newIndex) {
    setState(() {
      // ReorderableListView reports the destination index as if the dragged
      // item were still in place.
      if (newIndex > oldIndex) newIndex -= 1;
      final moved = _fields.removeAt(oldIndex);
      _fields.insert(newIndex, moved);
      _dirty = true;
    });
  }

  // ==================== SAVE ====================

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      SnackbarHelper.showError(context, 'category_name_required'.tr());
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final urdu = _nameUrdu.text.trim();
      final existing = widget.category;
      final category = StitchCategory(
        id: _categoryId,
        name: name,
        nameUrdu: urdu.isEmpty ? null : urdu,
        gender: _gender,
        iconKey: _iconKey,
        sortOrder: existing?.sortOrder ?? await _service.nextSortOrder(),
        hidden: existing?.hidden ?? false,
        builtinKey: existing?.builtinKey,
        createdAt: existing?.createdAt,
        fields: _fields,
      );
      await _service.save(category);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      AppLogger.error('EditCategory', 'save failed', error: e, stackTrace: st);
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

  // ==================== BUILD ====================

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
        appBar: AppBar(
          title: Text(_isNew ? 'new_category'.tr() : 'edit_category'.tr()),
        ),
        body: ReorderableListView(
          // Deep bottom padding so the floating "Add Field" button cannot cover
          // the last field's edit/remove buttons.
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          header: _buildHeader(),
          onReorder: _reorderField,
          children: [
            for (var i = 0; i < _fields.length; i++)
              _FieldTile(
                key: ValueKey(_fields[i].id),
                index: i,
                field: _fields[i],
                onEdit: () => _editField(i),
                onRemove: () => _removeField(i),
              ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addField,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: Text('add_field'.tr()),
        ),
        bottomNavigationBar: _buildSaveBar(),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _iconPreview(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'category_icon'.tr(),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        OutlinedButton.icon(
                          onPressed: _pickIcon,
                          icon: const Icon(Icons.palette_outlined, size: 18),
                          label: Text('choose_icon'.tr()),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _fieldLabel('category_name'.tr()),
              const SizedBox(height: 6),
              _textInput(
                _name,
                hint: 'category_name_hint'.tr(),
                onChanged: (_) => _markDirty(),
              ),
              const SizedBox(height: 12),
              _fieldLabel('category_name_urdu'.tr()),
              const SizedBox(height: 6),
              _textInput(
                _nameUrdu,
                hint: 'optional'.tr(),
                fontFamily: 'NotoNastaliqUrdu',
                onChanged: (_) => _markDirty(),
              ),
              const SizedBox(height: 16),
              _fieldLabel('offered_to'.tr()),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in const ['both', 'male', 'female'])
                    _chip(
                      label: _genderLabel(g),
                      selected: _gender == g,
                      onTap: () {
                        setState(() {
                          _gender = g;
                          _dirty = true;
                        });
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_isBuiltin) _builtinNotice(),
        if (_isBuiltin) const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _isBuiltin
                      ? 'extra_fields'.tr()
                      : 'measurement_fields'.tr(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '${_fields.length}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (_fields.isEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.straighten,
                    color: AppColors.textHint, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isBuiltin
                        ? 'no_extra_fields_hint'.tr()
                        : 'no_fields_hint'.tr(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'drag_to_reorder'.tr(),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _builtinNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dashboardAccent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20, color: AppColors.primaryDark),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'builtin_category_notice'.tr(),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
        height: 50,
        child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.primaryLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
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
                  'save_category'.tr(),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
        ),
      ),
    );
  }

  Future<void> _pickIcon() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('choose_icon'.tr()),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        // Fixed height so the grid scrolls inside the dialog. With shrinkWrap
        // the 28 icons would lay out six rows tall and overflow on a short
        // phone.
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: GridView.count(
            crossAxisCount: 5,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final key in CategoryIcons.keys)
                Material(
                  color: key == _iconKey
                      ? AppColors.primary
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.of(ctx).pop(key),
                    child: Icon(
                      CategoryIcons.resolve(key),
                      color: key == _iconKey
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('cancel'.tr()),
          ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() {
      _iconKey = picked;
      _dirty = true;
    });
  }

  Widget _iconPreview() {
    final (circle, icon) = CategoryIcons.tintFor(_categoryId);
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: circle,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(CategoryIcons.resolve(_iconKey), color: icon, size: 28),
    );
  }

  String _genderLabel(String g) {
    switch (g) {
      case 'male':
        return 'male'.tr();
      case 'female':
        return 'female'.tr();
      default:
        return 'both_genders'.tr();
    }
  }

  // ── shared small builders ──

  Widget _card({required Widget child}) {
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
      child: child,
    );
  }

  Widget _fieldLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      );

  Widget _textInput(
    TextEditingController controller, {
    String? hint,
    String? fontFamily,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      // Explicit colour: the global input theme paints a near-white fill, on
      // which the default light text is invisible.
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
}

/// One row in the field list. Kept as its own widget so the reorderable list
/// can key it by field id.
class _FieldTile extends StatelessWidget {
  final int index;
  final CategoryField field;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _FieldTile({
    super.key,
    required this.index,
    required this.field,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 8, right: 4),
        leading: ReorderableDragStartListener(
          index: index,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.drag_handle, color: AppColors.textHint),
          ),
        ),
        title: Text(
          field.label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          [
            _typeLabel(field.type),
            if (field.groupLabel.trim().isNotEmpty) field.groupLabel.trim(),
            if (field.type == CategoryFieldType.choice)
              field.options.join(' / '),
          ].join('  ·  '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: AppColors.primary,
              tooltip: 'edit'.tr(),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: AppColors.error,
              tooltip: 'remove'.tr(),
              onPressed: onRemove,
            ),
          ],
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
}
