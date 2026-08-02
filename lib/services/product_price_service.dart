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

  final FirebaseFirestore? _providedFirestore;

  ProductPriceService({FirebaseFirestore? firestore})
    : _providedFirestore = firestore;

  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;

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

  Future<ProductPriceLatest?> fetchLatest({
    required String brandId,
    required String productId,
    required String unitId,
    required String currency,
  }) async {
    final latestKey = buildLatestKey(
      brandId: brandId,
      productId: productId,
      unitId: unitId,
      currency: currency,
    );
    final snapshot = await _latest.doc(latestKey).get();
    final data = snapshot.data();
    return data == null ? null : ProductPriceLatest.fromMap(snapshot.id, data);
  }

  @Deprecated('Protected price writes are backend-command-only in workflow v2.')
  Future<void> recordConfirmedPrice({
    required CatalogActor actor,
    required String brandId,
    required String productId,
    required String unitId,
    required String unitValue,
    required double price,
    required String currency,
    required String sourceInvoiceId,
  }) {
    throw UnsupportedError(
      'Protected price writes must use the authenticated invoice command API.',
    );
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
}
