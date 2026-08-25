import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_item_editor_dialog.dart';

void main() {
  testWidgets(
    'catalog item editor keeps controllers alive through add, close, and reopen',
    (tester) async {
      final results = <PurchaseItemEditorResult?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                key: const Key('open-catalog-editor'),
                onPressed: () async {
                  results.add(
                    await showDialog<PurchaseItemEditorResult>(
                      context: context,
                      builder: (_) => const PurchaseItemEditorDialog.catalog(
                        productName: 'اختبار',
                        unitValue: 'حبة',
                      ),
                    ),
                  );
                },
                child: const Text('فتح'),
              ),
            ),
          ),
        ),
      );

      for (final quantity in <String>['1', '2', '3', '10']) {
        await tester.tap(find.byKey(const Key('open-catalog-editor')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('purchase-item-quantity')),
          quantity,
        );
        await tester.tap(find.byKey(const Key('confirm-purchase-item')));
        await tester.pumpAndSettle();

        expect(results.last?.quantity, double.parse(quantity));
        expect(tester.takeException(), isNull);
      }
      expect(results, hasLength(4));
    },
  );

  testWidgets('unmatched item editor can cancel and then add safely', (
    tester,
  ) async {
    final results = <PurchaseItemEditorResult?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              key: const Key('open-unmatched-editor'),
              onPressed: () async {
                results.add(
                  await showDialog<PurchaseItemEditorResult>(
                    context: context,
                    builder: (_) => const PurchaseItemEditorDialog.unmatched(),
                  ),
                );
              },
              child: const Text('فتح'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-unmatched-editor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel-purchase-item')));
    await tester.pumpAndSettle();
    expect(results.single, isNull);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('open-unmatched-editor')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('purchase-item-name')),
      'مادة اختبار',
    );
    await tester.enterText(find.byKey(const Key('purchase-item-unit')), 'علبة');
    await tester.enterText(
      find.byKey(const Key('purchase-item-quantity')),
      '3',
    );
    await tester.tap(find.byKey(const Key('confirm-purchase-item')));
    await tester.pumpAndSettle();

    expect(results.last?.isUnmatched, isTrue);
    expect(results.last?.materialName, 'مادة اختبار');
    expect(results.last?.quantity, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalog editor preserves an editable selected unit, price, and line note', (
    tester,
  ) async {
    PurchaseItemEditorResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showDialog<PurchaseItemEditorResult>(
                  context: context,
                  builder: (_) => const PurchaseItemEditorDialog.catalog(
                    productName: 'مادة',
                    unitValue: 'علبة',
                    catalogUnits: [
                      CatalogUnit(id: 'one', displayValue: 'حبة', rawValue: 'حبة'),
                      CatalogUnit(id: 'box', displayValue: 'علبة', rawValue: 'علبة'),
                    ],
                    initialCatalogUnitId: 'box',
                    initialQuantity: 3,
                    initialProvisionalPrice: 12.5,
                    initialLineNotes: 'ملاحظة',
                  ),
                );
              },
              child: const Text('فتح'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-item-catalog-unit')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('purchase-item-quantity')), '4');
    await tester.enterText(
      find.byKey(const Key('purchase-item-provisional-price')),
      '15',
    );
    await tester.enterText(find.byKey(const Key('purchase-item-notes')), 'تم التعديل');
    await tester.tap(find.byKey(const Key('confirm-purchase-item')));
    await tester.pumpAndSettle();

    expect(result?.catalogUnitId, 'box');
    expect(result?.quantity, 4);
    expect(result?.provisionalPrice, 15);
    expect(result?.lineNotes, 'تم التعديل');
    expect(tester.takeException(), isNull);
  });
}
