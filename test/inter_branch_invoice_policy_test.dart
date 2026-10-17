import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/inter_branch_invoice_model.dart';
import 'package:store_collection_app/utils/inter_branch_invoice_policies.dart';

void main() {
  group('direct inter-branch authorization policy', () {
    test(
      'only a branch manager with a source branch can create a transfer',
      () {
        expect(
          InterBranchInvoicePolicy.canCreateInterBranchTransfer(
            role: UserRole.manager,
            branchId: 'branch-a',
          ),
          isTrue,
        );
        for (final role in const [
          UserRole.collector,
          UserRole.accountant,
          UserRole.admin,
        ]) {
          expect(
            InterBranchInvoicePolicy.canCreateInterBranchTransfer(
              role: role,
              branchId: 'branch-a',
            ),
            isFalse,
          );
        }
        expect(
          InterBranchInvoicePolicy.canCreateInterBranchTransfer(
            role: UserRole.manager,
            branchId: null,
          ),
          isFalse,
        );
      },
    );

    test('only the receiving manager can confirm receipt', () {
      final invoice = _invoice(
        status: InterBranchInvoiceStatus.pendingReceiverReview,
      );

      expect(
        InterBranchInvoicePolicy.actionsFor(
          role: UserRole.manager,
          branchId: 'receiver',
          invoice: invoice,
        ),
        contains(InterBranchInvoiceAction.confirmReceipt),
      );
      expect(
        InterBranchInvoicePolicy.actionsFor(
          role: UserRole.manager,
          branchId: 'supplier',
          invoice: invoice,
        ),
        isNot(contains(InterBranchInvoiceAction.confirmReceipt)),
      );
      expect(
        InterBranchInvoicePolicy.canView(
          role: UserRole.manager,
          branchId: 'unrelated',
          invoice: invoice,
        ),
        isFalse,
      );
    });

    test('general manager and accountant have distinct global actions', () {
      final pricing = _invoice(
        status: InterBranchInvoiceStatus.pendingPriceEntry,
      );
      final accounting = _invoice(
        status: InterBranchInvoiceStatus.pendingAccountingEntry,
      );

      expect(
        InterBranchInvoicePolicy.actionsFor(
          role: UserRole.collector,
          branchId: null,
          invoice: pricing,
        ),
        contains(InterBranchInvoiceAction.confirmPrices),
      );
      expect(
        InterBranchInvoicePolicy.actionsFor(
          role: UserRole.accountant,
          branchId: null,
          invoice: accounting,
        ),
        contains(InterBranchInvoiceAction.postAccounting),
      );
      expect(
        InterBranchInvoicePolicy.actionsFor(
          role: UserRole.accountant,
          branchId: null,
          invoice: pricing,
        ),
        isNot(contains(InterBranchInvoiceAction.confirmPrices)),
      );
    });

    test('only the general manager can receive a main-branch transfer', () {
      final invoice = _invoice(
        status: InterBranchInvoiceStatus.pendingReceiverReview,
        receivingMainBranch: true,
      );

      expect(
        InterBranchInvoicePolicy.actionsFor(
          role: UserRole.collector,
          branchId: null,
          invoice: invoice,
        ),
        contains(InterBranchInvoiceAction.confirmReceipt),
      );
      expect(
        InterBranchInvoicePolicy.actionsFor(
          role: UserRole.manager,
          branchId: 'receiver',
          invoice: invoice,
        ),
        isNot(contains(InterBranchInvoiceAction.confirmReceipt)),
      );
    });

    test('a malformed historic main-branch name is not shown to the user', () {
      final invoice = InterBranchInvoiceRead(
        id: 'main-label',
        data: <String, dynamic>{
          InterBranchInvoiceFields.receivingBranchType: 'main',
          InterBranchInvoiceFields.receivingBranchName: '?????',
        },
      );

      expect(invoice.receivingBranchDisplayName, 'الفرع الرئيسي');
    });

    test('price visibility excludes both supplying and receiving managers', () {
      expect(
        InterBranchInvoicePolicy.mayReadProtectedPrices(UserRole.manager),
        isFalse,
      );
      expect(
        InterBranchInvoicePolicy.mayReadProtectedPrices(UserRole.collector),
        isTrue,
      );
      expect(
        InterBranchInvoicePolicy.mayReadProtectedPrices(UserRole.accountant),
        isTrue,
      );
      expect(
        InterBranchInvoicePolicy.mayReadProtectedPrices(UserRole.admin),
        isTrue,
      );
      expect(
        InterBranchInvoicePolicy.mayConfirmProtectedPrices(UserRole.accountant),
        isFalse,
      );
    });

    test('sent, received and global queues use the corrected direction', () {
      final pricing = _invoice(
        status: InterBranchInvoiceStatus.pendingPriceEntry,
      );
      expect(
        InterBranchInvoicePolicy.matchesScope(
          invoice: pricing,
          scope: InterBranchInvoiceListScope.sent,
          branchId: 'supplier',
        ),
        isTrue,
      );
      expect(
        InterBranchInvoicePolicy.matchesScope(
          invoice: pricing,
          scope: InterBranchInvoiceListScope.received,
          branchId: 'receiver',
        ),
        isTrue,
      );
      expect(
        InterBranchInvoicePolicy.matchesScope(
          invoice: pricing,
          scope: InterBranchInvoiceListScope.pricingQueue,
        ),
        isTrue,
      );
    });

    test(
      'version 3 exposes accounting only after receipt and never pricing',
      () {
        final transfer = _invoice(
          status: InterBranchInvoiceStatus.pendingDualAccounting,
          workflowVersion: 3,
        );
        expect(
          InterBranchInvoicePolicy.actionsFor(
            role: UserRole.accountant,
            branchId: null,
            invoice: transfer,
          ),
          contains(InterBranchInvoiceAction.postAccounting),
        );
        expect(
          InterBranchInvoicePolicy.actionsFor(
            role: UserRole.collector,
            branchId: null,
            invoice: transfer,
          ),
          isNot(contains(InterBranchInvoiceAction.confirmPrices)),
        );
      },
    );

    test('required task filtering keeps optional edits out of my tasks', () {
      final transfer = _invoice(
        status: InterBranchInvoiceStatus.pendingReceiverReview,
        workflowVersion: 3,
      );
      final creatorActions = InterBranchInvoicePolicy.actionsFor(
        role: UserRole.manager,
        branchId: 'supplier',
        actorId: 'supplier',
        invoice: transfer,
      );
      expect(creatorActions, contains(InterBranchInvoiceAction.requestEdit));
      expect(
        InterBranchInvoicePolicy.hasRequiredAction(creatorActions),
        isFalse,
      );

      final receiverActions = InterBranchInvoicePolicy.actionsFor(
        role: UserRole.manager,
        branchId: 'receiver',
        actorId: 'receiver',
        invoice: transfer,
      );
      expect(
        receiverActions,
        contains(InterBranchInvoiceAction.confirmReceipt),
      );
      expect(
        InterBranchInvoicePolicy.hasRequiredAction(receiverActions),
        isTrue,
      );
    });
  });
}

InterBranchInvoiceRead _invoice({
  required InterBranchInvoiceStatus status,
  bool receivingMainBranch = false,
  int workflowVersion = 2,
}) => InterBranchInvoiceRead(
  id: 'invoice-1',
  data: {
    'schema_version': workflowVersion,
    'workflow_version': workflowVersion,
    if (workflowVersion >= 3) 'participant_ids': const ['supplier'],
    if (workflowVersion >= 3) 'created_by': 'supplier',
    'revision': 2,
    'status': status.value,
    'sending_branch_id': 'supplier',
    'receiving_branch_id': 'receiver',
    if (receivingMainBranch) 'receiving_branch_type': 'main',
    'branch_ids': const ['supplier', 'receiver'],
  },
);
