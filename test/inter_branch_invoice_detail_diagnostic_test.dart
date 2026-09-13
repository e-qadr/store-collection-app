import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/inter_branch_invoice_detail_diagnostic.dart';
import 'package:store_collection_app/models/inter_branch_invoice_model.dart';

void main() {
  InterBranchInvoiceRead invoice({
    String sending = 'branch-source',
    String receiving = 'branch-receiver',
  }) => InterBranchInvoiceRead(
    id: 'transfer-123',
    data: {
      'invoice_number': 'TR001',
      'sending_branch_id': sending,
      'receiving_branch_id': receiving,
      'branch_ids': [sending, receiving],
    },
  );

  InterBranchInvoiceDetailDiagnostic diagnostic({
    String branchId = 'branch-source',
    InterBranchInvoiceRead? cachedInvoice,
  }) => InterBranchInvoiceDetailDiagnostic.forPermissionFailure(
    firebaseUid: 'uid-safe',
    role: UserRole.manager,
    branchId: branchId,
    branchName: 'Tarim',
    firebaseProjectId: 'store-collection-app',
    invoiceId: 'transfer-123',
    errorCode: 'permission-denied',
    cachedInvoice: cachedInvoice ?? invoice(),
  );

  test('permission diagnostic is an allow-listed, token-free payload', () {
    final values = diagnostic().toSafeDisplayMap();
    expect(values.values.join(' '), isNot(contains('token')));
    expect(values.keys.join(' '), isNot(contains('token')));
    expect(values['معرّف المستخدم'], 'uid-safe');
    expect(values['معرّف الفرع الفعّال'], 'branch-source');
    expect(values['معرّف المستند'], 'transfer-123');
    expect(values['المسار المقروء'], 'inter_branch_invoices/transfer-123');
    expect(values['رمز الخطأ'], 'permission-denied');
    expect(values['معرّف التطبيق'], 'com.storecollection.store_collection_app');
  });

  test(
    'participant diagnostic distinguishes source, receiver, unrelated and unknown',
    () {
      expect(diagnostic().participantClassification, 'SOURCE_PARTICIPANT');
      expect(
        diagnostic(branchId: 'branch-receiver').participantClassification,
        'RECEIVING_PARTICIPANT',
      );
      expect(
        diagnostic(branchId: 'branch-other').participantClassification,
        'UNRELATED',
      );
      expect(
        InterBranchInvoiceDetailDiagnostic.forPermissionFailure(
          firebaseUid: 'uid-safe',
          role: UserRole.manager,
          branchId: '',
          branchName: 'Tarim',
          firebaseProjectId: 'store-collection-app',
          invoiceId: 'transfer-123',
          errorCode: 'permission-denied',
        ).participantClassification,
        'UNKNOWN',
      );
    },
  );

  test('diagnostic exposes only cached public participation fields', () {
    final values = diagnostic().toSafeDisplayMap();
    expect(values['فرع الإرسال'], 'branch-source');
    expect(values['فرع الاستلام'], 'branch-receiver');
    expect(values['معرّفات الفروع'], 'branch-source, branch-receiver');
    expect(values.keys.join(' '), isNot(contains('السعر')));
    expect(values.keys.join(' '), isNot(contains('الإجمالي')));
  });

  test(
    'diagnostic never exposes protected price data from a cached header',
    () {
      final cachedInvoice = InterBranchInvoiceRead(
        id: 'transfer-123',
        data: {
          'invoice_number': 'TR001',
          'sending_branch_id': 'branch-source',
          'receiving_branch_id': 'branch-receiver',
          'branch_ids': ['branch-source', 'branch-receiver'],
          'unit_price': 987.65,
          'total': 987.65,
        },
      );

      final payload = diagnostic(
        cachedInvoice: cachedInvoice,
      ).toSafeDisplayMap().values.join(' ');

      expect(payload, isNot(contains('987.65')));
      expect(payload, isNot(contains('unit_price')));
      expect(payload, isNot(contains('total')));
    },
  );
}
