import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionRecordFilters {
  final String? currency;
  final String? status;
  final String? amountMatchStatus;
  final DateTime? createdFrom;
  final DateTime? createdTo;
  final DateTime? periodFrom;
  final DateTime? periodTo;

  const TransactionRecordFilters({
    this.currency,
    this.status,
    this.amountMatchStatus,
    this.createdFrom,
    this.createdTo,
    this.periodFrom,
    this.periodTo,
  });

  bool get isActive =>
      currency != null ||
      status != null ||
      amountMatchStatus != null ||
      createdFrom != null ||
      createdTo != null ||
      periodFrom != null ||
      periodTo != null;

  int get activeCount => [
    currency,
    status,
    amountMatchStatus,
    createdFrom,
    createdTo,
    periodFrom,
    periodTo,
  ].where((value) => value != null).length;
}

DateTime? transactionDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

DateTime _startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _endOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day, 23, 59, 59, 999, 999);

bool matchesTransactionRecord(
  Map<String, dynamic> data,
  TransactionRecordFilters filters,
) {
  if (filters.currency != null && data['currency'] != filters.currency) {
    return false;
  }
  if (filters.status != null && data['status'] != filters.status) {
    return false;
  }
  if (filters.amountMatchStatus != null) {
    final value = data['amount_matches'];
    final currentStatus = value == true
        ? 'matched'
        : value == false
        ? 'unmatched'
        : 'unreviewed';
    if (currentStatus != filters.amountMatchStatus) return false;
  }

  final createdAt = transactionDate(data['timestamp']);
  if (filters.createdFrom != null &&
      (createdAt == null ||
          createdAt.isBefore(_startOfDay(filters.createdFrom!)))) {
    return false;
  }
  if (filters.createdTo != null &&
      (createdAt == null || createdAt.isAfter(_endOfDay(filters.createdTo!)))) {
    return false;
  }

  if (filters.periodFrom != null || filters.periodTo != null) {
    final recordFrom = transactionDate(data['dateFrom']);
    final recordTo = transactionDate(data['dateTo']);
    if (recordFrom == null || recordTo == null) return false;

    // تعرض السندات التي تتقاطع فترة تحصيلها مع الفترة المحددة.
    if (filters.periodFrom != null &&
        recordTo.isBefore(_startOfDay(filters.periodFrom!))) {
      return false;
    }
    if (filters.periodTo != null &&
        recordFrom.isAfter(_endOfDay(filters.periodTo!))) {
      return false;
    }
  }

  return true;
}

List<T> filterAndSortTransactionRecords<T>({
  required Iterable<T> records,
  required Map<String, dynamic> Function(T record) dataOf,
  required TransactionRecordFilters filters,
}) {
  final result = records
      .where((record) => matchesTransactionRecord(dataOf(record), filters))
      .toList();

  result.sort((a, b) {
    final aDate = transactionDate(dataOf(a)['timestamp']);
    final bDate = transactionDate(dataOf(b)['timestamp']);
    if (aDate == null && bDate == null) return 0;
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    return bDate.compareTo(aDate);
  });
  return result;
}

Map<String, double> totalsByCurrency(
  Iterable<Map<String, dynamic>> transactions,
) {
  final totals = <String, double>{};
  for (final transaction in transactions) {
    final currency = (transaction['currency'] as String?)?.trim();
    final amount = (transaction['amount'] as num?)?.toDouble();
    if (currency == null || currency.isEmpty || amount == null) continue;
    totals.update(currency, (value) => value + amount, ifAbsent: () => amount);
  }
  return Map.fromEntries(
    totals.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}
