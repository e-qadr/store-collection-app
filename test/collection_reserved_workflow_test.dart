import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/transaction_model.dart';

void main() {
  test('legacy direct Collection voucher remains a pending voucher', () {
    final direct = TransactionModel(
      id: 'direct',
      transactionNumber: 'ET004',
      branchId: 'branch-a',
      collectorId: 'collector-a',
      amount: 10,
      dateFrom: DateTime(2026),
      dateTo: DateTime(2026),
      transactionDate: DateTime(2026),
      status: TransactionStatus.pending,
      timestamp: DateTime(2026),
      currency: 'YER',
      amountMatches: null,
    ).toJson();

    expect(direct['status'], 'pending');
    expect(direct.containsKey('collection_workflow'), isFalse);
  });

  test('reserved voucher status remains backward-compatible in the model', () {
    final model = TransactionModel.fromJson({
      'id': 'reserved',
      'transaction_number': 'ET003',
      'branchId': 'branch-a',
      'collectorId': '',
      'amount': 10,
      'dateFrom': Timestamp.fromDate(DateTime(2026)),
      'dateTo': Timestamp.fromDate(DateTime(2026)),
      'transaction_date': Timestamp.fromDate(DateTime(2026)),
      'timestamp': Timestamp.fromDate(DateTime(2026)),
      'notes': '',
      'status': 'reservedForCollection',
      'currency': 'YER',
      'amount_matches': null,
      'history': const [],
    });

    expect(model.status, TransactionStatus.reservedForCollection);
    expect(model.transactionNumber, 'ET003');
  });
}
