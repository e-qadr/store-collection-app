import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/inter_branch_invoice_price_model.dart';
import 'package:store_collection_app/services/pdf_service.dart';

void main() {
  test(
    'manager PDF rejects prices even when public data is maliciously priced',
    () {
      final input = PdfService.prepareSecureInterBranchInvoicePdfInput(
        invoiceId: 'invoice-1',
        publicData: _publicInvoice,
        audienceRole: UserRole.manager,
        priceSnapshot: _priceSnapshot(),
      );

      expect(input.showPrices, isFalse);
      expect(input.data, isNot(contains('unit_price')));
      expect(input.data, isNot(contains('total_price')));
      final item = (input.data['items'] as List).single as Map<String, dynamic>;
      expect(item, isNot(contains('unit_price')));
      expect(item, isNot(contains('total_price')));
      expect(item['name'], 'منتج عام');
    },
  );

  test(
    'authorized PDF merges only a structurally matching restricted price',
    () {
      final input = PdfService.prepareSecureInterBranchInvoicePdfInput(
        invoiceId: 'invoice-1',
        publicData: _publicInvoice,
        audienceRole: UserRole.collector,
        priceSnapshot: _priceSnapshot(),
      );
      final item = (input.data['items'] as List).single as Map<String, dynamic>;

      expect(input.showPrices, isTrue);
      expect(item['unit_price'], 7);
      expect(item['total_price'], 35);
      expect(item['unit_price'], isNot(999999));
    },
  );

  test('authorized PDF rejects a restricted snapshot with a stale digest', () {
    final input = PdfService.prepareSecureInterBranchInvoicePdfInput(
      invoiceId: 'invoice-1',
      publicData: _publicInvoice,
      audienceRole: UserRole.accountant,
      priceSnapshot: _priceSnapshot(digest: 'stale'),
    );

    expect(input.showPrices, isFalse);
    final item = (input.data['items'] as List).single as Map<String, dynamic>;
    expect(item, isNot(contains('unit_price')));
  });
}

final _publicInvoice = <String, dynamic>{
  'id': 'invoice-1',
  'schema_version': 2,
  'workflow_version': 2,
  'revision': 3,
  'status': 'pendingAccountingEntry',
  'item_digest': 'digest-1',
  'created_at': DateTime.utc(2026, 8, 2),
  'unit_price': 999999,
  'total_price': 999999,
  'items': const [
    {
      'item_id': 'line-1',
      'product_id': 'product-1',
      'product_name': 'منتج عام',
      'group_id': 'group-1',
      'group_name': 'مجموعة',
      'unit_id': 'unit_1',
      'unit_value': 'حبة',
      'unit_raw_value': 'حبة',
      'supplied_quantity': 5,
      'received_quantity': 5,
      'unit_price': 999999,
      'total_price': 999999,
    },
  ],
};

InterBranchInvoicePriceSnapshot _priceSnapshot({String digest = 'digest-1'}) =>
    InterBranchInvoicePriceSnapshot.fromMap('invoice-1', {
      'invoice_revision': 3,
      'pricing_revision': 1,
      'item_digest': digest,
      'currency': 'YER',
      'invoice_total': 35,
      'items': const [
        {
          'item_id': 'line-1',
          'product_id': 'product-1',
          'unit_id': 'unit_1',
          'unit_value': 'حبة',
          'received_quantity': 5,
          'unit_price': 7,
          'line_total': 35,
        },
      ],
    });
