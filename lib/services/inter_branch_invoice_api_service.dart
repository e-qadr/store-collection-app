import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:store_collection_app/models/inter_branch_invoice_model.dart';
import 'package:store_collection_app/services/auth_api_service.dart';

class InterBranchInvoiceApiException implements Exception {
  final String code;
  final String message;

  const InterBranchInvoiceApiException(this.code, this.message);

  @override
  String toString() => message;
}

class InterBranchInvoiceCommandResult {
  final String invoiceId;
  final String invoiceNumber;
  final InterBranchInvoiceStatus status;
  final int revision;
  final bool idempotentReplay;

  const InterBranchInvoiceCommandResult({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.status,
    required this.revision,
    required this.idempotentReplay,
  });

  factory InterBranchInvoiceCommandResult.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status']?.toString().trim() ?? '';
    return InterBranchInvoiceCommandResult(
      invoiceId: json['invoice_id']?.toString() ?? '',
      invoiceNumber: json['invoice_number']?.toString() ?? '',
      status: rawStatus.isEmpty
          ? InterBranchInvoiceStatus.unknown
          : interBranchInvoiceStatusFromString(rawStatus),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      idempotentReplay: json['idempotent_replay'] == true,
    );
  }
}

class InterBranchInvoicePriceInput {
  final String itemId;
  final double unitPrice;

  const InterBranchInvoicePriceInput({
    required this.itemId,
    required this.unitPrice,
  });

  Map<String, dynamic> toJson() => {'item_id': itemId, 'unit_price': unitPrice};
}

class InterBranchInvoiceApiService {
  /// Version-2 public items are stored in a dedicated subcollection.
  static const int maxItems = 50;

  final String _baseUrl;
  final http.Client _client;
  final Future<String?> Function() _tokenProvider;

  InterBranchInvoiceApiService({
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
             return user == null
                 ? Future<String?>.value()
                 : user.getIdToken(true);
           });

  bool get isConfigured => _baseUrl.isNotEmpty;

  Future<InterBranchInvoiceCommandResult> createDirectInvoice({
    required String receivingBranchId,
    required List<InterBranchInvoiceItem> items,
    required String idempotencyKey,
    String? invoiceNotes,
  }) async {
    if (receivingBranchId.trim().isEmpty ||
        !_withinUtf8Limit(invoiceNotes, 1000) ||
        items.isEmpty ||
        items.length > maxItems) {
      throw ArgumentError(
        'Invoice must contain between 1 and $maxItems items.',
      );
    }
    if (items.any(
      (item) =>
          item.productId.trim().isEmpty ||
          item.unitId.trim().isEmpty ||
          !item.suppliedQuantity.isFinite ||
          item.suppliedQuantity <= 0 ||
          !_withinUtf8Limit(item.lineNotes, 100) ||
          item.unitPrice != null,
    )) {
      throw ArgumentError(
        'Every direct invoice item must be price-free and valid.',
      );
    }
    return _command(
      '/v1/inter-branch-invoices',
      idempotencyKey: idempotencyKey,
      body: {
        'receiving_branch_id': receivingBranchId.trim(),
        'items': items.map((item) => item.toDirectCommandMap()).toList(),
        if ((invoiceNotes ?? '').trim().isNotEmpty)
          'invoice_notes': invoiceNotes!.trim(),
      },
    );
  }

  Future<InterBranchInvoiceCommandResult> confirmReceipt({
    required String invoiceId,
    required int expectedRevision,
    required List<InterBranchInvoiceItem> items,
    required String idempotencyKey,
    String? receiverNotes,
  }) {
    if (invoiceId.trim().isEmpty ||
        expectedRevision <= 0 ||
        !_withinUtf8Limit(receiverNotes, 1000) ||
        items.isEmpty ||
        items.length > maxItems ||
        items.any(
          (item) =>
              item.itemId.trim().isEmpty ||
              !item.receivedQuantity.isFinite ||
              item.receivedQuantity < 0 ||
              !item.missingQuantity.isFinite ||
              item.missingQuantity < 0 ||
              !item.damagedQuantity.isFinite ||
              item.damagedQuantity < 0 ||
              !_withinUtf8Limit(item.discrepancyNotes, 100),
        )) {
      throw ArgumentError('Receipt quantities are invalid.');
    }
    return _command(
      '/v1/inter-branch-invoices/${Uri.encodeComponent(invoiceId)}/confirm-receipt',
      idempotencyKey: idempotencyKey,
      body: {
        'expected_revision': expectedRevision,
        if ((receiverNotes ?? '').trim().isNotEmpty)
          'receiver_notes': receiverNotes!.trim(),
        'items': items.map((item) => item.toReceiptCommandMap()).toList(),
      },
    );
  }

  Future<InterBranchInvoiceCommandResult> confirmPrices({
    required String invoiceId,
    required int expectedRevision,
    required String currency,
    required List<InterBranchInvoicePriceInput> items,
    required String idempotencyKey,
    String? pricingNotes,
  }) {
    if (invoiceId.trim().isEmpty ||
        expectedRevision <= 0 ||
        !_withinUtf8Limit(pricingNotes, 1000) ||
        !const {'YER', 'SAR', 'USD'}.contains(currency.toUpperCase()) ||
        items.isEmpty ||
        items.length > maxItems ||
        items.any(
          (item) =>
              item.itemId.trim().isEmpty ||
              !item.unitPrice.isFinite ||
              item.unitPrice < 0,
        )) {
      throw ArgumentError('Pricing confirmation is invalid.');
    }
    return _command(
      '/v1/inter-branch-invoices/${Uri.encodeComponent(invoiceId)}/confirm-prices',
      idempotencyKey: idempotencyKey,
      body: {
        'expected_revision': expectedRevision,
        'currency': currency.toUpperCase(),
        if ((pricingNotes ?? '').trim().isNotEmpty)
          'pricing_notes': pricingNotes!.trim(),
        'items': items.map((item) => item.toJson()).toList(),
      },
    );
  }

  Future<InterBranchInvoiceCommandResult> postAccounting({
    required String invoiceId,
    required int expectedRevision,
    required String accountingReference,
    required String idempotencyKey,
    String? accountingNotes,
  }) {
    if (invoiceId.trim().isEmpty ||
        expectedRevision <= 0 ||
        accountingReference.trim().isEmpty ||
        !_withinUtf8Limit(accountingReference, 200) ||
        !_withinUtf8Limit(accountingNotes, 1000)) {
      throw ArgumentError('Accounting posting is invalid.');
    }
    return _command(
      '/v1/inter-branch-invoices/${Uri.encodeComponent(invoiceId)}/post-accounting',
      idempotencyKey: idempotencyKey,
      body: {
        'expected_revision': expectedRevision,
        'accounting_reference': accountingReference.trim(),
        if ((accountingNotes ?? '').trim().isNotEmpty)
          'accounting_notes': accountingNotes!.trim(),
      },
    );
  }

  Future<InterBranchInvoiceCommandResult> _command(
    String path, {
    required String idempotencyKey,
    required Map<String, dynamic> body,
  }) async {
    _ensureConfigured();
    final key = idempotencyKey.trim();
    if (key.length < 8 ||
        key.length > 128 ||
        !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(key)) {
      throw ArgumentError('A valid ASCII idempotency key is required.');
    }
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const InterBranchInvoiceApiException(
        'unauthenticated',
        'انتهت جلسة الدخول. سجل الدخول مجدداً.',
      );
    }
    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $token',
              'idempotency-key': key,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const InterBranchInvoiceApiException(
        'network-error',
        'تعذر الاتصال بالخادم. تحقق من الشبكة وحاول مرة أخرى بنفس الطلب.',
      );
    }
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      final safeError = error is Map
          ? Map<String, dynamic>.from(error)
          : const <String, dynamic>{};
      final code = safeError['code']?.toString() ?? 'request-failed';
      throw InterBranchInvoiceApiException(code, safeMessageForCode(code));
    }
    final result = InterBranchInvoiceCommandResult.fromJson(decoded);
    if (result.invoiceId.isEmpty ||
        result.revision <= 0 ||
        result.status == InterBranchInvoiceStatus.unknown) {
      throw const InterBranchInvoiceApiException(
        'invalid-response',
        'تعذر التحقق من استجابة الخادم.',
      );
    }
    return result;
  }

  Map<String, dynamic> _decode(String source) {
    if (source.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(source);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  void _ensureConfigured() {
    if (!isConfigured) {
      throw const InterBranchInvoiceApiException(
        'configuration-error',
        'خدمة أوامر فواتير الفروع غير مهيأة في هذا الإصدار.',
      );
    }
  }

  static String generateIdempotencyKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static bool _withinUtf8Limit(String? value, int maximumBytes) =>
      utf8.encode(value?.trim() ?? '').length <= maximumBytes;

  /// Maps backend codes to bounded, user-safe Arabic text without exposing
  /// server messages, stack traces, payloads, or identifiers.
  static String safeMessageForCode(String code) {
    return switch (code) {
      'counter-uninitialized' =>
        'عداد فواتير الفرع غير مهيأ. تواصل مع الإدارة قبل إنشاء الفاتورة، ولم يتم استهلاك أي رقم.',
      'stale-revision' =>
        'تم تحديث الفاتورة من مستخدم آخر. أعد فتحها ثم حاول مجدداً.',
      'invalid-state' => 'هذه العملية لم تعد متاحة في حالة الفاتورة الحالية.',
      'unauthenticated' => 'انتهت جلسة الدخول. سجل الدخول مجدداً.',
      'forbidden' => 'لا تملك صلاحية تنفيذ هذه العملية.',
      'payload-too-large' => 'حجم بيانات الفاتورة أكبر من الحد الآمن المسموح.',
      'network-error' =>
        'تعذر الاتصال بالخادم. تحقق من الشبكة وحاول مرة أخرى بنفس الطلب.',
      _ => 'تعذر إتمام العملية بأمان. حاول مجدداً أو تواصل مع الإدارة.',
    };
  }
}
