import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_catalog_picker.dart';

void main() {
  const unit = CatalogUnit(id: 'primary', displayValue: 'حبة', rawValue: 'حبة');
  const existing = ProductCatalogModel(
    id: 'existing-product',
    brandId: 'brand-receiving',
    groupId: 'group-1',
    name: 'مادة موجودة',
    normalizedName: 'مادة موجودة',
    units: [unit],
    primaryUnitId: 'primary',
    nameUniqueKeyId: 'existing-name-key',
  );
  const created = ProductCatalogModel(
    id: 'created-product',
    brandId: 'brand-receiving',
    groupId: 'group-1',
    name: 'مادة جديدة',
    normalizedName: 'مادة جديدة',
    units: [unit],
    primaryUnitId: 'primary',
    nameUniqueKeyId: 'created-name-key',
  );

  testWidgets(
    'Purchase keeps canonical Add New Material available for a populated catalog',
    (tester) async {
      CatalogSelection? selected;
      var createCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                selected = await showPurchaseCatalogPicker(
                  context,
                  brandId: 'brand-receiving',
                  products: const [existing],
                  onCreateProduct: () async {
                    createCalls++;
                    return const CatalogSelection(product: created, unit: unit);
                  },
                );
              },
              child: const Text('فتح'),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.text('مادة موجودة'), findsOneWidget);
      expect(
        find.byKey(const Key('purchase-add-new-catalog-material')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('purchase-add-new-catalog-material')),
      );
      await tester.pumpAndSettle();

      expect(createCalls, 1);
      expect(selected?.product.id, 'created-product');
      expect(selected?.product.brandId, 'brand-receiving');
      expect(selected?.unit.id, 'primary');
    },
  );
}
