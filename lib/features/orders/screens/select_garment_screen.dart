import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/category_icons.dart';
import '../../../core/constants/measurement_keys.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/services/category_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/garment_labels.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../models/customer.dart';
import '../../../models/measurement.dart';
import '../../../models/stitch_category.dart';
import 'custom_measurement_screen.dart';
import 'measurement_screen.dart';

/// "What to stitch?" — the tailor's own category catalogue.
///
/// The list used to be hard-coded, which capped every shop at the same four
/// options (plus two permanently disabled "coming soon" cards). It now comes
/// from `stitch_categories`, so a tailor sees exactly the categories they
/// created, in the order they arranged, filtered to this customer's gender.
class SelectGarmentScreen extends StatefulWidget {
  final Customer customer;

  const SelectGarmentScreen({super.key, required this.customer});

  @override
  State<SelectGarmentScreen> createState() => _SelectGarmentScreenState();
}

class _SelectGarmentScreenState extends State<SelectGarmentScreen> {
  final _sync = SyncService();
  final _categories = CategoryService();

  List<StitchCategory> _options = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _categories.getForCustomer(widget.customer.gender);
      if (!mounted) return;
      setState(() {
        _options = list;
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.error('SelectGarment', 'category load failed',
          error: e, stackTrace: st);
      if (!mounted) return;
      setState(() => _loading = false);
      SnackbarHelper.showError(context, friendlyError(e));
    }
  }

  /// Which measurement buckets a built-in category writes to.
  List<String> _garmentTypesForBuiltin(String builtinKey) {
    switch (builtinKey) {
      case 'full_suit':
      case 'naap_suit':
        return ['shirt', 'shalwar_trouser'];
      case 'only_shirt':
        return ['shirt'];
      case 'only_shalwar_trouser':
        return ['shalwar_trouser'];
      default:
        return [];
    }
  }

  Future<void> _onCategoryTapped(StitchCategory category) async {
    try {
      final saved = await _loadSavedMeasurements(category);
      if (!mounted) return;
      if (saved.isNotEmpty) {
        _showSavedMeasurementsSheet(category, saved);
      } else {
        _navigateToMeasurements(category, null);
      }
    } catch (e, st) {
      AppLogger.error('SelectGarment', 'saved measurement load failed',
          error: e, stackTrace: st);
      if (!mounted) return;
      // A failed history lookup must not block a new order — fall through to a
      // blank form rather than dead-ending the tailor mid-sale.
      _navigateToMeasurements(category, null);
    }
  }

  Future<List<Measurement>> _loadSavedMeasurements(
      StitchCategory category) async {
    final garmentTypes = category.isBuiltin
        ? [
            ..._garmentTypesForBuiltin(category.builtinKey!),
            // A built-in the tailor extended also has a row of its own extra
            // fields to restore.
            if (category.fields.isNotEmpty) categoryGarmentType(category.id),
          ]
        : [categoryGarmentType(category.id)];

    final saved = <Measurement>[];
    for (final gt in garmentTypes) {
      final rows =
          await _sync.getMeasurementsByGarmentType(widget.customer.id, gt);
      // Rows come back newest-first and every order adds another for the same
      // garment. Taking only the newest matters: the measurement form is
      // overwritten per record it is given, so passing the whole history let the
      // OLDEST measurements win — a loyal customer with years of orders was
      // measured from their very first visit.
      if (rows.isNotEmpty) {
        saved.add(Measurement.fromMap(rows.first));
      }
    }
    return saved;
  }

  void _showSavedMeasurementsSheet(
      StitchCategory category, List<Measurement> measurements) {
    showModalBottomSheet(
      context: context,
      // Without this the sheet is capped at 9/16 of the screen and its action
      // buttons can be pushed out of reach.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textHint,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'saved_measurements_found'.tr(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ...measurements.map((m) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.dashboardAccent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.straighten,
                            size: 18, color: AppColors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${_measurementTitle(m, category)}'
                            ' — ${_formatDate(m.updatedAt)}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _navigateToMeasurements(category, null);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text('new_measurements'.tr()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _navigateToMeasurements(category, measurements);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text('use_saved'.tr()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// A custom category's rows are stored under `cat:<id>`, which is not
  /// something to show a tailor — use the category name instead.
  String _measurementTitle(Measurement m, StitchCategory category) {
    if (isCategoryGarmentType(m.garmentType)) return category.name;
    return GarmentLabels.titleCase(m.garmentType);
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _navigateToMeasurements(
      StitchCategory category, List<Measurement>? savedMeasurements) {
    final customer = widget.customer;

    if (!category.isBuiltin) {
      Navigator.of(context).push(
        SlidePageRoute(
          page: CustomMeasurementScreen(
            customerId: customer.id,
            customerName: customer.name,
            customerPhone: customer.phone,
            customerGender: customer.gender,
            customerSerialNumber: customer.serialNumber,
            category: category,
            savedMeasurement:
                (savedMeasurements != null && savedMeasurements.isNotEmpty)
                    ? savedMeasurements.first
                    : null,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      SlidePageRoute(
        page: MeasurementScreen(
          customerId: customer.id,
          customerName: customer.name,
          customerPhone: customer.phone,
          customerGender: customer.gender,
          customerSerialNumber: customer.serialNumber,
          // Built-ins keep their original stitch string so every existing
          // branch (which sections to show, the receipt, the WhatsApp text)
          // keeps working after a rename.
          stitchType: category.builtinKey!,
          category: category,
          savedMeasurements: savedMeasurements,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customer;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${customer.name} (#${customer.serialNumber})'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    children: [
                      Text(
                        'what_to_stitch'.tr(),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'کیا سینا ہے؟',
                        style: TextStyle(
                          fontSize: 15,
                          fontFamily: 'NotoNastaliqUrdu',
                          color: AppColors.textSecondary,
                          height: 2.0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      GridView.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.95,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: _options
                            .map((category) => _GarmentCard(
                                  category: category,
                                  onTap: () => _onCategoryTapped(category),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _GarmentCard extends StatelessWidget {
  final StitchCategory category;
  final VoidCallback onTap;

  const _GarmentCard({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (circle, iconColor) = CategoryIcons.tintFor(category.id);
    final urduName = category.nameUrdu?.trim() ?? '';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: circle,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    CategoryIcons.resolve(category.iconKey),
                    size: 26,
                    color: iconColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  category.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (urduName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    urduName,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'NotoNastaliqUrdu',
                      color: AppColors.textSecondary,
                      height: 1.8,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
