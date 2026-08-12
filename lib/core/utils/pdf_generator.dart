import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'app_logger.dart';
import 'garment_labels.dart';

class PdfGenerator {
  /// The receipt font.
  ///
  /// Noto Naskh Arabic is used as the document's **base** font — for the Latin
  /// text too, which it covers in full. That is not a stylistic choice, it is
  /// the only arrangement that works:
  ///
  ///  * The `pdf` package shapes Arabic by rewriting letters into the Arabic
  ///    Presentation Forms-B block (U+FE70–FEFF). It only does this for the
  ///    base font, so an Urdu font registered as a `fontFallback` produces
  ///    unjoined, unreadable output (dart_pdf issue #1743).
  ///  * Nastaliq, which this used before, contains **none** of those 141
  ///    codepoints — it composes its letterforms from ligatures instead. Every
  ///    shaped Urdu word therefore mapped to missing glyphs, and receipts came
  ///    out as scattered dots wherever the tailor had typed Urdu: shop name,
  ///    customer name, garment, measurement labels.
  ///
  /// Helvetica stays registered as a fallback for anything Naskh lacks. That
  /// direction is safe: Latin needs no shaping.
  static pw.Font? _urduFont;
  static pw.Font? _urduFontBold;
  static bool _fontLoadAttempted = false;

  static Future<void> _ensureFonts() async {
    if (_fontLoadAttempted) return;
    _fontLoadAttempted = true;
    try {
      _urduFont = pw.Font.ttf(
          await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf'));
      _urduFontBold = pw.Font.ttf(
          await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf'));
    } catch (e, st) {
      // Never block a receipt on a missing font. Without it Urdu will not
      // render, but the order still prints in Latin.
      AppLogger.error('PdfGenerator', 'Urdu font load failed',
          error: e, stackTrace: st);
    }
  }

  /// Document theme: Urdu-capable base font where available, Helvetica if the
  /// asset could not be read.
  static pw.ThemeData _buildTheme() {
    final base = _urduFont;
    final bold = _urduFontBold ?? _urduFont;
    if (base == null) {
      return pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
      );
    }
    return pw.ThemeData.withFont(
      base: base,
      bold: bold,
      // Naskh ships no italic face; reusing the upright one is better than
      // letting the package synthesise a slant across Arabic joins.
      italic: base,
      boldItalic: bold,
      fontFallback: [pw.Font.helvetica(), pw.Font.helveticaBold()],
    );
  }

  // ==================== Urdu text direction ====================
  //
  // This is the switch that makes Urdu readable, and it is easy to miss.
  //
  // The `pdf` package only shapes and reorders Arabic script when the *Text
  // widget* is right-to-left (`pdf/lib/src/widgets/text.dart`):
  //
  //     useBidi && _textDirection == TextDirection.rtl
  //         ? bidi.logicalToVisual(span.text!)   // joined, visual order
  //         : span.text                          // raw, unjoined
  //
  // Left at the default (ltr), Urdu prints as correct but *unjoined* letters in
  // logical order — which reads backwards to anyone who reads Urdu. Getting the
  // font right was necessary but did nothing on its own.
  //
  // Direction is chosen per string rather than set document-wide, because the
  // package's rtl path also reverses word order: applying it to English would
  // turn "Thank you for choosing" into "choosing for you Thank". Strings that
  // mix both scripts are therefore never passed through as one run — they are
  // split into single-script pieces at the call sites below.

  /// Arabic script, including the presentation forms the shaper emits.
  static bool _hasArabic(String s) => s.runes.any((r) =>
      (r >= 0x0600 && r <= 0x06FF) || // Arabic (Urdu lives here)
      (r >= 0x0750 && r <= 0x077F) || // Arabic Supplement
      (r >= 0xFB50 && r <= 0xFDFF) || // Presentation Forms-A
      (r >= 0xFE70 && r <= 0xFEFF)); // Presentation Forms-B

  static pw.TextDirection _dirOf(String s) =>
      _hasArabic(s) ? pw.TextDirection.rtl : pw.TextDirection.ltr;

  /// A [pw.Text] that renders Urdu correctly and leaves Latin untouched.
  /// Use this for anything the tailor typed.
  static pw.Widget _t(
    String text, {
    pw.TextStyle? style,
    pw.TextAlign? textAlign,
  }) {
    return pw.Text(
      text,
      style: style,
      textAlign: textAlign,
      textDirection: _dirOf(text),
    );
  }

  /// A field's name for the receipt: the tailor's own name, plus the Urdu one
  /// underneath when they entered both.
  ///
  /// Two lines rather than "English (اردو)" on one, so the two scripts never
  /// share a run and the bidi pass cannot reorder the English half.
  static pw.Widget _labelCell(
    String key,
    Map<String, String> labels,
    Map<String, String> urduLabels, {
    double fontSize = 10,
  }) {
    final primary = labels[key]?.trim() ?? '';
    final base =
        primary.isNotEmpty ? primary : GarmentLabels.measurementLabel(key);
    final urdu = urduLabels[key]?.trim() ?? '';
    final line = _t(base, style: pw.TextStyle(fontSize: fontSize));

    // A field named only in Urdu has the same string in both maps; printing it
    // twice would be noise.
    if (urdu.isEmpty || urdu == base) return line;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        line,
        _t(urdu,
            style: pw.TextStyle(fontSize: fontSize - 0.5, color: _mutedDark)),
      ],
    );
  }

  /// SQLite has no boolean type, so flags round-trip as `1`/`0` (and cloud
  /// backups may carry real bools or strings). Comparing such a value with
  /// `== true` silently fails, which previously hid the whole dupatta section
  /// from every receipt. Normalise all of those spellings here.
  static bool _isTrue(Object? v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v?.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

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
    /// Name snapshotted on the order. Wins over [stitchType], which for a
    /// tailor-defined category is an opaque id.
    String? categoryName,
    String? shirtSubType,
    String? bottomType,
    String? bottomWaistband,
    String? elasticWidth,
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
    await _ensureFonts();

    final pdf = pw.Document(theme: _buildTheme());

    final boldStyle = pw.TextStyle(
      fontSize: 11,
      fontWeight: pw.FontWeight.bold,
    );
    final normalStyle = pw.TextStyle(fontSize: 11);
    final headerStyle = pw.TextStyle(
      fontSize: 14,
      fontWeight: pw.FontWeight.bold,
      color: _tealDark,
    );

    final shopName = (shopProfile['shop_name'] ?? 'My Shop').toString();
    final ownerName = (shopProfile['owner_name'] ?? '').toString();
    final phone = (shopProfile['phone'] ?? '').toString();

    final garmentStr = [
      _garmentLabel(stitchType, categoryName: categoryName),
      if (shirtSubType != null && shirtSubType.isNotEmpty)
        _subTypeLabel(shirtSubType),
    ].where((s) => s.isNotEmpty).join(' | ');
    final bottomStr = [
      if (bottomType != null && bottomType.isNotEmpty)
        _subTypeLabel(bottomType),
      if (bottomWaistband != null && bottomWaistband.isNotEmpty)
        GarmentLabels.titleCase(bottomWaistband),
      // Elastic/belt width is captured during measurement but never used to
      // reach the worker's copy — without it the waistband cannot be sewn.
      if (elasticWidth != null && elasticWidth.isNotEmpty)
        '${GarmentLabels.titleCase(elasticWidth)}"',
    ].join(' | ');
    // Normalise the groups once rather than re-decoding the snapshot per widget.
    // A tailor-defined group arrives under an opaque `cat:<id>` and carries its
    // real heading and field names in its options snapshot.
    final groups = [
      for (final g in measurementGroups)
        _MeasurementGroup(
          heading: GarmentLabels.groupLabel(
            g['garmentType'] as String? ?? '',
            g['additionalOptions'] as Map<String, dynamic>?,
          ),
          measurements: (g['measurements'] as Map<String, dynamic>?) ?? const {},
          options: GarmentLabels.visibleOptions(
              g['additionalOptions'] as Map<String, dynamic>?),
          labels: GarmentLabels.labelSnapshot(
              g['additionalOptions'] as Map<String, dynamic>?),
          urduLabels: GarmentLabels.urduLabelSnapshot(
              g['additionalOptions'] as Map<String, dynamic>?),
        ),
    ];

    // One colour is captured PER SUIT, so a 3-suit order has 3 colours.
    // Flattening them lost which suit is which; number them when it matters.
    final colorsStr = colors.isEmpty
        ? '-'
        : (colors.length > 1
            ? [
                for (var i = 0; i < colors.length; i++) '${i + 1}. ${colors[i]}'
              ].join('   ')
            : colors.first);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          // ── HEADER (centered, prominent shop branding) ──
          pw.SizedBox(height: 4),
          pw.Center(
            child: _t(
              shopName,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 24,
                color: _brand,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (ownerName.isNotEmpty || phone.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Center(
              child: _t(
                [
                  if (ownerName.isNotEmpty) ownerName,
                  if (phone.isNotEmpty) phone,
                ].join('  |  '),
                style: pw.TextStyle(
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
                    fontWeight: pw.FontWeight.bold,
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
                // A tailor-defined category has no shirt/bottom split, so an
                // empty "Bottom: -" would just be noise on the worker's copy.
                if (bottomStr.isNotEmpty) _inlineLabel('Bottom', bottomStr),
                _inlineLabel('Quantity', quantity.toString()),
                _inlineLabel('Color', colorsStr),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // ── MEASUREMENTS ──
          if (groups.isNotEmpty) ...[
            _sectionHeader('Measurements', headerStyle),
            pw.SizedBox(height: 6),
            for (final group in groups) ...[
              pw.SizedBox(height: 8),
              _t(
                group.heading,
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12,
                  color: _brand,
                ),
              ),
              pw.SizedBox(height: 4),
              _buildMeasurementsTable(
                  group.measurements, group.labels, group.urduLabels),
              if (group.options.isNotEmpty)
                _buildAdditionalOptionsBlock(
                    group.options, group.labels, group.urduLabels),
            ],
            pw.SizedBox(height: 6),
          ],

          // ── DUPATTA DETAILS ──
          if (dupattaDetails != null &&
              _isTrue(dupattaDetails['included'])) ...[
            _sectionHeader('Dupatta Details', headerStyle),
            pw.SizedBox(height: 6),
            if ((dupattaDetails['finishing']?.toString() ?? '').isNotEmpty)
              _keyValue('Finishing',
                  _formatFinishing(dupattaDetails['finishing'].toString()),
                  boldStyle, normalStyle),
            if (dupattaDetails['pico_type'] != null)
              _keyValue('Pico Type',
                  GarmentLabels.titleCase(dupattaDetails['pico_type'].toString()),
                  boldStyle, normalStyle),
            if (dupattaDetails['pico_coverage'] != null)
              _keyValue('Pico Coverage',
                  GarmentLabels.titleCase(
                      dupattaDetails['pico_coverage'].toString()),
                  boldStyle, normalStyle),
            if (dupattaDetails['piping_coverage'] != null)
              _keyValue('Piping Coverage',
                  GarmentLabels.titleCase(
                      dupattaDetails['piping_coverage'].toString()),
                  boldStyle, normalStyle),
            if (dupattaDetails['lace_coverage'] != null)
              _keyValue('Lace Coverage',
                  GarmentLabels.titleCase(
                      dupattaDetails['lace_coverage'].toString()),
                  boldStyle, normalStyle),
            if (_isTrue(dupattaDetails['lace_provided_by_customer']))
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
                child: _bullet(item, normalStyle),
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
                  child: _bullet(line.trim(), normalStyle),
                ),
          ],

          // ── FOOTER (Thank You) ──
          pw.SizedBox(height: 20),
          pw.Container(height: 1, color: _brand),
          pw.SizedBox(height: 8),
          pw.Center(
            // Split so an Urdu shop name does not drag the English sentence
            // through the bidi pass and come out word-reversed.
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text('Thank you for choosing ',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 11,
                      color: _brand,
                    )),
                _t(shopName,
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 11,
                      color: _brand,
                    )),
              ],
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              'Generated by EzeeBook  |  ${_formatDateForFooter()}',
              style: pw.TextStyle(
                fontStyle: pw.FontStyle.italic,
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
        fontWeight: pw.FontWeight.bold,
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
              fontWeight: pw.FontWeight.bold,
              fontSize: 10,
            ),
          ),
          pw.Expanded(
            child: _t(
              value,
              style: pw.TextStyle(
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
            fontWeight: pw.FontWeight.bold,
            fontSize: 10,
            color: _mutedDark,
          ),
        ),
        _t(
          value,
          style: pw.TextStyle(
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
          pw.Expanded(child: _t(value, style: normalStyle)),
        ],
      ),
    );
  }

  static pw.Widget _buildMeasurementsTable(
    Map<String, dynamic> data,
    Map<String, String> labels,
    Map<String, String> urduLabels,
  ) {
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
                child: _labelCell(entries[i].key, labels, urduLabels),
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

  static String _garmentLabel(String type, {String? categoryName}) {
    final snapshot = categoryName?.trim() ?? '';
    if (snapshot.isNotEmpty) return snapshot;
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
    Map<String, dynamic> options,
    Map<String, String> labels,
    Map<String, String> urduLabels,
  ) {
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
            // Name and value are rendered as their own runs: either can be
            // Urdu, and a single mixed string would be reordered as a whole.
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _labelCell(e.key, labels, urduLabels),
                  pw.Text(':  ', style: const pw.TextStyle(fontSize: 10)),
                  pw.Expanded(
                    child: _t(displayValue,
                        style: const pw.TextStyle(fontSize: 10)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// A bulleted instruction line. The dash is its own run so a dictated Urdu
  /// instruction does not carry it to the wrong end of the line.
  static pw.Widget _bullet(String text, pw.TextStyle style) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('-  ', style: style),
        pw.Expanded(child: _t(text, style: style)),
      ],
    );
  }

  /// Dupatta finishing is stored as a comma-joined list ("pico,lace").
  /// Render it as "Pico, Lace" rather than dumping the raw string.
  static String _formatFinishing(String raw) {
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map(GarmentLabels.titleCase)
        .join(', ');
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

}

/// One measurement group ready to render: heading, values, options and the
/// label snapshot needed to name a tailor-defined field.
class _MeasurementGroup {
  final String heading;
  final Map<String, dynamic> measurements;
  final Map<String, dynamic> options;
  final Map<String, String> labels;
  final Map<String, String> urduLabels;

  const _MeasurementGroup({
    required this.heading,
    required this.measurements,
    required this.options,
    required this.labels,
    required this.urduLabels,
  });
}
