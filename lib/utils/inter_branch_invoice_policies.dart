import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/inter_branch_invoice_model.dart';

enum InterBranchInvoiceAction {
  legacySupplierApprove,
  legacySupplierReject,
  confirmReceipt,
  confirmPrices,
  postAccounting,
  requestEdit,
  requestCancellation,
  approveSharedRequest,
}

enum InterBranchInvoiceListScope {
  sent,
  received,
  pricingQueue,
  accountingQueue,
  allAuthorized,
}

class InterBranchInvoicePolicy {
  InterBranchInvoicePolicy._();

  static const creationDeniedMessage = 'لا تملك صلاحية إنشاء فواتير المناقلات.';

  /// Receipt and pricing permissions never imply permission to create a
  /// transfer. Creation is limited to a branch manager with a source branch.
  static bool canCreateInterBranchTransfer({
    required UserRole role,
    required String? branchId,
  }) => role == UserRole.manager && (branchId?.trim().isNotEmpty ?? false);

  static bool canView({
    required UserRole role,
    required String? branchId,
    required InterBranchInvoiceRead invoice,
  }) {
    if (role == UserRole.collector ||
        role == UserRole.accountant ||
        role == UserRole.admin) {
      return true;
    }
    final branch = branchId?.trim() ?? '';
    return role == UserRole.manager &&
        branch.isNotEmpty &&
        invoice.branchIds.contains(branch);
  }

  static Set<InterBranchInvoiceAction> actionsFor({
    required UserRole role,
    required String? branchId,
    required InterBranchInvoiceRead invoice,
    String? actorId,
  }) {
    if (!canView(role: role, branchId: branchId, invoice: invoice)) {
      return const {};
    }
    final branch = branchId?.trim() ?? '';
    final isSupplying = branch.isNotEmpty && invoice.sendingBranchId == branch;
    final isReceiving =
        branch.isNotEmpty && invoice.receivingBranchId == branch;
    final actions = <InterBranchInvoiceAction>{};

    if (invoice.isVersion3) {
      final participant =
          actorId != null && invoice.participantIds.contains(actorId);
      final mayRequestDirect =
          role == UserRole.manager &&
          isSupplying &&
          actorId != null &&
          actorId == invoice.createdBy &&
          invoice.status == InterBranchInvoiceStatus.pendingReceiverReview;
      final mayRequestShared =
          participant &&
          (invoice.status == InterBranchInvoiceStatus.pendingDualAccounting ||
              invoice.status == InterBranchInvoiceStatus.postedToAccounting);
      if (mayRequestDirect || mayRequestShared) {
        actions.add(InterBranchInvoiceAction.requestEdit);
        actions.add(InterBranchInvoiceAction.requestCancellation);
      }
      if (invoice.hasPendingAmendment &&
          actorId != null &&
          invoice.amendmentApproverIds.contains(actorId) &&
          !invoice.amendmentApprovals.containsKey(actorId)) {
        actions.add(InterBranchInvoiceAction.approveSharedRequest);
      }
      if (invoice.hasPendingCancellation &&
          actorId != null &&
          invoice.cancellationApproverIds.contains(actorId) &&
          !invoice.cancellationApprovals.containsKey(actorId)) {
        actions.add(InterBranchInvoiceAction.approveSharedRequest);
      }
    } else if (!invoice.isVersion2) {
      if (role == UserRole.manager &&
          isSupplying &&
          invoice.status == InterBranchInvoiceStatus.requestPending) {
        actions.addAll(const {
          InterBranchInvoiceAction.legacySupplierApprove,
          InterBranchInvoiceAction.legacySupplierReject,
        });
      }
      if (invoice.status.hasInvoice &&
          invoice.status != InterBranchInvoiceStatus.cancelled &&
          invoice.status !=
              InterBranchInvoiceStatus.cancellationPendingApprovals &&
          invoice.status != InterBranchInvoiceStatus.editPendingApprovals) {
        if (role == UserRole.collector ||
            role == UserRole.accountant ||
            (role == UserRole.manager && (isSupplying || isReceiving))) {
          actions.add(InterBranchInvoiceAction.requestEdit);
          if (role != UserRole.collector) {
            actions.add(InterBranchInvoiceAction.requestCancellation);
          }
        }
      }
      final sharedPending =
          invoice.status ==
              InterBranchInvoiceStatus.cancellationPendingApprovals ||
          invoice.status == InterBranchInvoiceStatus.editPendingApprovals;
      if (sharedPending &&
          (role == UserRole.accountant ||
              (role == UserRole.manager && (isSupplying || isReceiving)))) {
        actions.add(InterBranchInvoiceAction.approveSharedRequest);
      }
    }

    if (((role == UserRole.manager &&
                isReceiving &&
                !invoice.isReceivingMainBranch) ||
            (role == UserRole.collector && invoice.isReceivingMainBranch)) &&
        invoice.status == InterBranchInvoiceStatus.pendingReceiverReview) {
      actions.add(InterBranchInvoiceAction.confirmReceipt);
    }
    if (!invoice.isVersion3 &&
        role == UserRole.collector &&
        invoice.status == InterBranchInvoiceStatus.pendingPriceEntry) {
      actions.add(InterBranchInvoiceAction.confirmPrices);
    }
    if (role == UserRole.accountant &&
        (invoice.status == InterBranchInvoiceStatus.pendingAccountingEntry ||
            invoice.status == InterBranchInvoiceStatus.pendingDualAccounting)) {
      actions.add(InterBranchInvoiceAction.postAccounting);
    }
    return actions;
  }

  /// A task is an action that is waiting for this exact account. Optional
  /// actions such as starting an amendment are deliberately excluded so the
  /// task register never claims that a user has work when no decision is due.
  static bool hasRequiredAction(Set<InterBranchInvoiceAction> actions) {
    return actions.contains(InterBranchInvoiceAction.legacySupplierApprove) ||
        actions.contains(InterBranchInvoiceAction.legacySupplierReject) ||
        actions.contains(InterBranchInvoiceAction.confirmReceipt) ||
        actions.contains(InterBranchInvoiceAction.confirmPrices) ||
        actions.contains(InterBranchInvoiceAction.postAccounting) ||
        actions.contains(InterBranchInvoiceAction.approveSharedRequest);
  }

  static bool matchesScope({
    required InterBranchInvoiceRead invoice,
    required InterBranchInvoiceListScope scope,
    String? branchId,
  }) {
    final branch = branchId?.trim() ?? '';
    switch (scope) {
      case InterBranchInvoiceListScope.sent:
        return branch.isNotEmpty && invoice.sendingBranchId == branch;
      case InterBranchInvoiceListScope.received:
        return branch.isNotEmpty && invoice.receivingBranchId == branch;
      case InterBranchInvoiceListScope.pricingQueue:
        return invoice.status == InterBranchInvoiceStatus.pendingPriceEntry;
      case InterBranchInvoiceListScope.accountingQueue:
        return invoice.status ==
                InterBranchInvoiceStatus.pendingAccountingEntry ||
            invoice.status == InterBranchInvoiceStatus.pendingDualAccounting;
      case InterBranchInvoiceListScope.allAuthorized:
        return branch.isEmpty || invoice.branchIds.contains(branch);
    }
  }

  static bool mayReadProtectedPrices(UserRole role) =>
      role == UserRole.collector ||
      role == UserRole.accountant ||
      role == UserRole.admin;

  static bool mayConfirmProtectedPrices(UserRole role) =>
      role == UserRole.collector;
}
