import 'database_helper.dart';

/// Local data access facade.
///
/// This used to perform "dual saves" (local SQLite + Supabase cloud). The app
/// is now fully offline, so every method simply delegates to
/// [DatabaseHelper]. The class name and method signatures are kept unchanged
/// so the feature screens that call it need no edits.
class SyncService {
  final _db = DatabaseHelper();

  // ==================== READ ====================

  Future<List<Map<String, dynamic>>> getAllCustomers() => _db.getAllCustomers();

  Future<int> getCustomerCount() => _db.getCustomerCount();

  Future<int> getNextCustomerSerial() => _db.getNextCustomerSerial();

  Future<int> getActiveOrderCount() => _db.getActiveOrderCount();

  Future<int> getOverdueOrderCount() => _db.getOverdueOrderCount();

  Future<List<Map<String, dynamic>>> getAllOrders() => _db.getAllOrders();

  Future<List<Map<String, dynamic>>> getAllOrdersWithCustomer() =>
      _db.getAllOrdersWithCustomer();

  Future<List<Map<String, dynamic>>> getOrdersForCustomer(String customerId) =>
      _db.getOrdersForCustomer(customerId);

  Future<int> getOrderCountForCustomer(String customerId) =>
      _db.getOrderCountForCustomer(customerId);

  Future<List<Map<String, dynamic>>> getOrdersByStatus(String status) =>
      _db.getOrdersByStatus(status);

  Future<List<Map<String, dynamic>>> getTodaysDeliveries() =>
      _db.getTodaysDeliveries();

  Future<List<Map<String, dynamic>>> getOverdueOrders() =>
      _db.getOverdueOrders();

  Future<List<Map<String, dynamic>>> getUncollectedOrders() =>
      _db.getUncollectedOrders();

  Future<List<Map<String, dynamic>>> getMeasurementsForCustomer(
          String customerId) =>
      _db.getMeasurementsForCustomer(customerId);

  Future<List<Map<String, dynamic>>> getMeasurementsByGarmentType(
          String customerId, String garmentType) =>
      _db.getMeasurementsByGarmentType(customerId, garmentType);

  Future<List<Map<String, dynamic>>> getMeasurementsForOrder(String orderId) =>
      _db.getMeasurementsForOrder(orderId);

  Future<Map<String, dynamic>?> getDupattaForOrder(String orderId) =>
      _db.getDupattaForOrder(orderId);

  // ==================== SHOP PROFILE ====================

  /// Save the local shop profile. Returns true on success.
  Future<bool> saveShopProfile(Map<String, dynamic> profile) async {
    await _db.upsertShopProfile(profile);
    return true;
  }

  Future<Map<String, dynamic>?> getShopProfile() => _db.getShopProfile();

  // ==================== CUSTOMER ====================

  Future<void> saveCustomer(Map<String, dynamic> customer) =>
      _db.insertCustomer(customer);

  Future<void> updateCustomer(String id, Map<String, dynamic> customer) =>
      _db.updateCustomer(id, customer);

  Future<void> deleteCustomer(String id) => _db.deleteCustomer(id);

  // ==================== ORDER ====================

  Future<void> saveOrder(Map<String, dynamic> order) => _db.insertOrder(order);

  Future<void> updateOrder(String id, Map<String, dynamic> order) =>
      _db.updateOrder(id, order);

  Future<void> updateOrderStatus(String id, String status) =>
      _db.updateOrderStatus(id, status);

  Future<void> deleteOrder(String id) => _db.deleteOrder(id);

  // ==================== MEASUREMENT ====================

  Future<void> saveMeasurement(Map<String, dynamic> measurement) =>
      _db.insertMeasurement(measurement);

  Future<void> updateMeasurement(String id, Map<String, dynamic> measurement) =>
      _db.updateMeasurement(id, measurement);

  Future<void> deleteMeasurement(String id) => _db.deleteMeasurement(id);

  // ==================== DUPATTA DETAILS ====================

  Future<void> saveDupattaDetails(Map<String, dynamic> dupatta) =>
      _db.insertDupattaDetails(dupatta);

  Future<void> updateDupattaDetails(String id, Map<String, dynamic> dupatta) =>
      _db.updateDupattaDetails(id, dupatta);
}
