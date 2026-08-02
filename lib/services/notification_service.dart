import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:store_collection_app/utils/archive_workflow.dart';

class NotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const transactionsModule = 'transactions';
  static const consumableRequestsModule = 'consumable_requests';
  static const cashExpenseRequestsModule = 'cash_expense_requests';
  static const interBranchInvoicesModule = 'inter_branch_invoices';

  Stream<QuerySnapshot<Map<String, dynamic>>> getCurrentUserNotifications() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _firestore
        .collection('notifications')
        .where('recipient_id', isEqualTo: uid)
        .snapshots();
  }

  Future<void> markAsRead(String notificationId) {
    return _firestore.collection('notifications').doc(notificationId).update({
      'is_read': true,
      'read_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAllAsRead() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final snapshot = await _firestore
        .collection('notifications')
        .where('recipient_id', isEqualTo: uid)
        .get();
    final unread = snapshot.docs.where((doc) => doc.data()['is_read'] != true);
    final batch = _firestore.batch();
    for (final doc in unread) {
      batch.update(doc.reference, {
        'is_read': true,
        'read_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> notifyForNewTransaction({
    required String transactionId,
    required Map<String, dynamic> transactionData,
  }) async {
    final branchId = _string(transactionData, 'branchId');
    final transactionNumber = _referenceNumber(
      transactionData,
      keys: const ['transaction_number'],
      fallbackPrefix: 'TR',
      fallbackId: transactionId,
    );

    await _send(
      recipients: await _branchManagers(branchId),
      module: transactionsModule,
      entityCollection: 'transactions',
      entityId: transactionId,
      branchId: branchId,
      referenceNumber: transactionNumber,
      notificationType: 'transaction_created',
      title: 'سند جديد بانتظار الاعتماد',
      message: 'تم إنشاء السند رقم $transactionNumber في فرعك.',
      extraData: {
        'transaction_id': transactionId,
        'transaction_number': transactionNumber,
      },
    );
  }

  Future<void> notifyForStatus({
    required String transactionId,
    required String newStatus,
    String? message,
  }) async {
    final transactionDoc = await _firestore
        .collection('transactions')
        .doc(transactionId)
        .get();
    final data = transactionDoc.data();
    if (data == null) return;

    final branchId = _string(data, 'branchId');
    final transactionNumber = _referenceNumber(
      data,
      keys: const ['transaction_number'],
      fallbackPrefix: 'TR',
      fallbackId: transactionId,
    );
    final recipients = <String>{};
    String title;
    String body;

    switch (newStatus) {
      case 'pendingApprovalOfEdit':
        recipients.addAll(await _branchManagers(branchId));
        title = 'تعديل سند بانتظار الاعتماد';
        body = 'تم إرسال تعديل السند رقم $transactionNumber لاعتمادك.';
        break;
      case 'editRequestedByCollector':
      case 'rejectedByManager':
        recipients.add(_string(data, 'collectorId'));
        title = newStatus == 'rejectedByManager'
            ? 'تم رفض السند'
            : 'السند يحتاج إلى تعديل';
        body = message ?? 'يرجى مراجعة السند رقم $transactionNumber.';
        break;
      case 'approvedByManager':
        recipients.addAll(await _usersByRole('accountant'));
        title = 'سند جاهز للمراجعة المالية';
        body =
            'اعتمد المدير السند رقم $transactionNumber وأصبح جاهزا للمراجعة.';
        break;
      case 'approvedByAccountant':
        recipients.add(_string(data, 'collectorId'));
        recipients.addAll(await _branchManagers(branchId));
        title = 'تم الاعتماد النهائي للسند';
        body = 'تم اعتماد السند رقم $transactionNumber اعتمادا نهائيا.';
        break;
      case 'pending':
        recipients.addAll(await _branchManagers(branchId));
        title = 'سند معاد بانتظار الاعتماد';
        body = 'أعيد السند رقم $transactionNumber إلى مرحلة اعتماد المدير.';
        break;
      default:
        return;
    }

    await _send(
      recipients: recipients,
      module: transactionsModule,
      entityCollection: 'transactions',
      entityId: transactionId,
      branchId: branchId,
      referenceNumber: transactionNumber,
      notificationType: 'transaction_status_$newStatus',
      title: title,
      message: body,
      extraData: {
        'transaction_id': transactionId,
        'transaction_number': transactionNumber,
      },
    );
  }

  Future<void> notifyForArchive({
    required String transactionId,
    bool completed = false,
  }) async {
    final transactionDoc = await _firestore
        .collection('transactions')
        .doc(transactionId)
        .get();
    final data = transactionDoc.data();
    if (data == null) return;

    final branchId = _string(data, 'branchId');
    final transactionNumber = _referenceNumber(
      data,
      keys: const ['transaction_number'],
      fallbackPrefix: 'TR',
      fallbackId: transactionId,
    );
    final recipients = <String>{};
    if (completed) {
      for (final approval in archiveApprovalsOf(data).values) {
        if (approval is Map && approval['user_id'] is String) {
          recipients.add(approval['user_id'] as String);
        }
      }
    } else {
      if (!hasArchiveApproval(data, 'collector')) {
        recipients.add(_string(data, 'collectorId'));
      }
      if (!hasArchiveApproval(data, 'manager')) {
        recipients.addAll(await _branchManagers(branchId));
      }
      if (!hasArchiveApproval(data, 'accountant')) {
        recipients.addAll(await _usersByRole('accountant'));
      }
    }

    await _send(
      recipients: recipients,
      module: transactionsModule,
      entityCollection: 'transactions',
      entityId: transactionId,
      branchId: branchId,
      referenceNumber: transactionNumber,
      notificationType: completed
          ? 'transaction_archive_completed'
          : 'transaction_archive_requested',
      title: completed ? 'تمت أرشفة السند' : 'طلب أرشفة يحتاج اعتمادك',
      message: completed
          ? 'اكتملت الموافقات وتمت أرشفة السند رقم $transactionNumber.'
          : 'السند رقم $transactionNumber ينتظر موافقتك على الأرشفة.',
      extraData: {
        'transaction_id': transactionId,
        'transaction_number': transactionNumber,
      },
    );
  }

  Future<void> notifyConsumableRequestCreated({
    required String requestId,
    required Map<String, dynamic> requestData,
  }) async {
    final branchId = _string(requestData, 'branch_id');
    final number = _referenceNumber(
      requestData,
      keys: const ['request_number'],
      fallbackPrefix: 'CR',
      fallbackId: requestId,
    );

    await _send(
      recipients: await _usersByRole('collector'),
      module: consumableRequestsModule,
      entityCollection: consumableRequestsModule,
      entityId: requestId,
      branchId: branchId,
      referenceNumber: number,
      notificationType: 'consumable_request_created',
      title: 'طلب مستهلكات جديد',
      message: 'طلب المستهلكات رقم $number بانتظار مراجعة المدير العام.',
      extraData: {'consumable_request_id': requestId},
    );
  }

  Future<void> notifyConsumableCollectorReviewed({
    required String requestId,
    required Map<String, dynamic> requestData,
  }) async {
    final branchId = _string(requestData, 'branch_id');
    final number = _referenceNumber(
      requestData,
      keys: const ['request_number'],
      fallbackPrefix: 'CR',
      fallbackId: requestId,
    );

    await _send(
      recipients: await _usersByRole('accountant'),
      module: consumableRequestsModule,
      entityCollection: consumableRequestsModule,
      entityId: requestId,
      branchId: branchId,
      referenceNumber: number,
      notificationType: 'consumable_collector_reviewed',
      title: 'طلب مستهلكات جاهز للمحاسبة',
      message: 'تمت مراجعة طلب المستهلكات رقم $number وهو بانتظار اعتمادك.',
      extraData: {'consumable_request_id': requestId},
    );
  }

  Future<void> notifyConsumableAccountingApproved({
    required String requestId,
    required Map<String, dynamic> requestData,
  }) async {
    final branchId = _string(requestData, 'branch_id');
    final number = _referenceNumber(
      requestData,
      keys: const ['request_number'],
      fallbackPrefix: 'CR',
      fallbackId: requestId,
    );

    await _send(
      recipients: {
        _string(requestData, 'created_by'),
        _string(requestData, 'reviewed_by'),
      },
      module: consumableRequestsModule,
      entityCollection: consumableRequestsModule,
      entityId: requestId,
      branchId: branchId,
      referenceNumber: number,
      notificationType: 'consumable_accounting_approved',
      title: 'تم اعتماد طلب المستهلكات',
      message: 'اعتمد المحاسب طلب المستهلكات رقم $number نهائيا.',
      extraData: {'consumable_request_id': requestId},
    );
  }

  Future<void> notifyCashExpenseCreated({
    required String requestId,
    required Map<String, dynamic> requestData,
  }) async {
    final branchId = _string(requestData, 'branch_id');
    final number = _cashExpenseNumber(requestId, requestData);

    await _send(
      recipients: await _usersByRole('collector'),
      module: cashExpenseRequestsModule,
      entityCollection: cashExpenseRequestsModule,
      entityId: requestId,
      branchId: branchId,
      referenceNumber: number,
      notificationType: 'cash_expense_created',
      title: 'سند صرف نقدي جديد',
      message: 'سند الصرف رقم $number بانتظار مراجعة المدير العام.',
      extraData: {'cash_expense_request_id': requestId},
    );
  }

  Future<void> notifyCashExpenseGeneralManagerDecision({
    required String requestId,
    required Map<String, dynamic> requestData,
    required bool approved,
  }) async {
    final branchId = _string(requestData, 'branch_id');
    final number = _cashExpenseNumber(requestId, requestData);
    final status = _string(requestData, 'status');
    final recipients = <String>{};
    late final String title;
    late final String body;
    late final String type;

    if (!approved || status == 'rejectedByGeneralManager') {
      recipients.add(_string(requestData, 'created_by'));
      title = 'تم رفض سند الصرف';
      body = 'رفض المدير العام سند الصرف رقم $number. يرجى مراجعته.';
      type = 'cash_expense_rejected_by_general_manager';
    } else if (status == 'pendingInvoiceAttachment') {
      recipients.add(_string(requestData, 'created_by'));
      title = 'سند الصرف يحتاج فاتورة';
      body =
          'اعتمد المدير العام سند الصرف رقم $number وهو بانتظار إرفاق الفاتورة.';
      type = 'cash_expense_invoice_required';
    } else {
      recipients.addAll(await _usersByRole('accountant'));
      title = 'سند صرف جاهز للمحاسبة';
      body = 'اعتمد المدير العام سند الصرف رقم $number وهو بانتظار اعتمادك.';
      type = 'cash_expense_general_manager_approved';
    }

    await _send(
      recipients: recipients,
      module: cashExpenseRequestsModule,
      entityCollection: cashExpenseRequestsModule,
      entityId: requestId,
      branchId: branchId,
      referenceNumber: number,
      notificationType: type,
      title: title,
      message: body,
      extraData: {'cash_expense_request_id': requestId},
    );
  }

  Future<void> notifyCashExpenseInvoiceReady({
    required String requestId,
    required Map<String, dynamic> requestData,
  }) async {
    final branchId = _string(requestData, 'branch_id');
    final number = _cashExpenseNumber(requestId, requestData);

    await _send(
      recipients: await _usersByRole('accountant'),
      module: cashExpenseRequestsModule,
      entityCollection: cashExpenseRequestsModule,
      entityId: requestId,
      branchId: branchId,
      referenceNumber: number,
      notificationType: 'cash_expense_invoice_ready',
      title: 'سند صرف بانتظار الاعتماد المحاسبي',
      message: 'تم تجهيز فاتورة سند الصرف رقم $number لاعتماد المحاسب.',
      extraData: {'cash_expense_request_id': requestId},
    );
  }

  Future<void> notifyCashExpenseAccountingApproved({
    required String requestId,
    required Map<String, dynamic> requestData,
  }) async {
    final branchId = _string(requestData, 'branch_id');
    final number = _cashExpenseNumber(requestId, requestData);

    await _send(
      recipients: {
        _string(requestData, 'created_by'),
        _string(requestData, 'reviewed_by'),
        _string(requestData, 'invoice_approved_by'),
      },
      module: cashExpenseRequestsModule,
      entityCollection: cashExpenseRequestsModule,
      entityId: requestId,
      branchId: branchId,
      referenceNumber: number,
      notificationType: 'cash_expense_accounting_approved',
      title: 'تم اعتماد سند الصرف',
      message: 'اعتمد المحاسب سند الصرف رقم $number نهائيا.',
      extraData: {'cash_expense_request_id': requestId},
    );
  }

  Future<void> notifyCashExpenseEditRequested({
    required String requestId,
    required Map<String, dynamic> requestData,
  }) async {
    final branchId = _string(requestData, 'branch_id');
    final number = _cashExpenseNumber(requestId, requestData);

    await _send(
      recipients: await _cashExpenseEditPendingRecipients(requestData),
      module: cashExpenseRequestsModule,
      entityCollection: cashExpenseRequestsModule,
      entityId: requestId,
      branchId: branchId,
      referenceNumber: number,
      notificationType: 'cash_expense_edit_requested',
      title: 'طلب تعديل سند صرف',
      message: 'سند الصرف رقم $number لديه طلب تعديل بانتظار موافقتك.',
      extraData: {'cash_expense_request_id': requestId},
    );
  }

  Future<void> notifyCashExpenseEditDecision({
    required String requestId,
    required Map<String, dynamic> requestData,
    required bool approved,
  }) async {
    final branchId = _string(requestData, 'branch_id');
    final number = _cashExpenseNumber(requestId, requestData);
    final editRequest = _map(requestData['edit_request']);
    final allApproved = _cashExpenseEditApprovalsComplete(requestData);
    final rejected =
        !approved || _string(requestData, 'status') != 'editPendingApprovals';
    final recipients = <String>{};
    late final String title;
    late final String body;
    late final String type;

    if (rejected && !allApproved) {
      recipients.add(_string(editRequest, 'requested_by'));
      recipients.add(_string(requestData, 'created_by'));
      title = 'تم رفض طلب تعديل سند الصرف';
      body = 'تم رفض طلب تعديل سند الصرف رقم $number.';
      type = 'cash_expense_edit_rejected';
    } else if (allApproved) {
      recipients.add(_string(requestData, 'created_by'));
      title = 'اكتملت موافقات تعديل سند الصرف';
      body = 'اكتملت موافقات تعديل سند الصرف رقم $number ويمكن تعديل بياناته.';
      type = 'cash_expense_edit_fully_approved';
    } else {
      return;
    }

    await _send(
      recipients: recipients,
      module: cashExpenseRequestsModule,
      entityCollection: cashExpenseRequestsModule,
      entityId: requestId,
      branchId: branchId,
      referenceNumber: number,
      notificationType: type,
      title: title,
      message: body,
      extraData: {'cash_expense_request_id': requestId},
    );
  }

  Future<void> notifyCashExpenseManagerUpdatedAfterEdit({
    required String requestId,
    required Map<String, dynamic> requestData,
  }) async {
    final branchId = _string(requestData, 'branch_id');
    final number = _cashExpenseNumber(requestId, requestData);

    await _send(
      recipients: await _usersByRole('collector'),
      module: cashExpenseRequestsModule,
      entityCollection: cashExpenseRequestsModule,
      entityId: requestId,
      branchId: branchId,
      referenceNumber: number,
      notificationType: 'cash_expense_manager_updated_after_edit',
      title: 'سند صرف معدل بانتظار المراجعة',
      message: 'عدّل مدير الفرع سند الصرف رقم $number بعد اكتمال الموافقات.',
      extraData: {'cash_expense_request_id': requestId},
    );
  }

  Future<void> notifyInterBranchRequestCreated({
    required String invoiceId,
    required Map<String, dynamic> invoiceData,
  }) async {
    final sendingBranchId = _string(invoiceData, 'sending_branch_id');
    final number = _interBranchReference(invoiceId, invoiceData);

    await _send(
      recipients: await _branchManagers(sendingBranchId),
      module: interBranchInvoicesModule,
      entityCollection: interBranchInvoicesModule,
      entityId: invoiceId,
      branchId: sendingBranchId,
      branchIds: _interBranchIds(invoiceData),
      referenceNumber: number,
      notificationType: 'inter_branch_request_created',
      title: 'طلب بين الفروع بانتظارك',
      message:
          'يوجد طلب منتجات بين الفروع رقم $number بانتظار موافقة الفرع المورد.',
      extraData: {'inter_branch_invoice_id': invoiceId},
    );
  }

  Future<void> notifyInterBranchSupplierDecision({
    required String invoiceId,
    required Map<String, dynamic> invoiceData,
    required bool approved,
  }) async {
    final receivingBranchId = _string(invoiceData, 'receiving_branch_id');
    final sendingBranchId = _string(invoiceData, 'sending_branch_id');
    final number = _interBranchReference(invoiceId, invoiceData);

    await _send(
      recipients: await _branchManagers(receivingBranchId),
      module: interBranchInvoicesModule,
      entityCollection: interBranchInvoicesModule,
      entityId: invoiceId,
      branchId: receivingBranchId,
      branchIds: _interBranchIds(invoiceData),
      referenceNumber: number,
      notificationType: approved
          ? 'inter_branch_supplier_approved'
          : 'inter_branch_supplier_rejected',
      title: approved ? 'تم إنشاء فاتورة بين الفروع' : 'تم رفض طلب بين الفروع',
      message: approved
          ? 'وافق الفرع المورد على الطلب رقم $number وهو بانتظار استلامك.'
          : 'رفض الفرع المورد الطلب رقم $number.',
      extraData: {
        'inter_branch_invoice_id': invoiceId,
        'sending_branch_id': sendingBranchId,
        'receiving_branch_id': receivingBranchId,
      },
    );
  }

  Future<void> notifyInterBranchReceiptConfirmed({
    required String invoiceId,
    required Map<String, dynamic> invoiceData,
  }) async {
    final sendingBranchId = _string(invoiceData, 'sending_branch_id');
    final number = _interBranchReference(invoiceId, invoiceData);

    await _send(
      recipients: await _usersByRole('collector'),
      module: interBranchInvoicesModule,
      entityCollection: interBranchInvoicesModule,
      entityId: invoiceId,
      branchId: sendingBranchId,
      branchIds: _interBranchIds(invoiceData),
      referenceNumber: number,
      notificationType: 'inter_branch_receipt_confirmed',
      title: 'فاتورة بين الفروع بانتظار التسعير',
      message:
          'تم تأكيد استلام الفاتورة رقم $number وهي بانتظار إدخال الأسعار.',
      extraData: {'inter_branch_invoice_id': invoiceId},
    );
  }

  Future<void> notifyInterBranchPricesEntered({
    required String invoiceId,
    required Map<String, dynamic> invoiceData,
  }) async {
    final sendingBranchId = _string(invoiceData, 'sending_branch_id');
    final number = _interBranchReference(invoiceId, invoiceData);

    await _send(
      recipients: await _usersByRole('accountant'),
      module: interBranchInvoicesModule,
      entityCollection: interBranchInvoicesModule,
      entityId: invoiceId,
      branchId: sendingBranchId,
      branchIds: _interBranchIds(invoiceData),
      referenceNumber: number,
      notificationType: 'inter_branch_prices_entered',
      title: 'فاتورة بين الفروع جاهزة للمحاسبة',
      message:
          'تم إدخال أسعار الفاتورة رقم $number وهي بانتظار الترحيل المحاسبي.',
      extraData: {'inter_branch_invoice_id': invoiceId},
    );
  }

  Future<void> notifyInterBranchAccountingPosted({
    required String invoiceId,
    required Map<String, dynamic> invoiceData,
  }) async {
    final sendingBranchId = _string(invoiceData, 'sending_branch_id');
    final receivingBranchId = _string(invoiceData, 'receiving_branch_id');
    final number = _interBranchReference(invoiceId, invoiceData);

    await _send(
      recipients: {
        ...await _branchManagers(sendingBranchId),
        ...await _branchManagers(receivingBranchId),
        ...await _usersByRole('collector'),
      },
      module: interBranchInvoicesModule,
      entityCollection: interBranchInvoicesModule,
      entityId: invoiceId,
      branchId: sendingBranchId,
      branchIds: _interBranchIds(invoiceData),
      referenceNumber: number,
      notificationType: 'inter_branch_accounting_posted',
      title: 'تم ترحيل فاتورة بين الفروع',
      message: 'تم ترحيل الفاتورة رقم $number محاسبيا.',
      extraData: {'inter_branch_invoice_id': invoiceId},
    );
  }

  Future<void> notifyInterBranchSharedRequest({
    required String invoiceId,
    required Map<String, dynamic> invoiceData,
    required bool isCancellation,
  }) async {
    final sendingBranchId = _string(invoiceData, 'sending_branch_id');
    final number = _interBranchReference(invoiceId, invoiceData);
    final approvals = _map(
      invoiceData[isCancellation ? 'cancellation_approvals' : 'edit_approvals'],
    );

    await _send(
      recipients: await _interBranchApprovalRecipients(invoiceData, approvals),
      module: interBranchInvoicesModule,
      entityCollection: interBranchInvoicesModule,
      entityId: invoiceId,
      branchId: sendingBranchId,
      branchIds: _interBranchIds(invoiceData),
      referenceNumber: number,
      notificationType: isCancellation
          ? 'inter_branch_cancellation_requested'
          : 'inter_branch_edit_requested',
      title: isCancellation ? 'طلب إلغاء فاتورة' : 'طلب تعديل فاتورة',
      message: isCancellation
          ? 'الفاتورة رقم $number لديها طلب إلغاء بانتظار موافقتك.'
          : 'الفاتورة رقم $number لديها طلب تعديل بانتظار موافقتك.',
      extraData: {'inter_branch_invoice_id': invoiceId},
    );
  }

  Future<void> notifyInterBranchSharedDecision({
    required String invoiceId,
    required Map<String, dynamic> invoiceData,
    required bool isCancellation,
    required bool approved,
  }) async {
    final sendingBranchId = _string(invoiceData, 'sending_branch_id');
    final receivingBranchId = _string(invoiceData, 'receiving_branch_id');
    final number = _interBranchReference(invoiceId, invoiceData);
    final status = _string(invoiceData, 'status');
    final request = _map(
      invoiceData[isCancellation ? 'cancellation_request' : 'edit_request'],
    );
    final requestStatus = isCancellation
        ? 'cancellationPendingApprovals'
        : 'editPendingApprovals';
    final complete = status != requestStatus;

    if (!complete) return;

    final recipients = <String>{
      _string(request, 'requested_by'),
      ...await _branchManagers(sendingBranchId),
      ...await _branchManagers(receivingBranchId),
    };
    late final String title;
    late final String body;
    late final String type;

    if (!approved) {
      title = isCancellation
          ? 'تم رفض طلب إلغاء الفاتورة'
          : 'تم رفض طلب تعديل الفاتورة';
      body = isCancellation
          ? 'تم رفض طلب إلغاء الفاتورة رقم $number.'
          : 'تم رفض طلب تعديل الفاتورة رقم $number.';
      type = isCancellation
          ? 'inter_branch_cancellation_rejected'
          : 'inter_branch_edit_rejected';
    } else {
      title = isCancellation ? 'تم إلغاء الفاتورة' : 'تم اعتماد تعديل الفاتورة';
      body = isCancellation
          ? 'اكتملت موافقات إلغاء الفاتورة رقم $number.'
          : 'اكتملت موافقات تعديل الفاتورة رقم $number.';
      type = isCancellation
          ? 'inter_branch_cancellation_approved'
          : 'inter_branch_edit_approved';
    }

    await _send(
      recipients: recipients,
      module: interBranchInvoicesModule,
      entityCollection: interBranchInvoicesModule,
      entityId: invoiceId,
      branchId: sendingBranchId,
      branchIds: _interBranchIds(invoiceData),
      referenceNumber: number,
      notificationType: type,
      title: title,
      message: body,
      extraData: {'inter_branch_invoice_id': invoiceId},
    );
  }

  Future<Set<String>> _branchManagers(String branchId) async {
    final recipients = <String>{};
    if (branchId.isEmpty) return recipients;

    final branchDoc = await _firestore
        .collection('branches')
        .doc(branchId)
        .get();
    final assignedManager =
        branchDoc.data()?['branch_manager_id'] as String? ?? '';
    if (assignedManager.isNotEmpty) recipients.add(assignedManager);

    final branchUsers = await _firestore
        .collection('users')
        .where('branchId', isEqualTo: branchId)
        .get();
    recipients.addAll(
      branchUsers.docs
          .where((doc) => doc.data()['role'] == 'manager')
          .map((doc) => doc.id),
    );
    return recipients;
  }

  Future<Set<String>> _usersByRole(String role) async {
    final snapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: role)
        .get();
    return snapshot.docs.map((doc) => doc.id).toSet();
  }

  Future<Set<String>> _cashExpenseEditPendingRecipients(
    Map<String, dynamic> data,
  ) async {
    final approvals = _map(data['edit_approvals']);
    final branchId = _string(data, 'branch_id');
    final recipients = <String>{};
    if (approvals['manager'] is! Map) {
      recipients.addAll(await _branchManagers(branchId));
    }
    if (approvals['general_manager'] is! Map) {
      recipients.addAll(await _usersByRole('collector'));
    }
    if (approvals['accountant'] is! Map) {
      recipients.addAll(await _usersByRole('accountant'));
    }
    return recipients;
  }

  bool _cashExpenseEditApprovalsComplete(Map<String, dynamic> data) {
    final approvals = _map(data['edit_approvals']);
    return const ['manager', 'general_manager', 'accountant'].every(
      (party) =>
          approvals[party] is Map && approvals[party]['approved'] == true,
    );
  }

  Future<Set<String>> _interBranchApprovalRecipients(
    Map<String, dynamic> data,
    Map<String, dynamic> approvals,
  ) async {
    final recipients = <String>{};
    final sendingBranchId = _string(data, 'sending_branch_id');
    final receivingBranchId = _string(data, 'receiving_branch_id');
    if (approvals['supplyingManager'] is! Map) {
      recipients.addAll(await _branchManagers(sendingBranchId));
    }
    if (approvals['receivingManager'] is! Map) {
      recipients.addAll(await _branchManagers(receivingBranchId));
    }
    if (approvals['accountant'] is! Map) {
      recipients.addAll(await _usersByRole('accountant'));
    }
    return recipients;
  }

  Future<void> _send({
    required Set<String> recipients,
    required String module,
    required String entityCollection,
    required String entityId,
    required String title,
    required String message,
    String? branchId,
    Iterable<String>? branchIds,
    String? referenceNumber,
    String? notificationType,
    Map<String, dynamic> extraData = const {},
  }) async {
    final senderId = FirebaseAuth.instance.currentUser?.uid;
    recipients.removeWhere((uid) => uid.isEmpty || uid == senderId);
    if (recipients.isEmpty) return;

    final cleanBranchIds = branchIds
        ?.where((id) => id.trim().isNotEmpty)
        .map((id) => id.trim())
        .toSet()
        .toList();
    final batch = _firestore.batch();
    for (final recipientId in recipients) {
      final ref = _firestore.collection('notifications').doc();
      batch.set(ref, {
        'id': ref.id,
        'recipient_id': recipientId,
        'title': title,
        'message': message,
        'is_read': false,
        'push_status': 'pending',
        'module': module,
        'entity_collection': entityCollection,
        'entity_id': entityId,
        if ((branchId ?? '').trim().isNotEmpty) 'branch_id': branchId!.trim(),
        if (cleanBranchIds != null && cleanBranchIds.isNotEmpty)
          'branch_ids': cleanBranchIds,
        if ((referenceNumber ?? '').trim().isNotEmpty)
          'reference_number': referenceNumber!.trim(),
        if ((notificationType ?? '').trim().isNotEmpty)
          'notification_type': notificationType!.trim(),
        ...extraData,
        'created_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  String _cashExpenseNumber(String requestId, Map<String, dynamic> data) {
    return _referenceNumber(
      data,
      keys: const ['request_number'],
      fallbackPrefix: 'CE',
      fallbackId: requestId,
    );
  }

  String _interBranchReference(String invoiceId, Map<String, dynamic> data) {
    return _referenceNumber(
      data,
      keys: const ['invoice_number'],
      fallbackPrefix: 'IB',
      fallbackId: invoiceId,
    );
  }

  List<String> _interBranchIds(Map<String, dynamic> data) {
    return [
      _string(data, 'sending_branch_id'),
      _string(data, 'receiving_branch_id'),
    ].where((id) => id.isNotEmpty).toSet().toList();
  }

  String _referenceNumber(
    Map<String, dynamic> data, {
    required List<String> keys,
    required String fallbackPrefix,
    required String fallbackId,
  }) {
    for (final key in keys) {
      final value = _string(data, key);
      if (value.isNotEmpty && value != '-') return value;
    }
    return '$fallbackPrefix-${_shortId(fallbackId)}';
  }

  String _shortId(String id) => id.length > 6 ? id.substring(0, 6) : id;

  String _string(Map<String, dynamic> data, String key) {
    return data[key]?.toString().trim() ?? '';
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(value);
  }
}
