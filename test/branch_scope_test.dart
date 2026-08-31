import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/screens/purchase_invoices/new_purchase_invoice_screen.dart';
import 'package:store_collection_app/utils/branch_scope.dart';

void main() {
  const mainBranch = {
    'branch_type': 'main',
    'active': true,
    'brand_id': 'brand-1',
  };
  const normalBranch = {'active': true, 'brand_id': 'brand-1'};

  test('Main Branch is transfer-only, not operational or assignable', () {
    expect(isTransferOnlyMainBranch(mainBranch), isTrue);
    expect(isActiveOperationalBranch(mainBranch), isFalse);
    expect(isEligiblePurchaseReceivingBranch(mainBranch), isFalse);
    expect(canAssignUserToBranch(mainBranch), isFalse);
  });

  test('active normal branches remain operational and assignable', () {
    expect(isTransferOnlyMainBranch(normalBranch), isFalse);
    expect(isActiveOperationalBranch(normalBranch), isTrue);
    expect(isEligiblePurchaseReceivingBranch(normalBranch), isTrue);
    expect(canAssignUserToBranch(normalBranch), isTrue);
  });

  test('inactive normal branch remains unavailable for Purchase', () {
    expect(
      isEligiblePurchaseReceivingBranch(const {
        'active': false,
        'brand_id': 'brand-1',
      }),
      isFalse,
    );
  });
}
