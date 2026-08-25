import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/consumable_request_model.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_catalog_picker.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_item_editor_dialog.dart';
import 'package:store_collection_app/utils/transaction_records.dart';
import 'package:store_collection_app/widgets/grouped_branch_overview.dart';

void main() {
  final records = [
    _record('V10', 20, DateTime(2026, 1, 3), DateTime(2026, 2, 1), 'YER'),
    _record('V2', 80, DateTime(2026, 1, 1), DateTime(2026, 2, 3), 'USD'),
    _record('V1', 50, DateTime(2026, 1, 2), DateTime(2026, 2, 2), 'YER'),
  ];

  for (final field in [
    TransactionSortField.createdAt,
    TransactionSortField.businessDate,
  ]) {
    test('$field ascending and descending', () {
      final ascending = _sort(
        records,
        field,
        TransactionSortDirection.ascending,
      );
      final descending = _sort(
        records,
        field,
        TransactionSortDirection.descending,
      );
      expect(ascending.reversed.toList(), descending);
    });
  }

  test('voucher number uses natural numeric order', () {
    expect(
      _sort(
        records,
        TransactionSortField.voucherNumber,
        TransactionSortDirection.ascending,
      ),
      ['V1', 'V2', 'V10'],
    );
  });

  test('amount sorting works with active filters', () {
    final result = filterAndSortTransactionRecords(
      records: records,
      dataOf: (item) => item,
      filters: const TransactionRecordFilters(currency: 'YER'),
      sort: const TransactionRecordSort(
        field: TransactionSortField.amount,
        direction: TransactionSortDirection.descending,
      ),
    );
    expect(result.map((item) => item['transaction_number']), ['V1', 'V10']);
  });

  test('collector/accountant group branches while manager stays scoped', () {
    expect(usesGroupedBranchOverview(UserRole.collector, null), isTrue);
    expect(usesGroupedBranchOverview(UserRole.accountant, ''), isTrue);
    expect(usesGroupedBranchOverview(UserRole.manager, null), isFalse);
    expect(usesGroupedBranchOverview(UserRole.collector, 'branch-1'), isFalse);
    expect(groupedBranchPreviewLimit, 5);
  });

  test('catalog group display resolves names and never falls back to IDs', () {
    const product = ProductCatalogModel(
      id: 'product-1',
      brandId: 'brand-1',
      groupId: 'group-internal-id',
      name: 'مادة',
      normalizedName: 'مادة',
      units: [CatalogUnit(id: 'u1', displayValue: 'حبة', rawValue: 'حبه')],
      primaryUnitId: 'u1',
      nameUniqueKeyId: 'key',
    );
    expect(
      catalogGroupDisplayName(product, const {
        'group-internal-id': 'مواد عامة',
      }),
      'مواد عامة',
    );
    expect(catalogGroupDisplayName(product, const {}), isNull);
  });

  testWidgets('grouped overview renders records after a successful query', (
    tester,
  ) async {
    await tester.pumpWidget(
      _groupedOverview(
        (kind, branchId) => Stream.value([
          GroupedBranchOverviewRecord(
            id: 'expense-1',
            data: {
              'request_number': 'EXP-1',
              'title': 'تشغيل',
              'status': 'pendingManagerApproval',
              'created_at': DateTime(2026, 8, 25),
            },
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('EXP-1'), findsOneWidget);
    expect(find.text('تعذر تحميل سجلات الفرع.'), findsNothing);
  });

  testWidgets(
    'grouped overview renders an empty state after a successful query',
    (tester) async {
      await tester.pumpWidget(
        _groupedOverview((kind, branchId) => Stream.value([])),
      );
      await tester.pumpAndSettle();
      expect(find.text('لا توجد سجلات لهذا الفرع بعد.'), findsOneWidget);
      expect(find.text('تعذر تحميل سجلات الفرع.'), findsNothing);
    },
  );

  testWidgets('grouped overview renders an error only when its query fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      _groupedOverview(
        (kind, branchId) => Stream<List<GroupedBranchOverviewRecord>>.error(
          StateError('query failed'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('تعذر تحميل سجلات الفرع.'), findsOneWidget);
    expect(find.text('لا توجد سجلات لهذا الفرع بعد.'), findsNothing);
  });

  test('new consumption item stores identity and snapshots', () {
    const item = ConsumableRequestItem(
      productId: 'product-1',
      productVersion: 3,
      productCode: '09-100',
      groupId: 'group-1',
      name: 'كحيلان',
      unitId: 'unit-2',
      unit: 'علبة',
      rawUnit: 'علبه',
      requestedQuantity: 2,
    );
    expect(item.toMap(), containsPair('product_id', 'product-1'));
    expect(item.toMap(), containsPair('unit_id', 'unit-2'));
    expect(ConsumableRequestItem.fromMap(item.toMap()).name, 'كحيلان');
  });

  test('legacy free-text consumption item still renders', () {
    final item = ConsumableRequestItem.fromMap({
      'name': 'مادة تاريخية',
      'unit': 'حبة',
      'requested_quantity': 4,
    });
    expect(item.productId, isNull);
    expect(item.name, 'مادة تاريخية');
  });

  for (final mode in CatalogPickerMode.values) {
    testWidgets('${mode.name} uses shared picker core', (tester) async {
      await tester.pumpWidget(_PickerHarness(mode: mode));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('shared-catalog-picker-${mode.name}')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('shared-catalog-search')), findsOneWidget);
    });

    testWidgets(
      '${mode.name} uses readable selected and unselected unit chips',
      (tester) async {
        await tester.pumpWidget(_PickerHarness(mode: mode));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('shared-catalog-product-p1')));
        await tester.pumpAndSettle();

        final selected = tester.widget<ChoiceChip>(
          find.byKey(const Key('shared-catalog-unit-p1-u1')),
        );
        final unselected = tester.widget<ChoiceChip>(
          find.byKey(const Key('shared-catalog-unit-p1-u2')),
        );
        expect(selected.selected, isTrue);
        expect(unselected.selected, isFalse);
        expect(selected.labelStyle?.color, isNotNull);
        expect(unselected.labelStyle?.color, isNotNull);
        expect(selected.backgroundColor, isNotNull);
        expect(unselected.backgroundColor, isNotNull);
      },
    );
  }

  for (final mode in [
    CatalogPickerMode.consumption,
    CatalogPickerMode.transfer,
  ]) {
    testWidgets('${mode.name} editor exposes valid units without price', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PurchaseItemEditorDialog.catalog(
            productName: 'مادة',
            unitValue: 'حبة',
            catalogUnits: [
              CatalogUnit(id: 'u1', displayValue: 'حبة', rawValue: 'حبه'),
              CatalogUnit(id: 'u2', displayValue: 'علبة', rawValue: 'علبه'),
            ],
            initialCatalogUnitId: 'u1',
            showPricing: false,
          ),
        ),
      );
      expect(
        find.byKey(const Key('purchase-item-catalog-unit')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('purchase-item-provisional-price')),
        findsNothing,
      );
    });
  }
}

Map<String, dynamic> _record(
  String number,
  double amount,
  DateTime created,
  DateTime business,
  String currency,
) => {
  'transaction_number': number,
  'amount': amount,
  'timestamp': created,
  'transaction_date': business,
  'currency': currency,
  'status': 'pending',
  'dateFrom': business,
  'dateTo': business,
};

List<String> _sort(
  List<Map<String, dynamic>> records,
  TransactionSortField field,
  TransactionSortDirection direction,
) => filterAndSortTransactionRecords(
  records: records,
  dataOf: (item) => item,
  filters: const TransactionRecordFilters(),
  sort: TransactionRecordSort(field: field, direction: direction),
).map((item) => item['transaction_number'] as String).toList();

class _PickerHarness extends StatelessWidget {
  final CatalogPickerMode mode;
  const _PickerHarness({required this.mode});

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () => showCatalogPicker(
          context,
          brandId: 'brand-1',
          mode: mode,
          products: const [
            ProductCatalogModel(
              id: 'p1',
              brandId: 'brand-1',
              groupId: 'g1',
              name: 'كحيلان',
              normalizedName: 'كحيلان',
              units: [
                CatalogUnit(id: 'u1', displayValue: 'حبة', rawValue: 'حبه'),
                CatalogUnit(id: 'u2', displayValue: 'علبة', rawValue: 'علبه'),
              ],
              primaryUnitId: 'u1',
              nameUniqueKeyId: 'key',
            ),
          ],
        ),
        child: const Text('open'),
      ),
    ),
  );
}

Widget _groupedOverview(GroupedBranchRecordsStream recordsStream) =>
    MaterialApp(
      home: GroupedBranchOverview(
        role: UserRole.collector,
        kind: GroupedBranchOverviewKind.expenses,
        onViewAll: (_, _, _) {},
        branchStream: Stream.value(const [
          GroupedBranchOverviewBranch(id: 'branch-1', name: 'فرع الاختبار'),
        ]),
        recordsStream: recordsStream,
      ),
    );
