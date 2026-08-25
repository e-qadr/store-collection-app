import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:store_collection_app/services/purchase_invoice_api_service.dart';

void main() {
  test(
    'creation uses the separate purchase command and keeps provisional price protected in transit',
    () async {
      late http.Request captured;
      final service = PurchaseInvoiceApiService(
        baseUrl: 'https://api.example.test',
        tokenProvider: () async => 'id-token',
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'invoice_id': 'purchase-1',
              'purchase_number': 'PUR-1',
              'status': 'pendingReceiverReview',
              'revision': 1,
            }),
            201,
          );
        }),
      );
      final result = await service.createInvoice(
        receivingBranchId: 'branch-r',
        currency: 'YER',
        idempotencyKey: 'purchase-request-1',
        items: const [
          PurchaseInvoiceCreateItem.unmatched(
            materialName: 'مادة',
            groupText: '',
            unitText: 'حبة',
            orderedQuantity: 2,
            provisionalUnitPrice: 7,
            lineNotes: 'line note',
          ),
        ],
      );
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(captured.url.path, '/v1/purchase-invoices');
      expect(captured.headers['authorization'], 'Bearer id-token');
      expect(body['items'][0]['provisional_unit_price'], 7);
      expect(body['items'][0]['line_notes'], 'line note');
      expect(result.invoiceId, 'purchase-1');
    },
  );

  test(
    'backend messages are never surfaced and unresolved posting gets localized text',
    () async {
      final service = PurchaseInvoiceApiService(
        baseUrl: 'https://api.example.test',
        tokenProvider: () async => 'id-token',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'unresolved-materials',
                'message': 'SECRET INTERNAL PRICE 12345',
              },
            }),
            409,
          ),
        ),
      );
      await expectLater(
        service.postAccounting(
          invoiceId: 'purchase-1',
          expectedRevision: 3,
          accountingReference: 'ACC-1',
          idempotencyKey: 'purchase-post-1',
        ),
        throwsA(
          isA<PurchaseInvoiceApiException>()
              .having((error) => error.code, 'code', 'unresolved-materials')
              .having(
                (error) => error.message,
                'message',
                isNot(contains('12345')),
              ),
        ),
      );
    },
  );
}
