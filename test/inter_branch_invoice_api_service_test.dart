import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:store_collection_app/models/inter_branch_invoice_model.dart';
import 'package:store_collection_app/services/inter_branch_invoice_api_service.dart';

void main() {
  test('create command sends only stable price-free catalog inputs', () async {
    late http.Request captured;
    final service = InterBranchInvoiceApiService(
      baseUrl: 'https://api.example.test/',
      tokenProvider: () async => 'firebase-token',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'invoice_id': 'invoice-1',
            'invoice_number': 'AB0001',
            'status': 'pendingReceiverReview',
            'revision': 1,
          }),
          201,
        );
      }),
    );

    final result = await service.createDirectInvoice(
      receivingBranchId: 'receiver-1',
      idempotencyKey: 'create:invoice:1234',
      invoiceNotes: 'ملاحظة عامة',
      items: const [
        InterBranchInvoiceItem(
          productId: 'product-1',
          name: 'لا يجب إرسال هذا الاسم',
          unitId: 'unit_2',
          unit: 'علبة',
          requestedQuantity: 4.5,
          hasReceivedQuantity: false,
          lineNotes: 'سليم',
        ),
      ],
    );

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    final item = (body['items'] as List).single as Map<String, dynamic>;
    expect(captured.url.path, '/v1/inter-branch-invoices');
    expect(captured.headers['authorization'], 'Bearer firebase-token');
    expect(captured.headers['idempotency-key'], 'create:invoice:1234');
    expect(body['receiving_branch_id'], 'receiver-1');
    expect(item, {
      'product_id': 'product-1',
      'unit_id': 'unit_2',
      'supplied_quantity': 4.5,
      'line_notes': 'سليم',
    });
    expect(jsonEncode(body).contains('price'), isFalse);
    expect(jsonEncode(body).contains('لا يجب إرسال'), isFalse);
    expect(result.invoiceNumber, 'AB0001');
    expect(result.status, InterBranchInvoiceStatus.pendingReceiverReview);
  });

  test(
    'receipt command accepts zero received and sends revision once',
    () async {
      late Map<String, dynamic> body;
      final service = _service((request) {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return {
          'invoice_id': 'invoice-1',
          'status': 'pendingPriceEntry',
          'revision': 2,
        };
      });

      await service.confirmReceipt(
        invoiceId: 'invoice-1',
        expectedRevision: 1,
        idempotencyKey: 'receipt:invoice:1234',
        items: const [
          InterBranchInvoiceItem(
            itemId: 'line-1',
            name: 'منتج',
            unit: 'حبة',
            requestedQuantity: 5,
            receivedQuantity: 0,
            hasReceivedQuantity: true,
            missingQuantity: 5,
            discrepancyNotes: 'لم يصل',
          ),
        ],
      );

      expect(body['expected_revision'], 1);
      expect(body['items'], [
        {
          'item_id': 'line-1',
          'received_quantity': 0.0,
          'missing_quantity': 5.0,
          'discrepancy_notes': 'لم يصل',
        },
      ]);
    },
  );

  test(
    'rejects unknown success status as an invalid server response',
    () async {
      final service = _service(
        (_) => {
          'invoice_id': 'invoice-1',
          'status': 'futureUnrecognizedStatus',
          'revision': 2,
        },
      );

      await expectLater(
        service.postAccounting(
          invoiceId: 'invoice-1',
          expectedRevision: 1,
          accountingReference: 'ACC-1',
          idempotencyKey: 'posting:invoice:1234',
        ),
        throwsA(
          isA<InterBranchInvoiceApiException>().having(
            (error) => error.code,
            'code',
            'invalid-response',
          ),
        ),
      );
    },
  );

  test('pricing command sends prices only to the command route', () async {
    late http.Request captured;
    final service = InterBranchInvoiceApiService(
      baseUrl: 'https://api.example.test',
      tokenProvider: () async => 'firebase-token',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'invoice_id': 'invoice-1',
            'status': 'pendingAccountingEntry',
            'revision': 3,
          }),
          200,
        );
      }),
    );

    final result = await service.confirmPrices(
      invoiceId: 'invoice-1',
      expectedRevision: 2,
      currency: 'sar',
      idempotencyKey: 'pricing:invoice:1234',
      pricingNotes: 'تأكيد',
      items: const [
        InterBranchInvoicePriceInput(itemId: 'line-1', unitPrice: 12.5),
      ],
    );

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(
      captured.url.path,
      '/v1/inter-branch-invoices/invoice-1/confirm-prices',
    );
    expect(body, {
      'expected_revision': 2,
      'currency': 'SAR',
      'pricing_notes': 'تأكيد',
      'items': [
        {'item_id': 'line-1', 'unit_price': 12.5},
      ],
    });
    expect(result.invoiceNumber, isEmpty);
    expect(result.status, InterBranchInvoiceStatus.pendingAccountingEntry);
  });

  test('direct invoice line cap accepts 50 and rejects 51', () async {
    var requestCount = 0;
    final service = InterBranchInvoiceApiService(
      baseUrl: 'https://api.example.test',
      tokenProvider: () async => 'firebase-token',
      client: MockClient((_) async {
        requestCount++;
        return http.Response(
          jsonEncode({
            'invoice_id': 'invoice-limit',
            'invoice_number': 'AB0050',
            'status': 'pendingReceiverReview',
            'revision': 1,
          }),
          201,
        );
      }),
    );
    List<InterBranchInvoiceItem> items(int count) => List.generate(
      count,
      (index) => InterBranchInvoiceItem(
        productId: 'product-$index',
        name: 'منتج $index',
        unitId: 'unit_1',
        unit: 'حبة',
        requestedQuantity: 1,
        hasReceivedQuantity: false,
      ),
    );

    expect(InterBranchInvoiceApiService.maxItems, 50);
    await expectLater(
      service.createDirectInvoice(
        receivingBranchId: 'receiver-1',
        items: items(50),
        idempotencyKey: 'create:limit:50',
      ),
      completes,
    );
    await expectLater(
      service.createDirectInvoice(
        receivingBranchId: 'receiver-1',
        items: items(51),
        idempotencyKey: 'create:limit:51',
      ),
      throwsArgumentError,
    );
    expect(requestCount, 1);
  });

  test('secure idempotency keys are valid and non-repeating', () {
    final keys = List.generate(
      20,
      (_) => InterBranchInvoiceApiService.generateIdempotencyKey(),
    );
    expect(keys.toSet(), hasLength(keys.length));
    for (final key in keys) {
      expect(key.length, inInclusiveRange(8, 128));
      expect(RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(key), isTrue);
    }
  });
}

InterBranchInvoiceApiService _service(
  Map<String, dynamic> Function(http.Request request) response,
) => InterBranchInvoiceApiService(
  baseUrl: 'https://api.example.test',
  tokenProvider: () async => 'firebase-token',
  client: MockClient(
    (request) async => http.Response(jsonEncode(response(request)), 200),
  ),
);
