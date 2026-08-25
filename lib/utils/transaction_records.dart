import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionSortField { createdAt, businessDate, voucherNumber, amount }

enum TransactionSortDirection { ascending, descending }

class TransactionRecordSort {
  final TransactionSortField field;
  final TransactionSortDirection direction;

  const TransactionRecordSort({
    this.field = TransactionSortField.createdAt,
    this.direction = TransactionSortDirection.descending,
  });
}

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
  TransactionRecordSort sort = const TransactionRecordSort(),
}) {
  final result = records
      .where((record) => matchesTransactionRecord(dataOf(record), filters))
      .toList();

  result.sort((a, b) {
    final comparison = _compareTransactionValues(
      _sortValue(dataOf(a), sort.field),
      _sortValue(dataOf(b), sort.field),
    );
    final directed = sort.direction == TransactionSortDirection.ascending
        ? comparison
        : -comparison;
    if (directed != 0) return directed;
    return _compareTransactionValues(
      dataOf(a)['transaction_number']?.toString(),
      dataOf(b)['transaction_number']?.toString(),
    );
  });
  return result;
}

Object? _sortValue(Map<String, dynamic> data, TransactionSortField field) {
  return switch (field) {
    TransactionSortField.createdAt => transactionDate(data['timestamp']),
    TransactionSortField.businessDate =>
      transactionDate(data['transaction_date']) ??
          transactionDate(data['dateFrom']),
    TransactionSortField.voucherNumber =>
      data['transaction_number']?.toString() ?? '',
    TransactionSortField.amount => (data['amount'] as num?)?.toDouble(),
  };
}

int _compareTransactionValues(Object? left, Object? right) {
  if (left == null && right == null) return 0;
  if (left == null) return 1;
  if (right == null) return -1;
  if (left is DateTime && right is DateTime) return left.compareTo(right);
  if (left is num && right is num) return left.compareTo(right);
  return _naturalCompare(left.toString(), right.toString());
}

int _naturalCompare(String left, String right) {
  final leftNumber = num.tryParse(left.replaceAll(RegExp(r'\D'), ''));
  final rightNumber = num.tryParse(right.replaceAll(RegExp(r'\D'), ''));
  if (leftNumber != null && rightNumber != null) {
    final result = leftNumber.compareTo(rightNumber);
    if (result != 0) return result;
  }
  return left.compareTo(right);
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
