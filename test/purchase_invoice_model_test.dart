import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/purchase_invoice_model.dart';
import 'package:store_collection_app/models/purchase_invoice_price_model.dart';

void main() {
  test(
    'public purchase models parse scalable items and ignore injected prices',
    () {
      final invoice = PurchaseInvoiceRead(
        id: 'purchase-1',
        data: {
          'schema_version': 1,
          'workflow_version': 1,
          'workflow_identity': 'purchase_invoice_v1',
          'status': 'pendingReceiverReview',
          'revision': 1,
          'purchase_number': 'PUR-1',
          'receiving_branch_id': 'branch-r',
          'receiving_brand_id': 'brand-r',
          'item_count': 1,
          'item_digest': 'a' * 64,
          'currency': 'YER',
          'unit_price': 999,
          'invoice_total': 999,
        },
        itemDocuments: [
          {
            'item_id': 'item-1',
            'line_number': 1,
            'source_type': 'unmatched',
            'original_material_name': 'مادة أصلية',
            'original_group_text': '',
            'original_unit_text': 'حبة',
            'review_status': 'pending_review',
            'ordered_quantity': 2,
            'unit_price': 999,
          },
        ],
      );

      expect(invoice.status, PurchaseInvoiceStatus.pendingReceiverReview);
      expect(invoice.items.single.displayName, 'مادة أصلية');
      expect(invoice.items.single.needsReview, isTrue);
      expect(invoice.items.single.reviewLabel, 'بانتظار مراجعة المحاسب');
      expect(invoice.data.containsKey('unit_price'), isFalse);
      expect(invoice.data.containsKey('invoice_total'), isFalse);
      expect(invoice.itemDocuments!.single.containsKey('unit_price'), isFalse);
      expect(invoice.items.single.toString(), isNot(contains('999')));
    },
  );

  test(
    'protected purchase snapshot requires the exact active revision and digest',
    () {
      final invoice = PurchaseInvoiceRead(
        id: 'purchase-1',
        data: {
          'revision': 3,
          'item_count': 1,
          'item_digest': 'a' * 64,
          'currency': 'YER',
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
            'ordered_quantity': 1,
          },
        ],
      );
      final snapshot = PurchaseInvoicePriceSnapshot.fromMap({
        'invoice_id': 'purchase-1',
        'invoice_revision': 3,
        'pricing_revision': 1,
        'pricing_state': 'confirmed',
        'item_count': 1,
        'item_digest': 'a' * 64,
        'currency': 'YER',
        'items': [
          {'item_id': 'item-1', 'unit_price': 5, 'line_total': 5},
        ],
        'locked': false,
      });
      expect(snapshot.matches(invoice), isTrue);
      expect(
        PurchaseInvoicePriceSnapshot.fromMap({
          ...{
            'invoice_id': 'purchase-1',
            'invoice_revision': 3,
            'pricing_revision': 1,
            'pricing_state': 'confirmed',
            'item_count': 1,
            'item_digest': 'b' * 64,
            'currency': 'YER',
            'items': [
              {'item_id': 'item-1', 'unit_price': 5, 'line_total': 5},
            ],
            'locked': false,
          },
        }).matches(invoice),
        isFalse,
      );
    },
  );

  test(
    'locked posted prices remain usable after non-financial reconciliation',
    () {
      final invoice = PurchaseInvoiceRead(
        id: 'purchase-1',
        data: {
          'status': 'postedToAccounting',
          'revision': 6,
          'item_count': 1,
          'item_digest': 'c' * 64,
          'currency': 'YER',
        },
        itemDocuments: [
          {
            'item_id': 'item-1',
            'line_number': 1,
            'source_type': 'unmatched',
            'original_material_name': 'مادة أصلية',
            'original_group_text': '',
            'original_unit_text': 'حبة',
            'canonical_product_id': 'product-1',
            'canonical_product_name': 'مادة معتمدة',
            'canonical_unit_id': 'piece',
            'canonical_unit_value': 'حبة',
            'review_status': 'synchronized',
            'ordered_quantity': 2,
            'received_quantity': 1.5,
          },
        ],
      );
      final snapshot = PurchaseInvoicePriceSnapshot.fromMap({
        'invoice_id': 'purchase-1',
        'invoice_revision': 3,
        'locked_invoice_revision': 4,
        'pricing_revision': 1,
        'pricing_state': 'confirmed',
        'item_count': 1,
        'item_digest': 'a' * 64,
        'currency': 'YER',
        'items': [
          {
            'item_id': 'item-1',
            'original_material_name': 'مادة أصلية',
            'original_unit_text': 'حبة',
            'ordered_quantity': 2,
            'received_quantity': 1.5,
            'unit_price': 5,
            'line_total': 7.5,
          },
        ],
        'locked': true,
      });

      expect(snapshot.matches(invoice), isTrue);
      final quantityChanged = invoice.withItems([
        {...invoice.itemDocuments!.single, 'received_quantity': 1},
      ]);
      expect(snapshot.matches(quantityChanged), isFalse);
    },
  );

  test('provisional prices require the exact active public snapshot', () {
    final invoice = PurchaseInvoiceRead(
      id: 'purchase-1',
      data: {
        'revision': 2,
        'item_count': 1,
        'item_digest': 'a' * 64,
        'currency': 'SAR',
      },
      itemDocuments: const [],
    );
    final draft = PurchaseInvoicePriceSnapshot.fromMap({
      'invoice_id': 'purchase-1',
      'invoice_revision': 2,
      'pricing_revision': 0,
      'pricing_state': 'provisional',
      'item_count': 1,
      'item_digest': 'a' * 64,
      'currency': 'SAR',
      'locked': false,
    });
    expect(draft.matchesProvisional(invoice), isTrue);
    expect(
      PurchaseInvoicePriceSnapshot.fromMap({
        'invoice_id': 'purchase-1',
        'invoice_revision': 1,
        'pricing_revision': 0,
        'pricing_state': 'provisional',
        'item_count': 1,
        'item_digest': 'a' * 64,
        'currency': 'SAR',
        'locked': false,
      }).matchesProvisional(invoice),
      isFalse,
    );
  });
}
