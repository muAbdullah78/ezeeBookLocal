import 'package:flutter/material.dart';

/// The curated icon set a tailor picks from when creating a stitching category.
///
/// Deliberately small and concrete: a free icon search would mean scrolling
/// thousands of abstract glyphs, which is exactly the kind of screen the target
/// user gives up on. These are the shapes that map onto real shop work
/// (garments, cloth, tools, bedding, bags), each with a stable key so the
/// choice survives a backup/restore.
class CategoryIcons {
  CategoryIcons._();

  static const String fallbackKey = 'checkroom';

  /// Insertion order is the order shown in the picker.
  static const Map<String, IconData> catalogue = {
    'checkroom': Icons.checkroom,
    'dry_cleaning': Icons.dry_cleaning,
    'straighten': Icons.straighten,
    'square_foot': Icons.square_foot,
    'content_cut': Icons.content_cut,
    'design_services': Icons.design_services,
    'style': Icons.style,
    'auto_awesome': Icons.auto_awesome,
    'layers': Icons.layers,
    'texture': Icons.texture,
    'grid_on': Icons.grid_on,
    'palette': Icons.palette,
    'format_paint': Icons.format_paint,
    'iron': Icons.iron,
    'work_outline': Icons.work_outline,
    'shopping_bag': Icons.shopping_bag,
    'backpack': Icons.backpack,
    'inventory_2': Icons.inventory_2,
    'bed': Icons.bed,
    'weekend': Icons.weekend,
    'curtains': Icons.curtains,
    'umbrella': Icons.umbrella,
    'child_care': Icons.child_care,
    'female': Icons.female,
    'male': Icons.male,
    'diamond': Icons.diamond,
    'star_outline': Icons.star_outline,
    'favorite_border': Icons.favorite_border,
  };

  static List<String> get keys => catalogue.keys.toList();

  /// Icon for [key], falling back to the hanger when a backup carries a key
  /// this build does not know.
  static IconData resolve(String? key) =>
      catalogue[key] ?? catalogue[fallbackKey]!;

  /// Tint pairs used for the category cards. Picked by category id so a
  /// category keeps its colour when the tailor reorders the list.
  static const List<(Color circle, Color icon)> _tints = [
    (Color(0xFFE3F2FD), Color(0xFF1E88E5)),
    (Color(0xFFE8F5E9), Color(0xFF43A047)),
    (Color(0xFFFFF3E0), Color(0xFFF57C00)),
    (Color(0xFFF3E5F5), Color(0xFF8E24AA)),
    (Color(0xFFFCE4EC), Color(0xFFE91E63)),
    (Color(0xFFE0F2F1), Color(0xFF26A69A)),
    (Color(0xFFEDE7F6), Color(0xFF5E35B1)),
    (Color(0xFFFFFDE7), Color(0xFFF9A825)),
  ];

  /// Stable colour pair for a category. Uses the id's code units rather than
  /// [Object.hashCode], which is not guaranteed stable across app runs.
  static (Color circle, Color icon) tintFor(String id) {
    if (id.isEmpty) return _tints.first;
    var sum = 0;
    for (final unit in id.codeUnits) {
      sum = (sum + unit) % 100000;
    }
    return _tints[sum % _tints.length];
  }
}
