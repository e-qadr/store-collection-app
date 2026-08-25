import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/screens/inter_branch_invoices/inter_branch_invoices_dashboard.dart';
import 'package:store_collection_app/screens/products/product_catalog_management_screen.dart';
import 'package:store_collection_app/utils/material_management_access.dart';

void main() {
  group('Material Management role visibility', () {
    test('collector and accountant see Material Management', () {
      expect(MaterialManagementAccess.canAccess(UserRole.collector), isTrue);
      expect(MaterialManagementAccess.canAccess(UserRole.accountant), isTrue);
    });

    test('manager, ordinary employee, and unknown roles do not see it', () {
      expect(MaterialManagementAccess.canAccess(UserRole.manager), isFalse);
      expect(MaterialManagementAccess.canAccess(UserRole.admin), isFalse);
      expect(
        MaterialManagementAccess.canAccess(null, hasKnownRole: false),
        isFalse,
      );
    });

    for (final role in [UserRole.manager, UserRole.admin]) {
      testWidgets('${role.name} cannot directly open Material Management', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(home: ProductCatalogManagementScreen(role: role)),
        );

        expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      });
    }

    testWidgets('unknown role cannot directly open Material Management', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ProductCatalogManagementScreen(role: null, hasKnownRole: false),
        ),
      );

      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    });
  });

  test('inter-branch invoice dashboard remains available', () {
    const dashboard = InterBranchInvoicesDashboard(
      role: UserRole.collector,
      branchName: 'All branches',
    );
    expect(dashboard, isA<InterBranchInvoicesDashboard>());
  });
}
