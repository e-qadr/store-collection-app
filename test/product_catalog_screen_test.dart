import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/screens/products/product_catalog_management_screen.dart';

void main() {
  ProductCatalogModel product({
    required String id,
    required String name,
    required String normalizedName,
    String? legacyCode,
  }) {
    return ProductCatalogModel(
      id: id,
      brandId: 'brand-1',
      groupId: 'group-1',
      name: name,
      normalizedName: normalizedName,
      legacyCode: legacyCode,
      units: const [
        CatalogUnit(id: 'primary', displayValue: 'حبه', rawValue: 'حبه'),
      ],
      primaryUnitId: 'primary',
      nameUniqueKeyId: 'name-key',
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
}
