import 'dart:convert';

import 'package:url_launcher/url_launcher.dart';

import '../utils/app_logger.dart';
import '../utils/garment_labels.dart';
import '../utils/phone_utils.dart';

/// Why a WhatsApp send could not be started.
enum WhatsAppSendResult { sent, invalidNumber, launchFailed }

/// Builds and sends the customer-facing WhatsApp messages.
///
/// The order-confirmation text used to be built inline in the order-creation
/// screen, so it could only ever be sent at the moment the order was created —
/// if the tailor skipped it, the message was gone. Everything here is built
/// from a stored order row instead, so any message can be re-sent later from
/// the order screen or the dashboard.
class WhatsAppService {
  static final WhatsAppService _instance = WhatsAppService._internal();
  factory WhatsAppService() => _instance;
  WhatsAppService._internal();

  static const _divider = '━━━━━━━━━━━━━━━━━━━━━';

  /// Order-confirmation message ("your order has been placed").
  ///
  /// [order] is a stored order row (optionally joined with the customer, so it
  /// may carry `customer_name` / `customer_serial`). [shopProfile] is the local
  /// shop profile row.
  String buildOrderConfirmation({
    required Map<String, dynamic> order,
    Map<String, dynamic>? shopProfile,
    String? customerName,
    Object? customerSerial,
  }) {
    final name = customerName ?? (order['customer_name'] ?? '').toString();
    final serial = (customerSerial ?? order['customer_serial'] ?? '').toString();
    final garment = GarmentLabels.describe(
      stitchTypeValue: order['stitch_type']?.toString(),
      // A tailor-defined category's stitch_type is an opaque id; the name
      // snapshotted on the order is what the customer should read.
      categoryName: order['category_name']?.toString(),
      shirtSubType: order['shirt_sub_type']?.toString(),
      bottomType: order['bottom_type']?.toString(),
    );
    final colors = _colorsOf(order);
    final quantity = order['quantity']?.toString() ?? '1';

    final lines = <String>[
      '🧵 EzeeBook — Order Confirmation 🧵',
      _divider,
      'Assalam o Alaikum! ✨',
      'Your order has been placed successfully.',
      'آپ کا آرڈر کامیابی سے درج ہو گیا ہے۔',
      '',
      '👤 Customer: $name${serial.isNotEmpty ? ' (#$serial)' : ''}',
      '👔 Garment: $garment',
      '🔢 Quantity: $quantity suit(s)',
      if (colors.isNotEmpty) '🎨 Colors: $colors',
      '📅 Order Date: ${_formatDate(order['created_at'])}',
      '📅 Delivery Date: ${_formatDate(order['delivery_date'])}',
      '',
      'Thank you for choosing us!',
      'ہم پر اعتماد کرنے کا شکریہ! 🤲',
      _divider,
      ..._shopFooter(shopProfile),
    ];
    return lines.join('\n');
  }

  /// "Your order is ready" message, sent when the work is finished.
  ///
  /// Includes any remaining balance so the customer knows what to bring. This
  /// is customer-facing, unlike the worker PDF which deliberately omits money.
  String buildOrderReady({
    required Map<String, dynamic> order,
    Map<String, dynamic>? shopProfile,
    String? customerName,
  }) {
    final name = customerName ?? (order['customer_name'] ?? '').toString();
    final garment = GarmentLabels.describe(
      stitchTypeValue: order['stitch_type']?.toString(),
      // A tailor-defined category's stitch_type is an opaque id; the name
      // snapshotted on the order is what the customer should read.
      categoryName: order['category_name']?.toString(),
      shirtSubType: order['shirt_sub_type']?.toString(),
      bottomType: order['bottom_type']?.toString(),
    );
    final total = _toDouble(order['total_amount']);
    final advance = _toDouble(order['advance_payment']);
    final remaining = (total - advance) > 0 ? total - advance : 0.0;

    final lines = <String>[
      '🧵 EzeeBook — Order Ready 🧵',
      _divider,
      'Assalam o Alaikum${name.isNotEmpty ? ' $name' : ''}! ✨',
      'Your order is ready. Please collect it from the shop.',
      'آپ کا آرڈر تیار ہے۔ براہ کرم دکان سے وصول کریں۔',
      '',
      '👔 Garment: $garment',
      '🔢 Quantity: ${order['quantity']?.toString() ?? '1'}',
      if (remaining > 0)
        '💰 Remaining (Baqaya): Rs. ${remaining.toStringAsFixed(0)}',
      if (remaining <= 0 && total > 0) '✅ Fully Paid — شکریہ',
      '',
      'Thank you for choosing us!',
      'ہم پر اعتماد کرنے کا شکریہ! 🤲',
      _divider,
      ..._shopFooter(shopProfile),
    ];
    return lines.join('\n');
  }

  /// Open WhatsApp with [message] pre-filled for [phone].
  Future<WhatsAppSendResult> send({
    required String phone,
    required String message,
  }) async {
    final number = PhoneUtils.toWhatsAppFormat(phone);
    if (number == null || number.isEmpty) {
      return WhatsAppSendResult.invalidNumber;
    }
    final uri = Uri.parse(
      'https://wa.me/$number?text=${Uri.encodeComponent(message.trim())}',
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return ok ? WhatsAppSendResult.sent : WhatsAppSendResult.launchFailed;
    } catch (e, st) {
      AppLogger.error('WhatsAppService', 'launch failed',
          error: e, stackTrace: st);
      return WhatsAppSendResult.launchFailed;
    }
  }

  // ==================== helpers ====================

  List<String> _shopFooter(Map<String, dynamic>? shopProfile) {
    final shopName = (shopProfile?['shop_name'] ?? '').toString();
    final shopPhone = (shopProfile?['phone'] ?? '').toString();
    return [
      if (shopName.isNotEmpty) '✂️ $shopName',
      if (shopPhone.isNotEmpty) '📞 $shopPhone',
    ];
  }

  /// Colors are stored as a JSON array string; fall back to the raw value.
  String _colorsOf(Map<String, dynamic> order) {
    final raw = order['colors'];
    if (raw == null) return '';
    try {
      final decoded = json.decode(raw.toString());
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .join(', ');
      }
    } catch (_) {
      // not JSON — fall through
    }
    return raw.toString();
  }

  double _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// Render an ISO date (or `YYYY-MM-DD`) as `dd/MM/yyyy`.
  String _formatDate(Object? iso) {
    final s = iso?.toString() ?? '';
    if (s.isEmpty) return '-';
    try {
      final d = DateTime.parse(s).toLocal();
      return '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return s;
    }
  }
}
