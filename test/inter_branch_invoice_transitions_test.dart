import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/inter_branch_invoice_model.dart';
import 'package:store_collection_app/utils/inter_branch_invoice_transitions.dart';

void main() {
  group('inter-branch transition foundation', () {
    test('keeps historical request states recognizable', () {
      expect(
        InterBranchInvoiceTransitions.isLegacyRequestStatus(
          InterBranchInvoiceStatus.requestPending,
        ),
        isTrue,
      );
      expect(
        InterBranchInvoiceTransitions.isLegacyRequestStatus(
          InterBranchInvoiceStatus.approvedBySupplier,
        ),
        isTrue,
      );
    });

    test('permits both legacy approval and current service shortcut', () {
      expect(
        InterBranchInvoiceTransitions.allowsCoreTransition(
          InterBranchInvoiceStatus.requestPending,
          InterBranchInvoiceStatus.approvedBySupplier,
        ),
        isTrue,
      );
      expect(
        InterBranchInvoiceTransitions.allowsCoreTransition(
          InterBranchInvoiceStatus.requestPending,
          InterBranchInvoiceStatus.pendingReceiverReview,
        ),
        isTrue,
      );
    });

    test('rejects backward core transitions and terminal edits', () {
      expect(
        InterBranchInvoiceTransitions.allowsCoreTransition(
          InterBranchInvoiceStatus.postedToAccounting,
          InterBranchInvoiceStatus.pendingPriceEntry,
        ),
        isFalse,
      );
      expect(
        InterBranchInvoiceTransitions.canStartEdit(
          InterBranchInvoiceStatus.cancelled,
        ),
        isFalse,
      );
    });
  });
}
