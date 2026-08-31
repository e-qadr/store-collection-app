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
  }) {
    if (!canView(role: role, branchId: branchId, invoice: invoice)) {
      return const {};
    }
    final branch = branchId?.trim() ?? '';
    final isSupplying = branch.isNotEmpty && invoice.sendingBranchId == branch;
    final isReceiving =
        branch.isNotEmpty && invoice.receivingBranchId == branch;
    final actions = <InterBranchInvoiceAction>{};

    if (!invoice.isVersion2) {
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
    if (role == UserRole.collector &&
        invoice.status == InterBranchInvoiceStatus.pendingPriceEntry) {
      actions.add(InterBranchInvoiceAction.confirmPrices);
    }
    if (role == UserRole.accountant &&
        invoice.status == InterBranchInvoiceStatus.pendingAccountingEntry) {
      actions.add(InterBranchInvoiceAction.postAccounting);
    }
    return actions;
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
            InterBranchInvoiceStatus.pendingAccountingEntry;
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
