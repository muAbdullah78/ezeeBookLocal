import '../constants/measurement_keys.dart';

/// Shared garment / stitch-type label helpers.
///
/// These labels were previously duplicated across the order screens, the PDF
/// generator and the dashboard, which let them drift apart. Centralising them
/// keeps the receipt, the WhatsApp message and the UI in agreement.
class GarmentLabels {
  GarmentLabels._();

  /// Human label for an order's `stitch_type` (the category the tailor picked).
  ///
  /// Unknown values (including user-created custom categories, which store
  /// their own display name) fall back to a readable Title Case rendering.
  static String stitchType(String? type, {bool urdu = false}) {
    switch (type) {
      case 'full_suit':
        return urdu ? 'مکمل سوٹ' : 'Full Suit';
      case 'naap_suit':
        return urdu ? 'ناپ سوٹ' : 'Naap Suit';
      case 'only_shirt':
        return urdu ? 'صرف قمیض' : 'Only Shirt';
      case 'only_shalwar_trouser':
        return urdu ? 'صرف شلوار/ٹراؤزر' : 'Only Shalwar/Trouser';
      case 'one_piece_suit':
        return urdu ? 'ون پیس سوٹ' : 'One Piece Suit';
      case 'saari_blouse':
        return urdu ? 'ساڑھی/بلاؤز' : 'Saari/Blouse';
      default:
        return titleCase(type ?? '');
    }
  }

  /// Human label for a shirt/bottom sub-type.
  static String subType(String? type, {bool urdu = false}) {
    switch (type) {
      case 'kameez':
        return urdu ? 'قمیض' : 'Kameez';
      case 'kurti':
        return urdu ? 'کرتی' : 'Kurti';
      case 'short_shirt':
        return urdu ? 'شارٹ شرٹ' : 'Short Shirt';
      case 'choli':
        return urdu ? 'چولی' : 'Choli';
      case 'shalwar':
        return urdu ? 'شلوار' : 'Shalwar';
      case 'trouser':
        return urdu ? 'ٹراؤزر' : 'Trouser';
      case 'pajama':
        return urdu ? 'پاجامہ' : 'Pajama';
      case 'sharara':
        return urdu ? 'شرارہ' : 'Sharara';
      case 'gharara':
        return urdu ? 'غرارہ' : 'Gharara';
      default:
        return titleCase(type ?? '');
    }
  }

  /// Full garment description: category plus any sub-types, e.g.
  /// "Full Suit — Kameez + Shalwar".
  ///
  /// [categoryName] is the name snapshotted on the order. It wins when present:
  /// a tailor-defined category's `stitch_type` is an opaque id (title-casing it
  /// would print a UUID at the customer), and a renamed built-in should show its
  /// new name.
  static String describe({
    String? stitchTypeValue,
    String? categoryName,
    String? shirtSubType,
    String? bottomType,
    bool urdu = false,
  }) {
    final snapshot = categoryName?.trim() ?? '';
    var label =
        snapshot.isNotEmpty ? snapshot : stitchType(stitchTypeValue, urdu: urdu);
    final parts = <String>[
      if (shirtSubType != null && shirtSubType.isNotEmpty)
        subType(shirtSubType, urdu: urdu),
      if (bottomType != null && bottomType.isNotEmpty)
        subType(bottomType, urdu: urdu),
    ];
    if (parts.isNotEmpty) label += ' — ${parts.join(' + ')}';
    return label;
  }

  /// Storage key → the label the tailor actually sees on the measurement
  /// form. Measurements are saved under internal keys (`w_kandhe_ki_chorai`),
  /// and printing those raw produced receipts full of "W Kandhe Ki Chorai".
  static const Map<String, String> _measurementLabels = {
    // Men — shirt
    'length': 'Length', 'shoulder': 'Shoulder', 'chest': 'Chest',
    'collar': 'Collar', 'sleeve_width': 'Sleeve Width', 'waist': 'Waist',
    'hip': 'Hip', 'sleeve': 'Sleeve', 'cuff_width': 'Cuff Width',
    'cuff_length': 'Cuff Length',
    // Men — trouser / shalwar
    'trouser_length': 'Trouser Length', 'paincha': 'Paincha',
    'trouser_width': 'Trouser Width (Ghaira)', 'thigh': 'Thigh',
    'patti_width': 'Patti Width', 'shalwar_length': 'Shalwar Length',
    'paincha_shalwar': 'Paincha', 'shalwar_ghair': 'Shalwar Ghair',
    'patti_width_shalwar': 'Patti Width',
    // Women — shirt / kameez / kurti
    'w_length': 'Length', 'w_shoulder': 'Shoulder (Tera)', 'w_sleeve': 'Sleeve',
    'w_chest': 'Chest', 'w_hip': 'Hip', 'w_daman': 'Daman', 'w_chak': 'Chak',
    'w_front_neck': 'Front Neck', 'w_back_neck': 'Back Neck',
    'w_neck_width': 'Neck Width', 'w_kandhe_ki_chorai': 'Shoulder Width',
    'w_cuff_opening': 'Cuff Opening', 'w_cuff_ki_chorai': 'Cuff Width',
    // Women — choli
    'w_choli_length': 'Choli Length', 'w_choli_shoulder': 'Shoulder (Tera)',
    'w_choli_chest': 'Chest', 'w_under_bust': 'Under Bust',
    'w_choli_front_neck': 'Front Neck', 'w_choli_back_neck': 'Back Neck',
    'w_choli_neck_width': 'Neck Width',
    'w_choli_kandhe_ki_chaurai': 'Shoulder Width',
    'w_sleeve_opening': 'Sleeve Opening',
    'w_sleeve_opening_width': 'Sleeve Opening Width',
    'w_waist_band': 'Waist Band', 'w_choli_sleeve_length': 'Sleeve Length',
    // Women — bottoms
    'w_shalwar_length': 'Shalwar Length', 'w_trouser_length': 'Trouser Length',
    'w_pajama_length': 'Pajama Length', 'w_sharara_length': 'Sharara Length',
    'w_gharara_length': 'Gharara Length', 'w_front_asan': 'Front Asan',
    'w_back_asan': 'Back Asan', 'w_thigh': 'Thigh', 'w_paincha': 'Paincha',
    'w_ghera': 'Ghera', 'w_ghutna': 'Ghutna',
  };

  /// Readable name for a stored measurement key. Falls back to Title Case so
  /// fields added by a custom category still print sensibly.
  static String measurementLabel(String key) =>
      _measurementLabels[key] ?? titleCase(key);

  /// Label for a field, preferring the snapshot saved with the order.
  ///
  /// A tailor-defined field has no entry in [_measurementLabels] — its name is
  /// whatever the tailor typed — so the snapshot is the only truthful source.
  ///
  /// When the tailor gave the field both an English and an Urdu name, both are
  /// shown: the worker who reads the receipt may know only one of them, and
  /// picking one for them loses information the tailor deliberately entered.
  /// The two are only combined when they actually differ — a field named in
  /// Urdu alone has the same string in both places and must not print twice.
  static String fieldLabel(
    String key,
    Map<String, String>? snapshot, {
    Map<String, String>? urduSnapshot,
  }) {
    final primary = snapshot?[key]?.trim() ?? '';
    final urdu = urduSnapshot?[key]?.trim() ?? '';
    final base = primary.isNotEmpty ? primary : measurementLabel(key);
    if (urdu.isEmpty || urdu == base) return base;
    return '$base ($urdu)';
  }

  /// Heading for a measurement group.
  ///
  /// Custom groups are stored under `cat:<uuid>`, which must never reach the
  /// screen; their snapshotted section name is used instead.
  static String groupLabel(String garmentType, Map<String, dynamic>? options) {
    final section = options?[MeasurementMetaKeys.section]?.toString().trim();
    if (section != null && section.isNotEmpty) return section;
    if (isCategoryGarmentType(garmentType)) {
      return titleCase(garmentType.substring(kCategoryGarmentPrefix.length));
    }
    return measurementLabel(garmentType);
  }

  /// Pull the `{field_key: label}` snapshot out of a decoded options map.
  static Map<String, String> labelSnapshot(Map<String, dynamic>? options) =>
      _stringMap(options?[MeasurementMetaKeys.labels]);

  /// Pull the Urdu label snapshot. Empty for orders saved before it existed.
  static Map<String, String> urduLabelSnapshot(
          Map<String, dynamic>? options) =>
      _stringMap(options?[MeasurementMetaKeys.labelsUrdu]);

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      final label = v?.toString().trim() ?? '';
      if (label.isNotEmpty) out[k.toString()] = label;
    });
    return out;
  }

  /// The options a human should see — the reserved `_labels` / `_section`
  /// bookkeeping entries are stripped so they never print as instructions.
  static Map<String, dynamic> visibleOptions(Map<String, dynamic>? options) {
    if (options == null) return const {};
    return {
      for (final e in options.entries)
        if (!MeasurementMetaKeys.isMeta(e.key)) e.key: e.value,
    };
  }

  /// Convert a snake_case key into readable Title Case ("cuff_width" →
  /// "Cuff Width"). Used for measurement/option keys and for custom
  /// categories that have no built-in translation.
  static String titleCase(String key) {
    if (key.isEmpty) return '';
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
