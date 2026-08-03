import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/purchase_invoice_model.dart';
import 'package:store_collection_app/models/purchase_invoice_price_model.dart';
import 'package:store_collection_app/services/purchase_invoice_pdf_service.dart';

void main() {
  final invoice = PurchaseInvoiceRead(
    id: 'purchase-1',
    data: {
      'revision': 3,
      'item_count': 1,
      'item_digest': 'a' * 64,
      'currency': 'YER',
      'purchase_number': 'PUR-1',
      'receiving_branch_name': 'الفرع',
      'status': 'pendingAccountingEntry',
    },
    itemDocuments: [
      {
        'item_id': 'item-1',
        'line_number': 1,
        'source_type': 'catalog',
        'original_material_name': 'مادة',
        'original_group_text': 'مجموعة',
        'original_unit_text': 'حبة',
        'canonical_product_name': 'مادة',
        'canonical_unit_value': 'حبة',
        'review_status': 'not_required',
        'ordered_quantity': 2,
        'received_quantity': 2,
      },
    ],
  );
  final prices = PurchaseInvoicePriceSnapshot.fromMap({
    'invoice_id': 'purchase-1',
    'invoice_revision': 3,
    'pricing_revision': 1,
    'pricing_state': 'confirmed',
    'item_count': 1,
    'item_digest': 'a' * 64,
    'currency': 'YER',
    'items': [
      {'item_id': 'item-1', 'unit_price': 5, 'line_total': 10},
    ],
    'invoice_total': 10,
    'accounting_reference': 'ACC-PRIVATE',
    'locked': false,
  });

  test(
    'manager PDF input is strictly price-free even when a protected snapshot is supplied',
    () {
      final input = PurchaseInvoicePdfService.prepare(
        invoice: invoice,
        audienceRole: UserRole.manager,
        protectedPrices: prices,
      );
      expect(input.showPrices, isFalse);
      expect(input.accountingReference, isEmpty);
      expect(input.total, isNull);
      expect(input.items.single.containsKey('unit_price'), isFalse);
      expect(input.items.single.containsKey('line_total'), isFalse);
      expect(input.header.toString(), isNot(contains('ACC-PRIVATE')));
    },
  );

  test('authorized PDF merges only an exactly matched restricted snapshot', () {
    final input = PurchaseInvoicePdfService.prepare(
      invoice: invoice,
      audienceRole: UserRole.accountant,
      protectedPrices: prices,
    );
    expect(input.showPrices, isTrue);
    expect(input.items.single['unit_price'], 5);
    expect(input.accountingReference, 'ACC-PRIVATE');
  });
}
