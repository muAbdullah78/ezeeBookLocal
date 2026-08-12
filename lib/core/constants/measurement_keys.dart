/// Storage conventions shared by the measurement writers (the order flow) and
/// the measurement readers (the receipt, the order screen, the customer
/// profile).
///
/// Kept dependency-free on purpose: the PDF generator resolves labels through
/// these and must not drag the database layer in with them.

/// Reserved keys written into a measurement row's `additional_options`.
///
/// A tailor-defined field's label lives in their category schema, which they
/// can rename next month. Snapshotting the labels onto the saved measurement
/// keeps an already-printed receipt truthful, and lets the PDF render a form it
/// knows nothing about. Both keys are prefixed so they can never be mistaken
/// for one of the tailor's own options and printed as one.
class MeasurementMetaKeys {
  MeasurementMetaKeys._();

  /// `{field_key: label}` for every field in the group.
  static const String labels = '_labels';

  /// `{field_key: urdu_label}` for the fields that have one.
  ///
  /// Kept separate from [labels] rather than replacing it so receipts printed
  /// before this existed still resolve their field names.
  static const String labelsUrdu = '_labels_ur';

  /// Display name of the group (the category name at the time of the order).
  static const String section = '_section';

  static bool isMeta(String key) => key.startsWith('_');
}

/// Prefix for the `measurements.garment_type` of a tailor-defined category, so
/// custom rows stay distinguishable from the built-in 'shirt' /
/// 'shalwar_trouser' buckets without a schema change.
const String kCategoryGarmentPrefix = 'cat:';

String categoryGarmentType(String categoryId) =>
    '$kCategoryGarmentPrefix$categoryId';

bool isCategoryGarmentType(String garmentType) =>
    garmentType.startsWith(kCategoryGarmentPrefix);
