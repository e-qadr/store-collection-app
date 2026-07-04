import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:store_collection_app/theme/app_theme.dart';

enum ConsumableRequestStatus {
  pendingCollectorReview,
  pendingAccountingApproval,
  approvedByAccountant,
}

extension ConsumableRequestStatusX on ConsumableRequestStatus {
  String get value => name;

  String get label {
    switch (this) {
      case ConsumableRequestStatus.pendingCollectorReview:
        return 'بانتظار مراجعة المدير العام';
      case ConsumableRequestStatus.pendingAccountingApproval:
        return 'بانتظار اعتماد المحاسب';
      case ConsumableRequestStatus.approvedByAccountant:
        return 'معتمد نهائياً';
    }
  }

  Color get color {
    switch (this) {
      case ConsumableRequestStatus.pendingCollectorReview:
        return AppTheme.pendingColor;
      case ConsumableRequestStatus.pendingAccountingApproval:
        return AppTheme.accountantColor;
      case ConsumableRequestStatus.approvedByAccountant:
        return AppTheme.successColor;
    }
  }

  bool get isFinal => this == ConsumableRequestStatus.approvedByAccountant;
}

ConsumableRequestStatus consumableRequestStatusFromString(String? value) {
  return ConsumableRequestStatus.values.firstWhere(
    (status) => status.value == value,
    orElse: () => ConsumableRequestStatus.pendingCollectorReview,
  );
}

class ConsumableRequestFields {
  ConsumableRequestFields._();

  static const collection = 'consumable_requests';
  static const items = 'items';
  static const itemName = 'item_name';
  static const requestedQuantity = 'requested_quantity';
  static const collectorQuantity = 'collector_quantity';
  static const unit = 'unit';
  static const branchId = 'branch_id';
  static const branchName = 'branch_name';
  static const requestNumber = 'request_number';
  static const status = 'status';
  static const managerNotes = 'manager_notes';
  static const collectorNotes = 'collector_notes';
  static const accountantNotes = 'accountant_notes';
  static const accountingReference = 'accounting_reference';
  static const createdBy = 'created_by';
  static const createdAt = 'created_at';
  static const reviewedBy = 'reviewed_by';
  static const reviewedAt = 'reviewed_at';
  static const approvedBy = 'approved_by';
  static const approvedAt = 'approved_at';
  static const lastUpdated = 'last_updated';
  static const history = 'history';
}

class ConsumableRequestRead {
  final String id;
  final Map<String, dynamic> data;

  const ConsumableRequestRead({required this.id, required this.data});

  String get branchId =>
      data[ConsumableRequestFields.branchId]?.toString() ?? '';

  String get branchName =>
      data[ConsumableRequestFields.branchName]?.toString() ?? '';

  String get requestNumber =>
      data[ConsumableRequestFields.requestNumber]?.toString() ??
      'CR-${id.length > 6 ? id.substring(0, 6) : id}';

  String get managerNotes =>
      data[ConsumableRequestFields.managerNotes]?.toString() ?? '';

  String get collectorNotes =>
      data[ConsumableRequestFields.collectorNotes]?.toString() ?? '';

  String get accountantNotes =>
      data[ConsumableRequestFields.accountantNotes]?.toString() ?? '';

  String get accountingReference =>
      data[ConsumableRequestFields.accountingReference]?.toString() ?? '';

  ConsumableRequestStatus get status => consumableRequestStatusFromString(
    data[ConsumableRequestFields.status]?.toString(),
  );

  DateTime? get createdAt => _date(data[ConsumableRequestFields.createdAt]);

  DateTime? get reviewedAt => _date(data[ConsumableRequestFields.reviewedAt]);

  DateTime? get approvedAt => _date(data[ConsumableRequestFields.approvedAt]);

  List<ConsumableRequestItem> get items {
    final value = data[ConsumableRequestFields.items];
    if (value is List && value.isNotEmpty) {
      return value
          .whereType<Map>()
          .map((item) => ConsumableRequestItem.fromMap(item))
          .toList();
    }
    final requested =
        (data[ConsumableRequestFields.requestedQuantity] as num?)?.toDouble() ??
        0;
    return [
      ConsumableRequestItem(
        name: data[ConsumableRequestFields.itemName]?.toString() ?? '',
        unit: data[ConsumableRequestFields.unit]?.toString() ?? '',
        requestedQuantity: requested,
        collectorQuantity:
            (data[ConsumableRequestFields.collectorQuantity] as num?)
                ?.toDouble() ??
            requested,
      ),
    ];
  }

  List<Map<String, dynamic>> get history {
    final value = data[ConsumableRequestFields.history];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  double get totalRequestedQuantity =>
      items.fold<double>(0, (total, item) => total + item.requestedQuantity);

  double get totalCollectorQuantity =>
      items.fold<double>(0, (total, item) => total + item.collectorQuantity);

  bool get hasQuantityChanges =>
      items.any((item) => item.requestedQuantity != item.collectorQuantity);

  static DateTime? _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

class ConsumableRequestItem {
  final String name;
  final String unit;
  final double requestedQuantity;
  final double collectorQuantity;

  const ConsumableRequestItem({
    required this.name,
    required this.unit,
    required this.requestedQuantity,
    double? collectorQuantity,
  }) : collectorQuantity = collectorQuantity ?? requestedQuantity;

  factory ConsumableRequestItem.fromMap(Map<dynamic, dynamic> data) {
    final requested =
        (data[ConsumableRequestFields.requestedQuantity] as num?)?.toDouble() ??
        0;
    return ConsumableRequestItem(
      name:
          data['name']?.toString() ??
          data[ConsumableRequestFields.itemName]?.toString() ??
          '',
      unit: data[ConsumableRequestFields.unit]?.toString() ?? '',
      requestedQuantity: requested,
      collectorQuantity:
          (data[ConsumableRequestFields.collectorQuantity] as num?)
              ?.toDouble() ??
          requested,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      ConsumableRequestFields.unit: unit,
      ConsumableRequestFields.requestedQuantity: requestedQuantity,
      ConsumableRequestFields.collectorQuantity: collectorQuantity,
    };
  }

  ConsumableRequestItem copyWith({
    String? name,
    String? unit,
    double? requestedQuantity,
    double? collectorQuantity,
  }) {
    return ConsumableRequestItem(
      name: name ?? this.name,
      unit: unit ?? this.unit,
      requestedQuantity: requestedQuantity ?? this.requestedQuantity,
      collectorQuantity: collectorQuantity ?? this.collectorQuantity,
    );
  }
}
