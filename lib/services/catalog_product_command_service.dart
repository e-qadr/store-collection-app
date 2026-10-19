import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/services/auth_api_service.dart';

/// Error returned by the trusted catalog command API. Product documents have
/// dynamic units, so their write validation intentionally runs on the server
/// rather than in a Firestore Rule that cannot iterate arbitrary unit lists.
class CatalogProductCommandException implements Exception {
  final String code;
  final String message;

  const CatalogProductCommandException(this.code, this.message);

  @override
  String toString() => message;
}

class CatalogProductCommandService {
  final String _baseUrl;
  final http.Client _client;
  final Future<String?> Function() _tokenProvider;

  CatalogProductCommandService({
    String? baseUrl,
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  }) : _baseUrl = (baseUrl ?? AuthApiService.configuredBaseUrl).replaceAll(
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

  Future<String> createProduct({
    required String brandId,
    required String groupId,
    required String name,
    String? legacyCode,
    required List<CatalogUnit> units,
    required String primaryUnitId,
    required Map<String, dynamic> sourceMetadata,
  }) async {
    final response = await _post('/v1/catalog-products', {
      'brand_id': brandId.trim(),
      'group_id': groupId.trim(),
      'name': name.trim(),
      if (legacyCode?.trim().isNotEmpty ?? false)
        'legacy_code': legacyCode!.trim(),
      'units': units.map((unit) => unit.toMap()).toList(growable: false),
      'primary_unit_id': primaryUnitId.trim(),
      'source_metadata': sourceMetadata,
    });
    final productId = response['product_id']?.toString().trim() ?? '';
    if (productId.isEmpty) {
      throw const CatalogProductCommandException(
        'invalid-response',
        'تعذر تأكيد إنشاء المادة من الخادم.',
      );
    }
    return productId;
  }

  Future<void> updateProduct({
    required String productId,
    required String groupId,
    required String name,
    String? legacyCode,
    required List<CatalogUnit> units,
    required String primaryUnitId,
    Map<String, dynamic>? sourceMetadata,
  }) => _post('/v1/catalog-products/${Uri.encodeComponent(productId.trim())}', {
    'group_id': groupId.trim(),
    'name': name.trim(),
    if (legacyCode?.trim().isNotEmpty ?? false)
      'legacy_code': legacyCode!.trim(),
    'units': units.map((unit) => unit.toMap()).toList(growable: false),
    'primary_unit_id': primaryUnitId.trim(),
    if (sourceMetadata != null) 'source_metadata': sourceMetadata,
  });

  Future<void> archiveProduct({
    required String productId,
    required String reason,
  }) => _lifecycle(productId, 'archive', reason);

  Future<void> reactivateProduct({
    required String productId,
    required String reason,
  }) => _lifecycle(productId, 'reactivate', reason);

  Future<void> _lifecycle(String productId, String action, String reason) =>
      _post(
        '/v1/catalog-products/${Uri.encodeComponent(productId.trim())}/$action',
        {'reason': reason.trim()},
      );

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    if (_baseUrl.isEmpty) {
      throw const CatalogProductCommandException(
        'configuration-error',
        'خدمة إدارة المواد غير مهيأة.',
      );
    }
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const CatalogProductCommandException(
        'unauthenticated',
        'انتهت جلسة الدخول. سجل الدخول مجددًا.',
      );
    }
    late http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $token',
              'idempotency-key': _idempotencyKey(),
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const CatalogProductCommandException(
        'network-error',
        'تعذر الاتصال بخدمة المواد. تحقق من الشبكة وحاول مرة أخرى.',
      );
    }
    final decoded = _decode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    final error = decoded['error'];
    final code = error is Map
        ? error['code']?.toString() ?? 'request-failed'
        : 'request-failed';
    throw CatalogProductCommandException(code, _messageFor(code));
  }

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic>
          ? decoded
          : Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _idempotencyKey() {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  String _messageFor(String code) => switch (code) {
    'forbidden' => 'لا تملك صلاحية إدارة المواد.',
    'catalog-duplicate' => 'توجد مادة مماثلة بالفعل في الكتالوج.',
    'catalog-group-invalid' => 'المجموعة المختارة غير متاحة.',
    'product-not-found' => 'المادة المطلوبة لم تعد متاحة.',
    'product-archived' => 'أعد تفعيل المادة قبل تعديلها.',
    'catalog-provenance-immutable' => 'لا يمكن تغيير مصدر المادة بعد إنشائها.',
    'protected-price-field-forbidden' => 'لا يمكن حفظ أسعار ضمن بيانات المادة.',
    'unauthenticated' => 'انتهت جلسة الدخول. سجل الدخول مجددًا.',
    _ => 'تعذر حفظ المادة بأمان. حاول مرة أخرى.',
  };
}
