import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/inter_branch_invoice_model.dart';
import 'package:store_collection_app/models/inter_branch_invoice_price_model.dart';

void main() {
  group('workflow-v2 public reader', () {
    test('uses direct snapshots and never trusts public price fields', () {
      final createdAt = DateTime.utc(2026, 8, 2, 10);
      final invoice = InterBranchInvoiceRead(
        id: 'invoice-1',
        data: {
          'schema_version': 2,
          'workflow_version': 2,
          'revision': 1,
          'status': 'pendingReceiverReview',
          'created_at': createdAt,
          'item_digest': 'digest-1',
          'sending_branch_id': 'supplier',
          'receiving_branch_id': 'receiver',
          'unit_price': 999,
          'total_price': 999,
          'items': [
            {
              'item_id': 'line-1',
              'product_id': 'product-1',
              'product_version': 3,
              'product_name': 'منتج عربي',
              'product_legacy_code': '100-2',
              'group_id': 'group-1',
              'group_name': 'مجموعة',
              'unit_id': 'unit_1',
              'unit_value': 'حبة',
              'unit_raw_value': 'حبه',
              'supplied_quantity': 5,
              'unit_price': 999,
              'total_price': 999,
            },
          ],
        },
      );

      expect(invoice.isVersion2, isTrue);
      expect(invoice.status, InterBranchInvoiceStatus.pendingReceiverReview);
      expect(invoice.invoiceCreatedAt, createdAt);
      expect(invoice.receivedQuantity, isNull);
      expect(invoice.unitPrice, isNull);
      expect(invoice.totalPrice, isNull);
      expect(invoice.hasPrices, isFalse);
      expect(invoice.items.single.name, 'منتج عربي');
      expect(invoice.items.single.legacyCode, '100-2');
      expect(invoice.items.single.unit, 'حبة');
      expect(invoice.items.single.rawUnit, 'حبه');
      expect(invoice.items.single.hasReceivedQuantity, isFalse);
      expect(invoice.items.single.unitPrice, isNull);
    });

    test('does not turn a missing v2 status into a legacy request action', () {
      final invoice = InterBranchInvoiceRead(
        id: 'invoice-2',
        data: const {'schema_version': 2, 'workflow_version': 2},
      );

      expect(invoice.status, InterBranchInvoiceStatus.unknown);
      expect(invoice.status.hasInvoice, isFalse);
    });
  });

  test('legacy manual items and price snapshots remain readable', () {
    final invoice = InterBranchInvoiceRead(
      id: 'legacy-1',
      data: const {
        'status': 'pricedByGeneralManager',
        'item_name': 'اسم يدوي قديم',
        'unit': 'كرتون',
        'requested_quantity': 2,
        'received_quantity': 2,
        'unit_price': 10,
        'total_price': 20,
      },
    );

    expect(invoice.isVersion2, isFalse);
    expect(invoice.status, InterBranchInvoiceStatus.pendingAccountingEntry);
    expect(invoice.itemName, 'اسم يدوي قديم');
    expect(invoice.unitPrice, 10);
    expect(invoice.totalPrice, 20);
  });

  test(
    'restricted snapshot must match digest, revision and every public item',
    () {
      final invoice = _receivedInvoice();
      final matching = InterBranchInvoicePriceSnapshot.fromMap('invoice-3', {
        'invoice_revision': 3,
        'pricing_revision': 1,
        'item_digest': 'digest-3',
        'currency': 'YER',
        'invoice_total': 35,
        'items': [
          {
            'item_id': 'line-3',
            'product_id': 'product-3',
            'unit_id': 'unit_1',
            'unit_value': 'حبة',
            'received_quantity': 5,
            'unit_price': 7,
            'line_total': 35,
          },
        ],
      });
      final wrongDigest = InterBranchInvoicePriceSnapshot.fromMap('invoice-3', {
        'invoice_revision': 3,
        'pricing_revision': 1,
        'item_digest': 'different',
        'currency': 'YER',
        'items': matching.items
            .map(
              (item) => {
                'item_id': item.itemId,
                'product_id': item.productId,
                'unit_id': item.unitId,
                'received_quantity': item.receivedQuantity,
                'unit_price': item.unitPrice,
                'line_total': item.lineTotal,
              },
            )
            .toList(),
      });

      expect(matching.matchesPublicInvoice(invoice), isTrue);
      expect(wrongDigest.matchesPublicInvoice(invoice), isFalse);
    },
  );
}

InterBranchInvoiceRead _receivedInvoice() => InterBranchInvoiceRead(
  id: 'invoice-3',
  data: const {
    'schema_version': 2,
    'workflow_version': 2,
    'revision': 3,
    'status': 'pendingAccountingEntry',
    'item_digest': 'digest-3',
    'items': [
      {
        'item_id': 'line-3',
        'product_id': 'product-3',
        'product_name': 'منتج',
        'group_id': 'group-3',
        'group_name': 'مجموعة',
        'unit_id': 'unit_1',
        'unit_value': 'حبة',
        'unit_raw_value': 'حبة',
        'supplied_quantity': 5,
        'received_quantity': 5,
      },
    ],
  },
);
