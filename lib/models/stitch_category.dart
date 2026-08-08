import 'dart:convert';

import 'package:uuid/uuid.dart';

/// What kind of input a category field renders on the measurement form.
///
/// Tailors do not all work the same way — one records a numeric "ghera", the
/// next wants a Yes/No for "double stitch" and a third needs to pick one of
/// three collar styles. These are the four shapes that cover it.
enum CategoryFieldType {
  /// A numeric measurement, shown with an inches suffix.
  number,

  /// Free text (cloth brand, a short note kept with the measurements).
  text,

  /// A Yes/No switch.
  toggle,

  /// One value out of a fixed list the tailor typed.
  choice,
}

/// One field on a stitching category's measurement form.
class CategoryField {
  final String id;
  final String categoryId;

  /// Section heading this field sits under ("Shirt", "Shalwar"). Empty means
  /// the form's default section.
  final String groupLabel;

  /// Key the value is stored under inside `measurements.measurement_data`.
  /// Custom fields are always prefixed (see [buildFieldKey]) so they can never
  /// collide with a built-in measurement key.
  final String fieldKey;

  final String label;
  final String? labelUrdu;
  final CategoryFieldType type;

  /// Allowed values for [CategoryFieldType.choice]; empty otherwise.
  final List<String> options;

  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  CategoryField({
    String? id,
    required this.categoryId,
    this.groupLabel = '',
    required this.fieldKey,
    required this.label,
    this.labelUrdu,
    this.type = CategoryFieldType.number,
    this.options = const [],
    this.sortOrder = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// The label to show, preferring Urdu when the app is in Urdu and an Urdu
  /// label was actually entered.
  String displayLabel({bool urdu = false}) {
    if (urdu && (labelUrdu?.trim().isNotEmpty ?? false)) return labelUrdu!.trim();
    return label;
  }

  bool get isMeasurement => type == CategoryFieldType.number;

  Map<String, dynamic> toMap() => {
        'id': id,
        'category_id': categoryId,
        'group_label': groupLabel,
        'field_key': fieldKey,
        'label': label,
        'label_urdu': labelUrdu,
        'field_type': type.name,
        'options': options.isEmpty ? null : json.encode(options),
        'sort_order': sortOrder,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory CategoryField.fromMap(Map<String, dynamic> map) {
    return CategoryField(
      id: map['id'] as String?,
      categoryId: (map['category_id'] ?? '').toString(),
      groupLabel: (map['group_label'] ?? '').toString(),
      fieldKey: (map['field_key'] ?? '').toString(),
      label: (map['label'] ?? '').toString(),
      labelUrdu: map['label_urdu'] as String?,
      type: typeFromStorage(map['field_type'] as String?),
      options: decodeOptions(map['options']),
      sortOrder: _asInt(map['sort_order']),
      createdAt: _asDate(map['created_at']),
      updatedAt: _asDate(map['updated_at']),
    );
  }

  CategoryField copyWith({
    String? groupLabel,
    String? fieldKey,
    String? label,
    String? labelUrdu,
    bool clearLabelUrdu = false,
    CategoryFieldType? type,
    List<String>? options,
    int? sortOrder,
  }) {
    return CategoryField(
      id: id,
      categoryId: categoryId,
      groupLabel: groupLabel ?? this.groupLabel,
      fieldKey: fieldKey ?? this.fieldKey,
      label: label ?? this.label,
      labelUrdu: clearLabelUrdu ? null : (labelUrdu ?? this.labelUrdu),
      type: type ?? this.type,
      options: options ?? this.options,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  static CategoryFieldType typeFromStorage(String? raw) {
    switch (raw) {
      case 'text':
        return CategoryFieldType.text;
      case 'toggle':
        return CategoryFieldType.toggle;
      case 'choice':
        return CategoryFieldType.choice;
      default:
        return CategoryFieldType.number;
    }
  }

  /// Options round-trip as a JSON array. A damaged blob must not take the
  /// whole form down, so anything unreadable degrades to "no options".
  static List<String> decodeOptions(Object? raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    try {
      final decoded = json.decode(raw.toString());
      if (decoded is List) {
        return decoded.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      }
    } catch (_) {
      // fall through
    }
    return const [];
  }

  /// Build a stable storage key for a new field.
  ///
  /// Always prefixed with `c_` so a tailor's "length" can never overwrite the
  /// built-in `length` measurement, and suffixed when [taken] already holds the
  /// slug (two fields legitimately called "Width" in different sections).
  static String buildFieldKey(String label, Set<String> taken) {
    var slug = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (slug.isEmpty) slug = 'field';
    final base = 'c_$slug';
    if (!taken.contains(base)) return base;
    var i = 2;
    while (taken.contains('${base}_$i')) {
      i++;
    }
    return '${base}_$i';
  }
}

/// A stitching category the tailor can pick when placing an order.
///
/// The four categories the app shipped with are seeded as rows here with a
/// [builtinKey] set: they keep their hand-tuned measurement form (which
/// encodes real tailoring logic such as waistband → elastic width) but can be
/// renamed, re-iconed, reordered, hidden, and extended with extra fields.
/// Categories the tailor creates have a null [builtinKey] and are rendered
/// entirely from their own [fields].
class StitchCategory {
  final String id;
  final String name;
  final String? nameUrdu;

  /// 'male', 'female' or 'both' — which customers this category is offered for.
  final String gender;

  /// Key into the curated icon catalogue (see `core/constants/category_icons.dart`).
  final String iconKey;

  final int sortOrder;
  final bool hidden;

  /// Non-null for the four categories the app ships with.
  final String? builtinKey;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Loaded separately by `CategoryService`; empty until then.
  final List<CategoryField> fields;

  StitchCategory({
    String? id,
    required this.name,
    this.nameUrdu,
    this.gender = 'both',
    this.iconKey = 'checkroom',
    this.sortOrder = 0,
    this.hidden = false,
    this.builtinKey,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.fields = const [],
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isBuiltin => builtinKey != null && builtinKey!.isNotEmpty;

  /// Built-ins run the hand-tuned form; everything else runs the generic one.
  bool get usesBuiltinForm => isBuiltin;

  String displayName({bool urdu = false}) {
    if (urdu && (nameUrdu?.trim().isNotEmpty ?? false)) return nameUrdu!.trim();
    return name;
  }

  bool appliesTo(String customerGender) =>
      gender == 'both' || gender == customerGender;

  /// Fields grouped by their section heading, preserving field order and the
  /// order in which the sections first appear.
  Map<String, List<CategoryField>> get fieldsByGroup {
    final grouped = <String, List<CategoryField>>{};
    for (final f in fields) {
      grouped.putIfAbsent(f.groupLabel.trim(), () => []).add(f);
    }
    return grouped;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'name_urdu': nameUrdu,
        'gender': gender,
        'icon_key': iconKey,
        'sort_order': sortOrder,
        'hidden': hidden ? 1 : 0,
        'builtin_key': builtinKey,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory StitchCategory.fromMap(
    Map<String, dynamic> map, {
    List<CategoryField> fields = const [],
  }) {
    return StitchCategory(
      id: map['id'] as String?,
      name: (map['name'] ?? '').toString(),
      nameUrdu: map['name_urdu'] as String?,
      gender: (map['gender'] ?? 'both').toString(),
      iconKey: (map['icon_key'] ?? 'checkroom').toString(),
      sortOrder: _asInt(map['sort_order']),
      // SQLite has no boolean type: this arrives as 1/0.
      hidden: _asBool(map['hidden']),
      builtinKey: map['builtin_key'] as String?,
      createdAt: _asDate(map['created_at']),
      updatedAt: _asDate(map['updated_at']),
      fields: fields,
    );
  }

  StitchCategory copyWith({
    String? name,
    String? nameUrdu,
    bool clearNameUrdu = false,
    String? gender,
    String? iconKey,
    int? sortOrder,
    bool? hidden,
    List<CategoryField>? fields,
  }) {
    return StitchCategory(
      id: id,
      name: name ?? this.name,
      nameUrdu: clearNameUrdu ? null : (nameUrdu ?? this.nameUrdu),
      gender: gender ?? this.gender,
      iconKey: iconKey ?? this.iconKey,
      sortOrder: sortOrder ?? this.sortOrder,
      hidden: hidden ?? this.hidden,
      builtinKey: builtinKey,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      fields: fields ?? this.fields,
    );
  }
}

// ==================== shared coercion helpers ====================
//
// Rows can arrive straight from SQLite (ints for booleans) or from a restored
// JSON backup (real bools, numbers as strings). Everything is normalised here
// so a hand-edited backup file cannot crash the category screens.

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

bool _asBool(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v?.toString().trim().toLowerCase();
  return s == 'true' || s == '1' || s == 'yes';
}

DateTime _asDate(Object? v) {
  final s = v?.toString() ?? '';
  return DateTime.tryParse(s) ?? DateTime.now();
}
