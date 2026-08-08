import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/pdf_generator.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../models/measurement.dart';
import '../../../services/error_reporter.dart';

class OrderViewScreen extends StatefulWidget {
  final Map<String, dynamic> order;

  const OrderViewScreen({super.key, required this.order});

  @override
  State<OrderViewScreen> createState() => _OrderViewScreenState();
}

class _OrderViewScreenState extends State<OrderViewScreen> {
  final _sync = SyncService();
  late Map<String, dynamic> _order;
  List<Measurement> _measurements = [];
  bool _measurementsExpanded = false;

  @override
  void initState() {
    super.initState();
    _order = Map<String, dynamic>.from(widget.order);
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final measMaps = await _sync.getMeasurementsForOrder(_order['id']);
    if (mounted) {
      setState(() {
        _measurements = measMaps.map((m) => Measurement.fromMap(m)).toList();
      });
    }
  }

  String _getStatus() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (_order['status'] == 'pending' &&
        (_order['delivery_date'] ?? '').compareTo(today) < 0) {
      return 'overdue';
    }
    return _order['status'] ?? 'pending';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return AppColors.warning;
      case 'completed':
        return AppColors.success;
      case 'delivered':
        return AppColors.info;
      case 'overdue':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  Color _statusBgColor(String status) {
    switch (status) {
      case 'pending':
        return AppColors.warningLight;
      case 'completed':
        return AppColors.successLight;
      case 'delivered':
        return const Color(0xFFBBDEFB);
      case 'overdue':
        return AppColors.errorLight;
      default:
        return AppColors.divider;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'order_status_pending'.tr();
      case 'completed':
        return 'order_status_completed'.tr();
      case 'delivered':
        return 'order_status_delivered'.tr();
      case 'overdue':
        return 'order_overdue'.tr();
      default:
        return status;
    }
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '-';
    try {
      final date = DateTime.parse(isoDate);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (_) {
      return isoDate;
    }
  }

  String _garmentLabel() {
    final isUrdu = context.locale.languageCode == 'ur';
    switch (_order['stitch_type']) {
      case 'full_suit':
        return isUrdu ? 'مکمل سوٹ' : 'Full Suit';
      case 'naap_suit':
        return isUrdu ? 'ناپ سوٹ' : 'Naap Suit';
      case 'only_shirt':
        return isUrdu ? 'صرف قمیض' : 'Only Shirt';
      case 'only_shalwar_trouser':
        return isUrdu ? 'صرف شلوار/ٹراؤزر' : 'Only Shalwar/Trouser';
      default:
        return _order['stitch_type'] ?? '';
    }
  }

  String _subTypeLabel(String type) {
    final isUrdu = context.locale.languageCode == 'ur';
    switch (type) {
      case 'kameez':
        return isUrdu ? 'قمیض' : 'Kameez';
      case 'kurti':
        return isUrdu ? 'کرتی' : 'Kurti';
      case 'short_shirt':
        return isUrdu ? 'شارٹ شرٹ' : 'Short Shirt';
      case 'choli':
        return isUrdu ? 'چولی' : 'Choli';
      case 'shalwar':
        return isUrdu ? 'شلوار' : 'Shalwar';
      case 'trouser':
        return isUrdu ? 'ٹراؤزر' : 'Trouser';
      case 'pajama':
        return isUrdu ? 'پاجامہ' : 'Pajama';
      case 'sharara':
        return isUrdu ? 'شرارہ' : 'Sharara';
      case 'gharara':
        return isUrdu ? 'غرارہ' : 'Gharara';
      default:
        return type;
    }
  }

  List<String> _colorsList() {
    try {
      final decoded = json.decode(_order['colors'] ?? '[]');
      if (decoded is List) return decoded.cast<String>();
    } catch (_) {}
    final c = _order['colors'] ?? '';
    return c.toString().isEmpty ? [] : [c.toString()];
  }

  Future<void> _updateStatus(String newStatus) async {
    await _sync.updateOrderStatus(_order['id'], newStatus);
    if (mounted) {
      setState(() {
        _order['status'] = newStatus;
        _order['updated_at'] = DateTime.now().toIso8601String();
      });
      SnackbarHelper.showSuccess(context, '${'order_status_updated'.tr()} — ${_statusLabel(newStatus)}');
    }
  }

  Future<void> _openWhatsApp(String phone, String message) async {
    final phoneNumber = PhoneUtils.toWhatsAppFormat(phone);
    if (phoneNumber == null || phoneNumber.isEmpty) {
      if (!mounted) return;
      SnackbarHelper.showError(context, 'whatsapp_invalid_number'.tr());
      return;
    }
    final uri = Uri.parse(
        'https://wa.me/$phoneNumber?text=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _buildShareMessage() {
    final name = _order['customer_name'] ?? '';
    final serial = _order['customer_serial'] ?? '';
    final garment = _garmentLabel();
    final total = (_order['total_amount'] ?? 0).toDouble();
    final advance = (_order['advance_payment'] ?? 0).toDouble();
    final remaining = total > advance ? total - advance : 0.0;
    final isFullyPaid = remaining == 0 && total > 0;
    final delivery = _formatDate(_order['delivery_date']);
    final status = _statusLabel(_getStatus());

    final lines = <String>[
      'EzeeBook - Order Summary',
      '',
      'Customer: $name (#$serial)',
      'Garment: $garment',
      'Quantity: ${_order['quantity'] ?? 1}',
      'Delivery: $delivery',
      'Status: $status',
      '',
      'Total: Rs. ${total.toStringAsFixed(0)}',
      'Advance: Rs. ${advance.toStringAsFixed(0)}',
      if (isFullyPaid) 'Remaining: Fully Paid' else 'Remaining: Rs. ${remaining.toStringAsFixed(0)}',
    ];

    final specialList = _decodeInstructions(_order['special_instructions']);
    final extraList = _decodeInstructions(_order['extra_instructions']);
    if (specialList.isNotEmpty || extraList.isNotEmpty) {
      lines.add('');
      if (specialList.isNotEmpty) {
        lines.add('Instructions:');
        for (final t in specialList) {
          lines.add('• $t');
        }
      }
      if (extraList.isNotEmpty) {
        lines.add('Extra:');
        for (final t in extraList) {
          lines.add('• $t');
        }
      }
    }

    return lines.join('\n');
  }

  Future<Map<String, dynamic>> _loadShopProfile() async {
    try {
      final profile = await SyncService().getShopProfile();
      return profile ?? {};
    } catch (e, st) {
      AppLogger.error('OrderViewScreen', 'shop_profile load failed',
          error: e, stackTrace: st);
      return {};
    }
  }

  Future<void> _generateAndPreviewPdf() async {
    final pdfBytes = await _buildPdfBytes();
    if (pdfBytes == null || !mounted) return;
    try {
      await Printing.layoutPdf(
        onLayout: (_) => Uint8List.fromList(pdfBytes),
      );
    } catch (e, st) {
      AppLogger.error('OrderViewScreen', 'Printing.layoutPdf failed',
          error: e, stackTrace: st);
      if (!mounted) return;
      SnackbarHelper.showError(context, 'error_generating_pdf'.tr());
    }
  }

  Future<void> _generateAndSharePdf() async {
    final pdfBytes = await _buildPdfBytes();
    if (pdfBytes == null || !mounted) return;

    try {
      final dir = await getTemporaryDirectory();
      final serial = _order['customer_serial'] ?? '';
      final file = File('${dir.path}/order_$serial.pdf');
      await file.writeAsBytes(pdfBytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'EzeeBook - Order #$serial',
        ),
      );
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'error_sharing_pdf'.tr());
      }
    }
  }

  Future<List<int>?> _buildPdfBytes() async {
    // Show loading
    if (mounted) {
      SnackbarHelper.showInfo(context, 'generating_pdf'.tr());
    }

    try {
      final shopProfile = await _loadShopProfile();
      final dupatta = await _sync.getDupattaForOrder(_order['id']);

      // Build grouped measurements — preserve garment-type structure for PDF
      final List<Map<String, dynamic>> groupedMeasurements = [];
      for (final m in _measurements) {
        if (m.measurements.isEmpty) continue;
        Map<String, dynamic> options = {};
        if (m.additionalOptions != null && m.additionalOptions!.isNotEmpty) {
          try {
            options = Map<String, dynamic>.from(
                json.decode(m.additionalOptions!) as Map<String, dynamic>);
          } catch (_) {}
        }
        groupedMeasurements.add({
          'garmentType': m.garmentType,
          'measurements': Map<String, dynamic>.from(m.measurements),
          'additionalOptions': options,
        });
      }

      // Parse extra and special instructions
      final decodedExtra = _decodeInstructions(_order['extra_instructions']);
      final List<String>? extraList = decodedExtra.isEmpty ? null : decodedExtra;
      final decodedSpecial = _decodeInstructions(_order['special_instructions']);
      final String? specialText =
          decodedSpecial.isEmpty ? null : decodedSpecial.join('\n');

      return await PdfGenerator.generateOrderPdf(
        shopProfile: shopProfile,
        customerName: _order['customer_name'] ?? '',
        customerPhone: _order['customer_phone'] ?? '',
        customerSerialNumber:
            int.tryParse(_order['customer_serial']?.toString() ?? '0') ?? 0,
        customerGender: _order['customer_gender'] ?? 'male',
        stitchType: _order['stitch_type'] ?? '',
        shirtSubType: _order['shirt_sub_type'],
        bottomType: _order['bottom_type'],
        bottomWaistband: _order['bottom_waistband'],
        elasticWidth: _order['elastic_width']?.toString(),
        quantity: int.tryParse(_order['quantity']?.toString() ?? '1') ?? 1,
        colors: _colorsList(),
        orderDate: _formatDate(_order['created_at']),
        deliveryDate: _formatDate(_order['delivery_date']),
        status: _getStatus(),
        measurementGroups: groupedMeasurements,
        dupattaDetails: dupatta,
        extraInstructions: extraList,
        specialInstructions: specialText,
      );
    } catch (e, st) {
      AppLogger.error('OrderViewScreen', 'generateOrderPdf failed',
          error: e, stackTrace: st);
      await ErrorReporter.reportError(e, st, hint: 'pdf_generation');
      if (mounted) {
        SnackbarHelper.showError(context, 'error_generating_pdf'.tr());
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _getStatus();
    final total = (_order['total_amount'] ?? 0).toDouble();
    final advance = (_order['advance_payment'] ?? 0).toDouble();
    final remaining = total > advance ? total - advance : 0.0;
    final isFullyPaid = remaining == 0 && total > 0;

    String dateLabel = '';
    final createdRaw = _order['created_at'];
    if (createdRaw != null && createdRaw.toString().isNotEmpty) {
      try {
        dateLabel = DateFormat('dd MMM yy').format(DateTime.parse(createdRaw.toString()));
      } catch (_) {}
    }
    final titleText = 'order_title_format'.tr(namedArgs: {
      'serial': '${_order['customer_serial'] ?? ''}',
      'date': dateLabel,
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(titleText),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              final phone = _order['customer_phone'] ?? '';
              if (phone.isNotEmpty) {
                _openWhatsApp(phone, _buildShareMessage());
              } else {
                SnackbarHelper.showInfo(context, 'no_phone_number'.tr());
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // Status section
          _buildStatusSection(status),
          const SizedBox(height: 14),

          // Customer info
          _buildCard(
            title: 'customer_info'.tr(),
            icon: Icons.person_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('customer_name'.tr(),
                    '${_order['customer_name']} (#${_order['customer_serial']})'),
                if ((_order['customer_phone'] ?? '').toString().isNotEmpty)
                  Row(
                    children: [
                      Expanded(
                        child: _infoRow('phone_number'.tr(),
                            _order['customer_phone'] ?? ''),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chat, color: AppColors.success, size: 22),
                        tooltip: 'WhatsApp',
                        onPressed: () {
                          final phone = _order['customer_phone'] ?? '';
                          _openWhatsApp(phone, 'order_pickup_message'.tr(namedArgs: {
                            'name': _order['customer_name'] ?? '',
                          }));
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Garment info
          _buildCard(
            title: 'garment_info'.tr(),
            icon: Icons.checkroom,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('what_to_stitch'.tr(), _garmentLabel()),
                if (_order['shirt_sub_type'] != null)
                  _infoRow('shirt_kameez'.tr(),
                      _subTypeLabel(_order['shirt_sub_type'])),
                if (_order['bottom_type'] != null)
                  _infoRow('shalwar'.tr(),
                      _subTypeLabel(_order['bottom_type'])),
                _infoRow('how_many_suits'.tr(),
                    '${_order['quantity'] ?? 1}'),
                if (_colorsList().isNotEmpty)
                  _infoRow('suit_color'.tr(), _colorsList().join(', ')),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Measurements (expandable)
          if (_measurements.isNotEmpty) ...[
            _buildMeasurementsCard(),
            const SizedBox(height: 10),
          ],

          // Dates & Payment
          _buildCard(
            title: 'dates_payment'.tr(),
            icon: Icons.receipt_long,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('order_date'.tr(),
                    _formatDate(_order['created_at'])),
                _infoRow('delivery_date'.tr(),
                    _formatDate(_order['delivery_date'])),
                const Divider(height: 16),
                _infoRow('total_amount'.tr(),
                    'Rs. ${total.toStringAsFixed(0)}'),
                _infoRow('advance_payment'.tr(),
                    'Rs. ${advance.toStringAsFixed(0)}'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'remaining_balance'.tr(),
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      isFullyPaid
                          ? 'fully_paid'.tr()
                          : 'Rs. ${remaining.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isFullyPaid
                            ? AppColors.success
                            : (remaining > 0 ? AppColors.error : AppColors.success),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Extra Instructions card (entered during measurement phase)
          if ((_order['extra_instructions'] ?? '').toString().isNotEmpty)
            _buildCard(
              title: 'extra_instructions'.tr(),
              icon: Icons.straighten,
              child: _instructionsList(_order['extra_instructions']),
            ),

          // Special Instructions card (entered at checkout)
          if ((_order['special_instructions'] ?? '').toString().isNotEmpty)
            _buildCard(
              title: 'special_instructions'.tr(),
              icon: Icons.note_alt_outlined,
              child: _instructionsList(_order['special_instructions']),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _generateAndPreviewPdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text('download_pdf'.tr()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _generateAndSharePdf,
                  icon: const Icon(Icons.share),
                  label: Text('share_pdf'.tr()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusSection(String status) {
    final rawStatus = _order['status'] ?? 'pending';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: _statusBgColor(status),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _statusLabel(status),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _statusColor(status),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Action buttons based on status
          if (rawStatus == 'pending') ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _updateStatus('completed'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text('mark_completed'.tr()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _confirmCancel(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text('cancel_order'.tr()),
                  ),
                ),
              ],
            ),
          ] else if (rawStatus == 'completed') ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _updateStatus('delivered'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.info,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text('mark_delivered'.tr()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final phone = _order['customer_phone'] ?? '';
                      final name = _order['customer_name'] ?? '';
                      if (phone.isNotEmpty) {
                        _openWhatsApp(phone, 'order_pickup_message'.tr(namedArgs: {'name': name}));
                      }
                    },
                    icon: const Icon(Icons.chat, size: 18),
                    label: Text('send_pickup_msg'.tr()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (rawStatus == 'delivered') ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: AppColors.success, size: 22),
                const SizedBox(width: 8),
                Text(
                  'order_delivered_done'.tr(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ] else if (rawStatus == 'cancelled') ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cancel, color: AppColors.error, size: 22),
                const SizedBox(width: 8),
                Text(
                  'order_cancelled'.tr(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.error,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _confirmCancel() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('cancel_order'.tr()),
        content: Text('cancel_order_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('no'.tr()),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _updateStatus('cancelled');
            },
            child: Text('yes'.tr(),
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildMeasurementsCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header (tappable to expand/collapse)
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            onTap: () =>
                setState(() => _measurementsExpanded = !_measurementsExpanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.straighten, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'measurements'.tr(),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '${_measurements.length}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _measurementsExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          // Expandable content
          if (_measurementsExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _measurements.map((m) {
                  final data = m.measurements;
                  Map<String, dynamic> options = {};
                  try {
                    if (m.additionalOptions != null &&
                        m.additionalOptions!.isNotEmpty) {
                      options = json.decode(m.additionalOptions!)
                          as Map<String, dynamic>;
                    }
                  } catch (_) {}
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      Text(
                        m.garmentType.tr(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // 2-column measurement grid
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: data.entries
                            .where((e) =>
                                e.value != null &&
                                e.value.toString().isNotEmpty)
                            .map((e) => SizedBox(
                                  width: (MediaQuery.of(context).size.width -
                                          60) /
                                      2,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          e.key.tr(),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        '${e.value} ${'inches'.tr()}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ),
                      // Additional options
                      if (options.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        ...options.entries
                            .where((e) =>
                                e.value != null &&
                                e.value.toString().isNotEmpty)
                            .map((e) => Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    '${e.key.tr()}: ${e.value.toString().tr()}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                )),
                      ],
                      const SizedBox(height: 6),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _instructionsList(dynamic raw) {
    final items = _decodeInstructions(raw);
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map<Widget>((text) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ',
                        style: TextStyle(
                            fontSize: 14, color: AppColors.textPrimary)),
                    Expanded(
                      child: Text(
                        text,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  List<String> _decodeInstructions(dynamic raw) {
    if (raw == null) return [];
    final str = raw.toString();
    if (str.isEmpty) return [];
    try {
      final decoded = json.decode(str);
      if (decoded is List) {
        return decoded
            .map<String>((item) {
              if (item is Map && item['text'] != null) {
                return item['text'].toString();
              }
              return item.toString();
            })
            .where((t) => t.trim().isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return [str];
  }
}
