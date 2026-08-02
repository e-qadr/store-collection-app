import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/models/product_price_model.dart';
import 'package:store_collection_app/services/product_price_service.dart';

void main() {
  test(
    'latest price retains source and immutable-history pointer metadata',
    () {
      final latest = ProductPriceLatest.fromMap('latest-1', {
        'latest_key': 'latest-1',
        'history_event_id': 'history-2',
        'brand_id': 'brand-1',
        'product_id': 'product-1',
        'unit_id': 'unit_2',
        'unit_value': 'علبة',
        'currency': 'SAR',
        'price': 42.5,
        'source_invoice_id': 'invoice-9',
        'changed_by': 'collector-1',
        'changed_by_name': 'المدير العام',
        'changed_by_role': 'collector',
        'version': 2,
      });

      expect(latest.price, 42.5);
      expect(latest.unitId, 'unit_2');
      expect(latest.sourceInvoiceId, 'invoice-9');
      expect(latest.historyEventId, 'history-2');
      expect(latest.version, 2);
    },
  );

  test('only collector can directly confirm protected price memory', () {
    const collector = CatalogActor(
      uid: 'collector-1',
      name: 'المدير العام',
      role: 'collector',
    );
    const accountant = CatalogActor(
      uid: 'accountant-1',
      name: 'محاسب',
      role: 'accountant',
    );
    const admin = CatalogActor(uid: 'admin-1', name: 'مسؤول', role: 'admin');
    const inactiveCollector = CatalogActor(
      uid: 'collector-2',
      name: 'مدير غير نشط',
      role: 'collector',
      active: false,
    );

    expect(
      () => ProductPriceService.validateConfirmedPriceWriter(collector),
      returnsNormally,
    );
    expect(
      () => ProductPriceService.validateConfirmedPriceWriter(accountant),
      throwsStateError,
    );
    expect(
      () => ProductPriceService.validateConfirmedPriceWriter(admin),
      throwsStateError,
    );
    expect(
      () => ProductPriceService.validateConfirmedPriceWriter(inactiveCollector),
      throwsStateError,
    );
  });
}
