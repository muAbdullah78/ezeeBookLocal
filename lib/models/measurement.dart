import 'dart:convert';
import 'package:uuid/uuid.dart';

class Measurement {
  final String id;
  final String customerId;
  final String? orderId;
  final String garmentType;
  final String measurementData;
  final String? additionalOptions;
  final DateTime createdAt;
  final DateTime updatedAt;

  Measurement({
    String? id,
    required this.customerId,
    this.orderId,
    required this.garmentType,
    required this.measurementData,
    this.additionalOptions,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Get a specific measurement value from the JSON data.
  /// Returns null if the key doesn't exist.
  String? getValue(String key) {
    try {
      final data = json.decode(measurementData) as Map<String, dynamic>;
      return data[key]?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Get all measurement values as a Map.
  Map<String, dynamic> get measurements {
    try {
      return json.decode(measurementData) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_id': customerId,
      'order_id': orderId,
      'garment_type': garmentType,
      'measurement_data': measurementData,
      'additional_options': additionalOptions,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Measurement.fromMap(Map<String, dynamic> map) {
    return Measurement(
      id: map['id'],
      customerId: map['customer_id'],
      orderId: map['order_id'],
      garmentType: map['garment_type'],
      measurementData: map['measurement_data'],
      additionalOptions: map['additional_options'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Measurement copyWith({
    String? customerId,
    String? orderId,
    String? garmentType,
    String? measurementData,
    String? additionalOptions,
  }) {
    return Measurement(
      id: id,
      customerId: customerId ?? this.customerId,
      orderId: orderId ?? this.orderId,
      garmentType: garmentType ?? this.garmentType,
      measurementData: measurementData ?? this.measurementData,
      additionalOptions: additionalOptions ?? this.additionalOptions,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
