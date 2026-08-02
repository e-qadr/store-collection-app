import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:store_collection_app/models/inter_branch_invoice_model.dart';

/// Restricted workflow-v2 pricing data. Instances of this model must never be
/// merged into a public invoice map or passed to a manager-facing response.
class InterBranchInvoicePriceSnapshot {
  final String invoiceId;
  final String currency;
  final int pricingRevision;
  final int invoiceRevision;
  final String itemDigest;
  final List<InterBranchInvoicePriceItem> items;
  final double total;
  final String pricingNotes;
  final String accountingNotes;
  final bool locked;
  final String confirmedBy;
  final DateTime? confirmedAt;
  final String? lockedBy;
  final DateTime? lockedAt;

  const InterBranchInvoicePriceSnapshot({
    required this.invoiceId,
    required this.currency,
    required this.pricingRevision,
    required this.invoiceRevision,
    required this.itemDigest,
    required this.items,
    required this.total,
    required this.pricingNotes,
    required this.accountingNotes,
    required this.locked,
    required this.confirmedBy,
    this.confirmedAt,
    this.lockedBy,
    this.lockedAt,
  });

  factory InterBranchInvoicePriceSnapshot.fromMap(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final rawItems = data['items'];
    return InterBranchInvoicePriceSnapshot(
      invoiceId: data['invoice_id']?.toString() ?? documentId,
      currency: data['currency']?.toString() ?? '',
      pricingRevision: (data['pricing_revision'] as num?)?.toInt() ?? 0,
      invoiceRevision:
          (data['invoice_revision'] as num?)?.toInt() ??
          (data['public_invoice_revision'] as num?)?.toInt() ??
          0,
      itemDigest:
          data['item_digest']?.toString() ??
          data['invoice_item_digest']?.toString() ??
          '',
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(InterBranchInvoicePriceItem.fromMap)
                .toList(growable: false)
          : const [],
      total:
          (data['invoice_total'] as num?)?.toDouble() ??
          (data['total'] as num?)?.toDouble() ??
          0,
      pricingNotes: data['pricing_notes']?.toString() ?? '',
      accountingNotes: data['accounting_notes']?.toString() ?? '',
      locked: data['locked'] == true,
      confirmedBy: data['confirmed_by']?.toString() ?? '',
      confirmedAt: _date(data['confirmed_at']),
      lockedBy: _nonEmpty(data['locked_by']),
      lockedAt: _date(data['locked_at']),
    );
  }

  InterBranchInvoicePriceItem? itemById(String itemId) {
    for (final item in items) {
      if (item.itemId == itemId) return item;
    }
    return null;
  }

  /// Structural protection before displaying or producing a priced PDF.
  /// The backend remains the authoritative posting validator.
  bool matchesPublicInvoice(InterBranchInvoiceRead invoice) {
    if (!invoice.isVersion2 || invoice.id != invoiceId || items.isEmpty) {
      return false;
    }
    if (!const {'YER', 'SAR', 'USD'}.contains(currency) ||
        !total.isFinite ||
        total < 0) {
      return false;
    }
    if (itemDigest.isEmpty ||
        invoice.itemDigest.isEmpty ||
        itemDigest != invoice.itemDigest) {
      return false;
    }
    if (invoiceRevision <= 0 || invoiceRevision > invoice.revision) {
      return false;
    }
    if (items.length != invoice.items.length) {
      return false;
    }
    var calculatedTotal = 0.0;
    for (final publicItem in invoice.items) {
      final protectedItem = itemById(publicItem.itemId);
      if (protectedItem == null ||
          protectedItem.productId != publicItem.productId ||
          protectedItem.unitId != publicItem.unitId ||
          protectedItem.receivedQuantity != publicItem.receivedQuantity ||
          !protectedItem.unitPrice.isFinite ||
          protectedItem.unitPrice < 0 ||
          !protectedItem.lineTotal.isFinite ||
          protectedItem.lineTotal < 0 ||
          !_approximatelyEqual(
            protectedItem.lineTotal,
            protectedItem.receivedQuantity * protectedItem.unitPrice,
          )) {
        return false;
      }
      calculatedTotal += protectedItem.lineTotal;
    }
    return calculatedTotal.isFinite &&
        _approximatelyEqual(calculatedTotal, total);
  }
}

class InterBranchInvoicePriceItem {
  final String itemId;
  final String productId;
  final String unitId;
  final String productNameSnapshot;
  final String unitValueSnapshot;
  final double receivedQuantity;
  final double unitPrice;
  final double lineTotal;
  final String? suggestedSourceInvoiceId;
  final DateTime? suggestedSourceChangedAt;

  const InterBranchInvoicePriceItem({
    required this.itemId,
    required this.productId,
    required this.unitId,
    required this.productNameSnapshot,
    required this.unitValueSnapshot,
    required this.receivedQuantity,
    required this.unitPrice,
    required this.lineTotal,
    this.suggestedSourceInvoiceId,
    this.suggestedSourceChangedAt,
  });

  factory InterBranchInvoicePriceItem.fromMap(Map<dynamic, dynamic> data) {
    return InterBranchInvoicePriceItem(
      itemId: data['item_id']?.toString() ?? '',
      productId: data['product_id']?.toString() ?? '',
      unitId: data['unit_id']?.toString() ?? '',
      productNameSnapshot:
          data['product_name_snapshot']?.toString() ??
          data['name_snapshot']?.toString() ??
          '',
      unitValueSnapshot:
          data['unit_value_snapshot']?.toString() ??
          data['unit_snapshot']?.toString() ??
          data['unit_value']?.toString() ??
          '',
      receivedQuantity: (data['received_quantity'] as num?)?.toDouble() ?? 0,
      unitPrice: (data['unit_price'] as num?)?.toDouble() ?? 0,
      lineTotal: (data['line_total'] as num?)?.toDouble() ?? 0,
      suggestedSourceInvoiceId: _nonEmpty(data['suggested_source_invoice_id']),
      suggestedSourceChangedAt: _date(data['suggested_source_changed_at']),
    );
  }
}

DateTime? _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String? _nonEmpty(dynamic value) {
  final clean = value?.toString().trim();
  return clean == null || clean.isEmpty ? null : clean;
}

bool _approximatelyEqual(double left, double right) {
  final scale = left.abs() > right.abs() ? left.abs() : right.abs();
  final tolerance = scale < 1 ? 0.000001 : scale * 0.000000001;
  return (left - right).abs() <= tolerance;
}
