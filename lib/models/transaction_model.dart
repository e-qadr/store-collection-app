import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:store_collection_app/models/enums.dart';

class TransactionModel {
  final String id;
  final String transactionNumber;
  final String branchId;
  final String collectorId;
  final double amount;
  final DateTime dateFrom;
  final DateTime dateTo;
  final DateTime transactionDate;
  final String notes;
  final TransactionStatus status;
  final DateTime timestamp;
  final String currency;
  final bool? amountMatches;
  final double? cashierAmount;
  final Map<String, dynamic>? pendingEditData;
  final List<Map<String, dynamic>>? history; // تمت إضافة هذا الحقل

  TransactionModel({
    required this.id,
    required this.transactionNumber,
    required this.branchId,
    required this.collectorId,
    required this.amount,
    required this.dateFrom,
    required this.dateTo,
    required this.transactionDate,
    this.notes = '',
    required this.status,
    required this.timestamp,
    required this.currency,
    required this.amountMatches,
    this.cashierAmount,
    this.pendingEditData, // تمت الإضافة
    this.history,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'],
      transactionNumber: json['transaction_number'],
      branchId: json['branchId'],
      collectorId: json['collectorId'],
      amount: (json['amount'] as num).toDouble(),
      dateFrom: (json['dateFrom'] as Timestamp).toDate(),
      dateTo: (json['dateTo'] as Timestamp).toDate(),
      transactionDate: (json['transaction_date'] as Timestamp).toDate(),
      notes: json['notes'] ?? '',
      status: TransactionStatus.values.firstWhere(
        (e) => e.name == json['status'],
      ),
      timestamp: (json['timestamp'] as Timestamp).toDate(),
      currency: json['currency'] ?? 'YER',
      amountMatches: json['amount_matches'] as bool?,
      cashierAmount: (json['cashier_amount'] as num?)?.toDouble(),
      pendingEditData: json['pending_edit_data'], // قراءة التعديلات المعلقة
      history: (json['history'] as List?)
          ?.map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'id': id,
      'transaction_number': transactionNumber,
      'branchId': branchId,
      'collectorId': collectorId,
      'amount': amount,
      'dateFrom': Timestamp.fromDate(dateFrom),
      'dateTo': Timestamp.fromDate(dateTo),
      'transaction_date': Timestamp.fromDate(transactionDate),
      'notes': notes,
      'status': status.name,
      'timestamp': Timestamp.fromDate(timestamp),
      'currency': currency,
      'amount_matches': amountMatches,
      'cashier_amount': cashierAmount,
      'history': history,
    };

    // إضافة الحقل فقط إذا كان يحتوي على بيانات
    if (pendingEditData != null) {
      data['pending_edit_data'] = pendingEditData;
    }

    return data;
  }
}
