import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:store_collection_app/models/transaction_model.dart';
import 'package:store_collection_app/services/notification_service.dart';

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
      'name': data?['name'] ?? 'مستخدم غير معروف',
      'role': data?['role'] ?? 'unknown',
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
        return 'معتمد من المحصل';
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
      print('Database Error: $e');
      rethrow;
    }
  }

  // 2. جلب السندات مع الفلاتر
  Stream<QuerySnapshot> getBranchTransactions({
    required String branchId,
    String? currency,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    Query query = _firestore
        .collection('transactions')
        .where('branchId', isEqualTo: branchId);

    if (currency != null) query = query.where('currency', isEqualTo: currency);
    if (status != null) query = query.where('status', isEqualTo: status);
    if (startDate != null)
      query = query.where('timestamp', isGreaterThanOrEqualTo: startDate);
    if (endDate != null)
      query = query.where(
        'timestamp',
        isLessThanOrEqualTo: endDate.add(const Duration(days: 1)),
      );

    return query.orderBy('timestamp', descending: true).snapshots();
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
      await _firestore.collection('transactions').doc(transactionId).update({
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
      });
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

  Future<void> approveByAccountant(String transactionId) async {
    try {
      final actor = await _getCurrentActor();
      final historyEntry = _historyEntry(
        action: 'approved_by_accountant',
        message: 'تم الاعتماد والمراجعة النهائية للسند',
        actor: actor,
      );
      await _firestore.collection('transactions').doc(transactionId).update({
        'status': 'approvedByAccountant',
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
        'manager_notes': 'رد المحصل (رفض التعديل): $rejectReason',
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
