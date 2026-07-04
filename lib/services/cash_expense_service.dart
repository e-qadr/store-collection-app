import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:store_collection_app/models/cash_expense_request_model.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/services/external_invoice_upload_service.dart';

class CashExpenseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ExternalInvoiceUploadService _invoiceUploadService =
      ExternalInvoiceUploadService();

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(CashExpenseFields.collection);

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
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) throw Exception('عنوان المصروف مطلوب.');
    if (amount <= 0) throw Exception('مبلغ المصروف يجب أن يكون أكبر من صفر.');

    final actor = await _getCurrentActor();
    _validateManagerBranch(actor, branchId);

    final doc = _collection.doc();
    final requestNumber = 'CE-${DateTime.now().millisecondsSinceEpoch}';
    await doc.set({
      'id': doc.id,
      CashExpenseFields.requestNumber: requestNumber,
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
      CashExpenseFields.createdBy: actor['uid'],
      CashExpenseFields.createdAt: FieldValue.serverTimestamp(),
      CashExpenseFields.lastUpdated: FieldValue.serverTimestamp(),
      CashExpenseFields.history: [
        _historyEntry(
          action: 'request_created',
          message: 'تم إنشاء طلب صرف نقدي',
          actor: actor,
          note: notes,
          changes: {'amount': amount},
        ),
      ],
    });
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

      transaction.update(docRef, {
        CashExpenseFields.status:
            CashExpenseStatus.pendingInvoiceAttachment.value,
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
            message: 'اعتمد المدير العام سند الصرف النقدي',
            actor: actor,
            note: cleanNotes,
            changes: {'approved_amount': approvedAmount},
          ),
        ]),
      });
    });
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
