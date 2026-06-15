import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/services/pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ينشئ ملف سند PDF منظم', () async {
    final bytes = await PdfService.buildSingleTransaction(
      branchName: 'الفرع الرئيسي',
      data: {
        'transaction_number': 'AM005',
        'amount': 1500,
        'currency': 'YER',
        'status': 'approvedByAccountant',
        'timestamp': DateTime(2026, 6, 15, 10, 30),
        'dateFrom': DateTime(2026, 6, 1),
        'dateTo': DateTime(2026, 6, 15),
        'amount_matches': false,
        'cashier_amount': 1490,
        'notes': 'ملاحظة تجريبية',
        'manager_notes': 'تمت المراجعة',
        'history': [
          {
            'action': 'created',
            'actor_name': 'محمد',
            'actor_role': 'collector',
            'message': 'تم إنشاء السند',
            'timestamp': DateTime(2026, 6, 15, 10, 30),
          },
        ],
      },
    );

    expect(bytes.length, greaterThan(1000));
  });

  test('ينشئ تقرير PDF منظم مع أكثر من عملة', () async {
    final bytes = await PdfService.buildTransactionsReportFromData(
      branchName: 'الفرع الرئيسي',
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2026, 6, 30),
      records: [
        {
          'transaction_number': 'AM005',
          'amount': 1500,
          'currency': 'YER',
          'status': 'approvedByAccountant',
          'timestamp': DateTime(2026, 6, 15, 10, 30),
          'dateFrom': DateTime(2026, 6, 1),
          'dateTo': DateTime(2026, 6, 15),
          'amount_matches': true,
          'notes': '',
        },
        {
          'transaction_number': 'AM006',
          'amount': 50,
          'currency': 'USD',
          'status': 'pending',
          'timestamp': DateTime(2026, 6, 16, 11),
          'dateFrom': DateTime(2026, 6, 16),
          'dateTo': DateTime(2026, 6, 16),
          'amount_matches': false,
          'notes': 'مراجعة',
        },
      ],
    );

    expect(bytes.length, greaterThan(1000));
  });
}
