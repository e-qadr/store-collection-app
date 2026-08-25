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
      const collector = CatalogActor(
        uid: 'collector-1',
        name: 'المدير العام',
        role: 'collector',
      );
      const admin = CatalogActor(uid: 'admin-1', name: 'مسؤول', role: 'admin');
      const inactiveCollector = CatalogActor(
        uid: 'collector-2',
        name: 'مدير غير نشط',
        role: 'collector',
        active: false,
      );
      const unknown = CatalogActor(
        uid: 'unknown-1',
        name: 'غير معروف',
        role: 'unknown',
      );

      expect(accountant.isAccountant, isTrue);
      expect(manager.isAccountant, isFalse);
      expect(manager.canReadProtectedPrices, isFalse);
      expect(collector.canReadProtectedPrices, isTrue);
      expect(accountant.canReadProtectedPrices, isTrue);
      expect(admin.canReadProtectedPrices, isTrue);
      expect(collector.canWriteProtectedPrices, isTrue);
      expect(accountant.canWriteProtectedPrices, isTrue);
      expect(admin.canWriteProtectedPrices, isFalse);
      expect(inactiveCollector.canReadProtectedPrices, isFalse);
      expect(inactiveCollector.canWriteProtectedPrices, isFalse);
      expect(unknown.canReadProtectedPrices, isFalse);
      expect(unknown.canWriteProtectedPrices, isFalse);
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

    test('builds one deterministic Uncategorized identity per brand', () {
      final first = UncategorizedProductGroupContract.documentIdForBrand(
        'brand-a',
      );
      final repeated = UncategorizedProductGroupContract.documentIdForBrand(
        'brand-a',
      );
      final otherBrand = UncategorizedProductGroupContract.documentIdForBrand(
        'brand-b',
      );

      expect(first, 'system-group-brand-a-uncategorized');
      expect(repeated, first);
      expect(otherBrand, 'system-group-brand-b-uncategorized');
      expect(otherBrand, isNot(first));
    });

    test('validates idempotent system-group documents and reserved names', () {
      const brandId = 'brand-a';
      final documentId = UncategorizedProductGroupContract.documentIdForBrand(
        brandId,
      );
      final document = <String, dynamic>{
        'id': documentId,
        'brand_id': brandId,
        'name': 'غير مصنف',
        'normalized_name': 'غير مصنف',
        'active': true,
        'is_system_group': true,
        'system_key': 'uncategorized',
        'last_audit_event_id': 'audit-system-group',
      };

      expect(
        UncategorizedProductGroupContract.matchesExistingDocument(
          documentId: documentId,
          brandId: brandId,
          data: document,
        ),
        isTrue,
      );
      final parsed = ProductGroupModel.fromMap(documentId, document);
      expect(parsed.isSystemGroup, isTrue);
      expect(parsed.systemKey, 'uncategorized');
      expect(parsed.canBeArchived, isFalse);
      expect(
        UncategorizedProductGroupContract.isReservedIdentity(name: 'غير مصنف'),
        isTrue,
      );
      expect(
        UncategorizedProductGroupContract.isReservedIdentity(
          name: 'uncategorized',
        ),
        isTrue,
      );
      expect(
        UncategorizedProductGroupContract.matchesExistingDocument(
          documentId: documentId,
          brandId: brandId,
          data: {...document, 'system_key': 'other'},
        ),
        isFalse,
      );
    });

    test('parses legacy groups without system fields as ordinary groups', () {
      final legacy = ProductGroupModel.fromMap('legacy-group', {
        'brand_id': 'brand-a',
        'name': 'عطور',
        'normalized_name': 'عطور',
        'active': true,
      });

      expect(legacy.isSystemGroup, isFalse);
      expect(legacy.systemKey, isNull);
      expect(legacy.canBeArchived, isTrue);
    });

    test('audit parsing retains before and after group reassignment', () {
      final event = ProductAuditEvent.fromMap('audit-2', {
        'entity_type': 'product',
        'entity_id': 'product-1',
        'brand_id': 'brand-a',
        'action': 'recategorized',
        'actor_uid': 'accountant-1',
        'actor_name': 'محاسب',
        'actor_role': 'accountant',
        'before': {'group_id': 'group-old'},
        'after': {
          'group_id': 'system-group-brand-a-uncategorized',
          'last_audit_event_id': 'audit-2',
        },
      });

      expect(event.before['group_id'], 'group-old');
      expect(event.action, 'recategorized');
      expect(event.after['group_id'], 'system-group-brand-a-uncategorized');
      expect(event.after['last_audit_event_id'], 'audit-2');
    });
  });
}
