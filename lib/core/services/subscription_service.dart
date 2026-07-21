import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../services/error_reporter.dart';
import '../database/database_helper.dart';
import '../utils/app_logger.dart';
import 'time_service.dart';

class SubscriptionService {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  final _client = Supabase.instance.client;
  final _db = DatabaseHelper();

  String? get _userId => _client.auth.currentUser?.id;

  /// Local preview period. No Play Console trial offer is configured — users
  /// pay immediately on subscribe. This 72-hour window lets new signups
  /// explore the app before subscribing. It is NOT a 14-day trial and NOT a
  /// Play grace period; keep this number in sync with the store listing.
  static const Duration kFreePreviewDuration = Duration(hours: 72);

  // Hardcoded plans — used when offline or Supabase fetch fails
  static const List<Map<String, dynamic>> defaultPlans = [
    {
      'id': 'monthly',
      'display_name': 'Monthly',
      'duration_months': 1,
      'price_pkr': 950,
      'is_active': true,
    },
    {
      'id': 'quarterly',
      'display_name': '3 Months',
      'duration_months': 3,
      'price_pkr': 2500,
      'is_active': true,
    },
    {
      'id': 'yearly',
      'display_name': '12 Months',
      'duration_months': 12,
      'price_pkr': 9000,
      'is_active': true,
    },
  ];

  /// Check if user has an active subscription.
  /// 1. Resolve trusted time (TimeService); if unavailable, return false
  /// 2. Check local SQLite first (fast, offline-friendly)
  /// 3. If not found locally, check Supabase cloud
  /// 4. If found in cloud, cache locally
  Future<bool> hasActiveSubscription() async {
    final trustedNow = await TimeService().trustedNow();
    if (trustedNow == null) return false;

    // Check local first (fast path)
    final local = await _db.getActiveSubscription(trustedNow);
    if (local != null) return true;

    // Check cloud
    try {
      if (_userId == null) return false;
      final cloud = await _client
          .from('user_subscriptions')
          .select()
          .eq('user_id', _userId!)
          .eq('status', 'active')
          .gte('end_date', trustedNow.toIso8601String())
          .order('end_date', ascending: false)
          .limit(1)
          .maybeSingle();

      if (cloud != null) {
        final localData = {
          'id': cloud['id'],
          'plan_id': cloud['plan_id'],
          'status': cloud['status'],
          'start_date': cloud['start_date'],
          'end_date': cloud['end_date'],
          'promo_code_used': cloud['promo_code_used'],
          'created_at': cloud['created_at'],
          'updated_at': cloud['updated_at'],
        };
        try {
          await _db.insertSubscription(localData);
        } catch (_) {
          AppLogger.info('SubscriptionService',
              'hasActiveSubscription: insert failed, falling back to update');
          await _db.updateSubscription(cloud['id'], localData);
        }
        return true;
      }
    } catch (e, st) {
      AppLogger.error('SubscriptionService',
          'hasActiveSubscription cloud check failed',
          error: e, stackTrace: st);
      // Network error — local already returned false above
    }

    return false;
  }

  /// Get current active subscription details
  Future<Map<String, dynamic>?> getCurrentSubscription() async {
    final trustedNow = await TimeService().trustedNow();
    if (trustedNow == null) return null;

    final local = await _db.getActiveSubscription(trustedNow);
    if (local != null) return local;

    try {
      if (_userId == null) return null;
      final cloud = await _client
          .from('user_subscriptions')
          .select()
          .eq('user_id', _userId!)
          .eq('status', 'active')
          .gte('end_date', trustedNow.toIso8601String())
          .order('end_date', ascending: false)
          .limit(1)
          .maybeSingle();

      if (cloud != null) {
        final localData = {
          'id': cloud['id'],
          'plan_id': cloud['plan_id'],
          'status': cloud['status'],
          'start_date': cloud['start_date'],
          'end_date': cloud['end_date'],
          'promo_code_used': cloud['promo_code_used'],
          'created_at': cloud['created_at'],
          'updated_at': cloud['updated_at'],
        };
        try {
          await _db.insertSubscription(localData);
        } catch (_) {
          await _db.updateSubscription(cloud['id'], localData);
        }
        return localData;
      }
    } catch (_) {
      // offline
    }

    return null;
  }

  /// Get available plans — try Supabase, fallback to hardcoded
  Future<List<Map<String, dynamic>>> getPlans() async {
    try {
      final plans = await _client
          .from('subscription_plans')
          .select()
          .order('duration_months', ascending: true);
      if (plans.isNotEmpty) return List<Map<String, dynamic>>.from(plans);
    } catch (_) {
      // offline or table not created yet
    }
    return defaultPlans;
  }

  /// Atomically redeems a promo code for the current user via the
  /// redeem_promo_code RPC. Replaces the old validatePromoCode +
  /// usePromoCode two-step which had a TOCTOU race condition.
  Future<PromoRedemptionResult> redeemPromoCode(String code) async {
    if (_userId == null) {
      return PromoRedemptionResult(success: false, reason: 'not_authenticated');
    }
    try {
      final response = await _client.rpc(
        'redeem_promo_code',
        params: {
          'p_code': code.trim(),
          'p_user_id': _userId,
        },
      );

      if (response is! Map) {
        AppLogger.error('SubscriptionService',
            'redeemPromoCode: unexpected response shape: $response');
        return PromoRedemptionResult(
            success: false, reason: 'invalid_response');
      }

      final success = response['success'] == true;
      final reason = response['reason']?.toString();
      final rawPromoData = response['promo_data'];
      final promoData = rawPromoData is Map
          ? Map<String, dynamic>.from(rawPromoData)
          : null;

      return PromoRedemptionResult(
        success: success,
        reason: reason,
        promoData: promoData,
      );
    } catch (e, st) {
      AppLogger.error('SubscriptionService', 'redeemPromoCode RPC call failed',
          error: e, stackTrace: st);
      await ErrorReporter.reportError(e, st, hint: 'promo_redemption');
      return PromoRedemptionResult(success: false, reason: 'network_error');
    }
  }

  /// Create a new subscription (after payment confirmed).
  /// Cloud-first: writes to Supabase before local SQLite. If the cloud
  /// upsert fails we surface the failure (return false) so the caller
  /// can show an error and the user does not believe they subscribed.
  Future<bool> createSubscription(
    String planId, {
    String? promoCode,
    double? finalPrice,
    String paymentMethod = 'manual',
    DateTime? verifiedExpiresAt,
    String? purchaseToken,
    bool autoRenewing = false,
  }) async {
    final trustedNow = await TimeService().trustedNow();
    if (trustedNow == null) return false;

    final userId = _userId;
    if (userId == null) return false;

    final now = trustedNow.toUtc();

    // Determine end_date:
    //   - verifiedExpiresAt provided (Play Billing path): server is authoritative.
    //   - Otherwise (promo code / manual path): client-side computation from plan duration.
    final DateTime endDate;
    if (verifiedExpiresAt != null) {
      endDate = verifiedExpiresAt.toUtc();
    } else {
      final plans = await getPlans();
      final plan = plans.firstWhere((p) => p['id'] == planId, orElse: () => {});
      if (plan.isEmpty) return false;
      final durationMonths = plan['duration_months'] as int;
      endDate = DateTime.utc(
        now.year,
        now.month + durationMonths,
        now.day,
      );
    }
    final id = const Uuid().v4();

    final subscriptionData = {
      'id': id,
      'user_id': userId,
      'plan_id': planId,
      'status': 'active',
      'start_date': now.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'promo_code_used': promoCode,
      'payment_method': paymentMethod,
      if (purchaseToken != null) 'purchase_token': purchaseToken,
      'auto_renewing': autoRenewing,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    // CLOUD FIRST: if this fails, we don't write locally. User sees error.
    try {
      await _client.from('user_subscriptions').upsert(subscriptionData);
    } catch (e, st) {
      AppLogger.error('SubscriptionService',
          'createSubscription cloud upsert failed',
          error: e, stackTrace: st);
      await ErrorReporter.reportError(e, st,
          hint: 'subscription_save',
          context: {
            'subscription': {
              'plan_id': planId,
              'payment_method': paymentMethod
            }
          });
      return false;
    }

    // LOCAL: if this fails, the cloud row exists and next launch will
    // sync down via hasActiveSubscription. So we still return true.
    // Local table omits user_id / payment_method (single user per device).
    // auto_renewing stored as int (SQLite has no bool type).
    final localData = Map<String, dynamic>.from(subscriptionData)
      ..remove('user_id')
      ..remove('payment_method')
      ..['auto_renewing'] = autoRenewing ? 1 : 0;
    try {
      await _db.insertSubscription(localData);
    } catch (e, st) {
      AppLogger.error('SubscriptionService',
          'createSubscription local insert failed (will sync from cloud next launch)',
          error: e, stackTrace: st);
    }

    return true;
  }

  /// Sync subscription status from cloud
  Future<void> syncSubscriptionStatus() async {
    await hasActiveSubscription();
  }

  /// Returns true if the user has ever had a subscription record.
  /// Checks local first (fast, offline-tolerant); falls back to cloud
  /// for fresh logins on a new device before downloadAllData completes.
  Future<bool> hasAnySubscriptionHistory() async {
    // Fast path — local SQLite
    final recent = await _db.getMostRecentSubscription();
    if (recent != null) return true;

    // Fallback — cloud covers fresh login before downloadAllData runs
    try {
      if (_userId == null) return false;
      final cloudRows = await _client
          .from('user_subscriptions')
          .select('id')
          .eq('user_id', _userId!)
          .limit(1);
      return cloudRows.isNotEmpty;
    } catch (e, st) {
      AppLogger.error('SubscriptionService',
          'hasAnySubscriptionHistory cloud check failed',
          error: e, stackTrace: st);
      return false;
    }
  }

  /// Returns true if the user is within the 72-hour free trial window.
  /// Trial starts at the user's auth.users.createdAt timestamp.
  /// Returns false if no user, no createdAt, or no trusted time.
  Future<bool> isWithinFreeTrial() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    final createdAtStr = user.createdAt;
    if (createdAtStr.isEmpty) return false;
    final createdAt = DateTime.tryParse(createdAtStr)?.toUtc();
    if (createdAt == null) return false;

    final now = await TimeService().trustedNow();
    if (now == null) return false;

    final trialEnd = createdAt.add(kFreePreviewDuration);
    return now.isBefore(trialEnd);
  }

  /// Returns the DateTime when the trial ends, or null if no user /
  /// invalid createdAt / not in trial.
  Future<DateTime?> getTrialEndTime() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final createdAtStr = user.createdAt;
    if (createdAtStr.isEmpty) return null;
    final createdAt = DateTime.tryParse(createdAtStr)?.toUtc();
    if (createdAt == null) return null;
    return createdAt.add(kFreePreviewDuration);
  }

  /// Get days remaining in current subscription
  int getDaysRemaining(String endDate) {
    final end = DateTime.parse(endDate);
    final now = DateTime.now();
    final diff = end.difference(now).inDays;
    return diff < 0 ? 0 : diff;
  }

  /// Get plan display name by ID
  String getPlanName(String planId) {
    switch (planId) {
      case 'monthly':
        return 'Monthly';
      case 'quarterly':
        return '3 Months';
      case 'yearly':
        return 'Yearly';
      default:
        return planId;
    }
  }
}

/// Result returned by [SubscriptionService.redeemPromoCode].
///
/// On success, [promoData] contains the discount details:
///   - 'code': the redeemed code string
///   - 'discount_percent': int or null
///   - 'discount_amount': int or null (PKR fixed deduction)
///
/// Reason codes on failure:
///   RPC-side: invalid_code, not_yet_valid, expired, already_used, exhausted
///   Flutter-side: not_authenticated, invalid_response, network_error
class PromoRedemptionResult {
  final bool success;
  final String? reason;
  final Map<String, dynamic>? promoData;

  PromoRedemptionResult({
    required this.success,
    this.reason,
    this.promoData,
  });
}
