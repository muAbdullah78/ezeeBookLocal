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
