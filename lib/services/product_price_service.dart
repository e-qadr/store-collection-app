import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/models/product_price_model.dart';
import 'package:store_collection_app/utils/catalog_normalization.dart';

/// Stores protected price memory separately from manager-readable products.
///
/// Firestore Security Rules are still the enforcement boundary. Callers must
/// never copy these maps into product or public invoice documents.
class ProductPriceService {
  static const supportedCurrencies = <String>{'YER', 'SAR', 'USD'};

  final FirebaseFirestore _firestore;

  ProductPriceService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _latest =>
      _firestore.collection(ProductPriceCollections.latest);

  CollectionReference<Map<String, dynamic>> get _history =>
      _firestore.collection(ProductPriceCollections.history);

  Stream<ProductPriceLatest?> watchLatest({
    required String brandId,
    required String productId,
    required String unitId,
    required String currency,
  }) {
    final latestKey = buildLatestKey(
      brandId: brandId,
      productId: productId,
      unitId: unitId,
      currency: currency,
    );
    return _latest.doc(latestKey).snapshots().map((snapshot) {
      final data = snapshot.data();
      return data == null
          ? null
          : ProductPriceLatest.fromMap(snapshot.id, data);
    });
  }

  Stream<List<ProductPriceHistoryEntry>> watchHistory({
    required String brandId,
    required String productId,
    required String unitId,
    required String currency,
  }) {
    final latestKey = buildLatestKey(
      brandId: brandId,
      productId: productId,
      unitId: unitId,
      currency: currency,
    );
    return _history
        .where('latest_key', isEqualTo: latestKey)
        .orderBy('changed_at', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => ProductPriceHistoryEntry.fromMap(doc.id, doc.data()),
              )
              .toList(growable: false),
        );
  }

  Future<void> recordConfirmedPrice({
    required CatalogActor actor,
    required String brandId,
    required String productId,
    required String unitId,
    required String unitValue,
    required double price,
    required String currency,
    required String sourceInvoiceId,
  }) async {
    validateConfirmedPriceWriter(actor);
    final cleanBrandId = _required(brandId, 'Brand ID');
    final cleanProductId = _required(productId, 'Product ID');
    final cleanUnitId = _required(unitId, 'Unit ID');
    final cleanUnitValue = _required(unitValue, 'Unit value');
    final cleanCurrency = _currency(currency);
    final cleanSourceInvoiceId = _required(
      sourceInvoiceId,
      'Source invoice ID',
    );
    if (!price.isFinite || price < 0) {
      throw ArgumentError('Price must be a finite, non-negative number.');
    }

    final latestKey = productPriceLatestKey(
      brandId: cleanBrandId,
      productId: cleanProductId,
      unitId: cleanUnitId,
      currency: cleanCurrency,
    );
    final latestRef = _latest.doc(latestKey);
    final historyRef = _history.doc();
    final productRef = _firestore
        .collection(ProductCatalogCollections.products)
        .doc(cleanProductId);

    await _firestore.runTransaction((transaction) async {
      final product = await transaction.get(productRef);
      final previous = await transaction.get(latestRef);
      final productData = product.data();
      if (productData == null) throw StateError('Product was not found.');
      if (productData[ProductCatalogFields.brandId]?.toString() !=
          cleanBrandId) {
        throw StateError('Product belongs to a different brand.');
      }
      _validateProductUnit(productData, cleanUnitId, cleanUnitValue);

      final previousData = previous.data();
      final version = ((previousData?['version'] as num?)?.toInt() ?? 0) + 1;
      final common = <String, dynamic>{
        'brand_id': cleanBrandId,
        'product_id': cleanProductId,
        'unit_id': cleanUnitId,
        'unit_value': cleanUnitValue,
        'currency': cleanCurrency,
        'price': price,
        'source_invoice_id': cleanSourceInvoiceId,
        'changed_by': actor.uid,
        'changed_by_name': actor.name,
        'changed_by_role': actor.role,
        'changed_at': FieldValue.serverTimestamp(),
        'version': version,
      };
      transaction.set(latestRef, {
        'id': latestKey,
        'latest_key': latestKey,
        'history_event_id': historyRef.id,
        ...common,
      });
      transaction.set(historyRef, {
        'id': historyRef.id,
        'latest_key': latestKey,
        ...common,
        if (previousData?['price'] is num)
          'previous_price': (previousData!['price'] as num).toDouble(),
        if (_nonEmpty(previousData?['source_invoice_id']) != null)
          'previous_source_invoice_id': _nonEmpty(
            previousData?['source_invoice_id'],
          ),
      });
    });
  }

  String buildLatestKey({
    required String brandId,
    required String productId,
    required String unitId,
    required String currency,
  }) {
    return productPriceLatestKey(
      brandId: _required(brandId, 'Brand ID'),
      productId: _required(productId, 'Product ID'),
      unitId: _required(unitId, 'Unit ID'),
      currency: _currency(currency),
    );
  }

  void _validateProductUnit(
    Map<String, dynamic> productData,
    String unitId,
    String unitValue,
  ) {
    final units = productData[ProductCatalogFields.units];
    if (units is! List) throw StateError('Product has no selectable units.');
    for (final value in units.whereType<Map>()) {
      if (value['unit_id']?.toString() == unitId) {
        if (value['display_value']?.toString().trim() != unitValue) {
          throw StateError('Unit value does not match the catalog snapshot.');
        }
        return;
      }
    }
    throw StateError('Selected unit does not belong to the product.');
  }

  static void validateConfirmedPriceWriter(CatalogActor actor) {
    if (actor.uid.trim().isEmpty) throw ArgumentError('Actor UID is required.');
    if (actor.name.trim().isEmpty) {
      throw ArgumentError('Actor name is required.');
    }
    if (!actor.canWriteProtectedPrices) {
      throw StateError(
        'Only the general manager can confirm protected product prices.',
      );
    }
  }

  String _currency(String value) {
    final result = _required(value, 'Currency').toUpperCase();
    if (!supportedCurrencies.contains(result)) {
      throw ArgumentError('Unsupported currency.');
    }
    return result;
  }

  String _required(String value, String label) {
    final result = value.trim();
    if (result.isEmpty) throw ArgumentError('$label is required.');
    return result;
  }

  String? _nonEmpty(dynamic value) {
    final result = value?.toString().trim();
    return result == null || result.isEmpty ? null : result;
  }
}
