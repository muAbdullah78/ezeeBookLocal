import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_helper.dart';
import '../../services/error_reporter.dart';
import '../utils/app_logger.dart';

class SyncService {
  final _client = Supabase.instance.client;
  final _db = DatabaseHelper();

  String? get _userId => _client.auth.currentUser?.id;

  // ==================== READ (LOCAL) ====================

  Future<List<Map<String, dynamic>>> getAllCustomers() async {
    return await _db.getAllCustomers();
  }

  Future<int> getCustomerCount() async {
    return await _db.getCustomerCount();
  }

  Future<int> getNextCustomerSerial() async {
    return await _db.getNextCustomerSerial();
  }

  Future<int> getActiveOrderCount() async {
    return await _db.getActiveOrderCount();
  }

  Future<int> getOverdueOrderCount() async {
    return await _db.getOverdueOrderCount();
  }

  Future<List<Map<String, dynamic>>> getAllOrders() async {
    return await _db.getAllOrders();
  }

  Future<List<Map<String, dynamic>>> getAllOrdersWithCustomer() async {
    return await _db.getAllOrdersWithCustomer();
  }

  Future<List<Map<String, dynamic>>> getOrdersForCustomer(String customerId) async {
    return await _db.getOrdersForCustomer(customerId);
  }

  Future<int> getOrderCountForCustomer(String customerId) async {
    return await _db.getOrderCountForCustomer(customerId);
  }

  Future<List<Map<String, dynamic>>> getOrdersByStatus(String status) async {
    return await _db.getOrdersByStatus(status);
  }

  Future<List<Map<String, dynamic>>> getTodaysDeliveries() async {
    return await _db.getTodaysDeliveries();
  }

  Future<List<Map<String, dynamic>>> getOverdueOrders() async {
    return await _db.getOverdueOrders();
  }

  Future<List<Map<String, dynamic>>> getUncollectedOrders() async {
    return await _db.getUncollectedOrders();
  }

  Future<List<Map<String, dynamic>>> getMeasurementsForCustomer(String customerId) async {
    return await _db.getMeasurementsForCustomer(customerId);
  }

  Future<List<Map<String, dynamic>>> getMeasurementsByGarmentType(
      String customerId, String garmentType) async {
    return await _db.getMeasurementsByGarmentType(customerId, garmentType);
  }

  Future<List<Map<String, dynamic>>> getMeasurementsForOrder(String orderId) async {
    return await _db.getMeasurementsForOrder(orderId);
  }

  Future<Map<String, dynamic>?> getDupattaForOrder(String orderId) async {
    return await _db.getDupattaForOrder(orderId);
  }

  // ==================== SHOP PROFILE OPERATIONS ====================

  /// Save shop profile to local SQLite first, then mirror to cloud.
  /// Returns true if local save succeeded. Cloud failure is logged
  /// but does not fail the operation.
  Future<bool> saveShopProfile(Map<String, dynamic> profile) async {
    try {
      await _db.upsertShopProfile(profile);
    } catch (e, st) {
      AppLogger.error('SyncService', 'saveShopProfile local failed',
          error: e, stackTrace: st);
      return false;
    }

    try {
      await _client.from('shop_profiles').upsert(profile);
    } catch (e, st) {
      AppLogger.error('SyncService', 'saveShopProfile cloud failed',
          error: e, stackTrace: st);
      // Local succeeded; data is preserved. Will sync later.
    }

    return true;
  }

  /// Read shop profile. Tries local first; if local has no row
  /// (e.g. fresh install or post-migration), tries cloud once and
  /// caches the result locally. Returns null if both miss.
  Future<Map<String, dynamic>?> getShopProfile() async {
    final userId = _userId;
    if (userId == null) return null;

    // 1. Try local first
    try {
      final local = await _db.getShopProfile(userId);
      if (local != null) return local;
    } catch (e, st) {
      AppLogger.error('SyncService', 'getShopProfile local failed',
          error: e, stackTrace: st);
    }

    // 2. Local miss — try cloud once and cache locally
    try {
      final cloud = await _client
          .from('shop_profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (cloud != null) {
        try {
          await _db.upsertShopProfile(Map<String, dynamic>.from(cloud));
        } catch (e, st) {
          AppLogger.error('SyncService', 'getShopProfile local cache failed',
              error: e, stackTrace: st);
        }
        return Map<String, dynamic>.from(cloud);
      }
    } catch (e, st) {
      AppLogger.error('SyncService', 'getShopProfile cloud failed',
          error: e, stackTrace: st);
    }

    return null;
  }

  // ==================== CUSTOMER OPERATIONS ====================

  Future<void> saveCustomer(Map<String, dynamic> customer) async {
    await _db.insertCustomer(customer);

    try {
      if (_userId != null) {
        await _client.from('customers').upsert({
          ...customer,
          'user_id': _userId,
        });
      }
    } catch (e, st) {
      AppLogger.error('SyncService', 'saveCustomer cloud upload failed', error: e, stackTrace: st);
      await ErrorReporter.reportError(e, st, hint: 'customer_save');
    }
  }

  Future<void> updateCustomer(String id, Map<String, dynamic> customer) async {
    await _db.updateCustomer(id, customer);

    try {
      if (_userId != null) {
        await _client.from('customers').upsert({
          ...customer,
          'user_id': _userId,
        });
      }
    } catch (e, st) {
      AppLogger.error('SyncService', 'updateCustomer cloud upload failed', error: e, stackTrace: st);
    }
  }

  Future<void> deleteCustomer(String id) async {
    await _db.deleteCustomer(id);

    try {
      if (_userId != null) {
        await _client.from('customers').delete().eq('id', id);
      }
    } catch (e, st) {
      AppLogger.error('SyncService', 'deleteCustomer cloud failed', error: e, stackTrace: st);
    }
  }

  // ==================== ORDER OPERATIONS ====================

  Future<void> saveOrder(Map<String, dynamic> order) async {
    await _db.insertOrder(order);

    try {
      if (_userId != null) {
        await _client.from('orders').upsert({
          ...order,
          'user_id': _userId,
        });
      }
    } catch (e, st) {
      AppLogger.error('SyncService', 'saveOrder cloud upload failed', error: e, stackTrace: st);
      await ErrorReporter.reportError(e, st, hint: 'order_save');
    }
  }

  Future<void> updateOrder(String id, Map<String, dynamic> order) async {
    await _db.updateOrder(id, order);

    try {
      if (_userId != null) {
        await _client.from('orders').upsert({
          ...order,
          'user_id': _userId,
        });
      }
    } catch (e, st) {
      AppLogger.error('SyncService', 'updateOrder cloud upload failed', error: e, stackTrace: st);
    }
  }

  Future<void> updateOrderStatus(String id, String status) async {
    await _db.updateOrderStatus(id, status);

    try {
      if (_userId != null) {
        await _client.from('orders').update({
          'status': status,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', id);
      }
    } catch (e, st) {
      AppLogger.error('SyncService', 'updateOrderStatus cloud failed', error: e, stackTrace: st);
    }
  }

  Future<void> deleteOrder(String id) async {
    await _db.deleteOrder(id);

    try {
      if (_userId != null) {
        await _client.from('orders').delete().eq('id', id);
      }
    } catch (e, st) {
      AppLogger.error('SyncService', 'deleteOrder cloud failed', error: e, stackTrace: st);
    }
  }

  // ==================== MEASUREMENT OPERATIONS ====================

  Future<void> saveMeasurement(Map<String, dynamic> measurement) async {
    await _db.insertMeasurement(measurement);

    try {
      if (_userId != null) {
        await _client.from('measurements').upsert({
          ...measurement,
          'user_id': _userId,
        });
      }
    } catch (e, st) {
      AppLogger.error('SyncService', 'saveMeasurement cloud upload failed', error: e, stackTrace: st);
    }
  }

  Future<void> updateMeasurement(String id, Map<String, dynamic> measurement) async {
    await _db.updateMeasurement(id, measurement);

    try {
      if (_userId != null) {
        await _client.from('measurements').upsert({
          ...measurement,
          'user_id': _userId,
        });
      }
    } catch (e, st) {
      AppLogger.error('SyncService', 'updateMeasurement cloud upload failed', error: e, stackTrace: st);
    }
  }

  Future<void> deleteMeasurement(String id) async {
    await _db.deleteMeasurement(id);

    try {
      if (_userId != null) {
        await _client.from('measurements').delete().eq('id', id);
      }
    } catch (e, st) {
      AppLogger.error('SyncService', 'deleteMeasurement cloud failed', error: e, stackTrace: st);
    }
  }

  // ==================== DUPATTA DETAILS OPERATIONS ====================

  Future<void> saveDupattaDetails(Map<String, dynamic> dupatta) async {
    await _db.insertDupattaDetails(dupatta);

    try {
      if (_userId != null) {
        await _client.from('dupatta_details').upsert({
          ...dupatta,
          'user_id': _userId,
        });
      }
    } catch (e, st) {
      AppLogger.error('SyncService', 'saveDupattaDetails cloud upload failed', error: e, stackTrace: st);
    }
  }

  Future<void> updateDupattaDetails(String id, Map<String, dynamic> dupatta) async {
    await _db.updateDupattaDetails(id, dupatta);

    try {
      if (_userId != null) {
        await _client.from('dupatta_details').upsert({
          ...dupatta,
          'user_id': _userId,
        });
      }
    } catch (e, st) {
      AppLogger.error('SyncService', 'updateDupattaDetails cloud upload failed', error: e, stackTrace: st);
    }
  }

  // ==================== PULL FROM CLOUD ====================

  Future<void> downloadAllData() async {
    if (_userId == null) return;

    try {
      // Download customers
      final customers = await _client
          .from('customers')
          .select()
          .eq('user_id', _userId!)
          .order('serial_number', ascending: true);

      for (final customer in customers) {
        final localData = {
          'id': customer['id'],
          'name': customer['name'],
          'phone': customer['phone'],
          'gender': customer['gender'],
          'serial_number': customer['serial_number'],
          'created_at': customer['created_at'],
          'updated_at': customer['updated_at'],
        };
        try {
          await _db.insertCustomer(localData);
        } catch (_) {
          // Row exists locally — only overwrite if cloud is newer
          if (await _shouldOverwriteLocal(
              existing: await _db.getCustomer(customer['id']),
              incoming: localData)) {
            try {
              await _db.updateCustomer(customer['id'], localData);
            } catch (e, st) {
              AppLogger.error('SyncService',
                  'downloadAllData: customer update failed for ${customer['id']}',
                  error: e, stackTrace: st);
              // continue to next customer — do NOT abort the download
            }
          } else {
            AppLogger.info('SyncService',
                'downloadAllData: skipped customer update — local newer');
          }
        }
      }

      // Download orders
      final orders = await _client
          .from('orders')
          .select()
          .eq('user_id', _userId!)
          .order('created_at', ascending: false);

      for (final order in orders) {
        final localData = <String, dynamic>{
          'id': order['id'],
          'customer_id': order['customer_id'],
          'stitch_type': order['stitch_type'],
          'customer_gender': order['customer_gender'],
          'shirt_sub_type': order['shirt_sub_type'],
          'bottom_type': order['bottom_type'],
          'bottom_waistband': order['bottom_waistband'],
          'elastic_width': order['elastic_width'],
          'quantity': order['quantity'],
          'colors': order['colors'],
          'total_amount': order['total_amount'],
          'advance_payment': order['advance_payment'],
          'delivery_date': order['delivery_date'],
          'status': order['status'],
          'special_instructions': order['special_instructions'],
          'extra_instructions': order['extra_instructions'],
          'created_at': order['created_at'],
          'updated_at': order['updated_at'],
        };
        try {
          await _db.insertOrder(localData);
        } catch (_) {
          // Row exists locally — only overwrite if cloud is newer
          if (await _shouldOverwriteLocal(
              existing: await _db.getOrder(order['id']),
              incoming: localData)) {
            try {
              await _db.updateOrder(order['id'], localData);
            } catch (e, st) {
              AppLogger.error('SyncService',
                  'downloadAllData: order update failed for ${order['id']}',
                  error: e, stackTrace: st);
              // continue to next order — do NOT abort the download
            }
          } else {
            AppLogger.info('SyncService',
                'downloadAllData: skipped order update — local newer');
          }
        }
      }

      // Download measurements
      final measurements = await _client
          .from('measurements')
          .select()
          .eq('user_id', _userId!)
          .order('updated_at', ascending: false);

      for (final m in measurements) {
        final localData = <String, dynamic>{
          'id': m['id'],
          'customer_id': m['customer_id'],
          'order_id': m['order_id'],
          'garment_type': m['garment_type'],
          'measurement_data': m['measurement_data'],
          'additional_options': m['additional_options'],
          'created_at': m['created_at'],
          'updated_at': m['updated_at'],
        };
        try {
          await _db.insertMeasurement(localData);
        } catch (_) {
          // Row exists locally — only overwrite if cloud is newer
          if (await _shouldOverwriteLocal(
              existing: await _db.getMeasurement(m['id']),
              incoming: localData)) {
            try {
              await _db.updateMeasurement(m['id'], localData);
            } catch (e, st) {
              AppLogger.error('SyncService',
                  'downloadAllData: measurement update failed for ${m['id']}',
                  error: e, stackTrace: st);
              // continue to next measurement — do NOT abort the download
            }
          } else {
            AppLogger.info('SyncService',
                'downloadAllData: skipped measurement update — local newer');
          }
        }
      }

      // Download dupatta details
      final dupattas = await _client
          .from('dupatta_details')
          .select()
          .eq('user_id', _userId!)
          .order('created_at', ascending: false);

      for (final d in dupattas) {
        final localData = <String, dynamic>{
          'id': d['id'],
          'order_id': d['order_id'],
          'included': d['included'],
          'finishing': d['finishing'],
          'pico_coverage': d['pico_coverage'],
          'pico_type': d['pico_type'],
          'piping_coverage': d['piping_coverage'],
          'lace_coverage': d['lace_coverage'],
          'lace_provided_by_customer': d['lace_provided_by_customer'],
          'created_at': d['created_at'],
          'updated_at': d['updated_at'],
        };
        try {
          await _db.insertDupattaDetails(localData);
        } catch (_) {
          // Row exists locally — only overwrite if cloud is newer
          // (dupatta is keyed by order_id locally — there's one row per order)
          if (await _shouldOverwriteLocal(
              existing: await _db.getDupattaForOrder(d['order_id']),
              incoming: localData)) {
            try {
              await _db.updateDupattaDetails(d['id'], localData);
            } catch (e, st) {
              AppLogger.error('SyncService',
                  'downloadAllData: dupatta update failed for ${d['id']}',
                  error: e, stackTrace: st);
              // continue to next dupatta — do NOT abort the download
            }
          } else {
            AppLogger.info('SyncService',
                'downloadAllData: skipped dupatta update — local newer');
          }
        }
      }

      // Download shop_profiles
      try {
        final profile = await _client
            .from('shop_profiles')
            .select()
            .eq('id', _userId!)
            .maybeSingle();
        if (profile != null) {
          try {
            await _db.upsertShopProfile(Map<String, dynamic>.from(profile));
          } catch (e) {
            AppLogger.info('SyncService',
                'downloadAllData: shop_profile cache failed');
            // Non-fatal; continue
          }
        }
      } catch (e, st) {
        AppLogger.error('SyncService', 'downloadAllData shop_profiles failed',
            error: e, stackTrace: st);
      }

      // Download user_subscriptions
      try {
        final subRows = await _client
            .from('user_subscriptions')
            .select()
            .eq('user_id', _userId!);
        for (final row in subRows) {
          // Strip cloud-only columns before inserting locally
          final localData = Map<String, dynamic>.from(row)
            ..remove('user_id')
            ..remove('payment_method');
          try {
            await _db.insertSubscription(localData);
          } catch (_) {
            // Row exists — overwrite only if cloud is newer
            if (await _shouldOverwriteLocal(
                existing: await _db.getMostRecentSubscription(),
                incoming: localData)) {
              try {
                await _db.updateSubscription(row['id'] as String, localData);
              } catch (e, st) {
                AppLogger.error('SyncService',
                    'downloadAllData: subscription update failed for ${row['id']}',
                    error: e, stackTrace: st);
              }
            } else {
              AppLogger.info('SyncService',
                  'downloadAllData: skipped subscription update — local newer');
            }
          }
        }
      } catch (e, st) {
        AppLogger.error('SyncService',
            'downloadAllData: user_subscriptions download failed',
            error: e, stackTrace: st);
        // Non-fatal — continue; app still works from local data
      }

    } catch (e, st) {
      AppLogger.error('SyncService', 'downloadAllData failed', error: e, stackTrace: st);
    }
  }

  /// Returns true if the incoming map should overwrite the existing
  /// local row. Compares updated_at timestamps. If parsing fails for
  /// either side, defaults to TRUE (trust the incoming cloud copy).
  Future<bool> _shouldOverwriteLocal({
    required Map<String, dynamic>? existing,
    required Map<String, dynamic> incoming,
  }) async {
    if (existing == null) return true;
    final existingStr = existing['updated_at']?.toString();
    final incomingStr = incoming['updated_at']?.toString();
    if (existingStr == null || existingStr.isEmpty) return true;
    if (incomingStr == null || incomingStr.isEmpty) return false;
    try {
      final existingTs = DateTime.parse(existingStr);
      final incomingTs = DateTime.parse(incomingStr);
      return !existingTs.isAfter(incomingTs);
    } catch (e, st) {
      AppLogger.error('SyncService',
          'updated_at parse failed; defaulting to overwrite',
          error: e, stackTrace: st);
      return true;
    }
  }

  // ==================== DELETE ALL USER DATA ====================

  Future<void> deleteAllUserData() async {
    final userId = _userId;

    // Step 1: Call the delete_user() RPC. This deletes the auth.users
    // row, which cascades through every FK and removes all of this
    // user's cloud data atomically (customers, orders, measurements,
    // dupatta_details, shop_profiles, user_subscriptions).
    if (userId != null) {
      try {
        await _client.rpc('delete_user');
        AppLogger.info('SyncService', 'delete_user RPC succeeded');
      } catch (e, st) {
        AppLogger.error('SyncService', 'delete_user RPC failed',
            error: e, stackTrace: st);
        // Rethrow — we MUST not proceed to wipe local data if the cloud
        // deletion failed, because the user could re-login and find
        // their cloud data still there with no way to recover. The
        // calling screen will surface this to the user.
        rethrow;
      }
    }

    // Step 2: Wipe local SQLite. Only runs if RPC succeeded (or if
    // userId was null, which means there was nothing in the cloud).
    await _db.deleteAllData();
  }

  /// Push all local data to cloud (full sync)
  Future<void> uploadAllData() async {
    if (_userId == null) return;

    try {
      final customers = await _db.getAllCustomers();
      for (final customer in customers) {
        try {
          await _client.from('customers').upsert({
            ...customer,
            'user_id': _userId,
          });
        } catch (e, st) {
          AppLogger.error('SyncService',
              'uploadAllData customer upsert failed', error: e, stackTrace: st);
        }
      }

      final orders = await _db.getAllOrders();
      for (final order in orders) {
        try {
          await _client.from('orders').upsert({
            ...order,
            'user_id': _userId,
          });
        } catch (e, st) {
          AppLogger.error('SyncService',
              'uploadAllData order upsert failed', error: e, stackTrace: st);
        }
      }

      // For measurements and dupatta, iterate the parent lists already
      // loaded above. Use the existing helper methods to find children:
      for (final customer in customers) {
        final measurements = await _db.getMeasurementsForCustomer(
            customer['id'] as String);
        for (final m in measurements) {
          try {
            await _client.from('measurements').upsert({
              ...m,
              'user_id': _userId,
            });
          } catch (e, st) {
            AppLogger.error('SyncService',
                'uploadAllData measurement upsert failed',
                error: e, stackTrace: st);
          }
        }
      }

      for (final order in orders) {
        final dupatta = await _db.getDupattaForOrder(order['id'] as String);
        if (dupatta != null) {
          try {
            await _client.from('dupatta_details').upsert({
              ...dupatta,
              'user_id': _userId,
            });
          } catch (e, st) {
            AppLogger.error('SyncService',
                'uploadAllData dupatta upsert failed',
                error: e, stackTrace: st);
          }
        }
      }
    } catch (e, st) {
      AppLogger.error('SyncService', 'uploadAllData failed',
          error: e, stackTrace: st);
    }
  }
}
