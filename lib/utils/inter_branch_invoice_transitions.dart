import 'package:store_collection_app/models/inter_branch_invoice_model.dart';

/// Pure transition policy used by tests and future transactional guards.
///
/// It deliberately includes the old request states so historical documents
/// remain classifiable and processable while direct creation is introduced in
/// a later phase.
class InterBranchInvoiceTransitions {
  InterBranchInvoiceTransitions._();

  static const legacyRequestStatuses = <InterBranchInvoiceStatus>{
    InterBranchInvoiceStatus.requestPending,
    InterBranchInvoiceStatus.requestRejectedBySupplier,
    InterBranchInvoiceStatus.approvedBySupplier,
    InterBranchInvoiceStatus.invoiceCreated,
  };

  static const _coreTransitions =
      <InterBranchInvoiceStatus, Set<InterBranchInvoiceStatus>>{
        InterBranchInvoiceStatus.requestPending: {
          InterBranchInvoiceStatus.requestRejectedBySupplier,
          InterBranchInvoiceStatus.approvedBySupplier,
          InterBranchInvoiceStatus.pendingReceiverReview,
        },
        InterBranchInvoiceStatus.approvedBySupplier: {
          InterBranchInvoiceStatus.invoiceCreated,
          InterBranchInvoiceStatus.pendingReceiverReview,
        },
        InterBranchInvoiceStatus.invoiceCreated: {
          InterBranchInvoiceStatus.pendingReceiverReview,
        },
        InterBranchInvoiceStatus.pendingReceiverReview: {
          InterBranchInvoiceStatus.receivedByReceivingManager,
          InterBranchInvoiceStatus.pendingPriceEntry,
        },
        InterBranchInvoiceStatus.receivedByReceivingManager: {
          InterBranchInvoiceStatus.pendingPriceEntry,
        },
        InterBranchInvoiceStatus.pendingPriceEntry: {
          InterBranchInvoiceStatus.pricesEnteredByCollector,
          InterBranchInvoiceStatus.pendingAccountingEntry,
        },
        InterBranchInvoiceStatus.pricesEnteredByCollector: {
          InterBranchInvoiceStatus.pendingAccountingEntry,
        },
        InterBranchInvoiceStatus.pendingAccountingEntry: {
          InterBranchInvoiceStatus.postedToAccounting,
        },
      };

  static bool isLegacyRequestStatus(InterBranchInvoiceStatus status) =>
      legacyRequestStatuses.contains(status);

  static bool allowsCoreTransition(
    InterBranchInvoiceStatus current,
    InterBranchInvoiceStatus next,
  ) => _coreTransitions[current]?.contains(next) ?? false;

  static bool canStartEdit(InterBranchInvoiceStatus status) =>
      status.hasInvoice &&
      status != InterBranchInvoiceStatus.cancelled &&
      status != InterBranchInvoiceStatus.cancellationPendingApprovals &&
      status != InterBranchInvoiceStatus.editPendingApprovals;

  static bool canStartCancellation(InterBranchInvoiceStatus status) =>
      canStartEdit(status);
}
