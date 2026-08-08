import '../../models/stitch_category.dart';
import '../database/database_helper.dart';

/// Reads and writes the tailor's stitching categories.
///
/// Everything is local. The four categories the app ships with are seeded rows
/// (see [DatabaseHelper.seedBuiltinCategories]) so they behave like any other
/// entry in the catalogue.
class CategoryService {
  static final CategoryService _instance = CategoryService._internal();
  factory CategoryService() => _instance;
  CategoryService._internal();

  final _db = DatabaseHelper();

  /// Every category, in display order, each with its fields attached.
  ///
  /// Fields are fetched in one query and bucketed in memory — a category list
  /// of 30+ (which is realistic once a tailor adds their own) would otherwise
  /// mean 30+ round trips every time the order screen opens.
  Future<List<StitchCategory>> getAll() async {
    var rows = await _db.getStitchCategories();
    if (rows.isEmpty) {
      // Should be impossible (seeded on create, upgrade and restore), but an
      // empty catalogue means no orders can be placed at all — repair it
      // rather than showing the tailor a dead screen.
      await _repairSeed();
      rows = await _db.getStitchCategories();
    }

    final fieldRows = await _db.getAllCategoryFields();
    final byCategory = <String, List<CategoryField>>{};
    for (final r in fieldRows) {
      final field = CategoryField.fromMap(r);
      byCategory.putIfAbsent(field.categoryId, () => []).add(field);
    }

    return rows
        .map((r) => StitchCategory.fromMap(
              r,
              fields: byCategory[r['id']] ?? const [],
            ))
        .toList();
  }

  /// Categories offered when placing an order for a customer of [gender]:
  /// visible ones only, filtered to that gender.
  Future<List<StitchCategory>> getForCustomer(String gender) async {
    final all = await getAll();
    final visible =
        all.where((c) => !c.hidden && c.appliesTo(gender)).toList();
    // A tailor can hide every category. Falling back to the built-ins keeps
    // order placement possible instead of dead-ending the flow.
    if (visible.isEmpty) {
      return all.where((c) => c.isBuiltin).toList();
    }
    return visible;
  }

  Future<StitchCategory?> getById(String id) async {
    final row = await _db.getStitchCategory(id);
    if (row == null) return null;
    final fields = (await _db.getCategoryFields(id))
        .map(CategoryField.fromMap)
        .toList();
    return StitchCategory.fromMap(row, fields: fields);
  }

  /// Create or update a category together with its whole field list.
  Future<void> save(StitchCategory category) async {
    await _db.upsertStitchCategory(category.toMap());
    // Re-key the fields onto this category so a duplicated or newly built
    // category cannot carry another category's id in its rows.
    final fields = <Map<String, dynamic>>[];
    for (var i = 0; i < category.fields.length; i++) {
      final f = category.fields[i];
      fields.add({
        ...f.toMap(),
        'category_id': category.id,
        'sort_order': i,
      });
    }
    await _db.replaceCategoryFields(category.id, fields);
  }

  Future<void> reorder(List<String> orderedIds) =>
      _db.updateCategoryOrder(orderedIds);

  Future<void> setHidden(String id, bool hidden) =>
      _db.setCategoryHidden(id, hidden);

  Future<void> delete(String id) => _db.deleteStitchCategory(id);

  Future<int> orderCount(String categoryId) =>
      _db.getOrderCountForCategory(categoryId);

  /// Next free slot at the end of the list.
  Future<int> nextSortOrder() async {
    final rows = await _db.getStitchCategories();
    if (rows.isEmpty) return 0;
    var max = -1;
    for (final r in rows) {
      final v = int.tryParse(r['sort_order']?.toString() ?? '') ?? 0;
      if (v > max) max = v;
    }
    return max + 1;
  }

  /// Copy a category (including its fields) as a new editable entry.
  ///
  /// This is how a tailor starts from something that already works — clone
  /// "Full Suit", then adjust — rather than typing 13 fields from scratch. The
  /// copy is never a built-in, so it renders from its own fields and can be
  /// deleted freely.
  Future<StitchCategory> duplicate(
    StitchCategory source, {
    required String newName,
  }) async {
    final copy = StitchCategory(
      name: newName,
      nameUrdu: source.nameUrdu,
      gender: source.gender,
      iconKey: source.iconKey,
      sortOrder: await nextSortOrder(),
      hidden: false,
      builtinKey: null,
      fields: const [],
    );

    // A built-in's real form is code, not rows, so cloning one starts from its
    // template field list; a custom category clones its own fields.
    final sourceFields = source.isBuiltin
        ? builtinTemplateFields(source.builtinKey!, copy.id)
        : source.fields
            .map((f) => CategoryField(
                  categoryId: copy.id,
                  groupLabel: f.groupLabel,
                  fieldKey: f.fieldKey,
                  label: f.label,
                  labelUrdu: f.labelUrdu,
                  type: f.type,
                  options: f.options,
                  sortOrder: f.sortOrder,
                ))
            .toList();

    final withFields = copy.copyWith(fields: sourceFields);
    await save(withFields);
    return withFields;
  }

  Future<void> _repairSeed() async {
    // seedBuiltinCategories takes a DatabaseExecutor; the plain database is one.
    await _db.seedBuiltinCategories(await _db.database);
  }

  // ==================== built-in templates ====================

  /// Editable starting points for a category cloned from a built-in.
  ///
  /// These mirror the fields the hand-tuned form collects, which is what makes
  /// "duplicate Full Suit and tweak it" produce something usable. They are
  /// plain data: the clone owns them and can rename or delete any of them.
  static List<CategoryField> builtinTemplateFields(
    String builtinKey,
    String categoryId,
  ) {
    final shirt = <(String, String, String)>[
      ('length', 'Length', 'لمبائی'),
      ('shoulder', 'Shoulder', 'کندھا'),
      ('chest', 'Chest', 'چھاتی'),
      ('collar', 'Collar', 'گلا'),
      ('sleeve', 'Sleeve', 'آستین'),
      ('sleeve_width', 'Sleeve Width', 'آستین چوڑائی'),
      ('waist', 'Waist', 'کمر'),
      ('hip', 'Hip', 'کولہا'),
      ('cuff_width', 'Cuff Width', 'کف چوڑائی'),
      ('cuff_length', 'Cuff Length', 'کف لمبائی'),
    ];
    final bottom = <(String, String, String)>[
      ('bottom_length', 'Length', 'لمبائی'),
      ('paincha', 'Paincha', 'پائنچا'),
      ('ghera', 'Ghera', 'گھیرا'),
      ('thigh', 'Thigh', 'ران'),
      ('patti_width', 'Patti Width', 'پٹی چوڑائی'),
    ];

    final groups = <(String, List<(String, String, String)>)>[
      if (builtinKey != 'only_shalwar_trouser') ('Shirt', shirt),
      if (builtinKey != 'only_shirt') ('Shalwar / Trouser', bottom),
    ];

    final out = <CategoryField>[];
    final taken = <String>{};
    for (final (groupLabel, entries) in groups) {
      for (final (slug, label, urdu) in entries) {
        final key = CategoryField.buildFieldKey('${groupLabel}_$slug', taken);
        taken.add(key);
        out.add(CategoryField(
          categoryId: categoryId,
          groupLabel: groupLabel,
          fieldKey: key,
          label: label,
          labelUrdu: urdu,
          sortOrder: out.length,
        ));
      }
    }
    return out;
  }
}
