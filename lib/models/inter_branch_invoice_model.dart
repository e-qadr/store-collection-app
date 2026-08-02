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
  unknown,
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
      case InterBranchInvoiceStatus.unknown:
        return 'حالة غير معروفة';
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
      case InterBranchInvoiceStatus.unknown:
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

  bool get hasInvoice {
    switch (this) {
      case InterBranchInvoiceStatus.approvedBySupplier:
      case InterBranchInvoiceStatus.invoiceCreated:
      case InterBranchInvoiceStatus.pendingReceiverReview:
      case InterBranchInvoiceStatus.receivedByReceivingManager:
      case InterBranchInvoiceStatus.pendingPriceEntry:
      case InterBranchInvoiceStatus.pricesEnteredByCollector:
      case InterBranchInvoiceStatus.pendingAccountingEntry:
      case InterBranchInvoiceStatus.postedToAccounting:
      case InterBranchInvoiceStatus.cancellationRequested:
      case InterBranchInvoiceStatus.cancellationPendingApprovals:
      case InterBranchInvoiceStatus.cancelled:
      case InterBranchInvoiceStatus.editRequested:
      case InterBranchInvoiceStatus.editPendingApprovals:
      case InterBranchInvoiceStatus.editApproved:
      case InterBranchInvoiceStatus.editRejected:
        return true;
      case InterBranchInvoiceStatus.requestPending:
      case InterBranchInvoiceStatus.requestRejectedBySupplier:
      case InterBranchInvoiceStatus.unknown:
        return false;
    }
  }

  bool get isFinal =>
      this == InterBranchInvoiceStatus.postedToAccounting ||
      this == InterBranchInvoiceStatus.cancelled ||
      this == InterBranchInvoiceStatus.requestRejectedBySupplier;
}

/// Converts canonical and historical aliases without losing the original value.
/// A missing value is the historical request default; an unknown non-empty value
/// stays unknown and must never become an actionable request accidentally.
InterBranchInvoiceStatus interBranchInvoiceStatusFromString(String? value) {
  final clean = value?.trim() ?? '';
  if (clean.isEmpty) return InterBranchInvoiceStatus.requestPending;
  switch (clean) {
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
  for (final status in InterBranchInvoiceStatus.values) {
    if (status != InterBranchInvoiceStatus.unknown && status.value == clean) {
      return status;
    }
  }
  return InterBranchInvoiceStatus.unknown;
}

class InterBranchInvoiceFields {
  InterBranchInvoiceFields._();

  static const collection = 'inter_branch_invoices';
  static const counterCollection = 'inter_branch_invoice_counters';
  static const priceCollection = 'inter_branch_invoice_prices';
  static const priceHistoryCollection = 'inter_branch_invoice_price_history';
  static const schemaVersion = 'schema_version';
  static const workflowVersion = 'workflow_version';
  static const creationMode = 'creation_mode';
  static const revision = 'revision';
  static const itemDigest = 'item_digest';
  static const itemCount = 'item_count';
  static const items = 'items';
  static const itemsSubcollection = 'items';
  static const itemName = 'item_name';
  static const requestedQuantity = 'requested_quantity';
  static const approvedQuantity = 'approved_quantity';
  static const receivedQuantity = 'received_quantity';
  static const unit = 'unit';
  static const receivingBranchId = 'receiving_branch_id';
  static const receivingBranchName = 'receiving_branch_name';
  static const receivingBrandId = 'receiving_brand_id';
  static const sendingBranchId = 'sending_branch_id';
  static const sendingBranchName = 'sending_branch_name';
  static const sendingBrandId = 'sending_brand_id';
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
  static const invoiceNotes = 'invoice_notes';
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
  final List<Map<String, dynamic>>? itemDocuments;

  const InterBranchInvoiceRead({
    required this.id,
    required this.data,
    this.itemDocuments,
  });

  int get schemaVersion =>
      _positiveInt(data[InterBranchInvoiceFields.schemaVersion], 1);
  int get workflowVersion =>
      _positiveInt(data[InterBranchInvoiceFields.workflowVersion], 1);
  bool get isVersion2 => workflowVersion >= 2;
  String get creationMode =>
      data[InterBranchInvoiceFields.creationMode]?.toString() ??
      (isVersion2 ? 'direct_supplier_invoice' : 'legacy_request');
  int get revision =>
      _positiveInt(data[InterBranchInvoiceFields.revision], isVersion2 ? 1 : 0);
  String get itemDigest =>
      data[InterBranchInvoiceFields.itemDigest]?.toString().trim() ?? '';
  int get itemCount => isVersion2
      ? _positiveInt(data[InterBranchInvoiceFields.itemCount], 0)
      : items.length;
  bool get itemsLoaded => !isVersion2 || itemDocuments != null;

  InterBranchInvoiceRead withItemDocuments(
    List<Map<String, dynamic>> documents,
  ) => InterBranchInvoiceRead(
    id: id,
    data: data,
    itemDocuments: documents,
  );

  String get rawStatus =>
      data[InterBranchInvoiceFields.status]?.toString().trim() ?? '';
  InterBranchInvoiceStatus get effectiveStatus =>
      rawStatus.isEmpty && isVersion2
      ? InterBranchInvoiceStatus.unknown
      : interBranchInvoiceStatusFromString(rawStatus);
  InterBranchInvoiceStatus get status => effectiveStatus;

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
  String get receivingBrandId =>
      data[InterBranchInvoiceFields.receivingBrandId]?.toString() ?? '';
  String get sendingBrandId =>
      data[InterBranchInvoiceFields.sendingBrandId]?.toString() ?? '';
  List<String> get branchIds {
    final value = data[InterBranchInvoiceFields.branchIds];
    if (value is List) {
      return value
          .map((item) => item.toString())
          .where((id) => id.isNotEmpty)
          .toList();
    }
    return {
      sendingBranchId,
      receivingBranchId,
    }.where((id) => id.isNotEmpty).toList();
  }

  String get invoiceNumber =>
      data[InterBranchInvoiceFields.invoiceNumber]?.toString() ?? '-';
  String get accountingReference =>
      data[InterBranchInvoiceFields.accountingReference]?.toString() ?? '';
  String get rejectionReason =>
      data[InterBranchInvoiceFields.rejectionReason]?.toString() ?? '';
  String get invoiceNotes =>
      data[InterBranchInvoiceFields.invoiceNotes]?.toString() ?? '';
  String get receiverNotes =>
      data[InterBranchInvoiceFields.receiverNotes]?.toString() ?? '';

  double get requestedQuantity => items.isNotEmpty
      ? items.fold<double>(0, (total, item) => total + item.suppliedQuantity)
      : _number(data[InterBranchInvoiceFields.requestedQuantity]) ?? 0;
  double? get approvedQuantity => items.isNotEmpty
      ? items.fold<double>(0, (total, item) => total + item.approvedQuantity)
      : _number(data[InterBranchInvoiceFields.approvedQuantity]);
  double? get receivedQuantity {
    if (items.isNotEmpty) {
      if (isVersion2 && items.any((item) => !item.hasReceivedQuantity)) {
        return null;
      }
      return items.fold<double>(
        0,
        (total, item) => total + item.receivedQuantity,
      );
    }
    return _number(data[InterBranchInvoiceFields.receivedQuantity]);
  }

  /// Legacy prices are intentionally ignored for workflow-v2 public documents.
  double? get unitPrice => isVersion2
      ? null
      : items.length == 1
      ? items.first.unitPrice
      : _number(data[InterBranchInvoiceFields.unitPrice]);
  double? get totalPrice => isVersion2
      ? null
      : items.isNotEmpty
      ? items.fold<double>(0, (total, item) => total + item.totalPrice)
      : _number(data[InterBranchInvoiceFields.totalPrice]);

  DateTime? get requestDate =>
      _date(data[InterBranchInvoiceFields.requestDate]);
  DateTime? get invoiceCreatedAt =>
      _date(data[InterBranchInvoiceFields.invoiceCreatedAt]) ??
      (isVersion2 ? createdAt : null);
  DateTime? get createdAt => _date(data[InterBranchInvoiceFields.createdAt]);
  DateTime? get lastUpdated =>
      _date(data[InterBranchInvoiceFields.lastUpdated]);
  DateTime? get postedAt => _date(data[InterBranchInvoiceFields.postedAt]);

  double get displayQuantity =>
      receivedQuantity ?? approvedQuantity ?? requestedQuantity;
  bool get hasPrices => !isVersion2 && unitPrice != null && totalPrice != null;

  List<InterBranchInvoiceItem> get items {
    if (isVersion2) {
      final documents = itemDocuments;
      if (documents == null) return const [];
      final ordered = [...documents]..sort((left, right) {
        final leftLine = (left['line_number'] as num?)?.toInt() ?? 0;
        final rightLine = (right['line_number'] as num?)?.toInt() ?? 0;
        return leftLine.compareTo(rightLine);
      });
      return ordered
          .map(
            (item) => InterBranchInvoiceItem.fromMap(
              item,
              allowLegacyPrices: false,
            ),
          )
          .toList(growable: false);
    }
    final value = data[InterBranchInvoiceFields.items];
    if (value is List && value.isNotEmpty) {
      return value
          .whereType<Map>()
          .map(
            (item) => InterBranchInvoiceItem.fromMap(
              item,
              allowLegacyPrices: !isVersion2,
            ),
          )
          .toList(growable: false);
    }
    return [
      InterBranchInvoiceItem(
        name: data[InterBranchInvoiceFields.itemName]?.toString() ?? '',
        unit: data[InterBranchInvoiceFields.unit]?.toString() ?? '',
        requestedQuantity:
            _number(data[InterBranchInvoiceFields.requestedQuantity]) ?? 0,
        approvedQuantity:
            _number(data[InterBranchInvoiceFields.approvedQuantity]) ??
            _number(data[InterBranchInvoiceFields.requestedQuantity]) ??
            0,
        receivedQuantity:
            _number(data[InterBranchInvoiceFields.receivedQuantity]) ??
            _number(data[InterBranchInvoiceFields.approvedQuantity]) ??
            _number(data[InterBranchInvoiceFields.requestedQuantity]) ??
            0,
        hasReceivedQuantity: data.containsKey(
          InterBranchInvoiceFields.receivedQuantity,
        ),
        unitPrice: isVersion2
            ? null
            : _number(data[InterBranchInvoiceFields.unitPrice]),
      ),
    ];
  }

  List<Map<String, dynamic>> get history {
    final value = data[InterBranchInvoiceFields.history];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
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
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(value);
  }
}

class InterBranchInvoiceItem {
  final String itemId;
  final String productId;
  final int productVersion;
  final String groupId;
  final String groupName;
  final String? legacyCode;
  final String name;
  final String unitId;
  final String unit;
  final String rawUnit;
  final double requestedQuantity;
  final double approvedQuantity;
  final double receivedQuantity;
  final bool hasReceivedQuantity;
  final double missingQuantity;
  final double damagedQuantity;
  final String lineNotes;
  final String discrepancyNotes;
  final double? unitPrice;

  const InterBranchInvoiceItem({
    this.itemId = '',
    this.productId = '',
    this.productVersion = 0,
    this.groupId = '',
    this.groupName = '',
    this.legacyCode,
    required this.name,
    this.unitId = '',
    required this.unit,
    this.rawUnit = '',
    required this.requestedQuantity,
    double? approvedQuantity,
    double? receivedQuantity,
    this.hasReceivedQuantity = true,
    this.missingQuantity = 0,
    this.damagedQuantity = 0,
    this.lineNotes = '',
    this.discrepancyNotes = '',
    this.unitPrice,
  }) : approvedQuantity = approvedQuantity ?? requestedQuantity,
       receivedQuantity =
           receivedQuantity ?? approvedQuantity ?? requestedQuantity;

  double get suppliedQuantity => requestedQuantity;
  double? get actualReceivedQuantity =>
      hasReceivedQuantity ? receivedQuantity : null;
  double get totalPrice =>
      unitPrice == null ? 0 : unitPrice! * receivedQuantity;

  bool get hasStableCatalogReference =>
      itemId.isNotEmpty && productId.isNotEmpty && unitId.isNotEmpty;

  factory InterBranchInvoiceItem.fromMap(
    Map<dynamic, dynamic> data, {
    bool allowLegacyPrices = true,
  }) {
    final supplied =
        _number(data['supplied_quantity']) ??
        _number(data['requested_quantity']) ??
        0;
    final approved = _number(data['approved_quantity']) ?? supplied;
    final unitValue =
        _firstString(data, const [
          'unit_value_snapshot',
          'unit_snapshot',
          'unit_value',
          'unit',
        ]) ??
        '';
    final hasReceivedQuantity = data.containsKey('received_quantity');
    return InterBranchInvoiceItem(
      itemId: data['item_id']?.toString() ?? '',
      productId: data['product_id']?.toString() ?? '',
      productVersion: (data['product_version'] as num?)?.toInt() ?? 0,
      groupId: data['group_id']?.toString() ?? '',
      groupName:
          _firstString(data, const ['group_name_snapshot', 'group_name']) ?? '',
      legacyCode: _firstString(data, const [
        'legacy_code_snapshot',
        'product_legacy_code',
        'legacy_code',
      ]),
      name:
          _firstString(data, const [
            'product_name_snapshot',
            'product_name',
            'name_snapshot',
            'name',
            'item_name',
          ]) ??
          '',
      unitId: data['unit_id']?.toString() ?? '',
      unit: unitValue,
      rawUnit:
          _firstString(data, const [
            'raw_unit_snapshot',
            'unit_raw_value',
            'raw_unit',
          ]) ??
          unitValue,
      requestedQuantity: supplied,
      approvedQuantity: approved,
      receivedQuantity: _number(data['received_quantity']) ?? approved,
      hasReceivedQuantity: hasReceivedQuantity,
      missingQuantity: _number(data['missing_quantity']) ?? 0,
      damagedQuantity: _number(data['damaged_quantity']) ?? 0,
      lineNotes: data['line_notes']?.toString() ?? '',
      discrepancyNotes:
          _firstString(data, const ['discrepancy_notes', 'discrepancy_note']) ??
          '',
      unitPrice: allowLegacyPrices ? _number(data['unit_price']) : null,
    );
  }

  /// Historical serialization retained only for version-1 client operations.
  Map<String, dynamic> toMap() => toLegacyMap();

  Map<String, dynamic> toLegacyMap() {
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

  /// Minimal price-free command input. The backend resolves every snapshot.
  Map<String, dynamic> toDirectCommandMap() {
    return {
      'product_id': productId,
      'unit_id': unitId,
      'supplied_quantity': suppliedQuantity,
      if (lineNotes.trim().isNotEmpty) 'line_notes': lineNotes.trim(),
    };
  }

  Map<String, dynamic> toReceiptCommandMap() {
    return {
      'item_id': itemId,
      'received_quantity': receivedQuantity,
      if (missingQuantity > 0) 'missing_quantity': missingQuantity,
      if (damagedQuantity > 0) 'damaged_quantity': damagedQuantity,
      if (discrepancyNotes.trim().isNotEmpty)
        'discrepancy_notes': discrepancyNotes.trim(),
    };
  }

  InterBranchInvoiceItem copyWith({
    String? itemId,
    String? productId,
    int? productVersion,
    String? groupId,
    String? groupName,
    String? legacyCode,
    String? name,
    String? unitId,
    String? unit,
    String? rawUnit,
    double? requestedQuantity,
    double? approvedQuantity,
    double? receivedQuantity,
    bool? hasReceivedQuantity,
    double? missingQuantity,
    double? damagedQuantity,
    String? lineNotes,
    String? discrepancyNotes,
    double? unitPrice,
  }) {
    return InterBranchInvoiceItem(
      itemId: itemId ?? this.itemId,
      productId: productId ?? this.productId,
      productVersion: productVersion ?? this.productVersion,
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      legacyCode: legacyCode ?? this.legacyCode,
      name: name ?? this.name,
      unitId: unitId ?? this.unitId,
      unit: unit ?? this.unit,
      rawUnit: rawUnit ?? this.rawUnit,
      requestedQuantity: requestedQuantity ?? this.requestedQuantity,
      approvedQuantity: approvedQuantity ?? this.approvedQuantity,
      receivedQuantity: receivedQuantity ?? this.receivedQuantity,
      hasReceivedQuantity: hasReceivedQuantity ?? this.hasReceivedQuantity,
      missingQuantity: missingQuantity ?? this.missingQuantity,
      damagedQuantity: damagedQuantity ?? this.damagedQuantity,
      lineNotes: lineNotes ?? this.lineNotes,
      discrepancyNotes: discrepancyNotes ?? this.discrepancyNotes,
      unitPrice: unitPrice ?? this.unitPrice,
    );
  }
}

double? _number(dynamic value) => value is num ? value.toDouble() : null;

int _positiveInt(dynamic value, int fallback) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  return number != null && number > 0 ? number : fallback;
}

String? _firstString(Map<dynamic, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}
