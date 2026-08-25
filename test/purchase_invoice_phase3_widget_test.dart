import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/purchase_invoice_model.dart';
import 'package:store_collection_app/models/purchase_invoice_price_model.dart';
import 'package:store_collection_app/screens/purchase_invoices/product_review_queue_screen.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_invoice_details_screen.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_invoices_dashboard.dart';

PurchaseInvoiceRead fixtureInvoice({
  String status = 'pendingReceiverReview',
  int revision = 1,
}) => PurchaseInvoiceRead(
  id: 'purchase-1',
  data: {
    'schema_version': 1,
    'workflow_version': 1,
    'workflow_identity': 'purchase_invoice_v1',
    'status': status,
    'revision': revision,
    'purchase_number': 'PUR-1',
    'receiving_branch_id': 'branch-r',
    'receiving_branch_name': 'فرع الاستلام',
    'receiving_brand_id': 'brand-r',
    'branch_ids': ['branch-r'],
    'item_count': 1,
    'item_digest': 'a' * 64,
    'currency': 'YER',
    'created_by': 'collector',
    'created_by_name': 'المدير العام',
    'created_by_role': 'collector',
    'history': const [],
  },
  itemDocuments: [
    {
      'item_id': 'item-1',
      'line_number': 1,
      'source_type': 'unmatched',
      'original_material_name': 'مادة غير مطابقة',
      'original_group_text': '',
      'original_unit_text': 'حبة',
      'review_task_id': 'task-1',
      'review_status': 'pending_review',
      'ordered_quantity': 2,
      if (status != 'pendingReceiverReview') 'received_quantity': 2,
    },
  ],
);

void main() {
  testWidgets(
    'purchase dashboards are Arabic RTL and expose role-specific controls',
    (tester) async {
      final invoice = fixtureInvoice(status: 'pendingPriceEntry', revision: 2);
      await tester.pumpWidget(
        MaterialApp(
          home: PurchaseInvoicesDashboard(
            role: UserRole.collector,
            branchName: 'جميع الفروع',
            invoiceStream: Stream.value([invoice]),
            showNotificationBell: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('فواتير المشتريات'), findsOneWidget);
      expect(find.byKey(const Key('new-purchase-invoice')), findsOneWidget);
      expect(find.text('فواتير الشراء الجديدة والقديمة'), findsOneWidget);
      expect(
        tester
            .widgetList<Directionality>(find.byType(Directionality))
            .any((widget) => widget.textDirection == TextDirection.rtl),
        isTrue,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PurchaseInvoicesDashboard(
            role: UserRole.manager,
            branchId: 'branch-r',
            branchName: 'فرع الاستلام',
            invoiceStream: Stream.value([invoice]),
            showNotificationBell: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-purchase-invoice')), findsNothing);
    },
  );

  testWidgets(
    'manager details show quantities and review state but never protected prices',
    (tester) async {
      final invoice = fixtureInvoice();
      final prices = PurchaseInvoicePriceSnapshot.fromMap({
        'invoice_id': invoice.id,
        'invoice_revision': invoice.revision,
        'pricing_revision': 1,
        'pricing_state': 'confirmed',
        'item_count': 1,
        'item_digest': invoice.itemDigest,
        'currency': 'YER',
        'items': [
          {'item_id': 'item-1', 'unit_price': 77, 'line_total': 154},
        ],
        'invoice_total': 154,
        'accounting_reference': 'PRIVATE-REF',
        'locked': false,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: PurchaseInvoiceDetailsScreen(
            invoiceId: invoice.id,
            role: UserRole.manager,
            branchId: 'branch-r',
            fixtureInvoice: invoice,
            fixturePrices: prices,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('مادة غير مطابقة'), findsOneWidget);
      expect(find.text('بانتظار مراجعة المحاسب'), findsOneWidget);
      expect(find.byKey(const Key('confirm-purchase-receipt')), findsOneWidget);
      expect(find.textContaining('77'), findsNothing);
      expect(find.textContaining('PRIVATE-REF'), findsNothing);
      expect(find.byKey(const Key('protected-price-item-1')), findsNothing);
    },
  );

  testWidgets('accountant completes missing initial prices before posting', (
    tester,
  ) async {
    final invoice = fixtureInvoice(
      status: 'pendingAccountingEntry',
      revision: 2,
    );
    final prices = PurchaseInvoicePriceSnapshot.fromMap({
      'invoice_id': invoice.id,
      'invoice_revision': invoice.revision,
      'pricing_revision': 0,
      'pricing_state': 'provisional',
      'item_count': 1,
      'item_digest': invoice.itemDigest,
      'currency': 'YER',
      'provisional_items': const [],
      'locked': false,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: PurchaseInvoiceDetailsScreen(
          invoiceId: invoice.id,
          role: UserRole.accountant,
          fixtureInvoice: invoice,
          fixturePrices: prices,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-purchase-prices')), findsOneWidget);
    expect(find.byKey(const Key('post-purchase-accounting')), findsNothing);
  });

  testWidgets(
    'authorized details may merge a matched protected price snapshot',
    (tester) async {
      final invoice = fixtureInvoice(
        status: 'pendingAccountingEntry',
        revision: 3,
      );
      final prices = PurchaseInvoicePriceSnapshot.fromMap({
        'invoice_id': invoice.id,
        'invoice_revision': invoice.revision,
        'pricing_revision': 1,
        'pricing_state': 'confirmed',
        'item_count': 1,
        'item_digest': invoice.itemDigest,
        'currency': 'YER',
        'items': [
          {'item_id': 'item-1', 'unit_price': 77, 'line_total': 154},
        ],
        'invoice_total': 154,
        'locked': false,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: PurchaseInvoiceDetailsScreen(
            invoiceId: invoice.id,
            role: UserRole.accountant,
            fixtureInvoice: invoice,
            fixturePrices: prices,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('protected-price-item-1')), findsOneWidget);
      expect(find.byKey(const Key('post-purchase-accounting')), findsOneWidget);
    },
  );

  testWidgets('authorized details reject a stale protected price snapshot', (
    tester,
  ) async {
    final invoice = fixtureInvoice(
      status: 'pendingAccountingEntry',
      revision: 3,
    );
    final stalePrices = PurchaseInvoicePriceSnapshot.fromMap({
      'invoice_id': invoice.id,
      'invoice_revision': invoice.revision - 1,
      'pricing_revision': 1,
      'pricing_state': 'confirmed',
      'item_count': 1,
      'item_digest': 'b' * 64,
      'currency': 'YER',
      'items': [
        {'item_id': 'item-1', 'unit_price': 77, 'line_total': 154},
      ],
      'invoice_total': 154,
      'locked': false,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: PurchaseInvoiceDetailsScreen(
          invoiceId: invoice.id,
          role: UserRole.accountant,
          fixtureInvoice: invoice,
          fixturePrices: stalePrices,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('protected-price-item-1')), findsNothing);
    expect(find.textContaining('77'), findsNothing);
  });

  testWidgets('accountant review queue clearly labels clarification requests', (
    tester,
  ) async {
    final task = ProductReviewTask(
      id: 'task-1',
      invoiceId: 'purchase-1',
      itemId: 'item-1',
      brandId: 'brand-r',
      receivingBranchId: 'branch-r',
      status: 'clarification_requested',
      revision: 2,
      originalMaterialName: 'مادة أصلية',
      originalGroupText: '',
      originalUnitText: 'حبة',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProductReviewQueueScreen(taskStream: Stream.value([task])),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('توضيح'), findsWidgets);
    expect(find.text('إعادة للمراجعة'), findsOneWidget);
  });
}
