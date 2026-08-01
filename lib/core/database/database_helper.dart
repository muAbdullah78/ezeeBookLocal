import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../constants/app_constants.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'ezeebook.db');

    return await openDatabase(
      path,
      version: 6,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createCustomersTable(db);
    await _createOrdersTable(db);
    await _createMeasurementsTable(db);
    await _createDupattaDetailsTable(db);
    await _createShopProfilesTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Defensive: v1 customers schema might have lacked serial_number.
      try {
        await db.execute(
          'ALTER TABLE customers ADD COLUMN serial_number INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {
        // Column already exists — fine
      }

      // Drop old orders and measurements tables (they had placeholder schemas)
      await db.execute('DROP TABLE IF EXISTS measurements');
      await db.execute('DROP TABLE IF EXISTS orders');

      // Recreate with new schemas
      await _createOrdersTable(db);
      await _createMeasurementsTable(db);
      await _createDupattaDetailsTable(db);
    }
    if (oldVersion < 4) {
      await _createShopProfilesTable(db);
    }
    if (oldVersion < 6) {
      // v6: the app dropped its subscription/cloud model and became fully
      // offline. Remove the now-unused subscription table and re-key the
      // single shop profile to the fixed local id (it used to be the cloud
      // auth user id).
      await db.execute('DROP TABLE IF EXISTS user_subscriptions');
      try {
        await db.execute(
          "UPDATE shop_profiles SET id = '$kLocalShopId'",
        );
      } catch (_) {
        // shop_profiles may not exist yet on very old installs — ignore.
      }
    }
  }

  Future<void> _createCustomersTable(Database db) async {
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        gender TEXT NOT NULL,
        serial_number INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createOrdersTable(Database db) async {
    await db.execute('''
      CREATE TABLE orders (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        stitch_type TEXT NOT NULL,
        customer_gender TEXT NOT NULL,
        shirt_sub_type TEXT,
        bottom_type TEXT,
        bottom_waistband TEXT,
        elastic_width TEXT,
        quantity INTEGER NOT NULL DEFAULT 1,
        colors TEXT,
        total_amount REAL NOT NULL DEFAULT 0,
        advance_payment REAL NOT NULL DEFAULT 0,
        delivery_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        special_instructions TEXT,
        extra_instructions TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createMeasurementsTable(Database db) async {
    await db.execute('''
      CREATE TABLE measurements (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        order_id TEXT,
        garment_type TEXT NOT NULL,
        measurement_data TEXT NOT NULL,
        additional_options TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createDupattaDetailsTable(Database db) async {
    await db.execute('''
      CREATE TABLE dupatta_details (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        included INTEGER NOT NULL DEFAULT 0,
        finishing TEXT,
        pico_coverage TEXT,
        pico_type TEXT,
        piping_coverage TEXT,
        lace_coverage TEXT,
        lace_provided_by_customer INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createShopProfilesTable(Database db) async {
    await db.execute('''
      CREATE TABLE shop_profiles (
        id TEXT PRIMARY KEY,
        owner_name TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '',
        shop_name TEXT NOT NULL DEFAULT '',
        address TEXT,
        email TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL DEFAULT ''
      )
    ''');
  }

  // ==================== SHOP PROFILE OPERATIONS ====================

  /// Insert or replace the shop profile row. Always keyed by [kLocalShopId].
  Future<int> upsertShopProfile(Map<String, dynamic> profile) async {
    final db = await database;
    final row = Map<String, dynamic>.from(profile);
    row['id'] = kLocalShopId; // single local shop — force the fixed key
    return await db.insert(
      'shop_profiles',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Read the local shop profile. Returns null if it has not been set up yet.
  Future<Map<String, dynamic>?> getShopProfile() async {
    final db = await database;
    final results = await db.query(
      'shop_profiles',
      where: 'id = ?',
      whereArgs: [kLocalShopId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  // ==================== CUSTOMER OPERATIONS ====================

  Future<int> insertCustomer(Map<String, dynamic> customer) async {
    final db = await database;
    return await db.insert('customers', customer);
  }

  Future<List<Map<String, dynamic>>> getAllCustomers() async {
    final db = await database;
    return await db.query('customers', orderBy: 'created_at DESC');
  }

  Future<Map<String, dynamic>?> getCustomer(String id) async {
    final db = await database;
    final results = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateCustomer(String id, Map<String, dynamic> customer) async {
    final db = await database;
    return await db.update('customers', customer, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCustomer(String id) async {
    final db = await database;
    // Manually clean up dependent rows — foreign-key cascade is not
    // guaranteed to be enabled on the local SQLite connection.
    final orders = await db.query('orders',
        columns: ['id'], where: 'customer_id = ?', whereArgs: [id]);
    for (final o in orders) {
      final orderId = o['id'] as String;
      await db.delete('dupatta_details', where: 'order_id = ?', whereArgs: [orderId]);
    }
    await db.delete('measurements', where: 'customer_id = ?', whereArgs: [id]);
    await db.delete('orders', where: 'customer_id = ?', whereArgs: [id]);
    return await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> searchCustomers(String query) async {
    final db = await database;
    return await db.query(
      'customers',
      where: 'name LIKE ? OR phone LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'name ASC',
    );
  }

  Future<int> getCustomerCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM customers');
    return result.first['count'] as int;
  }

  Future<int> getNextCustomerSerial() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COALESCE(MAX(serial_number), 0) + 1 AS next FROM customers',
    );
    return (result.first['next'] as int?) ?? 1;
  }

  // ==================== ORDER OPERATIONS ====================

  Future<int> insertOrder(Map<String, dynamic> order) async {
    final db = await database;
    return await db.insert('orders', order);
  }

  Future<List<Map<String, dynamic>>> getAllOrders() async {
    final db = await database;
    return await db.query('orders', orderBy: 'created_at DESC');
  }

  Future<Map<String, dynamic>?> getOrder(String id) async {
    final db = await database;
    final results = await db.query('orders', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllOrdersWithCustomer() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT orders.*, customers.name as customer_name, customers.serial_number as customer_serial, customers.phone as customer_phone
      FROM orders
      INNER JOIN customers ON orders.customer_id = customers.id
      ORDER BY orders.delivery_date ASC
    ''');
  }

  Future<List<Map<String, dynamic>>> getOrdersForCustomer(String customerId) async {
    final db = await database;
    return await db.query('orders',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'created_at DESC');
  }

  Future<int> getOrderCountForCustomer(String customerId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM orders WHERE customer_id = ?',
      [customerId],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getOrdersByStatus(String status) async {
    final db = await database;
    return await db.query('orders',
        where: 'status = ?',
        whereArgs: [status],
        orderBy: 'delivery_date ASC');
  }

  Future<int> updateOrderStatus(String id, String status) async {
    final db = await database;
    return await db.update(
      'orders',
      {'status': status, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateOrder(String id, Map<String, dynamic> order) async {
    final db = await database;
    return await db.update('orders', order, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteOrder(String id) async {
    final db = await database;
    // Manually clean up children — cascade is not guaranteed to be enabled.
    await db.delete('dupatta_details', where: 'order_id = ?', whereArgs: [id]);
    await db.delete('measurements', where: 'order_id = ?', whereArgs: [id]);
    return await db.delete('orders', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getActiveOrderCount() async {
    final db = await database;
    final result = await db.rawQuery(
        "SELECT COUNT(*) as count FROM orders WHERE status = 'pending'");
    return result.first['count'] as int;
  }

  Future<int> getOverdueOrderCount() async {
    final db = await database;
    final now = DateTime.now().toIso8601String().substring(0, 10);
    final result = await db.rawQuery(
        "SELECT COUNT(*) as count FROM orders WHERE status = 'pending' AND delivery_date < ?",
        [now]);
    return result.first['count'] as int;
  }

  Future<List<Map<String, dynamic>>> getTodaysDeliveries() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return await db.rawQuery('''
      SELECT orders.*, customers.name as customer_name
      FROM orders
      INNER JOIN customers ON orders.customer_id = customers.id
      WHERE orders.delivery_date = ? AND orders.status = 'pending'
      ORDER BY orders.created_at ASC
    ''', [today]);
  }

  Future<List<Map<String, dynamic>>> getOverdueOrders() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return await db.rawQuery('''
      SELECT orders.*, customers.name as customer_name
      FROM orders
      INNER JOIN customers ON orders.customer_id = customers.id
      WHERE orders.status = 'pending' AND orders.delivery_date < ?
      ORDER BY orders.delivery_date ASC
    ''', [today]);
  }

  Future<List<Map<String, dynamic>>> getUncollectedOrders() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return await db.rawQuery('''
      SELECT orders.*, customers.name as customer_name
      FROM orders
      INNER JOIN customers ON orders.customer_id = customers.id
      WHERE orders.status = 'completed' AND orders.delivery_date < ?
      ORDER BY orders.delivery_date ASC
    ''', [today]);
  }

  // ==================== MEASUREMENT OPERATIONS ====================

  Future<int> insertMeasurement(Map<String, dynamic> measurement) async {
    final db = await database;
    return await db.insert('measurements', measurement);
  }

  Future<List<Map<String, dynamic>>> getMeasurementsForCustomer(String customerId) async {
    final db = await database;
    return await db.query('measurements',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'updated_at DESC');
  }

  Future<Map<String, dynamic>?> getMeasurement(String id) async {
    final db = await database;
    final results = await db.query('measurements', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getMeasurementsByGarmentType(
      String customerId, String garmentType) async {
    final db = await database;
    return await db.query('measurements',
        where: 'customer_id = ? AND garment_type = ?',
        whereArgs: [customerId, garmentType],
        orderBy: 'updated_at DESC');
  }

  Future<List<Map<String, dynamic>>> getMeasurementsForOrder(String orderId) async {
    final db = await database;
    return await db.query('measurements',
        where: 'order_id = ?',
        whereArgs: [orderId],
        orderBy: 'garment_type ASC');
  }

  Future<int> updateMeasurement(String id, Map<String, dynamic> measurement) async {
    final db = await database;
    return await db.update('measurements', measurement, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteMeasurement(String id) async {
    final db = await database;
    return await db.delete('measurements', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== DUPATTA DETAILS OPERATIONS ====================

  Future<int> insertDupattaDetails(Map<String, dynamic> dupatta) async {
    final db = await database;
    return await db.insert('dupatta_details', dupatta);
  }

  Future<Map<String, dynamic>?> getDupattaForOrder(String orderId) async {
    final db = await database;
    final results = await db.query('dupatta_details',
        where: 'order_id = ?', whereArgs: [orderId]);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateDupattaDetails(String id, Map<String, dynamic> dupatta) async {
    final db = await database;
    return await db.update('dupatta_details', dupatta, where: 'id = ?', whereArgs: [id]);
  }

  // ==================== BACKUP / RESTORE ====================

  /// Read every row from every data table into a plain JSON-encodable map.
  /// Used by the backup/export flow so a tailor can move their data to a new
  /// device.
  Future<Map<String, dynamic>> exportAllData() async {
    final db = await database;
    Future<List<Map<String, dynamic>>> rows(String t) async =>
        (await db.query(t)).map((r) => Map<String, dynamic>.from(r)).toList();
    return {
      'customers': await rows('customers'),
      'orders': await rows('orders'),
      'measurements': await rows('measurements'),
      'dupatta_details': await rows('dupatta_details'),
      'shop_profiles': await rows('shop_profiles'),
    };
  }

  /// Replace ALL local data with the contents of a backup map (produced by
  /// [exportAllData]). Runs in a single transaction so a failure leaves the
  /// existing data untouched.
  Future<void> importAllData(Map<String, dynamic> data) async {
    final db = await database;
    List<Map<String, dynamic>> rows(dynamic v) => (v is List)
        ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];

    await db.transaction((txn) async {
      // Clear children first, then parents.
      await txn.delete('dupatta_details');
      await txn.delete('measurements');
      await txn.delete('orders');
      await txn.delete('customers');
      await txn.delete('shop_profiles');

      // Insert parents first, then children.
      for (final r in rows(data['customers'])) {
        await txn.insert('customers', r,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final r in rows(data['orders'])) {
        await txn.insert('orders', r,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final r in rows(data['measurements'])) {
        await txn.insert('measurements', r,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final r in rows(data['dupatta_details'])) {
        await txn.insert('dupatta_details', r,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final r in rows(data['shop_profiles'])) {
        r['id'] = kLocalShopId; // keep the single-shop invariant
        await txn.insert('shop_profiles', r,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  // ==================== DELETE ALL DATA ====================

  Future<void> deleteAllData() async {
    final db = await database;
    await db.delete('shop_profiles');
    await db.delete('dupatta_details');
    await db.delete('measurements');
    await db.delete('orders');
    await db.delete('customers');
  }

  /// Fully clear the local database by closing it and deleting the file.
  /// Used by "Erase all data" so the app returns to a first-launch state.
  Future<void> clearAllData() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'ezeebook.db');

    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    await deleteDatabase(path);
  }
}
