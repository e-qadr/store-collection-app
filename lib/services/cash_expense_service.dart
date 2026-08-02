import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:store_collection_app/models/cash_expense_request_model.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/services/external_invoice_upload_service.dart';
import 'package:store_collection_app/services/notification_service.dart';

class CashExpenseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ExternalInvoiceUploadService _invoiceUploadService =
      ExternalInvoiceUploadService();
  final NotificationService _notificationService = NotificationService();

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(CashExpenseFields.collection);

  Future<void> _notifySafely(Future<void> Function() notification) async {
    try {
      await notification();
    } catch (_) {
      // لا يجب أن يمنع فشل الإشعار تنفيذ العملية الأساسية.
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchRequests({
    required UserRole role,
    String? branchId,
  }) {
    if (role == UserRole.admin || branchId == null || branchId.isEmpty) {
      return _collection.limit(0).snapshots();
    }
    return _collection
        .where(CashExpenseFields.branchId, isEqualTo: branchId)
        .snapshots();
  }

  Future<void> createRequest({
    required String branchId,
    required String branchName,
    required String title,
    required String description,
    required double amount,
    required String currency,
    String? notes,
    Uint8List? invoiceFileBytes,
    String? invoiceFileName,
    String? invoiceContentType,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) throw Exception('عنوان المصروف مطلوب.');
    if (amount <= 0) throw Exception('مبلغ المصروف يجب أن يكون أكبر من صفر.');

    final actor = await _getCurrentActor();
    _validateManagerBranch(actor, branchId);

    final doc = _collection.doc();
    Map<String, dynamic>? initialInvoiceAttachment;
    if (invoiceFileBytes != null && invoiceFileBytes.isNotEmpty) {
      final fileName = (invoiceFileName ?? '').trim();
      if (fileName.isEmpty) throw Exception('اسم ملف الفاتورة غير صالح.');
      final uploadedFile = await _invoiceUploadService.uploadInvoice(
        requestId: doc.id,
        fileBytes: invoiceFileBytes,
        fileName: fileName,
        contentType: invoiceContentType ?? _contentTypeFromName(fileName),
      );
      initialInvoiceAttachment = uploadedFile.toMap();
    }

    await _firestore.runTransaction((transaction) async {
      final branchRef = _firestore.collection('branches').doc(branchId);
      final counterRef = _firestore
          .collection(CashExpenseFields.counterCollection)
          .doc(branchId);
      final branchSnapshot = await transaction.get(branchRef);
      if (!branchSnapshot.exists) throw Exception('الفرع المحدد غير موجود.');

      final branchCode = (branchSnapshot.data()?['branch_code'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      if (branchCode.isEmpty) {
        throw Exception('يجب ضبط رمز الفرع قبل إنشاء سند الصرف.');
      }

      final counterSnapshot = await transaction.get(counterRef);
      final rawNextNumber =
          (counterSnapshot.data()?['next_number'] as num?)?.toInt() ?? 1;
      final nextNumber = rawNextNumber < 1 ? 1 : rawNextNumber;
      if (nextNumber > 9999) {
        throw Exception('وصل ترقيم سندات الصرف لهذا الفرع إلى الحد الأقصى.');
      }
      final requestNumber =
          '$branchCode${nextNumber.toString().padLeft(4, '0')}';

      transaction.set(doc, {
        'id': doc.id,
        CashExpenseFields.requestNumber: requestNumber,
        'branch_code': branchCode,
        CashExpenseFields.branchId: branchId,
        CashExpenseFields.branchName: branchName,
        CashExpenseFields.title: cleanTitle,
        CashExpenseFields.description: description.trim(),
        CashExpenseFields.requestedAmount: amount,
        CashExpenseFields.approvedAmount: amount,
        CashExpenseFields.currency: currency.trim().isEmpty
            ? 'YER'
            : currency.trim().toUpperCase(),
        CashExpenseFields.status:
            CashExpenseStatus.pendingGeneralManagerReview.value,
        if ((notes ?? '').trim().isNotEmpty)
          CashExpenseFields.managerNotes: notes!.trim(),
        if (initialInvoiceAttachment != null)
          CashExpenseFields.invoiceAttachment: initialInvoiceAttachment,
        CashExpenseFields.createdBy: actor['uid'],
        CashExpenseFields.createdAt: FieldValue.serverTimestamp(),
        CashExpenseFields.lastUpdated: FieldValue.serverTimestamp(),
        CashExpenseFields.history: [
          _historyEntry(
            action: 'request_created',
            message: 'تم إنشاء طلب صرف نقدي',
            actor: actor,
            note: notes,
            changes: {
              'amount': amount,
              'request_number': requestNumber,
              'has_invoice': initialInvoiceAttachment != null,
            },
          ),
        ],
      });
      transaction.set(counterRef, {
        'branch_id': branchId,
        'branch_code': branchCode,
        'next_number': nextNumber + 1,
        'last_request_number': requestNumber,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
    final savedRequest = await doc.get();
    final savedData = savedRequest.data();
    if (savedData != null) {
      await _notifySafely(
        () => _notificationService.notifyCashExpenseCreated(
          requestId: doc.id,
          requestData: savedData,
        ),
      );
    }
  }

  Future<void> submitGeneralManagerDecision({
    required String requestId,
    required bool approved,
    required double approvedAmount,
    required String title,
    required String description,
    String? branchId,
    String? notes,
  }) async {
    final cleanNotes = notes?.trim() ?? '';
    if (!approved && cleanNotes.isEmpty) {
      throw Exception('سبب الرفض مطلوب.');
    }
    if (approvedAmount <= 0) {
      throw Exception('المبلغ المعتمد يجب أن يكون أكبر من صفر.');
    }

    final actor = await _getCurrentActor();
    _validateRole(
      actor,
      UserRole.collector,
      'هذا الإجراء متاح للمدير العام فقط.',
    );
    final docRef = _collection.doc(requestId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final data = _dataOrThrow(snapshot);
      _validateSelectedBranch(data, branchId);
      _ensureStatus(
        data,
        CashExpenseStatus.pendingGeneralManagerReview,
        'لا يمكن مراجعة هذا الطلب في حالته الحالية.',
      );

      if (!approved) {
        transaction.update(docRef, {
          CashExpenseFields.status:
              CashExpenseStatus.rejectedByGeneralManager.value,
          CashExpenseFields.rejectionReason: cleanNotes,
          CashExpenseFields.generalManagerNotes: cleanNotes,
          CashExpenseFields.reviewedBy: actor['uid'],
          CashExpenseFields.reviewedAt: FieldValue.serverTimestamp(),
          CashExpenseFields.lastUpdated: FieldValue.serverTimestamp(),
          CashExpenseFields.history: FieldValue.arrayUnion([
            _historyEntry(
              action: 'rejected_by_general_manager',
              message: 'رفض المدير العام طلب الصرف النقدي',
              actor: actor,
              note: cleanNotes,
            ),
          ]),
        });
        return;
      }

      final invoiceAttachment = data[CashExpenseFields.invoiceAttachment];
      final hasInvoice =
          invoiceAttachment is Map &&
          (invoiceAttachment['url']?.toString() ?? '').isNotEmpty;
      final nextStatus = hasInvoice
          ? CashExpenseStatus.pendingAccountingApproval
          : CashExpenseStatus.pendingInvoiceAttachment;

      transaction.update(docRef, {
        CashExpenseFields.status: nextStatus.value,
        CashExpenseFields.title: title.trim().isEmpty
            ? data[CashExpenseFields.title]
            : title.trim(),
        CashExpenseFields.description: description.trim(),
        CashExpenseFields.approvedAmount: approvedAmount,
        if (cleanNotes.isNotEmpty)
          CashExpenseFields.generalManagerNotes: cleanNotes,
        CashExpenseFields.reviewedBy: actor['uid'],
        CashExpenseFields.reviewedAt: FieldValue.serverTimestamp(),
        CashExpenseFields.lastUpdated: FieldValue.serverTimestamp(),
        CashExpenseFields.history: FieldValue.arrayUnion([
          _historyEntry(
            action: 'approved_by_general_manager',
            message: hasInvoice
                ? 'اعتمد المدير العام سند الصرف النقدي وأرسله للمحاسب'
                : 'اعتمد المدير العام سند الصرف النقدي',
            actor: actor,
            note: cleanNotes,
            changes: {
              'approved_amount': approvedAmount,
              'has_invoice': hasInvoice,
            },
          ),
        ]),
      });
    });
    final savedRequest = await docRef.get();
    final savedData = savedRequest.data();
    if (savedData != null) {
      await _notifySafely(
        () => _notificationService.notifyCashExpenseGeneralManagerDecision(
          requestId: requestId,
          requestData: savedData,
          approved: approved,
        ),
      );
    }
  }

  Future<void> attachInvoiceAndApprove({
    required String requestId,
    required Uint8List fileBytes,
    required String fileName,
    String? contentType,
    String? branchId,
    String? notes,
  }) async {
    if (fileBytes.isEmpty) throw Exception('ملف الفاتورة غير صالح.');

    final actor = await _getCurrentActor();
    final docRef = _collection.doc(requestId);
    final snapshot = await docRef.get();
    final data = _dataOrThrow(snapshot);
    _validateManagerBranch(
      actor,
      data[CashExpenseFields.branchId]?.toString() ?? '',
    );
    _validateSelectedBranch(data, branchId);
    _ensureStatus(
      data,
      CashExpenseStatus.pendingInvoiceAttachment,
      'لا يمكن إرفاق الفاتورة قبل اعتماد المدير العام.',
    );

    final uploadedFile = await _invoiceUploadService.uploadInvoice(
      requestId: requestId,
      fileBytes: fileBytes,
      fileName: fileName,
      contentType: contentType ?? _contentTypeFromName(fileName),
    );

    await _firestore.runTransaction((transaction) async {
      final fresh = await transaction.get(docRef);
      final freshData = _dataOrThrow(fresh);
      _ensureStatus(
        freshData,
        CashExpenseStatus.pendingInvoiceAttachment,
        'لا يمكن إرفاق الفاتورة في حالة هذا الطلب الحالية.',
      );
      transaction.update(docRef, {
        CashExpenseFields.status:
            CashExpenseStatus.pendingAccountingApproval.value,
        CashExpenseFields.invoiceAttachment: uploadedFile.toMap(),
        if ((notes ?? '').trim().isNotEmpty)
          CashExpenseFields.invoiceNotes: notes!.trim(),
        CashExpenseFields.invoiceApprovedBy: actor['uid'],
        CashExpenseFields.invoiceApprovedAt: FieldValue.serverTimestamp(),
        CashExpenseFields.lastUpdated: FieldValue.serverTimestamp(),
        CashExpenseFields.history: FieldValue.arrayUnion([
          _historyEntry(
            action: 'invoice_attached',
            message: 'أرفق مدير الفرع الفاتورة واعتمدها',
            actor: actor,
            note: notes,
            changes: {'file_name': uploadedFile.name},
          ),
        ]),
      });
    });
    final savedRequest = await docRef.get();
    final savedData = savedRequest.data();
    if (savedData != null) {
      await _notifySafely(
        () => _notificationService.notifyCashExpenseInvoiceReady(
          requestId: requestId,
          requestData: savedData,
        ),
      );
    }
  }

  Future<void> approveWithoutInvoice({
    required String requestId,
    String? branchId,
    String? notes,
  }) async {
    final actor = await _getCurrentActor();
    final docRef = _collection.doc(requestId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final data = _dataOrThrow(snapshot);
      _validateManagerBranch(
        actor,
        data[CashExpenseFields.branchId]?.toString() ?? '',
      );
      _validateSelectedBranch(data, branchId);
      _ensureStatus(
        data,
        CashExpenseStatus.pendingInvoiceAttachment,
        'لا يمكن اعتماد عدم وجود ملف في حالة هذا الطلب الحالية.',
      );

      transaction.update(docRef, {
        CashExpenseFields.status:
            CashExpenseStatus.pendingAccountingApproval.value,
        if ((notes ?? '').trim().isNotEmpty)
          CashExpenseFields.invoiceNotes: notes!.trim(),
        CashExpenseFields.invoiceApprovedBy: actor['uid'],
        CashExpenseFields.invoiceApprovedAt: FieldValue.serverTimestamp(),
        CashExpenseFields.lastUpdated: FieldValue.serverTimestamp(),
        CashExpenseFields.history: FieldValue.arrayUnion([
          _historyEntry(
            action: 'invoice_not_available',
            message: 'اعتمد مدير الفرع السند بدون ملف مرفق',
            actor: actor,
            note: notes,
            changes: {'has_invoice': false},
          ),
        ]),
      });
    });
    final savedRequest = await docRef.get();
    final savedData = savedRequest.data();
    if (savedData != null) {
      await _notifySafely(
        () => _notificationService.notifyCashExpenseInvoiceReady(
          requestId: requestId,
          requestData: savedData,
        ),
      );
    }
  }

  Future<void> approveAccounting({
    required String requestId,
    required String accountingReference,
    String? branchId,
    String? notes,
  }) async {
    final reference = accountingReference.trim();
    if (reference.isEmpty) throw Exception('المرجع المحاسبي مطلوب.');

    final actor = await _getCurrentActor();
    _validateRole(
      actor,
      UserRole.accountant,
      'الإدخال والاعتماد المحاسبي متاح للمحاسب فقط.',
    );
    final docRef = _collection.doc(requestId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final data = _dataOrThrow(snapshot);
      _validateSelectedBranch(data, branchId);
      _ensureStatus(
        data,
        CashExpenseStatus.pendingAccountingApproval,
        'لا يمكن الاعتماد المحاسبي قبل إرفاق الفاتورة.',
      );

      transaction.update(docRef, {
        CashExpenseFields.status: CashExpenseStatus.approvedByAccountant.value,
        CashExpenseFields.accountingReference: reference,
        if ((notes ?? '').trim().isNotEmpty)
          CashExpenseFields.accountantNotes: notes!.trim(),
        CashExpenseFields.approvedBy: actor['uid'],
        CashExpenseFields.approvedAt: FieldValue.serverTimestamp(),
        CashExpenseFields.lastUpdated: FieldValue.serverTimestamp(),
        CashExpenseFields.history: FieldValue.arrayUnion([
          _historyEntry(
            action: 'accountant_approved',
            message: 'أدخل المحاسب المصروف في النظام المحاسبي واعتمده نهائياً',
            actor: actor,
            note: notes,
            changes: {'accounting_reference': reference},
          ),
        ]),
      });
    });
    final savedRequest = await docRef.get();
    final savedData = savedRequest.data();
    if (savedData != null) {
      await _notifySafely(
        () => _notificationService.notifyCashExpenseAccountingApproved(
          requestId: requestId,
          requestData: savedData,
        ),
      );
    }
  }

  Future<void> updateManagerRequestAfterEditApproval({
    required String requestId,
    required String title,
    required String description,
    required double amount,
    String? branchId,
    String? notes,
    Uint8List? invoiceFileBytes,
    String? invoiceFileName,
    String? invoiceContentType,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) throw Exception('عنوان المصروف مطلوب.');
    if (amount <= 0) throw Exception('مبلغ المصروف يجب أن يكون أكبر من صفر.');

    final actor = await _getCurrentActor();
    final docRef = _collection.doc(requestId);
    final snapshot = await docRef.get();
    final data = _dataOrThrow(snapshot);
    _validateManagerBranch(
      actor,
      data[CashExpenseFields.branchId]?.toString() ?? '',
    );
    _validateSelectedBranch(data, branchId);
    _ensureStatus(
      data,
      CashExpenseStatus.pendingGeneralManagerReview,
      'لا يمكن تعديل الطلب في حالته الحالية.',
    );
    if (!_allEditApprovalsApproved(data)) {
      throw Exception('لا يمكن التعديل قبل اكتمال موافقات طلب التعديل.');
    }

    Map<String, dynamic>? replacementInvoiceAttachment;
    if (invoiceFileBytes != null && invoiceFileBytes.isNotEmpty) {
      final fileName = (invoiceFileName ?? '').trim();
      if (fileName.isEmpty) throw Exception('اسم ملف الفاتورة غير صالح.');
      final uploadedFile = await _invoiceUploadService.uploadInvoice(
        requestId: requestId,
        fileBytes: invoiceFileBytes,
        fileName: fileName,
        contentType: invoiceContentType ?? _contentTypeFromName(fileName),
      );
      replacementInvoiceAttachment = uploadedFile.toMap();
    }

    await _firestore.runTransaction((transaction) async {
      final fresh = await transaction.get(docRef);
      final freshData = _dataOrThrow(fresh);
      _ensureStatus(
        freshData,
        CashExpenseStatus.pendingGeneralManagerReview,
        'لا يمكن تعديل الطلب في حالته الحالية.',
      );
      if (!_allEditApprovalsApproved(freshData)) {
        throw Exception('لا يمكن التعديل قبل اكتمال موافقات طلب التعديل.');
      }

      transaction.update(docRef, {
        CashExpenseFields.title: cleanTitle,
        CashExpenseFields.description: description.trim(),
        CashExpenseFields.requestedAmount: amount,
        CashExpenseFields.approvedAmount: amount,
        if ((notes ?? '').trim().isNotEmpty)
          CashExpenseFields.managerNotes: notes!.trim(),
        if (replacementInvoiceAttachment != null)
          CashExpenseFields.invoiceAttachment: replacementInvoiceAttachment,
        CashExpenseFields.previousStatus: FieldValue.delete(),
        CashExpenseFields.editRequest: FieldValue.delete(),
        CashExpenseFields.editApprovals: FieldValue.delete(),
        CashExpenseFields.lastUpdated: FieldValue.serverTimestamp(),
        CashExpenseFields.history: FieldValue.arrayUnion([
          _historyEntry(
            action: 'manager_updated_after_edit_approval',
            message: 'عدل مدير الفرع سند الصرف بعد اكتمال الموافقات',
            actor: actor,
            note: notes,
            changes: {
              'amount': amount,
              'has_replacement_invoice': replacementInvoiceAttachment != null,
            },
          ),
        ]),
      });
    });
    final savedRequest = await docRef.get();
    final savedData = savedRequest.data();
    if (savedData != null) {
      await _notifySafely(
        () => _notificationService.notifyCashExpenseManagerUpdatedAfterEdit(
          requestId: requestId,
          requestData: savedData,
        ),
      );
    }
  }

  Future<void> requestEdit({
    required String requestId,
    required String reason,
    String? branchId,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) throw Exception('سبب طلب التعديل مطلوب.');

    final actor = await _getCurrentActor();
    final docRef = _collection.doc(requestId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final data = _dataOrThrow(snapshot);
      _validateSelectedBranch(data, branchId);
      final party = _editPartyForActor(actor, data);
      final currentStatus = cashExpenseStatusFromString(
        data[CashExpenseFields.status]?.toString(),
      );
      if (currentStatus.isFinal) {
        throw Exception('لا يمكن طلب تعديل بعد الإقفال النهائي أو الرفض.');
      }
      if (currentStatus == CashExpenseStatus.editPendingApprovals) {
        throw Exception('يوجد طلب تعديل بانتظار الموافقات حالياً.');
      }

      transaction.update(docRef, {
        CashExpenseFields.status: CashExpenseStatus.editPendingApprovals.value,
        CashExpenseFields.previousStatus: currentStatus.value,
        CashExpenseFields.editRequest: {
          'reason': cleanReason,
          'requested_by': actor['uid'],
          'requested_by_name': actor['name'],
          'requested_role': actor['role'],
          'requested_party': party,
          'requested_at': Timestamp.now(),
        },
        CashExpenseFields.editApprovals: {
          party: _editApprovalEntry(actor: actor, approved: true),
        },
        CashExpenseFields.lastUpdated: FieldValue.serverTimestamp(),
        CashExpenseFields.history: FieldValue.arrayUnion([
          _historyEntry(
            action: 'edit_requested',
            message: 'تم طلب تعديل سند الصرف النقدي',
            actor: actor,
            note: cleanReason,
            changes: {'previous_status': currentStatus.value, 'party': party},
          ),
        ]),
      });
    });
    final savedRequest = await docRef.get();
    final savedData = savedRequest.data();
    if (savedData != null) {
      await _notifySafely(
        () => _notificationService.notifyCashExpenseEditRequested(
          requestId: requestId,
          requestData: savedData,
        ),
      );
    }
  }

  Future<void> submitEditApproval({
    required String requestId,
    required bool approved,
    String? branchId,
    String? notes,
  }) async {
    final cleanNotes = notes?.trim() ?? '';
    if (!approved && cleanNotes.isEmpty) {
      throw Exception('سبب رفض طلب التعديل مطلوب.');
    }

    final actor = await _getCurrentActor();
    final docRef = _collection.doc(requestId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final data = _dataOrThrow(snapshot);
      _validateSelectedBranch(data, branchId);
      _ensureStatus(
        data,
        CashExpenseStatus.editPendingApprovals,
        'لا يوجد طلب تعديل بانتظار الموافقات.',
      );
      final party = _editPartyForActor(actor, data);
      final approvals = _editApprovals(data);
      if (approvals.containsKey(party)) {
        throw Exception('تم تسجيل قرار هذا الدور على طلب التعديل مسبقاً.');
      }

      final updatedApprovals = Map<String, dynamic>.from(approvals)
        ..[party] = _editApprovalEntry(
          actor: actor,
          approved: approved,
          note: cleanNotes,
        );
      final previousStatus = cashExpenseStatusFromString(
        data[CashExpenseFields.previousStatus]?.toString(),
      );
      final everyoneApproved = _requiredEditParties.every((party) {
        final entry = updatedApprovals[party];
        return entry is Map && entry['approved'] == true;
      });

      if (!approved) {
        transaction.update(docRef, {
          CashExpenseFields.status: previousStatus.value,
          CashExpenseFields.editApprovals: updatedApprovals,
          CashExpenseFields.lastUpdated: FieldValue.serverTimestamp(),
          CashExpenseFields.history: FieldValue.arrayUnion([
            _historyEntry(
              action: 'edit_rejected',
              message: 'تم رفض طلب تعديل سند الصرف النقدي',
              actor: actor,
              note: cleanNotes,
              changes: {
                'party': party,
                'restored_status': previousStatus.value,
              },
            ),
          ]),
        });
        return;
      }

      transaction.update(docRef, {
        CashExpenseFields.status: everyoneApproved
            ? CashExpenseStatus.pendingGeneralManagerReview.value
            : CashExpenseStatus.editPendingApprovals.value,
        CashExpenseFields.editApprovals: updatedApprovals,
        CashExpenseFields.lastUpdated: FieldValue.serverTimestamp(),
        CashExpenseFields.history: FieldValue.arrayUnion([
          _historyEntry(
            action: everyoneApproved ? 'edit_opened' : 'edit_approved',
            message: everyoneApproved
                ? 'اكتملت موافقات التعديل وأعيد السند للمراجعة'
                : 'تمت الموافقة على طلب تعديل سند الصرف النقدي',
            actor: actor,
            note: cleanNotes,
            changes: {'party': party, 'everyone_approved': everyoneApproved},
          ),
        ]),
      });
    });
    final savedRequest = await docRef.get();
    final savedData = savedRequest.data();
    if (savedData != null) {
      await _notifySafely(
        () => _notificationService.notifyCashExpenseEditDecision(
          requestId: requestId,
          requestData: savedData,
          approved: approved,
        ),
      );
    }
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

  Map<String, dynamic> _dataOrThrow(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) throw Exception('طلب الصرف غير موجود.');
    return data;
  }

  static const List<String> _requiredEditParties = [
    'manager',
    'general_manager',
    'accountant',
  ];

  Map<String, dynamic> _editApprovals(Map<String, dynamic> data) {
    final value = data[CashExpenseFields.editApprovals];
    if (value is! Map) return {};
    return Map<String, dynamic>.from(value);
  }

  bool _allEditApprovalsApproved(Map<String, dynamic> data) {
    final approvals = _editApprovals(data);
    return _requiredEditParties.every((party) {
      final entry = approvals[party];
      return entry is Map && entry['approved'] == true;
    });
  }

  Map<String, dynamic> _editApprovalEntry({
    required Map<String, String> actor,
    required bool approved,
    String? note,
  }) {
    return {
      'approved': approved,
      'actor_id': actor['uid'],
      'actor_name': actor['name'],
      'actor_role': actor['role'],
      'decided_at': Timestamp.now(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };
  }

  String _editPartyForActor(
    Map<String, String> actor,
    Map<String, dynamic> data,
  ) {
    final role = actor['role'];
    if (role == UserRole.manager.name) {
      _validateManagerBranch(
        actor,
        data[CashExpenseFields.branchId]?.toString() ?? '',
      );
      return 'manager';
    }
    if (role == UserRole.collector.name) return 'general_manager';
    if (role == UserRole.accountant.name) return 'accountant';
    throw Exception('هذا الإجراء غير متاح لهذا الدور.');
  }

  void _ensureStatus(
    Map<String, dynamic> data,
    CashExpenseStatus expected,
    String message,
  ) {
    final current = cashExpenseStatusFromString(
      data[CashExpenseFields.status]?.toString(),
    );
    if (current != expected) throw Exception(message);
  }

  void _validateManagerBranch(Map<String, String> actor, String branchId) {
    _validateRole(actor, UserRole.manager, 'هذا الإجراء متاح لمدير الفرع فقط.');
    if (actor['branchId'] != branchId) {
      throw Exception('لا يمكن تنفيذ الإجراء إلا من مدير الفرع المعني.');
    }
  }

  void _validateRole(Map<String, String> actor, UserRole role, String message) {
    if (actor['role'] == role.name) return;
    throw Exception(message);
  }

  void _validateSelectedBranch(Map<String, dynamic> data, String? branchId) {
    if (branchId == null || branchId.isEmpty) return;
    if (data[CashExpenseFields.branchId]?.toString() != branchId) {
      throw Exception('لا يمكن تنفيذ الإجراء إلا على طلبات الفرع المحدد.');
    }
  }

  String _contentTypeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    return 'application/octet-stream';
  }
}
