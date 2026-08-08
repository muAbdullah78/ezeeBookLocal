import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/category_icons.dart';
import '../../../core/services/category_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../models/stitch_category.dart';
import 'edit_category_screen.dart';

/// The tailor's catalogue of stitching categories.
///
/// Real shops run far more than the four categories the app shipped with — a
/// men's tailor might have a dozen, a women's tailor thirty. This screen is
/// where they build that list: add, rename, re-icon, reorder, hide what they
/// never stitch, and duplicate an existing category as a starting point.
class ManageCategoriesScreen extends StatefulWidget {
  const ManageCategoriesScreen({super.key});

  @override
  State<ManageCategoriesScreen> createState() => _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState extends State<ManageCategoriesScreen> {
  final _service = CategoryService();

  List<StitchCategory> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _service.getAll();
      if (!mounted) return;
      setState(() {
        _categories = list;
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.error('ManageCategories', 'load failed',
          error: e, stackTrace: st);
      if (!mounted) return;
      setState(() => _loading = false);
      SnackbarHelper.showError(context, friendlyError(e));
    }
  }

  // ==================== ACTIONS ====================

  Future<void> _openEditor({StitchCategory? category}) async {
    final changed = await Navigator.of(context).push<bool>(
      SlidePageRoute(page: EditCategoryScreen(category: category)),
    );
    if (changed == true) await _load();
  }

  Future<void> _toggleHidden(StitchCategory category) async {
    // Optimistic: the list is local and the write cannot realistically fail,
    // but reload afterwards so the on-screen state is what is actually stored.
    try {
      await _service.setHidden(category.id, !category.hidden);
      await _load();
    } catch (e, st) {
      AppLogger.error('ManageCategories', 'hide toggle failed',
          error: e, stackTrace: st);
      if (mounted) SnackbarHelper.showError(context, friendlyError(e));
    }
  }

  Future<void> _duplicate(StitchCategory category) async {
    try {
      final copy = await _service.duplicate(
        category,
        newName: '${category.name} (${'copy'.tr()})',
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      // Open the copy straight away — a duplicate exists to be edited.
      await _openEditor(category: await _service.getById(copy.id) ?? copy);
    } catch (e, st) {
      AppLogger.error('ManageCategories', 'duplicate failed',
          error: e, stackTrace: st);
      if (mounted) SnackbarHelper.showError(context, friendlyError(e));
    }
  }

  Future<void> _delete(StitchCategory category) async {
    // Deleting a category the tailor has already used would leave those orders
    // pointing at nothing, so say how many are involved before asking.
    final usedBy = await _service.orderCount(category.id);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('delete_category_title'.tr()),
        content: Text(
          usedBy > 0
              ? 'delete_category_used_message'.tr(namedArgs: {
                  'name': category.name,
                  'count': usedBy.toString(),
                })
              : 'delete_category_message'
                  .tr(namedArgs: {'name': category.name}),
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
            child: Text('delete'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.delete(category.id);
      await _load();
    } catch (e, st) {
      AppLogger.error('ManageCategories', 'delete failed',
          error: e, stackTrace: st);
      if (mounted) SnackbarHelper.showError(context, friendlyError(e));
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final moved = _categories.removeAt(oldIndex);
      _categories.insert(newIndex, moved);
    });
    try {
      await _service.reorder(_categories.map((c) => c.id).toList());
    } catch (e, st) {
      AppLogger.error('ManageCategories', 'reorder failed',
          error: e, stackTrace: st);
      // Re-read so the visible order matches what was actually saved.
      await _load();
      if (mounted) SnackbarHelper.showError(context, friendlyError(e));
    }
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('stitching_categories'.tr())),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : ReorderableListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              header: _buildHeader(),
              onReorder: _reorder,
              children: [
                for (var i = 0; i < _categories.length; i++)
                  _CategoryTile(
                    key: ValueKey(_categories[i].id),
                    index: i,
                    category: _categories[i],
                    onEdit: () => _openEditor(category: _categories[i]),
                    onDuplicate: () => _duplicate(_categories[i]),
                    onToggleHidden: () => _toggleHidden(_categories[i]),
                    onDelete: _categories[i].isBuiltin
                        ? null
                        : () => _delete(_categories[i]),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text('add_category'.tr()),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.dashboardAccent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline,
                size: 20, color: AppColors.primaryDark),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'categories_help'.tr(),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final int index;
  final StitchCategory category;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onToggleHidden;

  /// Null for built-ins, which can be hidden but never deleted — every order
  /// ever placed references them.
  final VoidCallback? onDelete;

  const _CategoryTile({
    super.key,
    required this.index,
    required this.category,
    required this.onEdit,
    required this.onDuplicate,
    required this.onToggleHidden,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final (circle, iconColor) = CategoryIcons.tintFor(category.id);
    final fieldCount = category.fields.length;

    return Opacity(
      opacity: category.hidden ? 0.55 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.only(left: 6, right: 0),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(Icons.drag_handle, color: AppColors.textHint),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: circle,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(CategoryIcons.resolve(category.iconKey),
                    color: iconColor, size: 22),
              ),
            ],
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (category.hidden) ...[
                const SizedBox(width: 6),
                _badge('hidden'.tr(), AppColors.textSecondary),
              ],
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              [
                _genderLabel(category.gender),
                if (category.isBuiltin)
                  fieldCount > 0
                      ? 'builtin_plus_extra'
                          .tr(namedArgs: {'count': fieldCount.toString()})
                      : 'builtin_form'.tr()
                else
                  'field_count'.tr(namedArgs: {'count': fieldCount.toString()}),
              ].join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  onEdit();
                  break;
                case 'duplicate':
                  onDuplicate();
                  break;
                case 'hide':
                  onToggleHidden();
                  break;
                case 'delete':
                  onDelete?.call();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(value: 'edit', child: Text('edit'.tr())),
              PopupMenuItem(value: 'duplicate', child: Text('duplicate'.tr())),
              PopupMenuItem(
                value: 'hide',
                child: Text(category.hidden ? 'show'.tr() : 'hide'.tr()),
              ),
              if (onDelete != null)
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'delete'.tr(),
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
            ],
          ),
          onTap: onEdit,
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
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
}
