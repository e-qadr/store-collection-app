import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:store_collection_app/theme/app_theme.dart';

enum CashExpenseStatus {
  pendingGeneralManagerReview,
  rejectedByGeneralManager,
  pendingInvoiceAttachment,
  pendingAccountingApproval,
  approvedByAccountant,
}

extension CashExpenseStatusX on CashExpenseStatus {
  String get value => name;

  String get label {
    switch (this) {
      case CashExpenseStatus.pendingGeneralManagerReview:
        return 'بانتظار المدير العام';
      case CashExpenseStatus.rejectedByGeneralManager:
        return 'مرفوض من المدير العام';
      case CashExpenseStatus.pendingInvoiceAttachment:
        return 'بانتظار إرفاق الفاتورة';
      case CashExpenseStatus.pendingAccountingApproval:
        return 'بانتظار اعتماد المحاسب';
      case CashExpenseStatus.approvedByAccountant:
        return 'معتمد نهائياً';
    }
  }

  Color get color {
    switch (this) {
      case CashExpenseStatus.pendingGeneralManagerReview:
        return AppTheme.pendingColor;
      case CashExpenseStatus.rejectedByGeneralManager:
        return AppTheme.errorColor;
      case CashExpenseStatus.pendingInvoiceAttachment:
        return AppTheme.managerColor;
      case CashExpenseStatus.pendingAccountingApproval:
        return AppTheme.accountantColor;
      case CashExpenseStatus.approvedByAccountant:
        return AppTheme.successColor;
    }
  }

  bool get isFinal =>
      this == CashExpenseStatus.approvedByAccountant ||
      this == CashExpenseStatus.rejectedByGeneralManager;
}

CashExpenseStatus cashExpenseStatusFromString(String? value) {
  return CashExpenseStatus.values.firstWhere(
    (status) => status.value == value,
    orElse: () => CashExpenseStatus.pendingGeneralManagerReview,
  );
}

class CashExpenseFields {
  CashExpenseFields._();

  static const collection = 'cash_expense_requests';
  static const requestNumber = 'request_number';
  static const branchId = 'branch_id';
  static const branchName = 'branch_name';
  static const title = 'title';
  static const description = 'description';
  static const requestedAmount = 'requested_amount';
  static const approvedAmount = 'approved_amount';
  static const currency = 'currency';
  static const status = 'status';
  static const managerNotes = 'manager_notes';
  static const generalManagerNotes = 'general_manager_notes';
  static const rejectionReason = 'rejection_reason';
  static const invoiceAttachment = 'invoice_attachment';
  static const invoiceNotes = 'invoice_notes';
  static const accountingReference = 'accounting_reference';
  static const accountantNotes = 'accountant_notes';
  static const createdBy = 'created_by';
  static const createdAt = 'created_at';
  static const reviewedBy = 'reviewed_by';
  static const reviewedAt = 'reviewed_at';
  static const invoiceApprovedBy = 'invoice_approved_by';
  static const invoiceApprovedAt = 'invoice_approved_at';
  static const approvedBy = 'approved_by';
  static const approvedAt = 'approved_at';
  static const lastUpdated = 'last_updated';
  static const history = 'history';
}

class CashExpenseRead {
  final String id;
  final Map<String, dynamic> data;

  const CashExpenseRead({required this.id, required this.data});

  String get branchId => data[CashExpenseFields.branchId]?.toString() ?? '';

  String get branchName => data[CashExpenseFields.branchName]?.toString() ?? '';

  String get requestNumber =>
      data[CashExpenseFields.requestNumber]?.toString() ??
      'CE-${id.length > 6 ? id.substring(0, 6) : id}';

  String get title => data[CashExpenseFields.title]?.toString() ?? '';

  String get description =>
      data[CashExpenseFields.description]?.toString() ?? '';

  String get currency => data[CashExpenseFields.currency]?.toString() ?? 'YER';

  String get managerNotes =>
      data[CashExpenseFields.managerNotes]?.toString() ?? '';

  String get generalManagerNotes =>
      data[CashExpenseFields.generalManagerNotes]?.toString() ?? '';

  String get rejectionReason =>
      data[CashExpenseFields.rejectionReason]?.toString() ?? '';

  String get invoiceNotes =>
      data[CashExpenseFields.invoiceNotes]?.toString() ?? '';

  String get accountingReference =>
      data[CashExpenseFields.accountingReference]?.toString() ?? '';

  String get accountantNotes =>
      data[CashExpenseFields.accountantNotes]?.toString() ?? '';

  double get requestedAmount =>
      (data[CashExpenseFields.requestedAmount] as num?)?.toDouble() ?? 0;

  double get approvedAmount =>
      (data[CashExpenseFields.approvedAmount] as num?)?.toDouble() ??
      requestedAmount;

  CashExpenseStatus get status =>
      cashExpenseStatusFromString(data[CashExpenseFields.status]?.toString());

  DateTime? get createdAt => _date(data[CashExpenseFields.createdAt]);

  DateTime? get reviewedAt => _date(data[CashExpenseFields.reviewedAt]);

  DateTime? get invoiceApprovedAt =>
      _date(data[CashExpenseFields.invoiceApprovedAt]);

  DateTime? get approvedAt => _date(data[CashExpenseFields.approvedAt]);

  Map<String, dynamic> get invoiceAttachment {
    final value = data[CashExpenseFields.invoiceAttachment];
    if (value is! Map) return const {};
    return Map<String, dynamic>.from(value);
  }

  String get invoiceFileName =>
      invoiceAttachment['name']?.toString() ?? 'لم ترفق فاتورة';

  String get invoiceUrl => invoiceAttachment['url']?.toString() ?? '';

  List<Map<String, dynamic>> get history {
    final value = data[CashExpenseFields.history];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  bool get hasAmountChange => requestedAmount != approvedAmount;

  static DateTime? _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
