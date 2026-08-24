import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
