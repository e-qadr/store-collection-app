import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:store_collection_app/models/purchase_invoice_model.dart';

class PurchaseInvoiceProtectedPriceItem {
  final String itemId;
  final String originalMaterialName;
  final String originalUnitText;
  final double orderedQuantity;
  final double receivedQuantity;
  final double unitPrice;
  final double lineTotal;

  const PurchaseInvoiceProtectedPriceItem({
    required this.itemId,
    required this.originalMaterialName,
    required this.originalUnitText,
    required this.orderedQuantity,
    required this.receivedQuantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory PurchaseInvoiceProtectedPriceItem.fromMap(
    Map<dynamic, dynamic> data,
  ) => PurchaseInvoiceProtectedPriceItem(
    itemId: data['item_id']?.toString() ?? '',
    originalMaterialName: data['original_material_name']?.toString() ?? '',
    originalUnitText: data['original_unit_text']?.toString() ?? '',
    orderedQuantity: (data['ordered_quantity'] as num?)?.toDouble() ?? 0,
    receivedQuantity: (data['received_quantity'] as num?)?.toDouble() ?? 0,
    unitPrice: (data['unit_price'] as num?)?.toDouble() ?? 0,
    lineTotal: (data['line_total'] as num?)?.toDouble() ?? 0,
  );

  bool matchesImmutableIdentity(PurchaseInvoiceItem item) =>
      itemId == item.id &&
      originalMaterialName == item.originalMaterialName &&
      originalUnitText == item.originalUnitText &&
      orderedQuantity == item.orderedQuantity &&
      receivedQuantity == item.receivedQuantity;
}

class PurchaseInvoicePriceSnapshot {
  final String invoiceId;
  final int invoiceRevision;
  final int pricingRevision;
  final String pricingState;
  final int itemCount;
  final String itemDigest;
  final String currency;
  final List<PurchaseInvoiceProtectedPriceItem> items;
  final Map<String, double> provisionalPrices;
  final double? invoiceTotal;
  final bool locked;
  final int lockedInvoiceRevision;
  final String accountingReference;
  final String accountantNotes;
  final bool overrideUsed;
  final DateTime? confirmedAt;

  const PurchaseInvoicePriceSnapshot({
    required this.invoiceId,
    required this.invoiceRevision,
    required this.pricingRevision,
    required this.pricingState,
    required this.itemCount,
    required this.itemDigest,
    required this.currency,
    required this.items,
    required this.provisionalPrices,
    required this.locked,
    this.lockedInvoiceRevision = 0,
    this.invoiceTotal,
    this.accountingReference = '',
    this.accountantNotes = '',
    this.overrideUsed = false,
    this.confirmedAt,
  });

  factory PurchaseInvoicePriceSnapshot.fromMap(Map<String, dynamic> data) {
    final provisional = <String, double>{};
    for (final raw in (data['provisional_items'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final id = raw['item_id']?.toString() ?? '';
      final price = (raw['unit_price'] as num?)?.toDouble();
      if (id.isNotEmpty && price != null) provisional[id] = price;
    }
    final override = data['posting_override'];
    return PurchaseInvoicePriceSnapshot(
      invoiceId: data['invoice_id']?.toString() ?? '',
      invoiceRevision: (data['invoice_revision'] as num?)?.toInt() ?? 0,
      pricingRevision: (data['pricing_revision'] as num?)?.toInt() ?? 0,
      pricingState: data['pricing_state']?.toString() ?? '',
      itemCount: (data['item_count'] as num?)?.toInt() ?? 0,
      itemDigest: data['item_digest']?.toString() ?? '',
      currency: data['currency']?.toString() ?? '',
      items: (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map(PurchaseInvoiceProtectedPriceItem.fromMap)
          .toList(growable: false),
      provisionalPrices: provisional,
      invoiceTotal: (data['invoice_total'] as num?)?.toDouble(),
      locked: data['locked'] == true,
      lockedInvoiceRevision:
          (data['locked_invoice_revision'] as num?)?.toInt() ?? 0,
      accountingReference: data['accounting_reference']?.toString() ?? '',
      accountantNotes: data['accountant_notes']?.toString() ?? '',
      overrideUsed: override is Map && override['used'] == true,
      confirmedAt: _date(data['confirmed_at']),
    );
  }

  PurchaseInvoiceProtectedPriceItem? itemById(String id) {
    for (final item in items) {
      if (item.itemId == id) return item;
    }
    return null;
  }

  bool matchesProvisional(PurchaseInvoiceRead invoice) =>
      invoiceId == invoice.id &&
      invoiceRevision == invoice.revision &&
      itemCount == invoice.itemCount &&
      itemDigest == invoice.itemDigest &&
      currency == invoice.currency &&
      pricingState == 'provisional' &&
      !locked;

  bool matches(PurchaseInvoiceRead invoice) {
    final exactCurrentSnapshot =
        invoiceRevision == invoice.revision && itemDigest == invoice.itemDigest;
    final immutablePostedSnapshot =
        locked &&
        invoice.status == PurchaseInvoiceStatus.postedToAccounting &&
        lockedInvoiceRevision > 0 &&
        lockedInvoiceRevision <= invoice.revision &&
        invoice.items.every((item) {
          final protectedItem = itemById(item.id);
          return protectedItem != null &&
              protectedItem.matchesImmutableIdentity(item);
        });
    return invoiceId == invoice.id &&
        (exactCurrentSnapshot || immutablePostedSnapshot) &&
        itemCount == invoice.itemCount &&
        currency == invoice.currency &&
        pricingState == 'confirmed' &&
        items.length == invoice.items.length &&
        invoice.items.every((item) => itemById(item.id) != null);
  }
}

DateTime? _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
