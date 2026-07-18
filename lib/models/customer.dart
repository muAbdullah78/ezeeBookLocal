import 'package:uuid/uuid.dart';

class Customer {
  final String id;
  final String name;
  final String phone;
  final String gender;
  final int serialNumber;
  final DateTime createdAt;
  final DateTime updatedAt;

  Customer({
    String? id,
    required this.name,
    required this.phone,
    required this.gender,
    this.serialNumber = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'gender': gender,
      'serial_number': serialNumber,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'],
      name: map['name'],
      phone: map['phone'],
      gender: map['gender'],
      serialNumber: map['serial_number'] ?? 0,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Customer copyWith({
    String? name,
    String? phone,
    String? gender,
    int? serialNumber,
  }) {
    return Customer(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      gender: gender ?? this.gender,
      serialNumber: serialNumber ?? this.serialNumber,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}