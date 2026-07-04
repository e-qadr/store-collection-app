import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum InterBranchInvoiceStatus {
  requestPending,
  requestRejectedBySupplier,
  approvedBySupplier,
  invoiceCreated,
  pendingReceiverReview,
  receivedByReceivingManager,
  pendingPriceEntry,
  pricesEnteredByCollector,
  pendingAccountingEntry,
  postedToAccounting,
  cancellationRequested,
  cancellationPendingApprovals,
  cancelled,
  editRequested,
  editPendingApprovals,
  editApproved,
  editRejected,
}

extension InterBranchInvoiceStatusX on InterBranchInvoiceStatus {
  String get value => name;

  String get label {
    switch (this) {
      case InterBranchInvoiceStatus.requestPending:
        return 'بانتظار موافقة الفرع المورد';
      case InterBranchInvoiceStatus.requestRejectedBySupplier:
        return 'مرفوض من الفرع المورد';
      case InterBranchInvoiceStatus.approvedBySupplier:
        return 'معتمد من الفرع المورد';
      case InterBranchInvoiceStatus.invoiceCreated:
        return 'تم إنشاء الفاتورة';
      case InterBranchInvoiceStatus.pendingReceiverReview:
        return 'بانتظار مراجعة الفرع المستلم';
      case InterBranchInvoiceStatus.receivedByReceivingManager:
        return 'تم استلام البضاعة';
      case InterBranchInvoiceStatus.pendingPriceEntry:
        return 'بانتظار إدخال الأسعار';
      case InterBranchInvoiceStatus.pricesEnteredByCollector:
        return 'تم إدخال الأسعار';
      case InterBranchInvoiceStatus.pendingAccountingEntry:
        return 'بانتظار الإدخال المحاسبي';
      case InterBranchInvoiceStatus.postedToAccounting:
        return 'مرحلة محاسبياً';
      case InterBranchInvoiceStatus.cancellationRequested:
        return 'طلب إلغاء';
      case InterBranchInvoiceStatus.cancellationPendingApprovals:
        return 'إلغاء بانتظار الموافقات';
      case InterBranchInvoiceStatus.cancelled:
        return 'ملغاة';
      case InterBranchInvoiceStatus.editRequested:
        return 'طلب تعديل';
      case InterBranchInvoiceStatus.editPendingApprovals:
        return 'تعديل بانتظار الموافقات';
      case InterBranchInvoiceStatus.editApproved:
        return 'تمت الموافقة على التعديل';
      case InterBranchInvoiceStatus.editRejected:
        return 'تم رفض التعديل';
    }
  }

  Color get color {
    switch (this) {
      case InterBranchInvoiceStatus.requestPending:
      case InterBranchInvoiceStatus.pendingReceiverReview:
      case InterBranchInvoiceStatus.pendingPriceEntry:
      case InterBranchInvoiceStatus.pendingAccountingEntry:
        return const Color(0xFFF57C00);
      case InterBranchInvoiceStatus.approvedBySupplier:
      case InterBranchInvoiceStatus.invoiceCreated:
      case InterBranchInvoiceStatus.receivedByReceivingManager:
      case InterBranchInvoiceStatus.pricesEnteredByCollector:
        return const Color(0xFF1565C0);
      case InterBranchInvoiceStatus.requestRejectedBySupplier:
      case InterBranchInvoiceStatus.cancelled:
      case InterBranchInvoiceStatus.editRejected:
        return const Color(0xFFC62828);
      case InterBranchInvoiceStatus.postedToAccounting:
      case InterBranchInvoiceStatus.editApproved:
        return const Color(0xFF2E7D32);
      case InterBranchInvoiceStatus.cancellationRequested:
      case InterBranchInvoiceStatus.cancellationPendingApprovals:
      case InterBranchInvoiceStatus.editRequested:
      case InterBranchInvoiceStatus.editPendingApprovals:
        return const Color(0xFF6A1B9A);
    }
  }

  bool get hasInvoice =>
      index >= InterBranchInvoiceStatus.approvedBySupplier.index &&
      this != InterBranchInvoiceStatus.requestRejectedBySupplier;

  bool get isFinal =>
      this == InterBranchInvoiceStatus.postedToAccounting ||
      this == InterBranchInvoiceStatus.cancelled ||
      this == InterBranchInvoiceStatus.requestRejectedBySupplier;
}

InterBranchInvoiceStatus interBranchInvoiceStatusFromString(String? value) {
  switch (value) {
    case 'pendingSenderReview':
      return InterBranchInvoiceStatus.requestPending;
    case 'approvedBySender':
      return InterBranchInvoiceStatus.pendingReceiverReview;
    case 'rejectedBySender':
      return InterBranchInvoiceStatus.requestRejectedBySupplier;
    case 'receivedByReceivingBranch':
      return InterBranchInvoiceStatus.pendingPriceEntry;
    case 'pricedByGeneralManager':
      return InterBranchInvoiceStatus.pendingAccountingEntry;
    case 'approvedByAccountant':
      return InterBranchInvoiceStatus.postedToAccounting;
  }
  return InterBranchInvoiceStatus.values.firstWhere(
    (status) => status.value == value,
    orElse: () => InterBranchInvoiceStatus.requestPending,
  );
}

class InterBranchInvoiceFields {
  InterBranchInvoiceFields._();

  static const collection = 'inter_branch_invoices';
  static const counterCollection = 'inter_branch_invoice_counters';
  static const items = 'items';
  static const itemName = 'item_name';
  static const requestedQuantity = 'requested_quantity';
  static const approvedQuantity = 'approved_quantity';
  static const receivedQuantity = 'received_quantity';
  static const unit = 'unit';
  static const receivingBranchId = 'receiving_branch_id';
  static const receivingBranchName = 'receiving_branch_name';
  static const sendingBranchId = 'sending_branch_id';
  static const sendingBranchName = 'sending_branch_name';
  static const branchIds = 'branch_ids';
  static const requestDate = 'request_date';
  static const status = 'status';
  static const invoiceNumber = 'invoice_number';
  static const invoiceCreatedAt = 'invoice_created_at';
  static const approvedBy = 'approved_by';
  static const approvedAt = 'approved_at';
  static const unitPrice = 'unit_price';
  static const totalPrice = 'total_price';
  static const accountingReference = 'accounting_reference';
  static const postedAt = 'posted_at';
  static const senderNotes = 'sender_notes';
  static const receiverNotes = 'receiver_notes';
  static const collectorNotes = 'collector_notes';
  static const generalManagerNotes = 'general_manager_notes';
  static const accountantNotes = 'accountant_notes';
  static const rejectionReason = 'rejection_reason';
  static const cancellationRequest = 'cancellation_request';
  static const cancellationApprovals = 'cancellation_approvals';
  static const editRequest = 'edit_request';
  static const editApprovals = 'edit_approvals';
  static const previousStatus = 'previous_status';
  static const createdBy = 'created_by';
  static const createdAt = 'created_at';
  static const lastUpdated = 'last_updated';
  static const history = 'history';
}

class InterBranchInvoiceRead {
  final String id;
  final Map<String, dynamic> data;

  const InterBranchInvoiceRead({required this.id, required this.data});

  String get itemName => items.isNotEmpty
      ? items.first.name
      : data[InterBranchInvoiceFields.itemName]?.toString() ?? '';

  String get unit => items.isNotEmpty
      ? items.first.unit
      : data[InterBranchInvoiceFields.unit]?.toString() ?? '';

  String get receivingBranchName =>
      data[InterBranchInvoiceFields.receivingBranchName]?.toString() ?? '';

  String get sendingBranchName =>
      data[InterBranchInvoiceFields.sendingBranchName]?.toString() ?? '';

  String get receivingBranchId =>
      data[InterBranchInvoiceFields.receivingBranchId]?.toString() ?? '';

  String get sendingBranchId =>
      data[InterBranchInvoiceFields.sendingBranchId]?.toString() ?? '';

  String get invoiceNumber =>
      data[InterBranchInvoiceFields.invoiceNumber]?.toString() ?? '-';

  String get accountingReference =>
      data[InterBranchInvoiceFields.accountingReference]?.toString() ?? '';

  String get rejectionReason =>
      data[InterBranchInvoiceFields.rejectionReason]?.toString() ?? '';

  double get requestedQuantity => items.isNotEmpty
      ? items.fold<double>(0, (total, item) => total + item.requestedQuantity)
      : (data[InterBranchInvoiceFields.requestedQuantity] as num?)
                ?.toDouble() ??
            0;

  double? get approvedQuantity => items.isNotEmpty
      ? items.fold<double>(0, (total, item) => total + item.approvedQuantity)
      : (data[InterBranchInvoiceFields.approvedQuantity] as num?)?.toDouble();

  double? get receivedQuantity => items.isNotEmpty
      ? items.fold<double>(0, (total, item) => total + item.receivedQuantity)
      : (data[InterBranchInvoiceFields.receivedQuantity] as num?)?.toDouble();

  double? get unitPrice => items.length == 1
      ? items.first.unitPrice
      : (data[InterBranchInvoiceFields.unitPrice] as num?)?.toDouble();

  double? get totalPrice => items.isNotEmpty
      ? items.fold<double>(0, (total, item) => total + item.totalPrice)
      : (data[InterBranchInvoiceFields.totalPrice] as num?)?.toDouble();

  InterBranchInvoiceStatus get status =>
      interBranchInvoiceStatusFromString(data[InterBranchInvoiceFields.status]);

  DateTime? get requestDate =>
      _date(data[InterBranchInvoiceFields.requestDate]);

  DateTime? get invoiceCreatedAt =>
      _date(data[InterBranchInvoiceFields.invoiceCreatedAt]);

  DateTime? get createdAt => _date(data[InterBranchInvoiceFields.createdAt]);

  DateTime? get postedAt => _date(data[InterBranchInvoiceFields.postedAt]);

  double get displayQuantity =>
      receivedQuantity ?? approvedQuantity ?? requestedQuantity;

  bool get hasPrices => unitPrice != null && totalPrice != null;

  List<InterBranchInvoiceItem> get items {
    final value = data[InterBranchInvoiceFields.items];
    if (value is List && value.isNotEmpty) {
      return value
          .whereType<Map>()
          .map((item) => InterBranchInvoiceItem.fromMap(item))
          .toList();
    }
    return [
      InterBranchInvoiceItem(
        name: data[InterBranchInvoiceFields.itemName]?.toString() ?? '',
        unit: data[InterBranchInvoiceFields.unit]?.toString() ?? '',
        requestedQuantity:
            (data[InterBranchInvoiceFields.requestedQuantity] as num?)
                ?.toDouble() ??
            0,
        approvedQuantity:
            (data[InterBranchInvoiceFields.approvedQuantity] as num?)
                ?.toDouble() ??
            (data[InterBranchInvoiceFields.requestedQuantity] as num?)
                ?.toDouble() ??
            0,
        receivedQuantity:
            (data[InterBranchInvoiceFields.receivedQuantity] as num?)
                ?.toDouble() ??
            (data[InterBranchInvoiceFields.approvedQuantity] as num?)
                ?.toDouble() ??
            (data[InterBranchInvoiceFields.requestedQuantity] as num?)
                ?.toDouble() ??
            0,
        unitPrice: (data[InterBranchInvoiceFields.unitPrice] as num?)
            ?.toDouble(),
      ),
    ];
  }

  List<Map<String, dynamic>> get history {
    final value = data[InterBranchInvoiceFields.history];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Map<String, dynamic> get cancellationApprovals =>
      _map(data[InterBranchInvoiceFields.cancellationApprovals]);

  Map<String, dynamic> get editApprovals =>
      _map(data[InterBranchInvoiceFields.editApprovals]);

  Map<String, dynamic> get cancellationRequest =>
      _map(data[InterBranchInvoiceFields.cancellationRequest]);

  Map<String, dynamic> get editRequest =>
      _map(data[InterBranchInvoiceFields.editRequest]);

  static DateTime? _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(value);
  }
}

class InterBranchInvoiceItem {
  final String name;
  final String unit;
  final double requestedQuantity;
  final double approvedQuantity;
  final double receivedQuantity;
  final double? unitPrice;

  const InterBranchInvoiceItem({
    required this.name,
    required this.unit,
    required this.requestedQuantity,
    double? approvedQuantity,
    double? receivedQuantity,
    this.unitPrice,
  }) : approvedQuantity = approvedQuantity ?? requestedQuantity,
       receivedQuantity =
           receivedQuantity ?? approvedQuantity ?? requestedQuantity;

  double get totalPrice =>
      unitPrice == null ? 0 : unitPrice! * receivedQuantity;

  factory InterBranchInvoiceItem.fromMap(Map<dynamic, dynamic> data) {
    final requested = (data['requested_quantity'] as num?)?.toDouble() ?? 0;
    final approved =
        (data['approved_quantity'] as num?)?.toDouble() ?? requested;
    return InterBranchInvoiceItem(
      name: data['name']?.toString() ?? data['item_name']?.toString() ?? '',
      unit: data['unit']?.toString() ?? '',
      requestedQuantity: requested,
      approvedQuantity: approved,
      receivedQuantity:
          (data['received_quantity'] as num?)?.toDouble() ?? approved,
      unitPrice: (data['unit_price'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'unit': unit,
      'requested_quantity': requestedQuantity,
      'approved_quantity': approvedQuantity,
      'received_quantity': receivedQuantity,
      if (unitPrice != null) 'unit_price': unitPrice,
      if (unitPrice != null) 'total_price': totalPrice,
    };
  }
}
