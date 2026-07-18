import 'dart:async';
import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/error_reporter.dart';
import '../utils/app_logger.dart';
import 'subscription_service.dart';

/// Type of event reported via [BillingService.onPurchaseComplete].
/// Distinguishing pending from error matters: pending purchases will
/// resolve later (e.g. cash payments via Google Play), so the screen
/// must NOT treat them as failures.
enum BillingEvent { success, error, cancelled, pending }

class BillingService {
  static final BillingService _instance = BillingService._internal();
  factory BillingService() => _instance;
  BillingService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  // Google Play product IDs — must match what is created in Play Console
  static const String monthlyProductId = 'ezeebook_monthly';
  static const String quarterlyProductId = 'ezeebook_quarterly';
  static const String yearlyProductId = 'ezeebook_yearly';

  // Map our plan IDs to Google Play product IDs
  static const Map<String, String> planToProductId = {
    'monthly': monthlyProductId,
    'quarterly': quarterlyProductId,
    'yearly': yearlyProductId,
  };

  List<ProductDetails> _products = [];
  bool _isAvailable = false;

  // Callback for when purchase completes — set by screens that initiate purchases
  void Function(String planId, BillingEvent event, String message)?
      onPurchaseComplete;

  /// Initialize billing — call once on app start. Safe to call on Windows (returns early).
  Future<void> initialize() async {
    if (!Platform.isAndroid) {
      _isAvailable = false;
      return;
    }

    try {
      _isAvailable = await _iap.isAvailable();
      if (!_isAvailable) return;

      // Listen to purchase updates
      _purchaseSubscription = _iap.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: _onPurchaseStreamDone,
        onError: _onPurchaseError,
      );

      await _loadProducts();
    } catch (_) {
      _isAvailable = false;
    }
  }

  Future<void> _loadProducts() async {
    if (!_isAvailable) return;

    final Set<String> productIds = {
      monthlyProductId,
      quarterlyProductId,
      yearlyProductId,
    };

    try {
      final ProductDetailsResponse response =
          await _iap.queryProductDetails(productIds);
      if (response.error == null) {
        _products = response.productDetails;
      }
    } catch (_) {
      // Products not yet created in Play Console — expected during development
      _products = [];
    }
  }

  bool get isAvailable => _isAvailable;

  ProductDetails? getProductForPlan(String planId) {
    final productId = planToProductId[planId];
    if (productId == null) return null;
    try {
      return _products.firstWhere((p) => p.id == productId);
    } catch (_) {
      return null;
    }
  }

  List<ProductDetails> get products => _products;

  /// Initiate a subscription purchase via Google Play.
  Future<bool> purchaseSubscription(String planId) async {
    if (!_isAvailable) {
      onPurchaseComplete?.call(planId, BillingEvent.error,
          'Google Play is not available on this device');
      return false;
    }

    final product = getProductForPlan(planId);
    if (product == null) {
      onPurchaseComplete?.call(planId, BillingEvent.error,
          'Product not found. Please try again later.');
      return false;
    }

    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);

    try {
      return await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      onPurchaseComplete?.call(planId, BillingEvent.error, 'Purchase failed: $e');
      return false;
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    for (final purchase in purchaseDetailsList) {
      _handlePurchase(purchase);
    }
  }

  Future<void> _handlePurchase(PurchaseDetails purchase) async {
    if (purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored) {
      // Invert planToProductId for a nullable lookup — unknown products error
      // rather than silently defaulting to 'monthly'.
      final planId = planToProductId.entries
          .firstWhere(
            (e) => e.value == purchase.productID,
            orElse: () => const MapEntry('', ''),
          )
          .key;

      if (planId.isEmpty) {
        AppLogger.error('BillingService',
            'Unknown product ID: ${purchase.productID}');
        onPurchaseComplete?.call('', BillingEvent.error, 'Unknown product');
        return;
      }

      final result = await _verifyPurchase(purchase, planId);
      if (!result.valid) {
        AppLogger.error('BillingService',
            'Server verification failed: ${result.reason}');
        onPurchaseComplete?.call(planId, BillingEvent.error,
            'Purchase verification failed: ${result.reason}');
        // Do NOT acknowledge with Google — let it retry later
        return;
      }

      // Verified. Pass server-provided expiry and token to createSubscription.
      final created = await SubscriptionService().createSubscription(
        planId,
        paymentMethod: 'play_billing',
        verifiedExpiresAt: result.expiresAt,
        purchaseToken: purchase.verificationData.serverVerificationData,
        autoRenewing: result.autoRenewing,
      );

      if (created) {
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        onPurchaseComplete?.call(planId, BillingEvent.success, '');
      } else {
        // Verification succeeded but subscription record failed to save.
        // Don't acknowledge with Google — retry on next app open.
        AppLogger.error('BillingService',
            'createSubscription failed after verification succeeded');
        onPurchaseComplete?.call(planId, BillingEvent.error,
            'Could not save subscription');
      }
    } else if (purchase.status == PurchaseStatus.error) {
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
      onPurchaseComplete?.call(
          '', BillingEvent.error, purchase.error?.message ?? 'Purchase error');
    } else if (purchase.status == PurchaseStatus.canceled) {
      onPurchaseComplete?.call('', BillingEvent.cancelled, 'Purchase cancelled');
    } else if (purchase.status == PurchaseStatus.pending) {
      // CRITICAL: pending is NOT an error. Just inform.
      onPurchaseComplete?.call(
        '',
        BillingEvent.pending,
        'Payment pending. We will activate your subscription as soon as it is confirmed.',
      );
    }
  }

  /// Verifies the purchase server-side via our verify-receipt Edge Function.
  /// Returns a VerifyResult with validity + verified expiry timestamp from the server.
  ///
  /// In Session 5 the Edge Function is a STUB that accepts any authenticated
  /// request. Session 6 will plug in real Google Play Developer API verification.
  Future<VerifyResult> _verifyPurchase(
      PurchaseDetails purchase, String planId) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'verify-receipt',
        body: {
          'purchase_token': purchase.verificationData.serverVerificationData,
          'product_id': purchase.productID,
          'plan_id': planId,
        },
      ).timeout(const Duration(seconds: 15));

      if (response.status != 200) {
        AppLogger.error('BillingService',
            'verify-receipt returned status ${response.status}: ${response.data}');
        return VerifyResult(valid: false, reason: 'server_error');
      }

      final data = response.data;
      if (data is! Map) {
        AppLogger.error('BillingService',
            'verify-receipt returned unexpected shape: $data');
        return VerifyResult(valid: false, reason: 'invalid_response');
      }

      final valid = data['valid'] == true;
      if (!valid) {
        return VerifyResult(
          valid: false,
          reason: data['reason']?.toString() ?? 'unknown',
        );
      }

      final sub = data['subscription'];
      if (sub is! Map) {
        AppLogger.error('BillingService',
            'verify-receipt valid=true but no subscription data');
        return VerifyResult(valid: false, reason: 'invalid_response');
      }

      final expiresAtStr = sub['expires_at']?.toString();
      if (expiresAtStr == null) {
        return VerifyResult(valid: false, reason: 'invalid_response');
      }

      final expiresAt = DateTime.tryParse(expiresAtStr);
      if (expiresAt == null) {
        return VerifyResult(valid: false, reason: 'invalid_response');
      }

      return VerifyResult(
        valid: true,
        expiresAt: expiresAt.toUtc(),
        autoRenewing: sub['auto_renewing'] == true,
      );
    } on TimeoutException {
      AppLogger.error('BillingService', 'verify-receipt timeout');
      return VerifyResult(valid: false, reason: 'timeout');
    } catch (e, st) {
      AppLogger.error('BillingService', 'verify-receipt failed',
          error: e, stackTrace: st);
      await ErrorReporter.reportError(e, st,
          hint: 'subscription_verify',
          context: {
            'billing': {'plan_id': planId, 'product_id': purchase.productID}
          });
      return VerifyResult(valid: false, reason: 'network_error');
    }
  }

  /// Restore previous purchases (reinstall / device switch).
  Future<void> restorePurchases() async {
    if (!_isAvailable) return;
    try {
      await _iap.restorePurchases();
    } catch (_) {}
  }

  void _onPurchaseStreamDone() {
    _purchaseSubscription?.cancel();
  }

  void _onPurchaseError(dynamic error) {
    // Log silently
  }

  void dispose() {
    _purchaseSubscription?.cancel();
  }
}

class VerifyResult {
  final bool valid;
  final String? reason;
  final DateTime? expiresAt;
  final bool autoRenewing;

  VerifyResult({
    required this.valid,
    this.reason,
    this.expiresAt,
    this.autoRenewing = false,
  });
}
