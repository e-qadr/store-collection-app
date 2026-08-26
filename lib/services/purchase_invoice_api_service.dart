import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/models/purchase_invoice_model.dart';
import 'package:store_collection_app/services/auth_api_service.dart';

class PurchaseInvoiceApiException implements Exception {
  final String code;
  final String message;
  final int? httpStatus;
  final String? sanitizedBackendMessage;
  final String? firstClientFrame;

  const PurchaseInvoiceApiException(
    this.code,
    this.message, {
    this.httpStatus,
    this.sanitizedBackendMessage,
    this.firstClientFrame,
  });

  @override
  String toString() => message;
}

class PurchaseInvoiceCommandResult {
  final String invoiceId;
  final String purchaseNumber;
  final PurchaseInvoiceStatus status;
  final int revision;
  final bool idempotentReplay;
  final String taskId;
  final String taskStatus;
  final int taskRevision;
  final String productId;

  const PurchaseInvoiceCommandResult({
    required this.invoiceId,
    required this.purchaseNumber,
    required this.status,
    required this.revision,
    required this.idempotentReplay,
    this.taskId = '',
    this.taskStatus = '',
    this.taskRevision = 0,
    this.productId = '',
  });

  factory PurchaseInvoiceCommandResult.fromJson(Map<String, dynamic> json) =>
      PurchaseInvoiceCommandResult(
        invoiceId: json['invoice_id']?.toString() ?? '',
        purchaseNumber: json['purchase_number']?.toString() ?? '',
        status: purchaseInvoiceStatusFromString(json['status']?.toString()),
        revision: (json['revision'] as num?)?.toInt() ?? 0,
        idempotentReplay: json['idempotent_replay'] == true,
        taskId: json['task_id']?.toString() ?? '',
        taskStatus: json['task_status']?.toString() ?? '',
        taskRevision: (json['task_revision'] as num?)?.toInt() ?? 0,
        productId: json['product_id']?.toString() ?? '',
      );
}

class PurchaseInvoiceCreateItem {
  final String sourceType;
  final String productId;
  final String unitId;
  final String materialName;
  final String groupText;
  final String unitText;
  final double orderedQuantity;
  final String lineNotes;
  final double? provisionalUnitPrice;

  const PurchaseInvoiceCreateItem.catalog({
    required this.productId,
    required this.unitId,
    required this.orderedQuantity,
    this.lineNotes = '',
    this.provisionalUnitPrice,
  }) : sourceType = 'catalog',
       materialName = '',
       groupText = '',
       unitText = '';

  const PurchaseInvoiceCreateItem.unmatched({
    required this.materialName,
    required this.unitText,
    required this.orderedQuantity,
    this.groupText = '',
    this.lineNotes = '',
    this.provisionalUnitPrice,
  }) : sourceType = 'unmatched',
       productId = '',
       unitId = '';

  Map<String, dynamic> toJson() => {
    'source_type': sourceType,
    if (sourceType == 'catalog') ...{
      'product_id': productId,
      'unit_id': unitId,
    } else ...{
      'material_name': materialName,
      'group_text': groupText,
      'unit_text': unitText,
    },
    'ordered_quantity': orderedQuantity,
    if (lineNotes.trim().isNotEmpty) 'line_notes': lineNotes.trim(),
    if (provisionalUnitPrice != null)
      'provisional_unit_price': provisionalUnitPrice,
  };
}

class PurchaseReceiptInput {
  final String itemId;
  final double receivedQuantity;
  final double damagedQuantity;
  final double missingQuantity;
  final String discrepancyNotes;

  const PurchaseReceiptInput({
    required this.itemId,
    required this.receivedQuantity,
    this.damagedQuantity = 0,
    this.missingQuantity = 0,
    this.discrepancyNotes = '',
  });

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    'received_quantity': receivedQuantity,
    'damaged_quantity': damagedQuantity,
    'missing_quantity': missingQuantity,
    if (discrepancyNotes.trim().isNotEmpty)
      'discrepancy_notes': discrepancyNotes.trim(),
  };
}

class PurchasePriceInput {
  final String itemId;
  final double unitPrice;

  const PurchasePriceInput({required this.itemId, required this.unitPrice});

  Map<String, dynamic> toJson() => {'item_id': itemId, 'unit_price': unitPrice};
}

class PurchaseAmendmentPriceInput {
  final String itemId;
  final double unitPrice;

  const PurchaseAmendmentPriceInput({
    required this.itemId,
    required this.unitPrice,
  });

  Map<String, dynamic> toJson() => {'item_id': itemId, 'unit_price': unitPrice};
}

class PurchaseInvoiceApiService {
  static const maxItems = 50;
  static const supportedCurrencies = {'YER', 'SAR', 'USD'};

  final String _baseUrl;
  final http.Client _client;
  final Future<String?> Function() _tokenProvider;

  PurchaseInvoiceApiService({
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

  Future<PurchaseInvoiceCommandResult> createInvoice({
    required String receivingBranchId,
    required String currency,
    required List<PurchaseInvoiceCreateItem> items,
    required String idempotencyKey,
    String? supplierName,
    String? supplierInvoiceNumber,
    String? supplierInvoiceDate,
    String? generalManagerNotes,
  }) {
    if (receivingBranchId.trim().isEmpty ||
        !supportedCurrencies.contains(currency.toUpperCase()) ||
        items.isEmpty ||
        items.length > maxItems ||
        items.any(
          (item) =>
              !item.orderedQuantity.isFinite ||
              item.orderedQuantity <= 0 ||
              (item.provisionalUnitPrice != null &&
                  (!item.provisionalUnitPrice!.isFinite ||
                      item.provisionalUnitPrice! < 0)) ||
              (item.sourceType == 'catalog'
                  ? item.productId.trim().isEmpty || item.unitId.trim().isEmpty
                  : item.materialName.trim().isEmpty ||
                        item.unitText.trim().isEmpty),
        )) {
      throw ArgumentError('بيانات فاتورة المشتريات غير مكتملة.');
    }
    return _command('/v1/purchase-invoices', idempotencyKey, {
      'receiving_branch_id': receivingBranchId.trim(),
      'currency': currency.toUpperCase(),
      if ((supplierName ?? '').trim().isNotEmpty)
        'supplier_name': supplierName!.trim(),
      if ((supplierInvoiceNumber ?? '').trim().isNotEmpty)
        'supplier_invoice_number': supplierInvoiceNumber!.trim(),
      if ((supplierInvoiceDate ?? '').trim().isNotEmpty)
        'supplier_invoice_date': supplierInvoiceDate!.trim(),
      if ((generalManagerNotes ?? '').trim().isNotEmpty)
        'general_manager_notes': generalManagerNotes!.trim(),
      'items': items.map((item) => item.toJson()).toList(),
    });
  }

  Future<PurchaseInvoiceCommandResult> confirmReceipt({
    required String invoiceId,
    required int expectedRevision,
    required List<PurchaseReceiptInput> items,
    required String idempotencyKey,
    String? receiverNotes,
  }) => _command(
    '/v1/purchase-invoices/${Uri.encodeComponent(invoiceId)}/confirm-receipt',
    idempotencyKey,
    {
      'expected_revision': expectedRevision,
      'items': items.map((item) => item.toJson()).toList(),
      if ((receiverNotes ?? '').trim().isNotEmpty)
        'receiver_notes': receiverNotes!.trim(),
    },
  );

  Future<PurchaseInvoiceCommandResult> confirmPrices({
    required String invoiceId,
    required int expectedRevision,
    required List<PurchasePriceInput> items,
    required String idempotencyKey,
    String? pricingNotes,
  }) => _command(
    '/v1/purchase-invoices/${Uri.encodeComponent(invoiceId)}/confirm-prices',
    idempotencyKey,
    {
      'expected_revision': expectedRevision,
      'items': items.map((item) => item.toJson()).toList(),
      if ((pricingNotes ?? '').trim().isNotEmpty)
        'pricing_notes': pricingNotes!.trim(),
    },
  );

  Future<PurchaseInvoiceCommandResult> postAccounting({
    required String invoiceId,
    required int expectedRevision,
    required String accountingReference,
    required String idempotencyKey,
    String? accountantNotes,
    bool overrideUnresolvedMaterials = false,
    String? overrideReason,
  }) => _command(
    '/v1/purchase-invoices/${Uri.encodeComponent(invoiceId)}/post-accounting',
    idempotencyKey,
    {
      'expected_revision': expectedRevision,
      'accounting_reference': accountingReference.trim(),
      if ((accountantNotes ?? '').trim().isNotEmpty)
        'accountant_notes': accountantNotes!.trim(),
      'override_unresolved_materials': overrideUnresolvedMaterials,
      if (overrideUnresolvedMaterials)
        'override_reason': overrideReason?.trim() ?? '',
    },
  );

  Future<PurchaseInvoiceCommandResult> createAmendment({
    required String invoiceId,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
    String? supplierName,
    String? supplierInvoiceNumber,
    String? supplierInvoiceDate,
    String? generalManagerNotes,
    List<PurchaseAmendmentPriceInput>? priceItems,
  }) => _command(
    '/v1/purchase-invoices/${Uri.encodeComponent(invoiceId)}/amendments',
    idempotencyKey,
    {
      'expected_revision': expectedRevision,
      'reason': reason.trim(),
      if (supplierName != null) 'supplier_name': supplierName.trim(),
      if (supplierInvoiceNumber != null)
        'supplier_invoice_number': supplierInvoiceNumber.trim(),
      if (supplierInvoiceDate != null)
        'supplier_invoice_date': supplierInvoiceDate.trim(),
      if (generalManagerNotes != null)
        'general_manager_notes': generalManagerNotes.trim(),
      if (priceItems != null)
        'price_items': priceItems.map((item) => item.toJson()).toList(),
    },
  );

  Future<PurchaseInvoiceCommandResult> decideAmendment({
    required String invoiceId,
    required String amendmentId,
    required int expectedRevision,
    required String decision,
    required String idempotencyKey,
    String? reason,
  }) => _command(
    '/v1/purchase-invoices/${Uri.encodeComponent(invoiceId)}/amendments/'
    '${Uri.encodeComponent(amendmentId)}/decision',
    idempotencyKey,
    {
      'expected_revision': expectedRevision,
      'decision': decision,
      if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim(),
    },
  );

  Future<PurchaseInvoiceCommandResult> reviewTask({
    required String taskId,
    required int expectedRevision,
    required int expectedInvoiceRevision,
    required String action,
    required String idempotencyKey,
    String? productId,
    String? unitId,
    String? groupId,
    String? materialName,
    String? legacyCode,
    List<CatalogUnit>? units,
    String? primaryUnitId,
    String? accountingReference,
    String? syncState,
    String? note,
  }) => _command(
    '/v1/product-review-tasks/${Uri.encodeComponent(taskId)}/decide',
    idempotencyKey,
    {
      'expected_revision': expectedRevision,
      'expected_invoice_revision': expectedInvoiceRevision,
      'action': action,
      if ((productId ?? '').trim().isNotEmpty) 'product_id': productId!.trim(),
      if ((unitId ?? '').trim().isNotEmpty) 'unit_id': unitId!.trim(),
      if ((groupId ?? '').trim().isNotEmpty) 'group_id': groupId!.trim(),
      if ((materialName ?? '').trim().isNotEmpty)
        'material_name': materialName!.trim(),
      if ((legacyCode ?? '').trim().isNotEmpty)
        'legacy_code': legacyCode!.trim(),
      if (units != null)
        'units': units
            .map(
              (unit) => {
                'unit_id': unit.id,
                'display_value': unit.displayValue,
                'raw_value': unit.rawValue,
              },
            )
            .toList(),
      if ((primaryUnitId ?? '').trim().isNotEmpty)
        'primary_unit_id': primaryUnitId!.trim(),
      if ((accountingReference ?? '').trim().isNotEmpty)
        'accounting_reference': accountingReference!.trim(),
      if ((syncState ?? '').trim().isNotEmpty) 'sync_state': syncState!.trim(),
      if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
    },
  );

  Future<PurchaseInvoiceCommandResult> _command(
    String path,
    String idempotencyKey,
    Map<String, dynamic> body,
  ) async {
    if (!isConfigured) {
      throw const PurchaseInvoiceApiException(
        'configuration-error',
        'خدمة أوامر فواتير المشتريات غير مهيأة.',
      );
    }
    final key = idempotencyKey.trim();
    if (key.length < 8 ||
        key.length > 128 ||
        !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(key)) {
      throw ArgumentError('مفتاح منع التكرار غير صالح.');
    }
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const PurchaseInvoiceApiException(
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
              'idempotency-key': key,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const PurchaseInvoiceApiException(
        'network-error',
        'تعذر الاتصال بالخادم. تحقق من الشبكة وحاول مرة أخرى.',
      );
    }
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final rawError = decoded['error'];
      final error = rawError is Map
          ? Map<String, dynamic>.from(rawError)
          : const <String, dynamic>{};
      final code = error['code']?.toString() ?? 'request-failed';
      final exception = PurchaseInvoiceApiException(
        code,
        safeMessageForCode(code),
        httpStatus: response.statusCode,
        sanitizedBackendMessage: _sanitizeBackendMessage(error['message']),
        firstClientFrame: _firstClientFrame(StackTrace.current),
      );
      _debugCommandFailure(exception);
      throw exception;
    }
    final result = PurchaseInvoiceCommandResult.fromJson(decoded);
    if (result.invoiceId.isEmpty || result.revision < 1) {
      throw const PurchaseInvoiceApiException(
        'invalid-response',
        'تعذر التحقق من استجابة الخادم.',
      );
    }
    return result;
  }

  static String generateIdempotencyKey() {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  static String safeMessageForCode(String code) => switch (code) {
    'stale-revision' =>
      'تم تحديث السجل من مستخدم آخر. أعد فتحه ثم حاول مجددًا.',
    'invalid-state' => 'هذا الإجراء غير متاح في الحالة الحالية.',
    'unresolved-materials' =>
      'توجد مواد غير محلولة. عالجها أو استخدم الاستثناء المدقق مع سبب.',
    'duplicate-supplier-invoice' => 'توجد فاتورة بنفس اسم المورد ورقم فاتورته.',
    'catalog-duplicate' => 'توجد مادة مطابقة في الكتالوج.',
    'payload-too-large' => 'حجم الفاتورة أكبر من الحد الآمن المسموح.',
    'forbidden' => 'لا تملك صلاحية تنفيذ هذا الإجراء.',
    'unauthenticated' => 'انتهت جلسة الدخول. سجل الدخول مجددًا.',
    'invalid-argument' =>
      'بيانات فاتورة المشتريات غير صالحة. راجع الفرع والمادة والوحدة والسعر.',
    'duplicate-item' => 'لا يمكن تكرار المادة والوحدة نفسها في الفاتورة.',
    'branch-not-found' => 'الفرع المستلم غير متاح.',
    'branch-brand-missing' ||
    'branch-brand-invalid' => 'بيانات العلامة التجارية للفرع غير مكتملة.',
    'receiving-manager-not-configured' =>
      'لا يوجد مدير نشط ومُعيَّن للفرع المستلم.',
    'accountant-not-configured' =>
      'لا يوجد محاسب نشط لمراجعة المادة غير المطابقة.',
    'product-brand-mismatch' =>
      'المادة المختارة لا تتبع للعلامة التجارية الخاصة بالفرع.',
    'catalog-snapshot-invalid' =>
      'بيانات المادة أو المجموعة أو الوحدة المختارة لم تعد صالحة. أعد اختيارها.',
    'idempotency-conflict' =>
      'تم استخدام مفتاح الإرسال لطلب مختلف. أعد فتح الفاتورة وحاول مجددًا.',
    'active-amendment-exists' => 'يوجد طلب تعديل معلق لهذه الفاتورة.',
    'posted-invoice-amendment-blocked' =>
      'الفاتورة المرحلة لا تُعدّل مباشرة؛ أنشئ مستند تصحيح أو عكس محاسبي.',
    'duplicate-amendment-approval' =>
      'تم تسجيل موافقتك على طلب التعديل مسبقاً.',
    'amendment-rejection-reason-required' => 'سبب رفض طلب التعديل مطلوب.',
    'amendment-no-changes' => 'أدخل تغييراً واحداً على الأقل في طلب التعديل.',
    _ => 'تعذر إتمام العملية بأمان. حاول مجددًا أو تواصل مع الإدارة.',
  };

  static String _sanitizeBackendMessage(dynamic value) {
    final message = value?.toString().trim() ?? '';
    if (message.isEmpty) return '';
    final sanitized = message
        .replaceAll(
          RegExp(r'bearer\s+[^\s]+', caseSensitive: false),
          'Bearer [redacted]',
        )
        .replaceAll(
          RegExp(
            r'\b(secret|internal|token|password|authorization)\b[^,;]*',
            caseSensitive: false,
          ),
          '[redacted]',
        )
        .replaceAll(
          RegExp(
            r'(token|password|authorization)\s*[:=]\s*[^\s,;]+',
            caseSensitive: false,
          ),
          r'$1=[redacted]',
        )
        .replaceAll(RegExp(r'[\r\n]+'), ' ');
    return sanitized.substring(0, sanitized.length.clamp(0, 240));
  }

  static String _firstClientFrame(StackTrace trace) {
    final lines = trace.toString().split('\n');
    return lines.firstWhere(
      (line) => line.contains('purchase_invoice_api_service.dart'),
      orElse: () => lines.isEmpty ? '' : lines.first,
    );
  }

  static void _debugCommandFailure(PurchaseInvoiceApiException error) {
    if (!kDebugMode) return;
    debugPrint(
      'Purchase invoice command rejected: http=${error.httpStatus ?? '-'} '
      'code=${error.code} message=${error.sanitizedBackendMessage ?? ''} '
      'frame=${error.firstClientFrame ?? ''}',
    );
  }

  Map<String, dynamic> _decode(String source) {
    try {
      final value = jsonDecode(source);
      return value is Map<String, dynamic> ? value : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
