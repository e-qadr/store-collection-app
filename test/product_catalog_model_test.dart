import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';

void main() {
  group('product catalog model', () {
    test('preserves independent raw unit spellings', () {
      final product = ProductCatalogModel.fromMap('product-1', {
        'brand_id': 'brand-1',
        'group_id': 'group-1',
        'name': 'منتج',
        'normalized_name': 'منتج',
        'primary_unit_id': 'primary',
        'name_unique_key_id': 'key-1',
        'last_audit_event_id': 'audit-1',
        'units': [
          {'unit_id': 'primary', 'display_value': 'حبه', 'raw_value': 'حبه'},
          {'unit_id': 'unit_2', 'display_value': 'علبه', 'raw_value': 'علبه'},
          {'unit_id': 'unit_3', 'display_value': 'اوقيه', 'raw_value': 'اوقيه'},
        ],
      });

      expect(product.id, 'product-1');
      expect(product.units.map((unit) => unit.id), [
        'primary',
        'unit_2',
        'unit_3',
      ]);
      expect(product.unitById('unit_2')?.rawValue, 'علبه');
      expect(product.unitById('unit_2')?.normalizedValue, isNull);
      expect(product.lastAuditEventId, 'audit-1');
    });

    test('does not expose a price property in catalog serialization', () {
      const unit = CatalogUnit(
        id: 'primary',
        displayValue: 'حبه',
        rawValue: 'حبه',
      );

      expect(
        unit.toMap().keys,
        containsAll(['unit_id', 'display_value', 'raw_value']),
      );
      expect(unit.toMap().keys.any((key) => key.contains('price')), isFalse);
    });

    test('keeps catalog writes accountant-only at the actor boundary', () {
      const accountant = CatalogActor(
        uid: 'accountant-1',
        name: 'محاسب',
        role: 'accountant',
      );
      const manager = CatalogActor(
        uid: 'manager-1',
        name: 'مدير',
        role: 'manager',
      );

      expect(accountant.isAccountant, isTrue);
      expect(manager.isAccountant, isFalse);
      expect(manager.canManageProtectedPrices, isFalse);
    });

    test('reads mandatory audit links for groups and accounting profiles', () {
      final group = ProductGroupModel.fromMap('group-1', {
        'brand_id': 'brand-1',
        'name': 'مجموعة',
        'normalized_name': 'مجموعة',
        'last_audit_event_id': 'audit-group-1',
      });
      final profile = ProductAccountingProfile.fromMap({
        'id': 'product-1',
        'product_id': 'product-1',
        'brand_id': 'brand-1',
        'sync_state': 'pending',
        'last_audit_event_id': 'audit-profile-1',
      });

      expect(group.lastAuditEventId, 'audit-group-1');
      expect(profile.id, 'product-1');
      expect(profile.lastAuditEventId, 'audit-profile-1');
    });
  });
}
