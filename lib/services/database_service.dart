import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:store_collection_app/models/transaction_model.dart';
import 'package:store_collection_app/services/notification_service.dart';
import 'package:store_collection_app/utils/archive_workflow.dart';

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  Future<void> _notifySafely(Future<void> Function() notification) async {
    try {
      await notification();
    } catch (_) {
      // لا يجب أن يؤدي فشل الإشعار إلى التراجع عن عملية السند الأساسية.
    }
  }

  Future<Map<String, String>> _getCurrentActor() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {'name': 'مستخدم غير معروف', 'role': 'unknown'};

    final doc = await _firestore.collection('users').doc(uid).get();
    final data = doc.data();
    return {
      'uid': uid,
      'name': data?['name'] ?? 'مستخدم غير معروف',
      'role': data?['role'] ?? 'unknown',
      'branchId': data?['branchId'] ?? '',
    };
  }

  Map<String, dynamic> _historyEntry({
    required String action,
    required String message,
    required Map<String, String> actor,
    Map<String, dynamic>? changes,
  }) {
    return {
      'action': action,
      'message': message,
      'actor_name': actor['name'],
      'actor_role': actor['role'],
      'timestamp': Timestamp.now(),
      if (changes != null) 'changes': changes,
    };
  }

  // أداة مساعدة لترجمة الحالة للسجل التاريخي
  String _getStatusArabicText(String status) {
    switch (status) {
      case 'pending':
        return 'قيد الانتظار';
      case 'approvedByCollector':
        return 'معتمد من المدير العام';
      case 'approvedByManager':
        return 'معتمد من المدير';
      case 'approvedByAccountant':
        return 'تم الاعتماد النهائي (المحاسب)';
      case 'editRequestedByCollector':
        return 'مطلوب تعديل';
      case 'pendingApprovalOfEdit':
        return 'تعديلات بانتظار المدير';
      case 'rejectedByManager':
        return 'مرفوض من المدير';
      default:
        return 'غير معروف';
    }
  }

  // 1. إضافة سند جديد مع السجل التاريخي (Audit Trail)
  Future<String> addTransaction(TransactionModel transaction) async {
    try {
      final actor = await _getCurrentActor();
      final branchRef = _firestore
          .collection('branches')
          .doc(transaction.branchId);
      final counterRef = _firestore
          .collection('branch_transaction_counters')
          .doc(transaction.branchId);
      final transactionRef = _firestore
          .collection('transactions')
          .doc(transaction.id);

      final transactionNumber = await _firestore.runTransaction((
        firestoreTransaction,
      ) async {
        final branchDoc = await firestoreTransaction.get(branchRef);
        if (!branchDoc.exists) throw Exception('الفرع المحدد غير موجود');

        final branchCode = ((branchDoc.data()?['branch_code'] ?? '') as String)
            .trim()
            .toUpperCase();
        if (branchCode.isEmpty) {
          throw Exception(
            'يجب إضافة رمز فريد للفرع من شاشة إدارة الفروع أولاً',
          );
        }

        final counterDoc = await firestoreTransaction.get(counterRef);
        final nextNumber =
            (counterDoc.data()?['next_number'] as num?)?.toInt() ?? 0;
        if (nextNumber > 999) {
          throw Exception('وصل ترقيم هذا الفرع إلى الحد الأقصى 999');
        }

        final transactionNumber =
            '$branchCode${nextNumber.toString().padLeft(3, '0')}';
        final data = transaction.toJson()
          ..['transaction_number'] = transactionNumber
          ..['branch_code'] = branchCode
          ..['history'] = [
            _historyEntry(
              action: 'created',
              message: 'تم إنشاء السند وإدخاله في النظام',
              actor: actor,
            ),
          ];

        firestoreTransaction.set(transactionRef, data);
        firestoreTransaction.set(counterRef, {
          'branch_id': transaction.branchId,
          'branch_code': branchCode,
          'next_number': nextNumber + 1,
        });
        return transactionNumber;
      });
      final savedTransaction = await transactionRef.get();
      await _notifySafely(
        () => _notificationService.notifyForNewTransaction(
          transactionId: transaction.id,
          transactionData: savedTransaction.data()!,
        ),
      );
      return transactionNumber;
    } catch (e) {
      debugPrint('Database Error: $e');
      rethrow;
    }
  }

  // 2. جلب السندات مع الفلاتر
  Stream<QuerySnapshot> getBranchTransactions({required String branchId}) {
    return _firestore
        .collection('transactions')
        .where('branchId', isEqualTo: branchId)
        .snapshots();
  }

  // 3. تحديث حالة السند (مع تسجيل الحدث في السجل)
  Future<void> updateTransactionStatus({
    required String transactionId,
    required String newStatus,
    String? managerNotes,
  }) async {
    try {
      final actor = await _getCurrentActor();
      String noteMsg = managerNotes != null && managerNotes.isNotEmpty
          ? '\nملاحظة: $managerNotes'
          : '';

      final historyEntry = _historyEntry(
        action: 'status_update',
        message:
            'تغيرت حالة السند إلى: ${_getStatusArabicText(newStatus)}$noteMsg',
        actor: actor,
      );

      Map<String, dynamic> updateData = {
        'status': newStatus,
        'last_updated': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([historyEntry]),
      };

      if (managerNotes != null && managerNotes.isNotEmpty) {
        updateData['manager_notes'] = managerNotes;
      }

      await _firestore
          .collection('transactions')
          .doc(transactionId)
          .update(updateData);
      await _notifySafely(
        () => _notificationService.notifyForStatus(
          transactionId: transactionId,
          newStatus: newStatus,
          message: managerNotes,
        ),
      );
    } catch (e) {
      throw Exception('Failed to update transaction status: $e');
    }
  }

  // 4. تقديم طلب تعديل (تسجيل القديم مقابل الجديد)
  Future<void> submitEditedTransaction({
    required String transactionId,
    required double newAmount,
    required String newCurrency,
    required bool? newAmountMatches,
    double? newCashierAmount,
    required DateTime newDateFrom,
    required DateTime newDateTo,
    required String newNotes,
  }) async {
    try {
      final actor = await _getCurrentActor();
      final doc = await _firestore
          .collection('transactions')
          .doc(transactionId)
          .get();
      final oldData = doc.data() as Map<String, dynamic>;

      final historyEntry = _historyEntry(
        action: 'edit_requested',
        message: 'تم تعديل بيانات السند وطلب الموافقة',
        actor: actor,
        changes: {
          'oldAmount': oldData['amount'],
          'newAmount': newAmount,
          'oldCurrency': oldData['currency'],
          'newCurrency': newCurrency,
          'oldAmountMatches': oldData['amount_matches'],
          'newAmountMatches': newAmountMatches,
          'oldCashierAmount': oldData['cashier_amount'],
          'newCashierAmount': newCashierAmount,
          'oldDateFrom': oldData['dateFrom'],
          'newDateFrom': Timestamp.fromDate(newDateFrom),
          'oldDateTo': oldData['dateTo'],
          'newDateTo': Timestamp.fromDate(newDateTo),
        },
      );

      await _firestore.collection('transactions').doc(transactionId).update({
        'pending_edit_data': {
          'amount': newAmount,
          'currency': newCurrency,
          'amount_matches': newAmountMatches,
          'cashier_amount': newCashierAmount,
          'dateFrom': Timestamp.fromDate(newDateFrom),
          'dateTo': Timestamp.fromDate(newDateTo),
          'notes': newNotes,
        },
        'status': 'pendingApprovalOfEdit',
        'last_updated': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([historyEntry]),
      });
      await _notifySafely(
        () => _notificationService.notifyForStatus(
          transactionId: transactionId,
          newStatus: 'pendingApprovalOfEdit',
        ),
      );
    } catch (e) {
      throw Exception('Failed to submit edited transaction: $e');
    }
  }

  // 5. اعتماد التعديلات
  Future<void> approveEditRequest({
    required String transactionId,
    required Map<String, dynamic> pendingData,
  }) async {
    try {
      final actor = await _getCurrentActor();
      final historyEntry = _historyEntry(
        action: 'edit_approved',
        message: 'تمت الموافقة على التعديلات وتحديث بيانات السند',
        actor: actor,
      );
      final updateData = <String, dynamic>{
        'amount': pendingData['amount'],
        'currency': pendingData['currency'],
        'dateFrom': pendingData['dateFrom'],
        'dateTo': pendingData['dateTo'],
        'notes': pendingData['notes'],
        'status': 'approvedByManager',
        'pending_edit_data': FieldValue.delete(),
        'manager_notes': FieldValue.delete(),
        'last_updated': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([historyEntry]),
      };
      if (pendingData.containsKey('amount_matches')) {
        updateData['amount_matches'] = pendingData['amount_matches'];
      }
      if (pendingData.containsKey('cashier_amount')) {
        updateData['cashier_amount'] =
            pendingData['cashier_amount'] ?? FieldValue.delete();
      }
      await _firestore
          .collection('transactions')
          .doc(transactionId)
          .update(updateData);
      await _notifySafely(
        () => _notificationService.notifyForStatus(
          transactionId: transactionId,
          newStatus: 'approvedByManager',
        ),
      );
    } catch (e) {
      throw Exception('Failed to approve edit: $e');
    }
  }

  // --- دوال المحاسب ---
  Future<void> requestEditByAccountant({
    required String transactionId,
    required String accountantNotes,
  }) async {
    try {
      final actor = await _getCurrentActor();
      final historyEntry = _historyEntry(
        action: 'edit_requested_by_accountant',
        message: 'تم طلب تعديل السند:\n$accountantNotes',
        actor: actor,
      );
      await _firestore.collection('transactions').doc(transactionId).update({
        'status': 'editRequestedByCollector',
        'manager_notes': 'طلب تعديل من المحاسب: $accountantNotes',
        'previous_status': 'approvedByManager',
        'last_updated': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([historyEntry]),
      });
      await _notifySafely(
        () => _notificationService.notifyForStatus(
          transactionId: transactionId,
          newStatus: 'editRequestedByCollector',
          message: accountantNotes,
        ),
      );
    } catch (e) {
      throw Exception('Failed to request edit by accountant: $e');
    }
  }

  Future<void> approveByAccountant(
    String transactionId, {
    String? accountantNotes,
  }) async {
    try {
      final actor = await _getCurrentActor();
      final notes = accountantNotes?.trim() ?? '';
      final historyEntry = _historyEntry(
        action: 'approved_by_accountant',
        message: notes.isEmpty
            ? 'تم الاعتماد والمراجعة النهائية للسند'
            : 'تم الاعتماد والمراجعة النهائية للسند\nملاحظات المحاسب: $notes',
        actor: actor,
      );
      await _firestore.collection('transactions').doc(transactionId).update({
        'status': 'approvedByAccountant',
        if (notes.isNotEmpty) 'accountant_notes': notes,
        'last_updated': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([historyEntry]),
      });
      await _notifySafely(
        () => _notificationService.notifyForStatus(
          transactionId: transactionId,
          newStatus: 'approvedByAccountant',
        ),
      );
    } catch (e) {
      throw Exception('Failed to approve by accountant: $e');
    }
  }

  Future<void> requestTransactionArchive(String transactionId) async {
    final actor = await _getCurrentActor();
    final transactionRef = _firestore
        .collection('transactions')
        .doc(transactionId);

    await _firestore.runTransaction((firestoreTransaction) async {
      final snapshot = await firestoreTransaction.get(transactionRef);
      final data = snapshot.data();
      if (data == null) throw Exception('السند غير موجود');
      _validateArchiveActor(data, actor);

      final archiveStatus = data['archive_status'] as String?;
      if (archiveStatus == 'archived') {
        throw Exception('تمت أرشفة هذا السند مسبقاً');
      }
      if (archiveStatus == 'pending') {
        throw Exception('طلب الأرشفة قيد الاعتماد بالفعل');
      }

      final role = actor['role']!;
      final approvals = <String, dynamic>{role: _archiveApproval(actor)};
      final historyEntry = _historyEntry(
        action: 'archive_requested',
        message: 'تم طلب أرشفة السند واعتماد الطلب من ${actor['name']}',
        actor: actor,
      );

      firestoreTransaction.update(transactionRef, {
        'archive_status': 'pending',
        'archive_requested_by': actor['uid'],
        'archive_requested_at': FieldValue.serverTimestamp(),
        'archive_approvals': approvals,
        'last_updated': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([historyEntry]),
      });
    });

    await _notifySafely(
      () => _notificationService.notifyForArchive(transactionId: transactionId),
    );
  }

  Future<void> approveTransactionArchive(String transactionId) async {
    final actor = await _getCurrentActor();
    final transactionRef = _firestore
        .collection('transactions')
        .doc(transactionId);
    var completed = false;

    await _firestore.runTransaction((firestoreTransaction) async {
      final snapshot = await firestoreTransaction.get(transactionRef);
      final data = snapshot.data();
      if (data == null) throw Exception('السند غير موجود');
      _validateArchiveActor(data, actor);

      if (data['archive_status'] != 'pending') {
        throw Exception('لا يوجد طلب أرشفة قيد الاعتماد');
      }

      final role = actor['role']!;
      if (hasArchiveApproval(data, role)) {
        throw Exception('لقد اعتمدت طلب الأرشفة مسبقاً');
      }

      final approvals = archiveApprovalsOf(data)
        ..[role] = _archiveApproval(actor);
      final updatedData = <String, dynamic>{
        ...data,
        'archive_approvals': approvals,
      };
      completed = areArchiveApprovalsComplete(updatedData);
      final historyEntry = _historyEntry(
        action: completed ? 'archived' : 'archive_approved',
        message: completed
            ? 'اكتملت الموافقات وتمت أرشفة السند'
            : 'اعتمد ${actor['name']} طلب أرشفة السند',
        actor: actor,
      );

      firestoreTransaction.update(transactionRef, {
        'archive_approvals': approvals,
        'archive_status': completed ? 'archived' : 'pending',
        if (completed) 'archived_at': FieldValue.serverTimestamp(),
        'last_updated': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([historyEntry]),
      });
    });

    await _notifySafely(
      () => _notificationService.notifyForArchive(
        transactionId: transactionId,
        completed: completed,
      ),
    );
  }

  Map<String, dynamic> _archiveApproval(Map<String, String> actor) {
    return {
      'user_id': actor['uid'],
      'user_name': actor['name'],
      'approved_at': Timestamp.now(),
    };
  }

  void _validateArchiveActor(
    Map<String, dynamic> transactionData,
    Map<String, String> actor,
  ) {
    final role = actor['role'];
    final uid = actor['uid'];
    if (!archiveRequiredRoles.contains(role) || uid == null || uid.isEmpty) {
      throw Exception('هذا الحساب غير مخول لاعتماد الأرشفة');
    }
    if (role == 'collector' && transactionData['collectorId'] != uid) {
      throw Exception('يمكن للمدير العام اعتماد أرشفة سنداته فقط');
    }
    if (role == 'manager' && transactionData['branchId'] != actor['branchId']) {
      throw Exception('يمكن للمدير اعتماد أرشفة سندات فرعه فقط');
    }
  }

  Future<void> rejectEditRequestByCollector({
    required String transactionId,
    required String rejectReason,
    required String returnToStatus,
  }) async {
    try {
      final actor = await _getCurrentActor();
      final historyEntry = _historyEntry(
        action: 'edit_request_rejected',
        message: 'تم رفض طلب التعديل مع السبب:\n$rejectReason',
        actor: actor,
      );
      await _firestore.collection('transactions').doc(transactionId).update({
        'status': returnToStatus,
        'manager_notes': 'رد المدير العام (رفض التعديل): $rejectReason',
        'last_updated': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([historyEntry]),
      });
      await _notifySafely(
        () => _notificationService.notifyForStatus(
          transactionId: transactionId,
          newStatus: returnToStatus,
          message: rejectReason,
        ),
      );
    } catch (e) {
      throw Exception('Failed to reject edit request: $e');
    }
  }
}
