import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/utils/garment_labels.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../models/customer.dart';
import '../../../models/measurement.dart';
import 'measurement_screen.dart';

class SelectGarmentScreen extends StatefulWidget {
  final Customer customer;

  const SelectGarmentScreen({super.key, required this.customer});

  @override
  State<SelectGarmentScreen> createState() => _SelectGarmentScreenState();
}

class _SelectGarmentScreenState extends State<SelectGarmentScreen> {
  final _sync = SyncService();

  List<_GarmentOption> get _garmentOptions {
    final base = [
      const _GarmentOption(
        stitchType: 'full_suit',
        titleKey: 'full_suit',
        urduName: 'مکمل سوٹ',
        icon: Icons.checkroom,
        circleColor: Color(0xFFE3F2FD),
        iconColor: Color(0xFF1E88E5),
        enabled: true,
      ),
      const _GarmentOption(
        stitchType: 'only_shirt',
        titleKey: 'only_shirt',
        urduName: 'صرف قمیض',
        icon: Icons.checkroom,
        circleColor: Color(0xFFE8F5E9),
        iconColor: Color(0xFF43A047),
        enabled: true,
      ),
      const _GarmentOption(
        stitchType: 'only_shalwar_trouser',
        titleKey: 'only_shalwar_trouser',
        urduName: 'صرف شلوار/ٹراؤزر',
        icon: Icons.straighten,
        circleColor: Color(0xFFFFF3E0),
        iconColor: Color(0xFFF57C00),
        enabled: true,
      ),
      const _GarmentOption(
        stitchType: 'naap_suit',
        titleKey: 'naap_suit',
        urduName: 'ناپ سوٹ',
        icon: Icons.square_foot,
        circleColor: Color(0xFFF3E5F5),
        iconColor: Color(0xFF8E24AA),
        enabled: true,
      ),
    ];

    if (widget.customer.gender == 'female') {
      base.addAll(const [
        _GarmentOption(
          stitchType: 'one_piece_suit',
          titleKey: 'one_piece_suit',
          urduName: 'ون پیس سوٹ',
          icon: Icons.style,
          circleColor: Color(0xFFFCE4EC),
          iconColor: Color(0xFFE91E63),
          enabled: false,
        ),
        _GarmentOption(
          stitchType: 'saari_blouse',
          titleKey: 'saari_blouse',
          urduName: 'ساڑھی/بلاؤز',
          icon: Icons.auto_awesome,
          circleColor: Color(0xFFE0F2F1),
          iconColor: Color(0xFF26A69A),
          enabled: false,
        ),
      ]);
    }

    return base;
  }

  List<String> _garmentTypesForStitch(String stitchType) {
    switch (stitchType) {
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

  Future<void> _onGarmentTapped(String stitchType) async {
    final garmentTypes = _garmentTypesForStitch(stitchType);
    final List<Measurement> savedMeasurements = [];

    for (final gt in garmentTypes) {
      final data = await _sync.getMeasurementsByGarmentType(
          widget.customer.id, gt);
      // Rows come back newest-first, and every order adds another row for the
      // same garment. Taking only the newest matters: _prefillFromSaved
      // overwrites the form for each record it is given, so passing the whole
      // history let the OLDEST measurements win — a loyal customer with years
      // of orders was measured from their very first visit.
      if (data.isNotEmpty) {
        savedMeasurements.add(Measurement.fromMap(data.first));
      }
    }

    if (!mounted) return;

    if (savedMeasurements.isNotEmpty) {
      _showSavedMeasurementsSheet(stitchType, savedMeasurements);
    } else {
      _navigateToMeasurements(stitchType, null);
    }
  }

  void _showSavedMeasurementsSheet(
      String stitchType, List<Measurement> measurements) {
    showModalBottomSheet(
      context: context,
      // Without this the sheet is capped at 9/16 of the screen and its
      // action buttons can be pushed out of reach.
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
                            // garment_type is stored as 'shirt' /
                            // 'shalwar_trouser', which have no translation
                            // entries — .tr() echoed the raw key at the user.
                            '${GarmentLabels.titleCase(m.garmentType)}'
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
                        _navigateToMeasurements(stitchType, null);
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
                        _navigateToMeasurements(stitchType, measurements);
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

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _navigateToMeasurements(
      String stitchType, List<Measurement>? savedMeasurements) {
    Navigator.of(context).push(
      SlidePageRoute(
        page: MeasurementScreen(
          customerId: widget.customer.id,
          customerName: widget.customer.name,
          customerPhone: widget.customer.phone,
          customerGender: widget.customer.gender,
          customerSerialNumber: widget.customer.serialNumber,
          stitchType: stitchType,
          savedMeasurements: savedMeasurements,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customer;
    final options = _garmentOptions;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${customer.name} (#${customer.serialNumber})'),
      ),
      body: SingleChildScrollView(
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
                  children: options.map((option) => _GarmentCard(
                        option: option,
                        onTap: option.enabled
                            ? () => _onGarmentTapped(option.stitchType)
                            : () => ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('coming_soon'.tr()),
                                    duration: const Duration(seconds: 2),
                                  ),
                                ),
                      )).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GarmentOption {
  final String stitchType;
  final String titleKey;
  final String urduName;
  final IconData icon;
  final Color circleColor;
  final Color iconColor;
  final bool enabled;

  const _GarmentOption({
    required this.stitchType,
    required this.titleKey,
    required this.urduName,
    required this.icon,
    required this.circleColor,
    required this.iconColor,
    required this.enabled,
  });
}

class _GarmentCard extends StatelessWidget {
  final _GarmentOption option;
  final VoidCallback? onTap;

  const _GarmentCard({required this.option, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: option.enabled ? 1.0 : 0.5,
      child: Container(
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
                      color: option.circleColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      option.icon,
                      size: 26,
                      color: option.iconColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    option.titleKey.tr(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    option.urduName,
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
                  if (!option.enabled) ...[
                    const SizedBox(height: 6),
                    Text(
                      'coming_soon'.tr(),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFF57C00),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
