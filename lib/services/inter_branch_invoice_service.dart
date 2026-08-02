import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/inter_branch_invoice_model.dart';
import 'package:store_collection_app/services/inter_branch_invoice_api_service.dart';
import 'package:store_collection_app/services/notification_service.dart';

class InterBranchInvoicePage {
  final List<InterBranchInvoiceRead> invoices;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;

  const InterBranchInvoicePage({
    required this.invoices,
    required this.cursor,
    required this.hasMore,
  });
}

class InterBranchInvoiceService {
  final FirebaseFirestore _firestore;
  final NotificationService _notificationService;
  final InterBranchInvoiceApiService commandApi;

  InterBranchInvoiceService({
    FirebaseFirestore? firestore,
    NotificationService? notificationService,
    InterBranchInvoiceApiService? commandApi,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _notificationService = notificationService ?? NotificationService(),
       commandApi = commandApi ?? InterBranchInvoiceApiService();

  static const requiredApprovalParties = <String>{
    'supplyingManager',
    'receivingManager',
    'accountant',
  };

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(InterBranchInvoiceFields.collection);

  Future<void> _notifySafely(Future<void> Function() notification) async {
    try {
      await notification();
    } catch (_) {
      // لا يجب أن يمنع فشل الإشعار تنفيذ العملية الأساسية.
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchInvoices({
    required UserRole role,
    String? branchId,
  }) {
    if (role == UserRole.admin) {
      return _collection
          .orderBy(InterBranchInvoiceFields.lastUpdated, descending: true)
          .limit(50)
          .snapshots();
    }
    if (role == UserRole.collector || role == UserRole.accountant) {
      return _collection
          .orderBy(InterBranchInvoiceFields.lastUpdated, descending: true)
          .limit(50)
          .snapshots();
    }
    if (branchId == null || branchId.isEmpty) {
      return _collection.limit(0).snapshots();
    }
    return _collection
        .where(InterBranchInvoiceFields.branchIds, arrayContains: branchId)
        .orderBy(InterBranchInvoiceFields.lastUpdated, descending: true)
        .limit(50)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPricingQueue({
    int limit = 50,
  }) {
    return _collection
        .where(
          InterBranchInvoiceFields.status,
          whereIn: const [
            'pendingPriceEntry',
            'receivedByReceivingManager',
            'receivedByReceivingBranch',
          ],
        )
        .orderBy(InterBranchInvoiceFields.lastUpdated, descending: true)
        .limit(limit)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchAccountingQueue({
    int limit = 50,
  }) {
    return _collection
        .where(
          InterBranchInvoiceFields.status,
          whereIn: const [
            'pendingAccountingEntry',
            'pricesEnteredByCollector',
            'pricedByGeneralManager',
          ],
        )
        .orderBy(InterBranchInvoiceFields.lastUpdated, descending: true)
        .limit(limit)
        .snapshots();
  }

  Future<InterBranchInvoicePage> fetchBranchPage({
    required String branchId,
    required bool sent,
    DocumentSnapshot<Map<String, dynamic>>? after,
    int pageSize = 30,
  }) async {
    final cleanBranchId = branchId.trim();
    if (cleanBranchId.isEmpty) throw ArgumentError('Branch ID is required.');
    Query<Map<String, dynamic>> query = _collection
        .where(InterBranchInvoiceFields.branchIds, arrayContains: cleanBranchId)
        .where(
          sent
              ? InterBranchInvoiceFields.sendingBranchId
              : InterBranchInvoiceFields.receivingBranchId,
          isEqualTo: cleanBranchId,
        )
        .orderBy(InterBranchInvoiceFields.lastUpdated, descending: true)
        .limit(pageSize);
    if (after != null) query = query.startAfterDocument(after);
    final snapshot = await query.get();
    return _page(snapshot, pageSize);
  }

  Future<InterBranchInvoicePage> fetchQueuePage({
    required UserRole role,
    DocumentSnapshot<Map<String, dynamic>>? after,
    int pageSize = 30,
  }) async {
    final statuses = switch (role) {
      UserRole.collector => const [
        'pendingPriceEntry',
        'receivedByReceivingManager',
        'receivedByReceivingBranch',
      ],
      UserRole.accountant => const [
        'pendingAccountingEntry',
        'pricesEnteredByCollector',
        'pricedByGeneralManager',
      ],
      _ => throw ArgumentError('This role has no global invoice queue.'),
    };
    Query<Map<String, dynamic>> query = _collection
        .where(InterBranchInvoiceFields.status, whereIn: statuses)
        .orderBy(InterBranchInvoiceFields.lastUpdated, descending: true)
        .limit(pageSize);
    if (after != null) query = query.startAfterDocument(after);
    final snapshot = await query.get();
    return _page(snapshot, pageSize);
  }

  Future<InterBranchInvoicePage> fetchAllPage({
    required UserRole role,
    DocumentSnapshot<Map<String, dynamic>>? after,
    int pageSize = 30,
  }) async {
    if (role != UserRole.admin) {
      throw ArgumentError('Only administrators may request the global list.');
    }
    Query<Map<String, dynamic>> query = _collection
        .orderBy(InterBranchInvoiceFields.lastUpdated, descending: true)
        .limit(pageSize);
    if (after != null) query = query.startAfterDocument(after);
    final snapshot = await query.get();
    return _page(snapshot, pageSize);
  }

  InterBranchInvoicePage _page(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    int pageSize,
  ) {
    return InterBranchInvoicePage(
      invoices: snapshot.docs
          .map((doc) => InterBranchInvoiceRead(id: doc.id, data: doc.data()))
          .toList(growable: false),
      cursor: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == pageSize,
    );
  }

  Future<InterBranchInvoiceCommandResult> createDirectInvoice({
    required String receivingBranchId,
    required List<InterBranchInvoiceItem> items,
    required String idempotencyKey,
    String? invoiceNotes,
  }) => commandApi.createDirectInvoice(
    receivingBranchId: receivingBranchId,
    items: items,
    idempotencyKey: idempotencyKey,
    invoiceNotes: invoiceNotes,
  );

  Future<InterBranchInvoiceCommandResult> confirmDirectReceipt({
    required String invoiceId,
    required int expectedRevision,
    required List<InterBranchInvoiceItem> items,
    required String idempotencyKey,
    String? receiverNotes,
  }) => commandApi.confirmReceipt(
    invoiceId: invoiceId,
    expectedRevision: expectedRevision,
    items: items,
    idempotencyKey: idempotencyKey,
    receiverNotes: receiverNotes,
  );

  Future<InterBranchInvoiceCommandResult> confirmDirectPrices({
    required String invoiceId,
    required int expectedRevision,
    required String currency,
    required List<InterBranchInvoicePriceInput> items,
    required String idempotencyKey,
    String? pricingNotes,
  }) => commandApi.confirmPrices(
    invoiceId: invoiceId,
    expectedRevision: expectedRevision,
    currency: currency,
    items: items,
    idempotencyKey: idempotencyKey,
    pricingNotes: pricingNotes,
  );

  Future<InterBranchInvoiceCommandResult> postDirectAccounting({
    required String invoiceId,
    required int expectedRevision,
    required String accountingReference,
    required String idempotencyKey,
    String? accountingNotes,
  }) => commandApi.postAccounting(
    invoiceId: invoiceId,
    expectedRevision: expectedRevision,
    accountingReference: accountingReference,
    idempotencyKey: idempotencyKey,
    accountingNotes: accountingNotes,
  );

  @Deprecated(
    'New request-first invoices are disabled. Use createDirectInvoice.',
  )
  Future<void> createRequest({
    required String itemName,
    required double requestedQuantity,
    required String unit,
    List<InterBranchInvoiceItem>? items,
    required String receivingBranchId,
    required String receivingBranchName,
    required String sendingBranchId,
    required String sendingBranchName,
  }) {
    throw UnsupportedError(
      'إنشاء طلبات الإصدار الأول متوقف. استخدم إنشاء الفاتورة المباشرة.',
    );
  }

  Future<void> submitSenderDecision({
    required String invoiceId,
    required bool approved,
    double? approvedQuantity,
    List<InterBranchInvoiceItem>? approvedItems,
    String? notes,
  }) async {
    final reason = notes?.trim() ?? '';
    if (!approved && reason.isEmpty) {
      throw Exception('سبب الرفض مطلوب.');
    }

    final actor = await _getCurrentActor();
    final docRef = _collection.doc(invoiceId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final data = _dataOrThrow(snapshot);
      _ensureLegacyWorkflow(data);
      _ensureStatus(
        data,
        InterBranchInvoiceStatus.requestPending,
        'لا يمكن اعتماد أو رفض هذا الطلب في حالته الحالية.',
      );
      _validateManagerBranch(
        actor,
        data[InterBranchInvoiceFields.sendingBranchId]?.toString() ?? '',
      );

      if (!approved) {
        transaction.update(docRef, {
          InterBranchInvoiceFields.status:
              InterBranchInvoiceStatus.requestRejectedBySupplier.value,
          InterBranchInvoiceFields.rejectionReason: reason,
          InterBranchInvoiceFields.senderNotes: reason,
          InterBranchInvoiceFields.lastUpdated: FieldValue.serverTimestamp(),
          InterBranchInvoiceFields.history: FieldValue.arrayUnion([
            _historyEntry(
              action: 'request_rejected_by_supplier',
              message: 'تم رفض الطلب من مدير الفرع المورد',
              actor: actor,
              note: reason,
            ),
          ]),
        });
        return;
      }

      final existingItems = _itemsFromData(data);
      final requestedQuantity =
          (data[InterBranchInvoiceFields.requestedQuantity] as num?)
              ?.toDouble() ??
          0;
      final approvedList =
          approvedItems ??
          existingItems
              .map(
                (item) => InterBranchInvoiceItem(
                  name: item.name,
                  unit: item.unit,
                  requestedQuantity: item.requestedQuantity,
                  approvedQuantity: item.approvedQuantity,
                ),
              )
              .toList();
      if (approvedList.isEmpty ||
          approvedList.any((item) => item.approvedQuantity <= 0)) {
        throw Exception('يجب أن تكون الكمية المعتمدة أكبر من صفر.');
      }
      final quantity = approvedQuantity ?? approvedList.first.approvedQuantity;

      final supplierBranchId =
          data[InterBranchInvoiceFields.sendingBranchId]?.toString() ?? '';
      final branchRef = _firestore.collection('branches').doc(supplierBranchId);
      final counterRef = _firestore
          .collection(InterBranchInvoiceFields.counterCollection)
          .doc(supplierBranchId);
      final branchSnapshot = await transaction.get(branchRef);
      final branchCode = (branchSnapshot.data()?['branch_code'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      if (!RegExp(r'^[A-Z]{2}$').hasMatch(branchCode)) {
        throw Exception(
          'يجب ضبط رمز الفرع المورد بحرفين إنجليزيين قبل إنشاء الفاتورة.',
        );
      }

      final counterSnapshot = await transaction.get(counterRef);
      final nextNumber =
          (counterSnapshot.data()?['next_number'] as num?)?.toInt() ?? 0;
      final invoiceNumber =
          '$branchCode${nextNumber.toString().padLeft(4, '0')}';

      transaction.set(counterRef, {
        'branch_id': supplierBranchId,
        'branch_code': branchCode,
        'next_number': nextNumber + 1,
        'last_invoice_number': invoiceNumber,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      transaction.update(docRef, {
        InterBranchInvoiceFields.status:
            InterBranchInvoiceStatus.pendingReceiverReview.value,
        InterBranchInvoiceFields.invoiceNumber: invoiceNumber,
        InterBranchInvoiceFields.invoiceCreatedAt: FieldValue.serverTimestamp(),
        InterBranchInvoiceFields.approvedBy: actor['uid'],
        InterBranchInvoiceFields.approvedAt: FieldValue.serverTimestamp(),
        InterBranchInvoiceFields.approvedQuantity: quantity,
        InterBranchInvoiceFields.items: approvedList
            .map((item) => item.toMap())
            .toList(),
        if (reason.isNotEmpty) InterBranchInvoiceFields.senderNotes: reason,
        InterBranchInvoiceFields.lastUpdated: FieldValue.serverTimestamp(),
        InterBranchInvoiceFields.history: FieldValue.arrayUnion([
          _historyEntry(
            action: 'supplier_approved_invoice_created',
            message: 'وافق مدير الفرع المورد وتم إنشاء الفاتورة',
            actor: actor,
            note: reason,
            changes: {
              'invoice_number': invoiceNumber,
              'old_quantity': requestedQuantity,
              'approved_quantity': quantity,
              'items_count': approvedList.length,
            },
          ),
        ]),
      });
    });
    final savedInvoice = await docRef.get();
    final savedData = savedInvoice.data();
    if (savedData != null) {
      await _notifySafely(
        () => _notificationService.notifyInterBranchSupplierDecision(
          invoiceId: invoiceId,
          invoiceData: savedData,
          approved: approved,
        ),
      );
    }
  }

  Future<void> confirmReceipt({
    required String invoiceId,
    double? receivedQuantity,
    List<InterBranchInvoiceItem>? receivedItems,
    String? notes,
  }) async {
    final actor = await _getCurrentActor();
    final docRef = _collection.doc(invoiceId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final data = _dataOrThrow(snapshot);
      _ensureLegacyWorkflow(data);
      _ensureStatus(
        data,
        InterBranchInvoiceStatus.pendingReceiverReview,
        'لا يمكن تأكيد الاستلام قبل إنشاء الفاتورة.',
      );
      _validateManagerBranch(
        actor,
        data[InterBranchInvoiceFields.receivingBranchId]?.toString() ?? '',
      );

      final approvedItems = _itemsFromData(data);
      final approvedQuantity =
          (data[InterBranchInvoiceFields.approvedQuantity] as num?)
              ?.toDouble() ??
          (data[InterBranchInvoiceFields.requestedQuantity] as num?)
              ?.toDouble() ??
          0;
      final receivedList =
          receivedItems ??
          approvedItems
              .map(
                (item) => InterBranchInvoiceItem(
                  name: item.name,
                  unit: item.unit,
                  requestedQuantity: item.requestedQuantity,
                  approvedQuantity: item.approvedQuantity,
                  receivedQuantity: item.approvedQuantity,
                  unitPrice: item.unitPrice,
                ),
              )
              .toList();
      if (receivedList.isEmpty ||
          receivedList.any((item) => item.receivedQuantity <= 0)) {
        throw Exception('يجب أن تكون كمية الاستلام أكبر من صفر.');
      }
      final quantity = receivedQuantity ?? receivedList.first.receivedQuantity;

      transaction.update(docRef, {
        InterBranchInvoiceFields.receivedQuantity: quantity,
        InterBranchInvoiceFields.items: receivedList
            .map((item) => item.toMap())
            .toList(),
        InterBranchInvoiceFields.status:
            InterBranchInvoiceStatus.pendingPriceEntry.value,
        if ((notes ?? '').trim().isNotEmpty)
          InterBranchInvoiceFields.receiverNotes: notes!.trim(),
        InterBranchInvoiceFields.lastUpdated: FieldValue.serverTimestamp(),
        InterBranchInvoiceFields.history: FieldValue.arrayUnion([
          _historyEntry(
            action: 'receiver_confirmed',
            message: 'تم تأكيد الاستلام من مدير الفرع المستلم',
            actor: actor,
            note: notes,
            changes: {
              'approved_quantity': approvedQuantity,
              'received_quantity': quantity,
            },
          ),
        ]),
      });
    });
    final savedInvoice = await docRef.get();
    final savedData = savedInvoice.data();
    if (savedData != null) {
      await _notifySafely(
        () => _notificationService.notifyInterBranchReceiptConfirmed(
          invoiceId: invoiceId,
          invoiceData: savedData,
        ),
      );
    }
  }

  Future<void> addPrice({
    required String invoiceId,
    required double unitPrice,
    String? branchId,
    String? notes,
  }) async {
    if (unitPrice <= 0) {
      throw Exception('يجب أن يكون السعر أكبر من صفر.');
    }

    final actor = await _getCurrentActor();
    _validateRole(
      actor,
      UserRole.collector,
      'إضافة الأسعار متاحة للمدير العام فقط.',
    );
    final docRef = _collection.doc(invoiceId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final data = _dataOrThrow(snapshot);
      _ensureLegacyWorkflow(data);
      final status = interBranchInvoiceStatusFromString(
        data[InterBranchInvoiceFields.status]?.toString(),
      );
      _validateSelectedSendingBranch(data, branchId);
      if (status != InterBranchInvoiceStatus.pendingPriceEntry &&
          status != InterBranchInvoiceStatus.pricesEnteredByCollector &&
          status != InterBranchInvoiceStatus.pendingAccountingEntry) {
        throw Exception('لا يمكن إدخال الأسعار قبل تأكيد الاستلام.');
      }

      final quantity = _quantityForTotals(data);
      final pricedItems = _itemsFromData(data)
          .map(
            (item) => InterBranchInvoiceItem(
              name: item.name,
              unit: item.unit,
              requestedQuantity: item.requestedQuantity,
              approvedQuantity: item.approvedQuantity,
              receivedQuantity: item.receivedQuantity,
              unitPrice: unitPrice,
            ),
          )
          .toList();
      transaction.update(docRef, {
        InterBranchInvoiceFields.unitPrice: unitPrice,
        InterBranchInvoiceFields.totalPrice: unitPrice * quantity,
        InterBranchInvoiceFields.items: pricedItems
            .map((item) => item.toMap())
            .toList(),
        InterBranchInvoiceFields.status:
            InterBranchInvoiceStatus.pendingAccountingEntry.value,
        if ((notes ?? '').trim().isNotEmpty)
          InterBranchInvoiceFields.collectorNotes: notes!.trim(),
        InterBranchInvoiceFields.lastUpdated: FieldValue.serverTimestamp(),
        InterBranchInvoiceFields.history: FieldValue.arrayUnion([
          _historyEntry(
            action: 'prices_entered_by_collector',
            message: 'تم إدخال أسعار الفاتورة من المدير العام',
            actor: actor,
            note: notes,
            changes: {
              'unit_price': unitPrice,
              'quantity': quantity,
              'total_price': unitPrice * quantity,
            },
          ),
        ]),
      });
    });
    final savedInvoice = await docRef.get();
    final savedData = savedInvoice.data();
    if (savedData != null) {
      await _notifySafely(
        () => _notificationService.notifyInterBranchPricesEntered(
          invoiceId: invoiceId,
          invoiceData: savedData,
        ),
      );
    }
  }

  Future<void> addItemPrices({
    required String invoiceId,
    required List<InterBranchInvoiceItem> pricedItems,
    String? branchId,
    String? notes,
  }) async {
    if (pricedItems.isEmpty ||
        pricedItems.any(
          (item) => item.unitPrice == null || item.unitPrice! <= 0,
        )) {
      throw Exception('يجب إدخال سعر صحيح لكل منتج.');
    }
    final actor = await _getCurrentActor();
    _validateRole(
      actor,
      UserRole.collector,
      'إضافة الأسعار متاحة للمدير العام فقط.',
    );
    final docRef = _collection.doc(invoiceId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final data = _dataOrThrow(snapshot);
      _ensureLegacyWorkflow(data);
      final status = interBranchInvoiceStatusFromString(
        data[InterBranchInvoiceFields.status]?.toString(),
      );
      _validateSelectedSendingBranch(data, branchId);
      if (status != InterBranchInvoiceStatus.pendingPriceEntry &&
          status != InterBranchInvoiceStatus.pricesEnteredByCollector &&
          status != InterBranchInvoiceStatus.pendingAccountingEntry) {
        throw Exception('لا يمكن إدخال الأسعار قبل تأكيد الاستلام.');
      }
      final total = pricedItems.fold<double>(
        0,
        (total, item) => total + item.totalPrice,
      );
      transaction.update(docRef, {
        InterBranchInvoiceFields.unitPrice: pricedItems.first.unitPrice,
        InterBranchInvoiceFields.totalPrice: total,
        InterBranchInvoiceFields.items: pricedItems
            .map((item) => item.toMap())
            .toList(),
        InterBranchInvoiceFields.status:
            InterBranchInvoiceStatus.pendingAccountingEntry.value,
        if ((notes ?? '').trim().isNotEmpty)
          InterBranchInvoiceFields.collectorNotes: notes!.trim(),
        InterBranchInvoiceFields.lastUpdated: FieldValue.serverTimestamp(),
        InterBranchInvoiceFields.history: FieldValue.arrayUnion([
          _historyEntry(
            action: 'prices_entered_by_collector',
            message: 'تم إدخال أسعار منتجات الفاتورة من المدير العام',
            actor: actor,
            note: notes,
            changes: {'items_count': pricedItems.length, 'total_price': total},
          ),
        ]),
      });
    });
    final savedInvoice = await docRef.get();
    final savedData = savedInvoice.data();
    if (savedData != null) {
      await _notifySafely(
        () => _notificationService.notifyInterBranchPricesEntered(
          invoiceId: invoiceId,
          invoiceData: savedData,
        ),
      );
    }
  }

  Future<void> confirmAccounting({
    required String invoiceId,
    required String accountingReference,
    String? branchId,
    String? notes,
  }) async {
    final reference = accountingReference.trim();
    if (reference.isEmpty) {
      throw Exception('رقم الفاتورة أو المرجع المحاسبي مطلوب.');
    }

    final actor = await _getCurrentActor();
    _validateRole(
      actor,
      UserRole.accountant,
      'الإدخال المحاسبي متاح للمحاسب فقط.',
    );
    final docRef = _collection.doc(invoiceId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final data = _dataOrThrow(snapshot);
      _ensureLegacyWorkflow(data);
      _validateSelectedSendingBranch(data, branchId);
      _ensureStatus(
        data,
        InterBranchInvoiceStatus.pendingAccountingEntry,
        'لا يمكن الترحيل المحاسبي قبل إدخال الأسعار.',
      );
      if ((data[InterBranchInvoiceFields.unitPrice] as num?) == null ||
          (data[InterBranchInvoiceFields.totalPrice] as num?) == null) {
        throw Exception('يجب إدخال الأسعار قبل الترحيل المحاسبي.');
      }

      transaction.update(docRef, {
        InterBranchInvoiceFields.status:
            InterBranchInvoiceStatus.postedToAccounting.value,
        InterBranchInvoiceFields.accountingReference: reference,
        InterBranchInvoiceFields.postedAt: FieldValue.serverTimestamp(),
        if ((notes ?? '').trim().isNotEmpty)
          InterBranchInvoiceFields.accountantNotes: notes!.trim(),
        InterBranchInvoiceFields.lastUpdated: FieldValue.serverTimestamp(),
        InterBranchInvoiceFields.history: FieldValue.arrayUnion([
          _historyEntry(
            action: 'posted_to_accounting',
            message: 'تم إدخال الفاتورة في النظام المحاسبي',
            actor: actor,
            note: notes,
            changes: {'accounting_reference': reference},
          ),
        ]),
      });
    });
    final savedInvoice = await docRef.get();
    final savedData = savedInvoice.data();
    if (savedData != null) {
      await _notifySafely(
        () => _notificationService.notifyInterBranchAccountingPosted(
          invoiceId: invoiceId,
          invoiceData: savedData,
        ),
      );
    }
  }

  Future<void> requestCancellation({
    required String invoiceId,
    required String reason,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) throw Exception('سبب الإلغاء مطلوب.');

    final actor = await _getCurrentActor();
    final docRef = _collection.doc(invoiceId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final data = _dataOrThrow(snapshot);
      _ensureLegacyWorkflow(data);
      final status = interBranchInvoiceStatusFromString(
        data[InterBranchInvoiceFields.status]?.toString(),
      );
      if (!status.hasInvoice || status == InterBranchInvoiceStatus.cancelled) {
        throw Exception('لا يمكن طلب إلغاء قبل إنشاء الفاتورة.');
      }
      if (status == InterBranchInvoiceStatus.cancellationPendingApprovals ||
          status == InterBranchInvoiceStatus.editPendingApprovals) {
        throw Exception('يوجد طلب موافقة معلق بالفعل.');
      }
      final party = _approvalParty(actor, data);
      if (party == 'collector') {
        throw Exception('إلغاء الفاتورة متاح للفرعين والمحاسب فقط.');
      }
      transaction.update(docRef, {
        InterBranchInvoiceFields.previousStatus: status.value,
        InterBranchInvoiceFields.status:
            InterBranchInvoiceStatus.cancellationPendingApprovals.value,
        InterBranchInvoiceFields.cancellationRequest: {
          'reason': cleanReason,
          'requested_by': actor['uid'],
          'requested_by_name': actor['name'],
          'requested_by_role': actor['role'],
          'requested_party': party,
          'requested_at': Timestamp.now(),
        },
        InterBranchInvoiceFields.cancellationApprovals: {
          party: _approval(actor, approved: true, note: cleanReason),
        },
        InterBranchInvoiceFields.lastUpdated: FieldValue.serverTimestamp(),
        InterBranchInvoiceFields.history: FieldValue.arrayUnion([
          _historyEntry(
            action: 'cancellation_requested',
            message: 'تم طلب إلغاء الفاتورة وبدء دورة الموافقات',
            actor: actor,
            note: cleanReason,
          ),
        ]),
      });
    });
    final savedInvoice = await docRef.get();
    final savedData = savedInvoice.data();
    if (savedData != null) {
      await _notifySafely(
        () => _notificationService.notifyInterBranchSharedRequest(
          invoiceId: invoiceId,
          invoiceData: savedData,
          isCancellation: true,
        ),
      );
    }
  }

  Future<void> approveCancellation({
    required String invoiceId,
    required bool approved,
    String? reason,
  }) async {
    final cleanReason = reason?.trim() ?? '';
    if (!approved && cleanReason.isEmpty) {
      throw Exception('سبب رفض الإلغاء مطلوب.');
    }
    await _approveSharedRequest(
      invoiceId: invoiceId,
      approved: approved,
      reason: cleanReason,
      requestStatus: InterBranchInvoiceStatus.cancellationPendingApprovals,
      approvalField: InterBranchInvoiceFields.cancellationApprovals,
      completedStatus: InterBranchInvoiceStatus.cancelled,
      rejectedStatus: null,
      approvedAction: 'cancellation_approved',
      rejectedAction: 'cancellation_rejected',
      completedAction: 'cancelled',
      approvedMessage: 'تمت الموافقة على طلب الإلغاء',
      rejectedMessage: 'تم رفض طلب الإلغاء',
      completedMessage: 'اكتملت الموافقات وتم إلغاء الفاتورة',
    );
    final savedInvoice = await _collection.doc(invoiceId).get();
    final savedData = savedInvoice.data();
    if (savedData != null) {
      await _notifySafely(
        () => _notificationService.notifyInterBranchSharedDecision(
          invoiceId: invoiceId,
          invoiceData: savedData,
          isCancellation: true,
          approved: approved,
        ),
      );
    }
  }

  Future<void> requestEdit({
    required String invoiceId,
    required String reason,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) throw Exception('سبب طلب التعديل مطلوب.');
    final actor = await _getCurrentActor();
    final docRef = _collection.doc(invoiceId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final data = _dataOrThrow(snapshot);
      _ensureLegacyWorkflow(data);
      final status = interBranchInvoiceStatusFromString(
        data[InterBranchInvoiceFields.status]?.toString(),
      );
      if (!status.hasInvoice || status == InterBranchInvoiceStatus.cancelled) {
        throw Exception('لا يمكن طلب تعديل قبل إنشاء الفاتورة.');
      }
      if (status == InterBranchInvoiceStatus.cancellationPendingApprovals ||
          status == InterBranchInvoiceStatus.editPendingApprovals) {
        throw Exception('يوجد طلب موافقة معلق بالفعل.');
      }
      final party = _approvalParty(actor, data, allowCollector: true);
      transaction.update(docRef, {
        InterBranchInvoiceFields.previousStatus: status.value,
        InterBranchInvoiceFields.status:
            InterBranchInvoiceStatus.editPendingApprovals.value,
        InterBranchInvoiceFields.editRequest: {
          'reason': cleanReason,
          'requested_by': actor['uid'],
          'requested_by_name': actor['name'],
          'requested_by_role': actor['role'],
          'requested_party': party,
          'requested_at': Timestamp.now(),
        },
        InterBranchInvoiceFields.editApprovals:
            requiredApprovalParties.contains(party)
            ? {party: _approval(actor, approved: true, note: cleanReason)}
            : <String, dynamic>{},
        InterBranchInvoiceFields.lastUpdated: FieldValue.serverTimestamp(),
        InterBranchInvoiceFields.history: FieldValue.arrayUnion([
          _historyEntry(
            action: 'edit_requested',
            message: 'تم طلب تعديل الفاتورة وبدء دورة الموافقات',
            actor: actor,
            note: cleanReason,
          ),
        ]),
      });
    });
    final savedInvoice = await docRef.get();
    final savedData = savedInvoice.data();
    if (savedData != null) {
      await _notifySafely(
        () => _notificationService.notifyInterBranchSharedRequest(
          invoiceId: invoiceId,
          invoiceData: savedData,
          isCancellation: false,
        ),
      );
    }
  }

  Future<void> approveEdit({
    required String invoiceId,
    required bool approved,
    String? reason,
  }) async {
    final cleanReason = reason?.trim() ?? '';
    if (!approved && cleanReason.isEmpty) {
      throw Exception('سبب رفض التعديل مطلوب.');
    }
    await _approveSharedRequest(
      invoiceId: invoiceId,
      approved: approved,
      reason: cleanReason,
      requestStatus: InterBranchInvoiceStatus.editPendingApprovals,
      approvalField: InterBranchInvoiceFields.editApprovals,
      completedStatus: InterBranchInvoiceStatus.editApproved,
      rejectedStatus: InterBranchInvoiceStatus.editRejected,
      approvedAction: 'edit_approved',
      rejectedAction: 'edit_rejected',
      completedAction: 'edit_fully_approved',
      approvedMessage: 'تمت الموافقة على طلب التعديل',
      rejectedMessage: 'تم رفض طلب التعديل',
      completedMessage: 'اكتملت الموافقات على طلب التعديل',
    );
    final savedInvoice = await _collection.doc(invoiceId).get();
    final savedData = savedInvoice.data();
    if (savedData != null) {
      await _notifySafely(
        () => _notificationService.notifyInterBranchSharedDecision(
          invoiceId: invoiceId,
          invoiceData: savedData,
          isCancellation: false,
          approved: approved,
        ),
      );
    }
  }

  Future<void> _approveSharedRequest({
    required String invoiceId,
    required bool approved,
    required String reason,
    required InterBranchInvoiceStatus requestStatus,
    required String approvalField,
    required InterBranchInvoiceStatus completedStatus,
    required InterBranchInvoiceStatus? rejectedStatus,
    required String approvedAction,
    required String rejectedAction,
    required String completedAction,
    required String approvedMessage,
    required String rejectedMessage,
    required String completedMessage,
  }) async {
    final actor = await _getCurrentActor();
    final docRef = _collection.doc(invoiceId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final data = _dataOrThrow(snapshot);
      _ensureLegacyWorkflow(data);
      _ensureStatus(
        data,
        requestStatus,
        'لا يوجد طلب موافقة مطابق لهذه العملية.',
      );
      final party = _approvalParty(actor, data);
      final approvals = _map(data[approvalField]);
      if (approvals[party] is Map) {
        throw Exception('تم تسجيل موافقتك مسبقاً.');
      }

      if (!approved) {
        final previousStatus = data[InterBranchInvoiceFields.previousStatus]
            ?.toString();
        transaction.update(docRef, {
          InterBranchInvoiceFields.status:
              (rejectedStatus ??
                      interBranchInvoiceStatusFromString(previousStatus))
                  .value,
          approvalField: {
            ...approvals,
            party: _approval(actor, approved: false, note: reason),
          },
          InterBranchInvoiceFields.lastUpdated: FieldValue.serverTimestamp(),
          InterBranchInvoiceFields.history: FieldValue.arrayUnion([
            _historyEntry(
              action: rejectedAction,
              message: rejectedMessage,
              actor: actor,
              note: reason,
            ),
          ]),
        });
        return;
      }

      final updatedApprovals = {
        ...approvals,
        party: _approval(actor, approved: true, note: reason),
      };
      final complete = requiredApprovalParties.every(
        (requiredParty) => updatedApprovals[requiredParty] is Map,
      );
      transaction.update(docRef, {
        approvalField: updatedApprovals,
        InterBranchInvoiceFields.status: complete
            ? completedStatus.value
            : requestStatus.value,
        InterBranchInvoiceFields.lastUpdated: FieldValue.serverTimestamp(),
        InterBranchInvoiceFields.history: FieldValue.arrayUnion([
          _historyEntry(
            action: complete ? completedAction : approvedAction,
            message: complete ? completedMessage : approvedMessage,
            actor: actor,
            note: reason,
          ),
        ]),
      });
    });
  }

  Future<Map<String, String>> _getCurrentActor() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return {'uid': '', 'name': 'مستخدم غير معروف', 'role': 'unknown'};
    }

    final doc = await _firestore.collection('users').doc(uid).get();
    final data = doc.data();
    return {
      'uid': uid,
      'name': data?['name']?.toString() ?? 'مستخدم غير معروف',
      'role': data?['role']?.toString() ?? 'unknown',
      'branchId': data?['branchId']?.toString() ?? '',
    };
  }

  Map<String, dynamic> _historyEntry({
    required String action,
    required String message,
    required Map<String, String> actor,
    String? note,
    Map<String, dynamic>? changes,
  }) {
    return {
      'action': action,
      'message': message,
      'actor_id': actor['uid'],
      'actor_name': actor['name'],
      'actor_role': actor['role'],
      'timestamp': Timestamp.now(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (changes != null) 'changes': changes,
    };
  }

  Map<String, dynamic> _approval(
    Map<String, String> actor, {
    required bool approved,
    String? note,
  }) {
    return {
      'approved': approved,
      'user_id': actor['uid'],
      'user_name': actor['name'],
      'user_role': actor['role'],
      'note': note ?? '',
      'approved_at': Timestamp.now(),
    };
  }

  Map<String, dynamic> _dataOrThrow(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) throw Exception('الفاتورة غير موجودة.');
    return data;
  }

  void _ensureLegacyWorkflow(Map<String, dynamic> data) {
    final version =
        (data[InterBranchInvoiceFields.workflowVersion] as num?)?.toInt() ?? 1;
    if (version >= 2) {
      throw Exception('يجب تنفيذ هذا الإجراء الآمن عبر خادم أوامر الفواتير.');
    }
  }

  void _ensureStatus(
    Map<String, dynamic> data,
    InterBranchInvoiceStatus expected,
    String message,
  ) {
    final current = interBranchInvoiceStatusFromString(
      data[InterBranchInvoiceFields.status]?.toString(),
    );
    if (current != expected) throw Exception(message);
  }

  void _validateManagerBranch(Map<String, String> actor, String branchId) {
    _validateRole(actor, UserRole.manager, 'هذا الإجراء متاح لمدير الفرع فقط.');
    if (actor['branchId'] != branchId) {
      throw Exception('لا يمكن تنفيذ الإجراء إلا من مدير الفرع المعني.');
    }
  }

  void _validateRole(
    Map<String, String> actor,
    UserRole role,
    String message, {
    bool alsoAllowAdmin = false,
  }) {
    if (actor['role'] == role.name) return;
    if (alsoAllowAdmin && actor['role'] == UserRole.admin.name) return;
    throw Exception(message);
  }

  void _validateSelectedSendingBranch(
    Map<String, dynamic> data,
    String? branchId,
  ) {
    if (branchId == null || branchId.isEmpty) return;
    if (data[InterBranchInvoiceFields.sendingBranchId]?.toString() !=
        branchId) {
      throw Exception('لا يمكن تنفيذ الإجراء إلا على فواتير الفرع المحدد.');
    }
  }

  String _approvalParty(
    Map<String, String> actor,
    Map<String, dynamic> data, {
    bool allowCollector = false,
  }) {
    final role = actor['role'];
    final branchId = actor['branchId'];
    if (role == UserRole.accountant.name) {
      return 'accountant';
    }
    if (allowCollector && role == UserRole.collector.name) return 'collector';
    if (role == UserRole.manager.name &&
        branchId == data[InterBranchInvoiceFields.sendingBranchId]) {
      return 'supplyingManager';
    }
    if (role == UserRole.manager.name &&
        branchId == data[InterBranchInvoiceFields.receivingBranchId]) {
      return 'receivingManager';
    }
    throw Exception('هذا المستخدم ليس من الأطراف المخولة لهذا الإجراء.');
  }

  double _quantityForTotals(Map<String, dynamic> data) {
    return (data[InterBranchInvoiceFields.receivedQuantity] as num?)
            ?.toDouble() ??
        (data[InterBranchInvoiceFields.approvedQuantity] as num?)?.toDouble() ??
        (data[InterBranchInvoiceFields.requestedQuantity] as num?)
            ?.toDouble() ??
        0;
  }

  List<InterBranchInvoiceItem> _itemsFromData(Map<String, dynamic> data) {
    return InterBranchInvoiceRead(id: '', data: data).items;
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(value);
  }
}
