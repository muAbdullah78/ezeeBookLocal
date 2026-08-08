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
  static String describe({
    String? stitchTypeValue,
    String? shirtSubType,
    String? bottomType,
    bool urdu = false,
  }) {
    var label = stitchType(stitchTypeValue, urdu: urdu);
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
