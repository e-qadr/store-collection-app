import 'package:cloud_firestore/cloud_firestore.dart';

class ProductPriceCollections {
  ProductPriceCollections._();

  static const latest = 'product_price_latest';
  static const history = 'product_price_history';
}

class ProductPriceLatest {
  final String id;
  final String latestKey;
  final String historyEventId;
  final String brandId;
  final String productId;
  final String unitId;
  final String unitValue;
  final String currency;
  final double price;
  final String sourceInvoiceId;
  final String changedBy;
  final String changedByName;
  final String changedByRole;
  final DateTime? changedAt;
  final int version;

  const ProductPriceLatest({
    required this.id,
    required this.latestKey,
    required this.historyEventId,
    required this.brandId,
    required this.productId,
    required this.unitId,
    required this.unitValue,
    required this.currency,
    required this.price,
    required this.sourceInvoiceId,
    required this.changedBy,
    required this.changedByName,
    required this.changedByRole,
    required this.version,
    this.changedAt,
  });

  factory ProductPriceLatest.fromMap(
    String documentId,
    Map<String, dynamic> data,
  ) {
    return ProductPriceLatest(
      id: data['id']?.toString() ?? documentId,
      latestKey: data['latest_key']?.toString() ?? documentId,
      historyEventId: data['history_event_id']?.toString() ?? '',
      brandId: data['brand_id']?.toString() ?? '',
      productId: data['product_id']?.toString() ?? '',
      unitId: data['unit_id']?.toString() ?? '',
      unitValue: data['unit_value']?.toString() ?? '',
      currency: data['currency']?.toString() ?? '',
      price: (data['price'] as num?)?.toDouble() ?? 0,
      sourceInvoiceId: data['source_invoice_id']?.toString() ?? '',
      changedBy: data['changed_by']?.toString() ?? '',
      changedByName: data['changed_by_name']?.toString() ?? '',
      changedByRole: data['changed_by_role']?.toString() ?? '',
      changedAt: _dateTimeOf(data['changed_at']),
      version: (data['version'] as num?)?.toInt() ?? 0,
    );
  }
}

class ProductPriceHistoryEntry {
  final String id;
  final String latestKey;
  final String brandId;
  final String productId;
  final String unitId;
  final String unitValue;
  final String currency;
  final double price;
  final double? previousPrice;
  final String? previousSourceInvoiceId;
  final String sourceInvoiceId;
  final String changedBy;
  final String changedByName;
  final String changedByRole;
  final DateTime? changedAt;
  final int version;

  const ProductPriceHistoryEntry({
    required this.id,
    required this.latestKey,
    required this.brandId,
    required this.productId,
    required this.unitId,
    required this.unitValue,
    required this.currency,
    required this.price,
    required this.sourceInvoiceId,
    required this.changedBy,
    required this.changedByName,
    required this.changedByRole,
    required this.version,
    this.previousPrice,
    this.previousSourceInvoiceId,
    this.changedAt,
  });

  factory ProductPriceHistoryEntry.fromMap(
    String documentId,
    Map<String, dynamic> data,
  ) {
    return ProductPriceHistoryEntry(
      id: data['id']?.toString() ?? documentId,
      latestKey: data['latest_key']?.toString() ?? '',
      brandId: data['brand_id']?.toString() ?? '',
      productId: data['product_id']?.toString() ?? '',
      unitId: data['unit_id']?.toString() ?? '',
      unitValue: data['unit_value']?.toString() ?? '',
      currency: data['currency']?.toString() ?? '',
      price: (data['price'] as num?)?.toDouble() ?? 0,
      previousPrice: (data['previous_price'] as num?)?.toDouble(),
      previousSourceInvoiceId: _nonEmpty(data['previous_source_invoice_id']),
      sourceInvoiceId: data['source_invoice_id']?.toString() ?? '',
      changedBy: data['changed_by']?.toString() ?? '',
      changedByName: data['changed_by_name']?.toString() ?? '',
      changedByRole: data['changed_by_role']?.toString() ?? '',
      changedAt: _dateTimeOf(data['changed_at']),
      version: (data['version'] as num?)?.toInt() ?? 0,
    );
  }
}

DateTime? _dateTimeOf(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

String? _nonEmpty(dynamic value) {
  final result = value?.toString().trim();
  return result == null || result.isEmpty ? null : result;
}
