import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum PurchaseInvoiceStatus {
  pendingReceiverReview,
  pendingPriceEntry,
  pendingAccountingEntry,
  postedToAccounting,
  unknown,
}

extension PurchaseInvoiceStatusX on PurchaseInvoiceStatus {
  String get value => name;

  String get label => switch (this) {
    PurchaseInvoiceStatus.pendingReceiverReview => 'بانتظار تأكيد مدير الفرع',
    PurchaseInvoiceStatus.pendingPriceEntry => 'بانتظار اعتماد الأسعار',
    PurchaseInvoiceStatus.pendingAccountingEntry => 'بانتظار المحاسب',
    PurchaseInvoiceStatus.postedToAccounting => 'مكتملة ومُرحّلة محاسبياً',
    PurchaseInvoiceStatus.unknown => 'حالة غير معروفة',
  };

  Color get color => switch (this) {
    PurchaseInvoiceStatus.pendingReceiverReview ||
    PurchaseInvoiceStatus.pendingPriceEntry ||
    PurchaseInvoiceStatus.pendingAccountingEntry => const Color(0xFFF57C00),
    PurchaseInvoiceStatus.postedToAccounting => const Color(0xFF2E7D32),
    PurchaseInvoiceStatus.unknown => const Color(0xFFC62828),
  };
}

PurchaseInvoiceStatus purchaseInvoiceStatusFromString(String? value) {
  return PurchaseInvoiceStatus.values.firstWhere(
    (status) => status != PurchaseInvoiceStatus.unknown && status.name == value,
    orElse: () => PurchaseInvoiceStatus.unknown,
  );
}

class PurchaseInvoiceCollections {
  PurchaseInvoiceCollections._();

  static const invoices = 'purchase_invoices';
  static const events = 'purchase_invoice_events';
  static const prices = 'purchase_invoice_prices';
  static const amendments = 'purchase_invoice_amendments';
  static const amendmentPrices = 'purchase_invoice_amendment_prices';
  static const reviewTasks = 'product_review_tasks';
  static const items = 'items';
}

class PurchaseInvoiceRead {
  final String id;
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>>? itemDocuments;

  PurchaseInvoiceRead({
    required this.id,
    required Map<String, dynamic> data,
    List<Map<String, dynamic>>? itemDocuments,
  }) : data = _sanitizePurchaseHeader(data),
       itemDocuments = itemDocuments == null
           ? null
           : List.unmodifiable(itemDocuments.map(_sanitizePurchaseItem));

  PurchaseInvoiceRead withItems(List<Map<String, dynamic>> items) =>
      PurchaseInvoiceRead(id: id, data: data, itemDocuments: items);

  int get schemaVersion => (data['schema_version'] as num?)?.toInt() ?? 0;
  int get workflowVersion => (data['workflow_version'] as num?)?.toInt() ?? 0;
  String get workflowIdentity => data['workflow_identity']?.toString() ?? '';
  int get revision => (data['revision'] as num?)?.toInt() ?? 0;
  int get itemCount => (data['item_count'] as num?)?.toInt() ?? 0;
  String get itemDigest => data['item_digest']?.toString() ?? '';
  PurchaseInvoiceStatus get status =>
      purchaseInvoiceStatusFromString(data['status']?.toString());
  String get purchaseNumber => data['purchase_number']?.toString() ?? '-';
  String get receivingBranchId => data['receiving_branch_id']?.toString() ?? '';
  String get receivingBranchName =>
      data['receiving_branch_name']?.toString() ?? '';
  String get receivingBrandId => data['receiving_brand_id']?.toString() ?? '';
  String get currency => data['currency']?.toString() ?? '';
  String get supplierName => data['supplier_name']?.toString() ?? '';
  String get supplierInvoiceNumber =>
      data['supplier_invoice_number']?.toString() ?? '';
  String get supplierInvoiceDate =>
      data['supplier_invoice_date']?.toString() ?? '';
  String get generalManagerNotes =>
      data['general_manager_notes']?.toString() ?? '';
  String get receiverNotes => data['receiver_notes']?.toString() ?? '';
  bool get postedWithUnresolvedOverride =>
      data['posted_with_unresolved_override'] == true;
  DateTime? get createdAt => _date(data['created_at']);
  DateTime? get receiptConfirmedAt => _date(data['receipt_confirmed_at']);
  DateTime? get postedAt => _date(data['posted_at']);
  DateTime? get lastUpdated => _date(data['last_updated']);
  String get openAmendmentId => data['open_amendment_id']?.toString() ?? '';
  bool get hasPendingAmendment => openAmendmentId.isNotEmpty;

  String get currentResponsibleParty => switch (status) {
    PurchaseInvoiceStatus.pendingReceiverReview => 'مدير الفرع المستلم',
    PurchaseInvoiceStatus.pendingPriceEntry => 'المدير العام',
    PurchaseInvoiceStatus.pendingAccountingEntry => 'المحاسب',
    PurchaseInvoiceStatus.postedToAccounting => 'مكتملة',
    PurchaseInvoiceStatus.unknown => 'غير محدد',
  };

  List<PurchaseInvoiceItem> get items {
    final documents = itemDocuments;
    if (documents == null) return const [];
    final sorted = [...documents]
      ..sort(
        (left, right) => ((left['line_number'] as num?)?.toInt() ?? 0)
            .compareTo((right['line_number'] as num?)?.toInt() ?? 0),
      );
    return sorted.map(PurchaseInvoiceItem.fromMap).toList(growable: false);
  }

  List<PurchaseInvoiceHistoryEvent> get history {
    final raw = data['history'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (event) => PurchaseInvoiceHistoryEvent.fromMap(
            Map<String, dynamic>.from(event),
          ),
        )
        .toList(growable: false);
  }
}

const _purchaseHeaderFields = <String>{
  'id',
  'schema_version',
  'workflow_version',
  'workflow_identity',
  'status',
  'revision',
  'purchase_number',
  'receiving_branch_id',
  'receiving_branch_name',
  'receiving_brand_id',
  'branch_ids',
  'item_count',
  'item_digest',
  'currency',
  'supplier_name',
  'supplier_invoice_number',
  'supplier_invoice_date',
  'general_manager_notes',
  'receiver_notes',
  'created_by',
  'created_by_name',
  'created_by_role',
  'created_at',
  'receipt_confirmed_by',
  'receipt_confirmed_by_name',
  'receipt_confirmed_at',
  'posted_by',
  'posted_by_name',
  'posted_at',
  'posted_with_unresolved_override',
  'last_updated',
  'open_amendment_id',
  'open_amendment_status',
  'history',
};

const _purchaseItemFields = <String>{
  'id',
  'invoice_id',
  'schema_version',
  'workflow_version',
  'workflow_identity',
  'invoice_revision',
  'branch_ids',
  'receiving_branch_id',
  'receiving_brand_id',
  'line_number',
  'item_id',
  'source_type',
  'original_material_name',
  'original_group_text',
  'original_unit_text',
  'canonical_product_id',
  'canonical_product_version',
  'canonical_product_name',
  'canonical_product_legacy_code',
  'canonical_group_id',
  'canonical_group_name',
  'canonical_group_legacy_code',
  'canonical_unit_id',
  'canonical_unit_value',
  'canonical_unit_raw_value',
  'review_task_id',
  'review_status',
  'ordered_quantity',
  'line_notes',
  'received_quantity',
  'damaged_quantity',
  'missing_quantity',
  'discrepancy_notes',
};

const _purchaseHistoryFields = <String>{
  'action',
  'message',
  'actor_id',
  'actor_name',
  'actor_role',
  'timestamp',
};

Map<String, dynamic> _sanitizePurchaseHeader(Map<String, dynamic> input) {
  final result = <String, dynamic>{
    for (final entry in input.entries)
      if (_purchaseHeaderFields.contains(entry.key)) entry.key: entry.value,
  };
  final history = result['history'];
  if (history is List) {
    result['history'] = List.unmodifiable(
      history.whereType<Map>().map(
        (event) => Map<String, dynamic>.unmodifiable({
          for (final entry in event.entries)
            if (_purchaseHistoryFields.contains(entry.key.toString()))
              entry.key.toString(): entry.value,
        }),
      ),
    );
  }
  return Map.unmodifiable(result);
}

Map<String, dynamic> _sanitizePurchaseItem(Map<String, dynamic> input) =>
    Map.unmodifiable({
      for (final entry in input.entries)
        if (_purchaseItemFields.contains(entry.key)) entry.key: entry.value,
    });

class PurchaseInvoiceItem {
  final String id;
  final int lineNumber;
  final String sourceType;
  final String originalMaterialName;
  final String originalGroupText;
  final String originalUnitText;
  final String canonicalProductId;
  final int canonicalProductVersion;
  final String canonicalProductName;
  final String canonicalProductLegacyCode;
  final String canonicalGroupId;
  final String canonicalGroupName;
  final String canonicalUnitId;
  final String canonicalUnitValue;
  final String canonicalUnitRawValue;
  final String reviewTaskId;
  final String reviewStatus;
  final double orderedQuantity;
  final double? receivedQuantity;
  final double damagedQuantity;
  final double missingQuantity;
  final String lineNotes;
  final String discrepancyNotes;

  const PurchaseInvoiceItem({
    required this.id,
    required this.lineNumber,
    required this.sourceType,
    required this.originalMaterialName,
    required this.originalGroupText,
    required this.originalUnitText,
    required this.reviewStatus,
    required this.orderedQuantity,
    this.canonicalProductId = '',
    this.canonicalProductVersion = 0,
    this.canonicalProductName = '',
    this.canonicalProductLegacyCode = '',
    this.canonicalGroupId = '',
    this.canonicalGroupName = '',
    this.canonicalUnitId = '',
    this.canonicalUnitValue = '',
    this.canonicalUnitRawValue = '',
    this.reviewTaskId = '',
    this.receivedQuantity,
    this.damagedQuantity = 0,
    this.missingQuantity = 0,
    this.lineNotes = '',
    this.discrepancyNotes = '',
  });

  factory PurchaseInvoiceItem.fromMap(Map<String, dynamic> data) {
    return PurchaseInvoiceItem(
      id: data['item_id']?.toString() ?? data['id']?.toString() ?? '',
      lineNumber: (data['line_number'] as num?)?.toInt() ?? 0,
      sourceType: data['source_type']?.toString() ?? '',
      originalMaterialName: data['original_material_name']?.toString() ?? '',
      originalGroupText: data['original_group_text']?.toString() ?? '',
      originalUnitText: data['original_unit_text']?.toString() ?? '',
      canonicalProductId: data['canonical_product_id']?.toString() ?? '',
      canonicalProductVersion:
          (data['canonical_product_version'] as num?)?.toInt() ?? 0,
      canonicalProductName: data['canonical_product_name']?.toString() ?? '',
      canonicalProductLegacyCode:
          data['canonical_product_legacy_code']?.toString() ?? '',
      canonicalGroupId: data['canonical_group_id']?.toString() ?? '',
      canonicalGroupName: data['canonical_group_name']?.toString() ?? '',
      canonicalUnitId: data['canonical_unit_id']?.toString() ?? '',
      canonicalUnitValue: data['canonical_unit_value']?.toString() ?? '',
      canonicalUnitRawValue: data['canonical_unit_raw_value']?.toString() ?? '',
      reviewTaskId: data['review_task_id']?.toString() ?? '',
      reviewStatus: data['review_status']?.toString() ?? '',
      orderedQuantity: (data['ordered_quantity'] as num?)?.toDouble() ?? 0,
      receivedQuantity: (data['received_quantity'] as num?)?.toDouble(),
      damagedQuantity: (data['damaged_quantity'] as num?)?.toDouble() ?? 0,
      missingQuantity: (data['missing_quantity'] as num?)?.toDouble() ?? 0,
      lineNotes: data['line_notes']?.toString() ?? '',
      discrepancyNotes: data['discrepancy_notes']?.toString() ?? '',
    );
  }

  bool get isUnmatched => sourceType == 'unmatched';
  bool get isResolved => const {
    'linked_material',
    'newly_created_material',
    'synchronized',
  }.contains(reviewStatus);
  bool get needsReview => isUnmatched && !isResolved;
  String get displayName => canonicalProductName.isNotEmpty
      ? canonicalProductName
      : originalMaterialName;
  String get displayUnit =>
      canonicalUnitValue.isNotEmpty ? canonicalUnitValue : originalUnitText;
  String get reviewLabel => switch (reviewStatus) {
    'not_required' => 'من الكتالوج',
    'pending_review' => 'بانتظار مراجعة المحاسب',
    'clarification_requested' => 'طُلب توضيح',
    'linked_material' => 'مرتبط بمادة موجودة',
    'newly_created_material' => 'مادة جديدة',
    'synchronized' => 'متزامن محاسبيًا',
    _ => 'حالة مراجعة غير معروفة',
  };
}

class PurchaseInvoiceHistoryEvent {
  final String action;
  final String message;
  final String actorName;
  final String actorRole;
  final DateTime? timestamp;

  const PurchaseInvoiceHistoryEvent({
    required this.action,
    required this.message,
    required this.actorName,
    required this.actorRole,
    this.timestamp,
  });

  factory PurchaseInvoiceHistoryEvent.fromMap(Map<String, dynamic> data) =>
      PurchaseInvoiceHistoryEvent(
        action: data['action']?.toString() ?? '',
        message: data['message']?.toString() ?? '',
        actorName: data['actor_name']?.toString() ?? '',
        actorRole: data['actor_role']?.toString() ?? '',
        timestamp: _date(data['timestamp']),
      );
}

class PurchaseInvoiceAmendment {
  final String id;
  final String invoiceId;
  final int invoiceRevision;
  final String status;
  final String reason;
  final Map<String, Map<String, dynamic>> changes;
  final bool includesProtectedPriceChanges;
  final List<PurchaseAmendmentActor> requiredApprovers;
  final List<PurchaseAmendmentActor> approvals;
  final String requestedByName;
  final String requestedByRole;
  final DateTime? requestedAt;
  final String rejectionReason;

  const PurchaseInvoiceAmendment({
    required this.id,
    required this.invoiceId,
    required this.invoiceRevision,
    required this.status,
    required this.reason,
    required this.changes,
    required this.includesProtectedPriceChanges,
    required this.requiredApprovers,
    required this.approvals,
    required this.requestedByName,
    required this.requestedByRole,
    this.requestedAt,
    this.rejectionReason = '',
  });

  factory PurchaseInvoiceAmendment.fromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    Map<String, Map<String, dynamic>> changes = const {};
    final rawChanges = data['changes'];
    if (rawChanges is Map) {
      changes = Map.unmodifiable({
        for (final entry in rawChanges.entries)
          if (entry.key is String && entry.value is Map)
            entry.key as String: Map.unmodifiable(
              Map<String, dynamic>.from(entry.value as Map),
            ),
      });
    }
    List<PurchaseAmendmentActor> actors(dynamic raw) => raw is List
        ? raw
              .whereType<Map>()
              .map(
                (entry) => PurchaseAmendmentActor.fromMap(
                  Map<String, dynamic>.from(entry),
                ),
              )
              .toList(growable: false)
        : const [];
    return PurchaseInvoiceAmendment(
      id: data['id']?.toString() ?? id,
      invoiceId: data['invoice_id']?.toString() ?? '',
      invoiceRevision: (data['invoice_revision'] as num?)?.toInt() ?? 0,
      status: data['status']?.toString() ?? '',
      reason: data['reason']?.toString() ?? '',
      changes: changes,
      includesProtectedPriceChanges:
          data['includes_protected_price_changes'] == true,
      requiredApprovers: actors(data['required_approvers']),
      approvals: actors(data['approvals']),
      requestedByName: data['requested_by_name']?.toString() ?? '',
      requestedByRole: data['requested_by_role']?.toString() ?? '',
      requestedAt: _date(data['requested_at']),
      rejectionReason: data['rejection_reason']?.toString() ?? '',
    );
  }

  List<PurchaseAmendmentActor> get pendingApprovers => requiredApprovers
      .where(
        (required) =>
            !approvals.any((approved) => approved.uid == required.uid),
      )
      .toList(growable: false);

  bool approvedBy(String uid) => approvals.any((actor) => actor.uid == uid);
}

class PurchaseAmendmentActor {
  final String uid;
  final String name;
  final String role;

  const PurchaseAmendmentActor({
    required this.uid,
    required this.name,
    required this.role,
  });

  factory PurchaseAmendmentActor.fromMap(Map<String, dynamic> data) =>
      PurchaseAmendmentActor(
        uid: data['uid']?.toString() ?? '',
        name: data['name']?.toString() ?? '',
        role: data['role']?.toString() ?? '',
      );
}

class PurchaseInvoiceAmendmentPrice {
  final String amendmentId;
  final String invoiceId;
  final String currency;
  final List<PurchaseAmendmentPriceItem> items;

  const PurchaseInvoiceAmendmentPrice({
    required this.amendmentId,
    required this.invoiceId,
    required this.currency,
    required this.items,
  });

  factory PurchaseInvoiceAmendmentPrice.fromMap(Map<String, dynamic> data) =>
      PurchaseInvoiceAmendmentPrice(
        amendmentId: data['amendment_id']?.toString() ?? '',
        invoiceId: data['invoice_id']?.toString() ?? '',
        currency: data['currency']?.toString() ?? '',
        items: (data['price_items'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (entry) => PurchaseAmendmentPriceItem(
                itemId: entry['item_id']?.toString() ?? '',
                oldUnitPrice: (entry['old_unit_price'] as num?)?.toDouble(),
                newUnitPrice: (entry['new_unit_price'] as num?)?.toDouble(),
              ),
            )
            .toList(growable: false),
      );
}

class PurchaseAmendmentPriceItem {
  final String itemId;
  final double? oldUnitPrice;
  final double? newUnitPrice;

  const PurchaseAmendmentPriceItem({
    required this.itemId,
    this.oldUnitPrice,
    this.newUnitPrice,
  });
}

class ProductReviewTask {
  final String id;
  final String invoiceId;
  final String itemId;
  final String brandId;
  final String receivingBranchId;
  final String status;
  final int revision;
  final String originalMaterialName;
  final String originalGroupText;
  final String originalUnitText;
  final String canonicalProductId;
  final String accountingReference;
  final String syncState;
  final DateTime? updatedAt;

  const ProductReviewTask({
    required this.id,
    required this.invoiceId,
    required this.itemId,
    required this.brandId,
    required this.receivingBranchId,
    required this.status,
    required this.revision,
    required this.originalMaterialName,
    required this.originalGroupText,
    required this.originalUnitText,
    this.canonicalProductId = '',
    this.accountingReference = '',
    this.syncState = '',
    this.updatedAt,
  });

  factory ProductReviewTask.fromMap(String id, Map<String, dynamic> data) =>
      ProductReviewTask(
        id: data['id']?.toString() ?? id,
        invoiceId: data['invoice_id']?.toString() ?? '',
        itemId: data['item_id']?.toString() ?? '',
        brandId: data['brand_id']?.toString() ?? '',
        receivingBranchId: data['receiving_branch_id']?.toString() ?? '',
        status: data['status']?.toString() ?? '',
        revision: (data['revision'] as num?)?.toInt() ?? 0,
        originalMaterialName: data['original_material_name']?.toString() ?? '',
        originalGroupText: data['original_group_text']?.toString() ?? '',
        originalUnitText: data['original_unit_text']?.toString() ?? '',
        canonicalProductId: data['canonical_product_id']?.toString() ?? '',
        accountingReference: data['accounting_reference']?.toString() ?? '',
        syncState: data['sync_state']?.toString() ?? '',
        updatedAt: _date(data['updated_at']),
      );
}

DateTime? _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
