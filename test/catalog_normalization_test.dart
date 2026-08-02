import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/utils/catalog_normalization.dart';

void main() {
  group('catalog duplicate normalization', () {
    test(
      'normalizes Arabic presentation differences without changing storage',
      () {
        const raw = '  أَصـناف   الإصالة  ';

        expect(normalizeCatalogText(raw), 'اصناف الاصالة');
        expect(raw, contains('أَ'));
      },
    );

    test('keeps unique product keys brand-scoped and deterministic', () {
      final first = productUniqueKeyId(
        brandId: 'brand-a',
        keyType: 'name',
        normalizedValue: 'منتج',
      );
      final repeated = productUniqueKeyId(
        brandId: 'brand-a',
        keyType: 'name',
        normalizedValue: 'منتج',
      );
      final otherBrand = productUniqueKeyId(
        brandId: 'brand-b',
        keyType: 'name',
        normalizedValue: 'منتج',
      );

      expect(first, repeated);
      expect(first, isNot(otherBrand));
      expect(first, isNot(contains('/')));
    });

    test('price memory key changes with unit or currency', () {
      final primaryYer = productPriceLatestKey(
        brandId: 'brand',
        productId: 'product',
        unitId: 'primary',
        currency: 'YER',
      );
      final secondaryYer = productPriceLatestKey(
        brandId: 'brand',
        productId: 'product',
        unitId: 'unit_2',
        currency: 'YER',
      );
      final primarySar = productPriceLatestKey(
        brandId: 'brand',
        productId: 'product',
        unitId: 'primary',
        currency: 'SAR',
      );

      expect(primaryYer, isNot(secondaryYer));
      expect(primaryYer, isNot(primarySar));
    });
  });
}
