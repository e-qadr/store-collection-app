import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/models/product_price_model.dart';
import 'package:store_collection_app/services/auth_api_service.dart';
import 'package:store_collection_app/utils/catalog_normalization.dart';

class ProductPriceCommandException implements Exception {
  final String code;
  final String message;

  const ProductPriceCommandException(this.code, this.message);

  @override
  String toString() => message;
}

/// Stores protected price memory separately from manager-readable products.
///
/// Firestore Security Rules are still the enforcement boundary. Callers must
/// never copy these maps into product or public invoice documents.
class ProductPriceService {
  static const supportedCurrencies = <String>{'YER', 'SAR', 'USD'};

  final FirebaseFirestore? _providedFirestore;
  final String _baseUrl;
  final http.Client _client;
  final Future<String?> Function() _tokenProvider;

  ProductPriceService({
    FirebaseFirestore? firestore,
    String? baseUrl,
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  }) : _providedFirestore = firestore,
       _baseUrl = (baseUrl ?? AuthApiService.configuredBaseUrl).replaceAll(
         RegExp(r'/+$'),
         '',
       ),
       _client = client ?? http.Client(),
       _tokenProvider =
           tokenProvider ??
           (() {
             final user = FirebaseAuth.instance.currentUser;
             return user == null ? Future<String?>.value() : user.getIdToken();
           });

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

  /// Updates protected price memory through the authenticated backend command.
  /// No Flutter client is ever granted a Firestore write to price collections.
  Future<void> updateCatalogPrice({
    required String productId,
    required String unitId,
    required String currency,
    required double price,
    required String idempotencyKey,
  }) async {
    final cleanProductId = _required(productId, 'Product ID');
    final cleanUnitId = _required(unitId, 'Unit ID');
    final cleanCurrency = _currency(currency);
    if (!price.isFinite || price < 0) {
      throw ArgumentError('Price must be a non-negative finite number.');
    }
    final key = idempotencyKey.trim();
    if (key.length < 8 ||
        key.length > 128 ||
        !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(key)) {
      throw ArgumentError('Invalid idempotency key.');
    }
    if (_baseUrl.isEmpty) {
      throw const ProductPriceCommandException(
        'configuration-error',
        'خدمة تسعير المواد غير مهيأة.',
      );
    }
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const ProductPriceCommandException(
        'unauthenticated',
        'انتهت جلسة الدخول. سجل الدخول مجددًا.',
      );
    }
    late http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl/v1/product-prices'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $token',
              'idempotency-key': key,
            },
            body: jsonEncode({
              'product_id': cleanProductId,
              'unit_id': cleanUnitId,
              'currency': cleanCurrency,
              'price': price,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ProductPriceCommandException(
        'network-error',
        'تعذر الاتصال بالخادم. تحقق من الشبكة وحاول مرة أخرى.',
      );
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String code = 'request-failed';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] is Map) {
        code = (decoded['error'] as Map)['code']?.toString() ?? code;
      }
    } catch (_) {
      // The backend response body is deliberately not surfaced to the UI.
    }
    throw ProductPriceCommandException(code, _safeMessage(code));
  }

  static String generateIdempotencyKey() {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
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
        'Only the General Manager or accountant can confirm protected product prices.',
      );
    }
  }

  String _safeMessage(String code) => switch (code) {
    'forbidden' => 'لا تملك صلاحية تسعير المواد.',
    'product-not-found' => 'المادة المحددة غير متاحة.',
    'catalog-snapshot-invalid' => 'الوحدة المحددة لم تعد صالحة لهذه المادة.',
    'unauthenticated' => 'انتهت جلسة الدخول. سجل الدخول مجددًا.',
    _ => 'تعذر حفظ السعر بأمان. حاول مرة أخرى أو تواصل مع الإدارة.',
  };

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
