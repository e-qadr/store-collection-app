import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/screens/products/product_catalog_management_screen.dart';
import 'package:store_collection_app/services/product_catalog_service.dart';

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

  test(
    'catalog search matches Arabic text anywhere and ranks exact then prefix',
    () {
      final products = [
        product(id: 'exact', name: 'كحيلان', normalizedName: 'كحيلان'),
        product(
          id: 'prefix',
          name: 'كحيلان فاخر',
          normalizedName: 'كحيلان فاخر',
        ),
        product(
          id: 'middle',
          name: 'عطر كحيلان فاخر',
          normalizedName: 'عطر كحيلان فاخر',
        ),
        product(
          id: 'end',
          name: 'مجموعة عطر كحيلان',
          normalizedName: 'مجموعة عطر كحيلان',
        ),
        product(id: 'other', name: 'بخور فاخر', normalizedName: 'بخور فاخر'),
      ];

      expect(
        filterCatalogProducts(
          products,
          ' كُحيلان ',
        ).map((entry) => entry.id).toList(),
        ['exact', 'prefix', 'middle', 'end'],
      );
      expect(
        filterCatalogProducts(
          products,
          'فاخر',
        ).map((entry) => entry.id).toSet(),
        {'prefix', 'middle', 'other'},
      );
      expect(filterCatalogProducts(products, 'غير موجود'), isEmpty);
      expect(filterCatalogProducts(products, '').length, products.length);
    },
  );

  test(
    'catalog search requires every normalized token and ranks phrase matches',
    () {
      final products = [
        product(
          id: 'exact-phrase',
          name: 'دخون شرائح',
          normalizedName: 'دخون شرائح',
        ),
        product(
          id: 'phrase-prefix',
          name: 'دخون شرائح طبيعي',
          normalizedName: 'دخون شرائح طبيعي',
        ),
        product(
          id: 'same-order',
          name: 'دخون طبيعي فاخر شرائح',
          normalizedName: 'دخون طبيعي فاخر شرائح',
        ),
        product(
          id: 'reversed',
          name: 'شرائح دخون طبيعي',
          normalizedName: 'شرائح دخون طبيعي',
        ),
        product(
          id: 'incense-only',
          name: 'دخون فقط',
          normalizedName: 'دخون فقط',
        ),
        product(
          id: 'slices-only',
          name: 'شرائح فقط',
          normalizedName: 'شرائح فقط',
        ),
        product(
          id: 'three-words',
          name: 'دخون ممتاز شرائح عود',
          normalizedName: 'دخون ممتاز شرائح عود',
        ),
        product(
          id: 'arabic-normalized',
          name: 'إصدار دخون شرائح',
          normalizedName: 'اصدار دخون شرائح',
        ),
      ];

      expect(
        filterCatalogProducts(
          products,
          '  دُخون   شرائح  ',
        ).map((entry) => entry.id).toList(),
        [
          'exact-phrase',
          'phrase-prefix',
          'arabic-normalized',
          'same-order',
          'three-words',
          'reversed',
        ],
      );
      expect(
        filterCatalogProducts(
          products,
          'شرائح دخون',
        ).map((entry) => entry.id).toSet(),
        {
          'exact-phrase',
          'phrase-prefix',
          'arabic-normalized',
          'same-order',
          'reversed',
          'three-words',
        },
      );
      expect(
        filterCatalogProducts(products, 'اصدار دخون').single.id,
        'arabic-normalized',
      );
      expect(
        filterCatalogProducts(
          products,
          'دخون ممتاز عود',
        ).map((entry) => entry.id),
        ['three-words'],
      );
      expect(filterCatalogProducts(products, 'دخون ورد شرائح'), isEmpty);
      expect(filterCatalogProducts(products, '   '), products);
    },
  );

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
