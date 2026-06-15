import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/utils/transaction_records.dart';

Map<String, dynamic> record({
  required double amount,
  required String currency,
  required String status,
  required DateTime timestamp,
  required DateTime dateFrom,
  required DateTime dateTo,
}) {
  return {
    'amount': amount,
    'currency': currency,
    'status': status,
    'timestamp': timestamp,
    'dateFrom': dateFrom,
    'dateTo': dateTo,
  };
}

void main() {
  final records = [
    record(
      amount: 100,
      currency: 'YER',
      status: 'pending',
      timestamp: DateTime(2026, 6, 10, 8),
      dateFrom: DateTime(2026, 6, 1),
      dateTo: DateTime(2026, 6, 10),
    ),
    record(
      amount: 250,
      currency: 'YER',
      status: 'approvedByManager',
      timestamp: DateTime(2026, 6, 12, 18),
      dateFrom: DateTime(2026, 6, 11),
      dateTo: DateTime(2026, 6, 20),
    ),
    record(
      amount: 50,
      currency: 'USD',
      status: 'approvedByManager',
      timestamp: DateTime(2026, 6, 14, 22),
      dateFrom: DateTime(2026, 6, 20),
      dateTo: DateTime(2026, 6, 30),
    ),
  ];

  test('يجمع المبالغ بشكل مستقل لكل عملة', () {
    expect(totalsByCurrency(records), {'USD': 50, 'YER': 350});
  });

  test('يفلتر العملة والحالة معاً ويرتب الأحدث أولاً', () {
    final result = filterAndSortTransactionRecords(
      records: records,
      dataOf: (item) => item,
      filters: const TransactionRecordFilters(
        currency: 'YER',
        status: 'approvedByManager',
      ),
    );
    expect(result, hasLength(1));
    expect(result.single['amount'], 250);
  });

  test('يضم كامل يوم النهاية في فلتر تاريخ الإنشاء', () {
    final result = filterAndSortTransactionRecords(
      records: records,
      dataOf: (item) => item,
      filters: TransactionRecordFilters(createdTo: DateTime(2026, 6, 12)),
    );
    expect(result.map((item) => item['amount']), [250, 100]);
  });

  test('يعرض السند إذا تقاطعت فترة التحصيل مع الفترة المختارة', () {
    final result = filterAndSortTransactionRecords(
      records: records,
      dataOf: (item) => item,
      filters: TransactionRecordFilters(
        periodFrom: DateTime(2026, 6, 9),
        periodTo: DateTime(2026, 6, 12),
      ),
    );
    expect(result.map((item) => item['amount']), [250, 100]);
  });

  test('يستبعد السجل ناقص التاريخ عند استخدام فلتر زمني', () {
    final incomplete = <String, dynamic>{
      'amount': 10,
      'currency': 'SAR',
      'status': 'pending',
    };
    expect(
      matchesTransactionRecord(
        incomplete,
        TransactionRecordFilters(createdFrom: DateTime(2026, 6, 1)),
      ),
      isFalse,
    );
  });

  test('يحسب عدد خيارات التصفية النشطة', () {
    final filters = TransactionRecordFilters(
      currency: 'USD',
      status: 'pending',
      periodFrom: DateTime(2026, 6, 1),
    );
    expect(filters.isActive, isTrue);
    expect(filters.activeCount, 3);
  });
}
