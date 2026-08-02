import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/screens/products/product_catalog_management_screen.dart';

void main() {
  ProductCatalogModel product({
    required String id,
    required String name,
    required String normalizedName,
    String? legacyCode,
    List<CatalogUnit> units = const [
      CatalogUnit(id: 'primary', displayValue: 'حبه', rawValue: 'حبه'),
    ],
    String primaryUnitId = 'primary',
    Map<String, dynamic> sourceMetadata = const {},
  }) {
    return ProductCatalogModel(
      id: id,
      brandId: 'brand-1',
      groupId: 'group-1',
      name: name,
      normalizedName: normalizedName,
      legacyCode: legacyCode,
      units: units,
      primaryUnitId: primaryUnitId,
      nameUniqueKeyId: 'name-key',
      sourceMetadata: sourceMetadata,
    );
  }

  test('يبحث دليل المواد بالاسم العربي المطبع أو الرمز القديم', () {
    final products = [
      product(
        id: 'p1',
        name: 'عِطر الأصالة',
        normalizedName: 'عطر الاصالة',
        legacyCode: '09-580',
      ),
      product(
        id: 'p2',
        name: 'بخور فاخر',
        normalizedName: 'بخور فاخر',
        legacyCode: '10-200',
      ),
    ];

    expect(filterCatalogProducts(products, 'الأصالة').single.id, 'p1');
    expect(filterCatalogProducts(products, '09-580').single.id, 'p1');
    expect(filterCatalogProducts(products, 'غير موجود'), isEmpty);
  });

  test('catalog editor preserves mixed and sparse secondary unit slots', () {
    final mixed = product(
      id: 'mixed',
      name: 'منتج مختلط',
      normalizedName: 'منتج مختلط',
      units: const [
        CatalogUnit(id: 'primary', displayValue: 'حبة', rawValue: 'حبة'),
        CatalogUnit(
          id: 'legacy-secondary',
          displayValue: 'علبة',
          rawValue: 'علبة',
        ),
        CatalogUnit(id: 'unit_3', displayValue: 'كرتون', rawValue: 'كرتون'),
      ],
    );
    final mixedSlots = catalogEditorSecondaryUnitSlots(mixed);

    expect(mixedSlots.unit2?.id, 'legacy-secondary');
    expect(mixedSlots.unit3?.id, 'unit_3');
    expect(
      {mixedSlots.unit2?.id, mixedSlots.unit3?.id},
      {'legacy-secondary', 'unit_3'},
    );

    final fullyLegacy = product(
      id: 'fully-legacy',
      name: 'منتج بوحدات قديمة',
      normalizedName: 'منتج بوحدات قديمة',
      units: const [
        CatalogUnit(id: 'legacy-primary', displayValue: 'حبة', rawValue: 'حبة'),
        CatalogUnit(
          id: 'legacy-secondary-2',
          displayValue: 'علبة',
          rawValue: 'علبة',
        ),
        CatalogUnit(
          id: 'legacy-secondary-3',
          displayValue: 'كرتون',
          rawValue: 'كرتون',
        ),
      ],
      primaryUnitId: 'legacy-primary',
    );
    final fullyLegacySlots = catalogEditorSecondaryUnitSlots(fullyLegacy);

    expect(fullyLegacySlots.unit2?.id, 'legacy-secondary-2');
    expect(fullyLegacySlots.unit3?.id, 'legacy-secondary-3');

    final stableUnit3Only = product(
      id: 'unit-3-only',
      name: 'منتج بوحدة ثالثة',
      normalizedName: 'منتج بوحدة ثالثة',
      units: const [
        CatalogUnit(id: 'primary', displayValue: 'حبة', rawValue: 'حبة'),
        CatalogUnit(id: 'unit_3', displayValue: 'كرتون', rawValue: 'كرتون'),
      ],
    );
    final stableUnit3Slots = catalogEditorSecondaryUnitSlots(stableUnit3Only);

    expect(stableUnit3Slots.unit2, isNull);
    expect(stableUnit3Slots.unit3?.id, 'unit_3');

    final legacyUnit3Only = product(
      id: 'legacy-unit-3-only',
      name: 'منتج قديم بوحدة ثالثة',
      normalizedName: 'منتج قديم بوحدة ثالثة',
      units: const [
        CatalogUnit(id: 'legacy-primary', displayValue: 'حبة', rawValue: 'حبة'),
        CatalogUnit(
          id: 'legacy-third',
          displayValue: 'كرتون',
          rawValue: 'كرتون',
        ),
      ],
      primaryUnitId: 'legacy-primary',
      sourceMetadata: const {'raw_unit_2': '', 'raw_unit_3': 'كرتون'},
    );
    final legacyUnit3Slots = catalogEditorSecondaryUnitSlots(legacyUnit3Only);

    expect(legacyUnit3Slots.unit2, isNull);
    expect(legacyUnit3Slots.unit3?.id, 'legacy-third');
  });

  test(
    'catalog editor preserves an approved unit until its raw value changes',
    () {
      const approved = CatalogUnit(
        id: 'unit_2',
        displayValue: 'حبة',
        rawValue: 'حبه',
        normalizedValue: 'حبة',
      );

      final unchanged = catalogEditorUpdatedUnit(
        existing: approved,
        fallbackId: 'unit_2',
        rawValue: 'حبه',
      );
      expect(unchanged.displayValue, 'حبة');
      expect(unchanged.rawValue, 'حبه');
      expect(unchanged.normalizedValue, 'حبة');

      final changed = catalogEditorUpdatedUnit(
        existing: approved,
        fallbackId: 'unit_2',
        rawValue: 'علبة',
      );
      expect(changed.displayValue, 'علبة');
      expect(changed.rawValue, 'علبة');
      expect(changed.normalizedValue, isNull);
    },
  );
}
