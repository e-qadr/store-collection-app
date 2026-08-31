import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/inter_branch_invoice_model.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/models/product_price_model.dart';
import 'package:store_collection_app/screens/inter_branch_invoices/inter_branch_invoice_details_screen.dart';
import 'package:store_collection_app/screens/inter_branch_invoices/inter_branch_invoices_dashboard.dart';
import 'package:store_collection_app/screens/inter_branch_invoices/new_inter_branch_invoice_screen.dart';
import 'package:store_collection_app/services/inter_branch_invoice_api_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestWidgetsFlutterBinding
            .instance
            .platformDispatcher
            .textScaleFactorTestValue =
        1;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearTextScaleFactorTestValue();
  });

  testWidgets('1. المدير المورد ينشئ فاتورة تحويل مباشرة', (tester) async {
    InterBranchInvoiceCommandResult? submitted;
    await _pumpCreation(
      tester,
      initialItems: [_commandItem(0)],
      submitter:
          ({
            required receivingBranchId,
            required items,
            required idempotencyKey,
            invoiceNotes,
          }) async {
            expect(receivingBranchId, 'branch-b');
            expect(items, hasLength(1));
            submitted = _commandResult();
            return submitted!;
          },
    );

    await _chooseReceivingBranch(tester);
    await tester.tap(find.text('إنشاء وإرسال للمراجعة'));
    await tester.pumpAndSettle();

    expect(submitted?.invoiceNumber, 'AA0051');
    expect(tester.takeException(), isNull);
  });

  testWidgets('1b. قائمة الوجهة تميّز الفرع الرئيسي للعلامة نفسها', (
    tester,
  ) async {
    await _pumpCreation(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();

    expect(find.text('الفرع الرئيسي — الفرع الرئيسي للعلامة'), findsOneWidget);
    expect(find.text('الفرع المستلم 1'), findsOneWidget);
  });

  testWidgets('2. البحث في المنتجات واختيار الوحدة يعملان باتجاه RTL', (
    tester,
  ) async {
    await _pumpCreation(
      tester,
      products: [_product(1, 'تفاح أحمر'), _product(2, 'أرز فاخر')],
    );

    expect(
      Directionality.of(tester.element(find.byType(Scaffold).first)),
      TextDirection.rtl,
    );
    await tester.tap(find.byKey(const Key('transfer-add-catalog-item')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shared-catalog-search')), findsOneWidget);
    expect(find.text('أرز فاخر'), findsOneWidget);
    expect(find.text('تفاح أحمر'), findsOneWidget);
    await tester.tap(find.text('أرز فاخر'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('shared-catalog-unit-product-2-unit_2')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('purchase-item-quantity')),
      '3',
    );
    await tester.tap(find.byKey(const Key('confirm-purchase-item')));
    await tester.pumpAndSettle();

    expect(find.text('أرز فاخر'), findsOneWidget);
    expect(find.textContaining('3 علبة'), findsOneWidget);
  });

  testWidgets('3. حد الخمسين سطرًا ظاهر ومطبق', (tester) async {
    await _pumpCreation(tester, initialItems: List.generate(50, _commandItem));

    expect(find.text('سطور الفاتورة (50/50)'), findsOneWidget);
    await tester.ensureVisible(find.text('إضافة مادة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة مادة'));
    await tester.pump();
    expect(find.textContaining('الحد الأقصى 50'), findsOneWidget);
  });

  testWidgets('4. المدير المستلم يؤكد الكميات والفروقات', (tester) async {
    List<InterBranchInvoiceItem>? submittedItems;
    await _pumpDetails(
      tester,
      role: UserRole.manager,
      branchId: 'branch-b',
      header: _v2Header(status: 'pendingReceiverReview', revision: 1),
      directReceiptSubmitter:
          ({
            required invoiceId,
            required expectedRevision,
            required items,
            required idempotencyKey,
            receiverNotes,
          }) async {
            submittedItems = items;
          },
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'تأكيد الاستلام'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'المستلم'), '4');
    await tester.enterText(find.widgetWithText(TextField, 'التالف'), '1');
    await tester.enterText(find.widgetWithText(TextField, 'الناقص'), '1');
    await tester.enterText(
      find.widgetWithText(TextField, 'ملاحظة الفرق (اختياري)'),
      'علبة تالفة',
    );
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(submittedItems, hasLength(1));
    expect(submittedItems!.single.receivedQuantity, 4);
    expect(submittedItems!.single.damagedQuantity, 1);
    expect(submittedItems!.single.missingQuantity, 1);
    expect(submittedItems!.single.discrepancyNotes, 'علبة تالفة');
  });

  testWidgets('5. المدير العام يرى اقتراح السعر ويؤكده صراحة', (tester) async {
    List<InterBranchInvoicePriceInput>? submittedPrices;
    await _pumpDetails(
      tester,
      role: UserRole.collector,
      header: _v2Header(status: 'pendingPriceEntry', revision: 2),
      item: _v2Item(receivedQuantity: 5),
      latestProductPriceLoader:
          ({
            required brandId,
            required productId,
            required unitId,
            required currency,
          }) async => ProductPriceLatest(
            id: 'latest-1',
            latestKey: 'latest-1',
            historyEventId: 'history-1',
            brandId: brandId,
            productId: productId,
            unitId: unitId,
            unitValue: 'علبة',
            currency: currency,
            price: 12.5,
            sourceInvoiceId: 'INV-OLD',
            changedBy: 'collector',
            changedByName: 'المدير العام',
            changedByRole: 'collector',
            version: 3,
            changedAt: DateTime(2026, 7, 1),
          ),
      directPriceSubmitter:
          ({
            required invoiceId,
            required expectedRevision,
            required currency,
            required items,
            required idempotencyKey,
            pricingNotes,
          }) async {
            expect(currency, 'SAR');
            submittedPrices = items;
          },
    );

    await tester.tap(find.text('إدخال الأسعار'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAR'));
    await tester.pumpAndSettle();
    expect(find.textContaining('اقتراح من فاتورة INV-OLD'), findsOneWidget);
    expect(find.textContaining('اقتراحات فقط'), findsOneWidget);
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(submittedPrices, hasLength(1));
    expect(submittedPrices!.single.unitPrice, 12.5);
  });

  testWidgets('6. مدير الفرع لا يرى قيم الأسعار أو أدواتها', (tester) async {
    var protectedLoaderCalled = false;
    await _pumpDetails(
      tester,
      role: UserRole.manager,
      branchId: 'branch-b',
      header: _v2Header(status: 'pendingPriceEntry', revision: 2),
      item: _v2Item(receivedQuantity: 5),
      protectedPriceSnapshotLoader: (_) async {
        protectedLoaderCalled = true;
        return null;
      },
    );

    expect(protectedLoaderCalled, isFalse);
    expect(find.text('إدخال الأسعار'), findsNothing);
    expect(find.textContaining('سعر الوحدة'), findsNothing);
    expect(find.textContaining('إجمالي سعر الفاتورة'), findsNothing);
  });

  testWidgets('7. المحاسب يرحل الفاتورة بمرجع محاسبي', (tester) async {
    String? submittedReference;
    await _pumpDetails(
      tester,
      role: UserRole.accountant,
      header: _v2Header(status: 'pendingAccountingEntry', revision: 3),
      item: _v2Item(receivedQuantity: 5),
      directAccountingSubmitter:
          ({
            required invoiceId,
            required expectedRevision,
            required accountingReference,
            required idempotencyKey,
            accountingNotes,
          }) async {
            submittedReference = accountingReference;
          },
    );

    await tester.tap(find.text('ترحيل محاسبي'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'رقم الفاتورة في النظام المحاسبي'),
      'ACC-2026-51',
    );
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(submittedReference, 'ACC-2026-51');
  });

  testWidgets('8. أخطاء API تظهر بنص عربي آمن', (tester) async {
    final codes = <String>[
      'invalid-state',
      'unauthenticated',
      'stale-revision',
      'counter-uninitialized',
    ];
    var attempt = 0;
    await _pumpCreation(
      tester,
      initialItems: [_commandItem(0)],
      submitter:
          ({
            required receivingBranchId,
            required items,
            required idempotencyKey,
            invoiceNotes,
          }) async {
            final code = codes[attempt++];
            throw InterBranchInvoiceApiException(
              code,
              InterBranchInvoiceApiService.safeMessageForCode(code),
            );
          },
    );
    await _chooseReceivingBranch(tester);

    for (final code in codes) {
      await tester.tap(find.text('إنشاء وإرسال للمراجعة'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.text(InterBranchInvoiceApiService.safeMessageForCode(code)),
        findsOneWidget,
      );
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold)),
      ).hideCurrentSnackBar();
      await tester.pumpAndSettle();
    }
    expect(attempt, 4);
  });

  testWidgets('9. تفاصيل وإجراءات الإصدار الأول تبقى متاحة', (tester) async {
    bool? supplierApproved;
    await _pumpDetails(
      tester,
      role: UserRole.manager,
      branchId: 'branch-a',
      header: _legacyHeader(),
      legacySupplierDecisionSubmitter:
          ({
            required invoiceId,
            required approved,
            required approvedItems,
            required notes,
          }) async {
            supplierApproved = approved;
          },
    );

    expect(find.text('طلب الفاتورة'), findsWidgets);
    expect(find.text('تكوين الفاتورة'), findsOneWidget);
    expect(find.text('رفض'), findsOneWidget);
    await tester.tap(find.text('تكوين الفاتورة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(supplierApproved, isTrue);
  });

  testWidgets('10. لوحة v2 تميز الوارد من الصادر للمدير', (tester) async {
    final incoming = InterBranchInvoiceRead(
      id: 'incoming',
      data: _v2Header(
        id: 'incoming',
        sendingBranchId: 'branch-b',
        receivingBranchId: 'branch-a',
      ),
    );
    final outgoing = InterBranchInvoiceRead(
      id: 'outgoing',
      data: _v2Header(
        id: 'outgoing',
        sendingBranchId: 'branch-a',
        receivingBranchId: 'branch-b',
      ),
    );
    await _pumpApp(
      tester,
      InterBranchInvoicesDashboard(
        role: UserRole.manager,
        branchId: 'branch-a',
        branchName: 'فرع أ',
        invoiceStream: _valueStream([incoming, outgoing]),
        showAppBarActions: false,
      ),
    );

    expect(find.text('الوارد إلى فرعي'), findsOneWidget);
    expect(find.text('فواتير فرعي الصادرة'), findsOneWidget);
    expect(find.textContaining('بصفته المورد'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(Scaffold).first)),
      TextDirection.rtl,
    );
  });
}

Future<void> _pumpCreation(
  WidgetTester tester, {
  List<ProductCatalogModel>? products,
  List<InterBranchInvoiceItem> initialItems = const [],
  DirectInvoiceSubmitter? submitter,
}) {
  return _pumpApp(
    tester,
    NewInterBranchInvoiceScreen(
      branchId: 'branch-a',
      branchName: 'الفرع المورد',
      fixture: DirectInvoiceCreationFixture(
        brandId: 'brand-a',
        branches: const [
          DirectInvoiceBranchOption(
            id: 'main-a',
            name: 'الفرع الرئيسي للعلامة',
            isMainBranch: true,
          ),
          DirectInvoiceBranchOption(id: 'branch-b', name: 'الفرع المستلم 1'),
        ],
        products: products ?? [_product(1, 'أرز فاخر')],
        initialItems: initialItems,
      ),
      submitter: submitter,
    ),
  );
}

Future<void> _pumpDetails(
  WidgetTester tester, {
  required UserRole role,
  required Map<String, dynamic> header,
  String? branchId,
  Map<String, dynamic>? item,
  ProtectedPriceSnapshotLoader? protectedPriceSnapshotLoader,
  LatestProductPriceLoader? latestProductPriceLoader,
  DirectReceiptSubmitter? directReceiptSubmitter,
  DirectPriceSubmitter? directPriceSubmitter,
  DirectAccountingSubmitter? directAccountingSubmitter,
  LegacySupplierDecisionSubmitter? legacySupplierDecisionSubmitter,
}) {
  return _pumpApp(
    tester,
    InterBranchInvoiceDetailsScreen(
      invoiceId: header['id']?.toString() ?? 'invoice-1',
      role: role,
      branchId: branchId,
      branchName: 'فرع الاختبار',
      invoiceDataStream: _valueStream(header),
      itemDataStream: _valueStream([item ?? _v2Item()]),
      protectedPriceSnapshotLoader:
          protectedPriceSnapshotLoader ?? (_) async => null,
      latestProductPriceLoader: latestProductPriceLoader,
      directReceiptSubmitter: directReceiptSubmitter,
      directPriceSubmitter: directPriceSubmitter,
      directAccountingSubmitter: directAccountingSubmitter,
      legacySupplierDecisionSubmitter: legacySupplierDecisionSubmitter,
    ),
  );
}

Future<void> _pumpApp(WidgetTester tester, Widget home) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1600));
  await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: home));
  await tester.pumpAndSettle();
}

Future<void> _chooseReceivingBranch(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('الفرع المستلم 1').last);
  await tester.pumpAndSettle();
}

Stream<T> _valueStream<T>(T value) => Stream<T>.multi((controller) {
  controller.add(value);
  controller.close();
}, isBroadcast: true);

ProductCatalogModel _product(int index, String name) => ProductCatalogModel(
  id: 'product-$index',
  brandId: 'brand-a',
  groupId: 'group-a',
  name: name,
  normalizedName: name,
  units: const [
    CatalogUnit(id: 'unit_1', displayValue: 'حبة', rawValue: 'حبه'),
    CatalogUnit(id: 'unit_2', displayValue: 'علبة', rawValue: 'علبة'),
  ],
  primaryUnitId: 'unit_1',
  nameUniqueKeyId: 'name-$index',
);

InterBranchInvoiceItem _commandItem(int index) => InterBranchInvoiceItem(
  itemId: 'line-${index + 1}',
  productId: 'product-${index + 1}',
  productVersion: 1,
  name: 'منتج ${index + 1}',
  groupId: 'group-a',
  unitId: 'unit_1',
  unit: 'حبة',
  rawUnit: 'حبه',
  requestedQuantity: 1,
  hasReceivedQuantity: false,
);

InterBranchInvoiceCommandResult _commandResult() =>
    const InterBranchInvoiceCommandResult(
      invoiceId: 'invoice-51',
      invoiceNumber: 'AA0051',
      status: InterBranchInvoiceStatus.pendingReceiverReview,
      revision: 1,
      idempotentReplay: false,
    );

Map<String, dynamic> _v2Header({
  String id = 'invoice-1',
  String status = 'pendingReceiverReview',
  int revision = 1,
  String sendingBranchId = 'branch-a',
  String receivingBranchId = 'branch-b',
}) => <String, dynamic>{
  'id': id,
  'schema_version': 2,
  'workflow_version': 2,
  'creation_mode': 'direct_supplier_invoice',
  'status': status,
  'revision': revision,
  'invoice_number': 'AA0051',
  'branch_code': 'AA',
  'sending_branch_id': sendingBranchId,
  'sending_branch_name': 'الفرع المورد',
  'sending_brand_id': 'brand-a',
  'receiving_branch_id': receivingBranchId,
  'receiving_branch_name': 'الفرع المستلم',
  'receiving_brand_id': 'brand-b',
  'branch_ids': [sendingBranchId, receivingBranchId],
  'item_count': 1,
  'item_digest': List.filled(64, 'a').join(),
  'created_by': 'manager-a',
  'created_by_name': 'مدير المورد',
  'created_by_role': 'manager',
  'created_at': DateTime(2026, 8, 3),
  'last_updated': DateTime(2026, 8, 3),
  'history': const <Map<String, dynamic>>[],
};

Map<String, dynamic> _v2Item({double? receivedQuantity}) => <String, dynamic>{
  'id': 'line-1',
  'invoice_id': 'invoice-1',
  'schema_version': 2,
  'workflow_version': 2,
  'creation_mode': 'direct_supplier_invoice',
  'invoice_revision': receivedQuantity == null ? 1 : 2,
  'branch_ids': const ['branch-a', 'branch-b'],
  'sending_branch_id': 'branch-a',
  'receiving_branch_id': 'branch-b',
  'line_number': 1,
  'item_id': 'line-1',
  'product_id': 'product-1',
  'product_version': 1,
  'product_brand_id': 'brand-a',
  'product_name': 'أرز فاخر',
  'group_id': 'group-a',
  'group_name': 'مواد غذائية',
  'unit_id': 'unit_2',
  'unit_value': 'علبة',
  'unit_raw_value': 'علبة',
  'supplied_quantity': 5,
  if (receivedQuantity != null) 'received_quantity': receivedQuantity,
  if (receivedQuantity != null) 'damaged_quantity': 0,
  if (receivedQuantity != null) 'missing_quantity': 0,
};

Map<String, dynamic> _legacyHeader() => <String, dynamic>{
  'id': 'legacy-1',
  'status': 'requestPending',
  'sending_branch_id': 'branch-a',
  'sending_branch_name': 'الفرع المورد',
  'receiving_branch_id': 'branch-b',
  'receiving_branch_name': 'الفرع المستلم',
  'branch_ids': const ['branch-a', 'branch-b'],
  'items': const [
    {
      'item_name': 'صنف قديم',
      'unit': 'حبة',
      'requested_quantity': 2,
      'approved_quantity': 2,
    },
  ],
  'created_by': 'manager-b',
  'created_at': DateTime(2025, 1, 1),
  'last_updated': DateTime(2025, 1, 1),
  'history': const <Map<String, dynamic>>[],
};
