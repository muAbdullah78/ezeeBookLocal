import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfGenerator {
  static const _teal = PdfColor.fromInt(0xFF26A69A);
  static const _tealDark = PdfColor.fromInt(0xFF00897B);
  static const _lightGrey = PdfColor.fromInt(0xFFE0E0E0);
  static const _brand = PdfColor.fromInt(0xFF1B8779);
  static const _panelBg = PdfColor.fromInt(0xFFF5F5F5);
  static const _muted = PdfColor.fromInt(0xFF666666);
  static const _mutedDark = PdfColor.fromInt(0xFF555555);
  static const _footerGrey = PdfColor.fromInt(0xFF999999);

  static Future<Uint8List> generateOrderPdf({
    required Map<String, dynamic> shopProfile,
    required String customerName,
    required String customerPhone,
    required int customerSerialNumber,
    required String customerGender,
    required String stitchType,
    String? shirtSubType,
    String? bottomType,
    String? bottomWaistband,
    required int quantity,
    required List<String> colors,
    required String orderDate,
    required String deliveryDate,
    required String status,
    required List<Map<String, dynamic>> measurementGroups,
    Map<String, dynamic>? dupattaDetails,
    List<String>? extraInstructions,
    String? specialInstructions,
  }) async {
    final pdf = pw.Document();

    // TODO: Load Urdu font for bilingual PDF support
    // final fontData = await rootBundle.load('assets/fonts/NotoNastaliqUrdu-Regular.ttf');
    // final urduFont = pw.Font.ttf(fontData);

    final boldStyle = pw.TextStyle(
      fontSize: 11,
      fontWeight: pw.FontWeight.bold,
    );
    final normalStyle = const pw.TextStyle(fontSize: 11);
    final headerStyle = pw.TextStyle(
      fontSize: 14,
      fontWeight: pw.FontWeight.bold,
      color: _tealDark,
    );

    final shopName = (shopProfile['shop_name'] ?? 'My Shop').toString();
    final ownerName = (shopProfile['owner_name'] ?? '').toString();
    final phone = (shopProfile['phone'] ?? '').toString();

    final garmentStr = [
      _garmentLabel(stitchType),
      if (shirtSubType != null && shirtSubType.isNotEmpty)
        _subTypeLabel(shirtSubType),
    ].where((s) => s.isNotEmpty).join(' | ');
    final bottomStr = [
      if (bottomType != null && bottomType.isNotEmpty)
        _subTypeLabel(bottomType),
      if (bottomWaistband != null && bottomWaistband.isNotEmpty)
        bottomWaistband,
    ].join(' | ');
    final colorsStr = colors.isEmpty ? '-' : colors.join(', ');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          // ── HEADER (centered, prominent shop branding) ──
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              shopName,
              style: pw.TextStyle(
                font: pw.Font.helveticaBold(),
                fontSize: 24,
                color: _brand,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (ownerName.isNotEmpty || phone.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                [
                  if (ownerName.isNotEmpty) ownerName,
                  if (phone.isNotEmpty) phone,
                ].join('  |  '),
                style: pw.TextStyle(
                  font: pw.Font.helvetica(),
                  fontSize: 10,
                  color: _muted,
                ),
              ),
            ),
          ],
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(
                child: pw.Container(height: 1, color: _brand),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10),
                child: pw.Text(
                  'ORDER RECEIPT',
                  style: pw.TextStyle(
                    font: pw.Font.helveticaBold(),
                    fontSize: 11,
                    color: _brand,
                    letterSpacing: 2,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Container(height: 1, color: _brand),
              ),
            ],
          ),
          pw.SizedBox(height: 14),

          // ── TWO-COLUMN: Customer Details | Order Details ──
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _columnHeader('Customer Details'),
                    pw.SizedBox(height: 4),
                    _miniRow('Name',
                        '$customerName  (#$customerSerialNumber)'),
                    if (customerPhone.isNotEmpty)
                      _miniRow('Phone', customerPhone),
                    _miniRow('Gender',
                        customerGender == 'male' ? 'Male' : 'Female'),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _columnHeader('Order Details'),
                    pw.SizedBox(height: 4),
                    _miniRow('Order Date', orderDate),
                    _miniRow('Delivery Date', deliveryDate),
                    _miniRow('Status', _statusLabel(status)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),

          // ── GARMENT SUMMARY (inline row) ──
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: _panelBg,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _inlineLabel('Garment', garmentStr.isEmpty ? '-' : garmentStr),
                _inlineLabel('Bottom', bottomStr.isEmpty ? '-' : bottomStr),
                _inlineLabel('Quantity', quantity.toString()),
                _inlineLabel('Color', colorsStr),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // ── MEASUREMENTS ──
          if (measurementGroups.isNotEmpty) ...[
            _sectionHeader('Measurements', headerStyle),
            pw.SizedBox(height: 6),
            for (final group in measurementGroups) ...[
              pw.SizedBox(height: 8),
              pw.Text(
                _formatGarmentName(group['garmentType'] as String? ?? ''),
                style: pw.TextStyle(
                  font: pw.Font.helveticaBold(),
                  fontSize: 12,
                  color: _brand,
                ),
              ),
              pw.SizedBox(height: 4),
              _buildMeasurementsTable(
                  group['measurements'] as Map<String, dynamic>),
              if ((group['additionalOptions'] as Map<String, dynamic>)
                  .isNotEmpty)
                _buildAdditionalOptionsBlock(
                    group['additionalOptions'] as Map<String, dynamic>),
            ],
            pw.SizedBox(height: 6),
          ],

          // ── DUPATTA DETAILS ──
          if (dupattaDetails != null &&
              dupattaDetails['included'] == true) ...[
            _sectionHeader('Dupatta Details', headerStyle),
            pw.SizedBox(height: 6),
            if (dupattaDetails['finishing'] != null)
              _keyValue('Finishing', dupattaDetails['finishing'].toString(),
                  boldStyle, normalStyle),
            if (dupattaDetails['pico_type'] != null)
              _keyValue('Pico Type', dupattaDetails['pico_type'].toString(),
                  boldStyle, normalStyle),
            if (dupattaDetails['pico_coverage'] != null)
              _keyValue('Pico Coverage',
                  dupattaDetails['pico_coverage'].toString(),
                  boldStyle, normalStyle),
            if (dupattaDetails['piping_coverage'] != null)
              _keyValue('Piping Coverage',
                  dupattaDetails['piping_coverage'].toString(),
                  boldStyle, normalStyle),
            if (dupattaDetails['lace_coverage'] != null)
              _keyValue('Lace Coverage',
                  dupattaDetails['lace_coverage'].toString(),
                  boldStyle, normalStyle),
            if (dupattaDetails['lace_provided_by_customer'] == true)
              pw.Text('Lace provided by customer', style: normalStyle),
            pw.SizedBox(height: 14),
          ],

          // ── EXTRA INSTRUCTIONS (from measurement phase) ──
          if (extraInstructions != null && extraInstructions.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _sectionHeader('Extra Instructions', headerStyle),
            pw.SizedBox(height: 4),
            for (final item in extraInstructions)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2, left: 4),
                child: pw.Text('-  $item', style: normalStyle),
              ),
          ],

          // ── SPECIAL INSTRUCTIONS (from checkout) ──
          if (specialInstructions != null &&
              specialInstructions.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _sectionHeader('Special Instructions', headerStyle),
            pw.SizedBox(height: 4),
            for (final line in specialInstructions.split('\n'))
              if (line.trim().isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2, left: 4),
                  child: pw.Text('-  ${line.trim()}', style: normalStyle),
                ),
          ],

          // ── FOOTER (Thank You) ──
          pw.SizedBox(height: 20),
          pw.Container(height: 1, color: _brand),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              'Thank you for choosing $shopName',
              style: pw.TextStyle(
                font: pw.Font.helveticaBold(),
                fontSize: 11,
                color: _brand,
              ),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              'Generated by EzeeBook  |  ${_formatDateForFooter()}',
              style: pw.TextStyle(
                font: pw.Font.helveticaOblique(),
                fontSize: 8,
                color: _footerGrey,
              ),
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ── Helper builders ──

  static pw.Widget _sectionHeader(String title, pw.TextStyle style) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _lightGrey, width: 0.5),
        ),
      ),
      child: pw.Text(title, style: style),
    );
  }

  static pw.Widget _columnHeader(String text) {
    return pw.Text(
      text,
      style: pw.TextStyle(
        font: pw.Font.helveticaBold(),
        fontSize: 12,
        color: _brand,
      ),
    );
  }

  static pw.Widget _miniRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '$label: ',
            style: pw.TextStyle(
              font: pw.Font.helveticaBold(),
              fontSize: 10,
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                font: pw.Font.helvetica(),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _inlineLabel(String label, String value) {
    return pw.Row(
      children: [
        pw.Text(
          '$label: ',
          style: pw.TextStyle(
            font: pw.Font.helveticaBold(),
            fontSize: 10,
            color: _mutedDark,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            font: pw.Font.helvetica(),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  static pw.Widget _keyValue(
    String key,
    String value,
    pw.TextStyle boldStyle,
    pw.TextStyle normalStyle,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text('$key:', style: boldStyle),
          ),
          pw.Expanded(child: pw.Text(value, style: normalStyle)),
        ],
      ),
    );
  }

  static pw.Widget _buildMeasurementsTable(Map<String, dynamic> data) {
    final entries = data.entries
        .where((e) => e.value != null && e.value.toString().isNotEmpty)
        .toList();

    if (entries.isEmpty) return pw.SizedBox();

    return pw.Table(
      border: pw.TableBorder.all(color: _lightGrey, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.5),
        1: pw.FlexColumnWidth(1.0),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _teal),
          children: [
            pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: pw.Text(
                'Measurement',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
            ),
            pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: pw.Text(
                'Value (inches)',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
            ),
          ],
        ),
        for (int i = 0; i < entries.length; i++)
          pw.TableRow(
            decoration: i % 2 == 1
                ? const pw.BoxDecoration(color: _panelBg)
                : null,
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                child: pw.Text(
                  _readableKey(entries[i].key),
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                child: pw.Text(
                  entries[i].value.toString(),
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ── Formatting helpers ──

  static String _readableKey(String key) {
    // Convert snake_case to Title Case
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) =>
            w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  static String _garmentLabel(String type) {
    switch (type) {
      case 'full_suit':
        return 'Full Suit';
      case 'naap_suit':
        return 'Naap Suit';
      case 'only_shirt':
        return 'Only Shirt';
      case 'only_shalwar_trouser':
        return 'Only Shalwar/Trouser';
      default:
        return _readableKey(type);
    }
  }

  static String _subTypeLabel(String type) {
    switch (type) {
      case 'kameez':
        return 'Kameez';
      case 'kurti':
        return 'Kurti';
      case 'short_shirt':
        return 'Short Shirt';
      case 'choli':
        return 'Choli';
      case 'shalwar':
        return 'Shalwar';
      case 'trouser':
        return 'Trouser';
      case 'pajama':
        return 'Pajama';
      case 'sharara':
        return 'Sharara';
      case 'gharara':
        return 'Gharara';
      default:
        return _readableKey(type);
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'completed':
        return 'Completed';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      case 'overdue':
        return 'Overdue';
      default:
        return _readableKey(status);
    }
  }

  static String _formatDateForFooter() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

  static pw.Widget _buildAdditionalOptionsBlock(
      Map<String, dynamic> options) {
    final validEntries = options.entries
        .where((e) => e.value != null && e.value.toString().isNotEmpty)
        .toList();
    if (validEntries.isEmpty) return pw.SizedBox();

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4, bottom: 2),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Additional Options:',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: _tealDark,
            ),
          ),
          pw.SizedBox(height: 2),
          ...validEntries.map((e) {
            final displayValue = _formatOptionValue(e.value);
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text(
                '${_formatOptionKey(e.key)}: $displayValue',
                style: const pw.TextStyle(fontSize: 10),
              ),
            );
          }),
        ],
      ),
    );
  }

  static String _formatOptionKey(String key) {
    return key
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  static String _formatOptionValue(dynamic value) {
    if (value == null) return '';
    if (value is bool) return value ? 'Yes' : 'No';
    final s = value.toString();
    if (s.contains('_')) {
      return s
          .split('_')
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
    }
    return s;
  }

  static String _formatGarmentName(String garmentType) {
    if (garmentType.isEmpty) return '';
    return garmentType
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
