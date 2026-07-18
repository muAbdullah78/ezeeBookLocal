import 'package:uuid/uuid.dart';

class Order {
  final String id;
  final String customerId;
  final String stitchType;
  final String customerGender;
  final String? shirtSubType;
  final String? bottomType;
  final String? bottomWaistband;
  final String? elasticWidth;
  final int quantity;
  final String? colors;
  final double totalAmount;
  final double advancePayment;
  final String deliveryDate;
  final String status;
  final String? specialInstructions;
  final String? extraInstructions;
  final DateTime createdAt;
  final DateTime updatedAt;

  Order({
    String? id,
    required this.customerId,
    required this.stitchType,
    required this.customerGender,
    this.shirtSubType,
    this.bottomType,
    this.bottomWaistband,
    this.elasticWidth,
    this.quantity = 1,
    this.colors,
    this.totalAmount = 0,
    this.advancePayment = 0,
    required this.deliveryDate,
    this.status = 'pending',
    this.specialInstructions,
    this.extraInstructions,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  double get remainingBalance => totalAmount - advancePayment;

  bool get isOverdue {
    if (status != 'pending') return false;
    final delivery = DateTime.tryParse(deliveryDate);
    if (delivery == null) return false;
    return DateTime.now().isAfter(delivery);
  }

  bool get isUncollected {
    if (status != 'completed') return false;
    final delivery = DateTime.tryParse(deliveryDate);
    if (delivery == null) return false;
    return DateTime.now().isAfter(delivery);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_id': customerId,
      'stitch_type': stitchType,
      'customer_gender': customerGender,
      'shirt_sub_type': shirtSubType,
      'bottom_type': bottomType,
      'bottom_waistband': bottomWaistband,
      'elastic_width': elasticWidth,
      'quantity': quantity,
      'colors': colors,
      'total_amount': totalAmount,
      'advance_payment': advancePayment,
      'delivery_date': deliveryDate,
      'status': status,
      'special_instructions': specialInstructions,
      'extra_instructions': extraInstructions,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Order.fromMap(Map<String, dynamic> map) {
    return Order(
      id: map['id'],
      customerId: map['customer_id'],
      stitchType: map['stitch_type'],
      customerGender: map['customer_gender'],
      shirtSubType: map['shirt_sub_type'],
      bottomType: map['bottom_type'],
      bottomWaistband: map['bottom_waistband'],
      elasticWidth: map['elastic_width'],
      quantity: map['quantity'] ?? 1,
      colors: map['colors'],
      totalAmount: (map['total_amount'] ?? 0).toDouble(),
      advancePayment: (map['advance_payment'] ?? 0).toDouble(),
      deliveryDate: map['delivery_date'],
      status: map['status'] ?? 'pending',
      specialInstructions: map['special_instructions'],
      extraInstructions: map['extra_instructions'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Order copyWith({
    String? customerId,
    String? stitchType,
    String? customerGender,
    String? shirtSubType,
    String? bottomType,
    String? bottomWaistband,
    String? elasticWidth,
    int? quantity,
    String? colors,
    double? totalAmount,
    double? advancePayment,
    String? deliveryDate,
    String? status,
    String? specialInstructions,
    String? extraInstructions,
  }) {
    return Order(
      id: id,
      customerId: customerId ?? this.customerId,
      stitchType: stitchType ?? this.stitchType,
      customerGender: customerGender ?? this.customerGender,
      shirtSubType: shirtSubType ?? this.shirtSubType,
      bottomType: bottomType ?? this.bottomType,
      bottomWaistband: bottomWaistband ?? this.bottomWaistband,
      elasticWidth: elasticWidth ?? this.elasticWidth,
      quantity: quantity ?? this.quantity,
      colors: colors ?? this.colors,
      totalAmount: totalAmount ?? this.totalAmount,
      advancePayment: advancePayment ?? this.advancePayment,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      status: status ?? this.status,
      specialInstructions: specialInstructions ?? this.specialInstructions,
      extraInstructions: extraInstructions ?? this.extraInstructions,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
