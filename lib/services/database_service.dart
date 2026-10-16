// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:store_collection_app/models/enums.dart';
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
      'actor_id': actor['uid'],
      'actor_name': actor['name'],
      'actor_role': actor['role'],
      'timestamp': Timestamp.now(),
      if (changes != null) 'changes': changes,
    };
  }

  /// Keeps the identity of the people who actually approved a collection
  /// voucher.  A role alone is not enough: a later amendment must go back to
  /// the same people, not every user that happens to have that role.
  Map<String, dynamic> _approvalParticipant(Map<String, String> actor) {
    return {
      'user_id': actor['uid'] ?? '',
      'user_name': actor['name'] ?? 'مستخدم غير معروف',
      'role': actor['role'] ?? 'unknown',
      'recorded_at': Timestamp.now(),
    };
  }

  Map<String, dynamic> _mapValue(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  /// Reads approvals saved by the current workflow and falls back to the
  /// audit trail for old vouchers created before this field existed.
  Map<String, Map<String, dynamic>> _recordedParticipants(
    Map<String, dynamic> data,
  ) {
    final participants = <String, Map<String, dynamic>>{};
    final stored = _mapValue(data['collection_approval_participants']);
    for (final entry in stored.entries) {
      final participant = _mapValue(entry.value);
      if ((participant['user_id']?.toString() ?? '').isNotEmpty) {
        participants[entry.key] = participant;
      }
    }

    final history = data['history'];
    if (history is List) {
      // The newest matching record wins, which is important for historical
      // vouchers that were approved more than once before this improvement.
      for (final raw in history) {
        final entry = _mapValue(raw);
        final role = entry['actor_role']?.toString() ?? '';
        final uid = entry['actor_id']?.toString() ?? '';
        final action = entry['action']?.toString() ?? '';
        final changes = _mapValue(entry['changes']);
        final newStatus = changes['to_status']?.toString() ?? '';
        final message = entry['message']?.toString() ?? '';
        final isRecordedApproval =
            (role == 'collector' && action == 'created') ||
            (role == 'manager' &&
                (newStatus == 'approvedByManager' ||
                    message.contains('معتمد من المدير'))) ||
            (role == 'accountant' &&
                (action == 'approved_by_accountant' ||
                    newStatus == 'approvedByAccountant' ||
                    message.contains('الاعتماد النهائي')));
        if (isRecordedApproval && uid.isNotEmpty) {
          participants[role] = {
            'user_id': uid,
            'user_name': entry['actor_name']?.toString() ?? 'مستخدم غير معروف',
            'role': role,
            'recorded_at': entry['timestamp'],
          };
        }
      }
    }
    return participants;
  }

  Map<String, Map<String, dynamic>> _requiredAmendmentParticipants(
    Map<String, dynamic> data,
    Map<String, String> actor,
  ) {
    final participants = _recordedParticipants(data);
    final status = data['status']?.toString() ?? 'pending';

    // A direct collection voucher is created by the collector/general manager.
    // Old records may only have collectorId, so retain that safe fallback.
    if (!participants.containsKey('collector')) {
      final collectorId = data['collectorId']?.toString() ?? '';
      if (collectorId.isNotEmpty) {
        participants['collector'] = {
          'user_id': collectorId,
          'user_name': data['collector_name']?.toString() ?? 'المدير العام',
          'role': 'collector',
        };
      } else if (actor['role'] == 'collector' && actor['uid'] != null) {
        participants['collector'] = _approvalParticipant(actor);
      }
    }

    final needsManager =
        status == 'approvedByManager' ||
        status == 'approvedByAccountant' ||
        participants.containsKey('manager');
    final needsAccountant =
        status == 'approvedByAccountant' ||
        participants.containsKey('accountant');

    final required = <String, Map<String, dynamic>>{};
    for (final role in const ['collector', 'manager', 'accountant']) {
      if (role == 'manager' && !needsManager) continue;
      if (role == 'accountant' && !needsAccountant) continue;
      final participant = participants[role];
      if (participant != null &&
          (participant['user_id']?.toString() ?? '').isNotEmpty) {
        required[role] = participant;
      }
    }
    return required;
  }

  String _missingParticipantMessage(
    Map<String, dynamic> data,
    Map<String, Map<String, dynamic>> required,
  ) {
    final status = data['status']?.toString() ?? '';
    if ((status == 'approvedByManager' || status == 'approvedByAccountant') &&
        !required.containsKey('manager')) {
      return 'لا يمكن تحديد مدير الفرع الذي اعتمد هذا السند القديم. افتح السند من حساب المدير الذي اعتمده ثم أعد المحاولة.';
    }
    if (status == 'approvedByAccountant' &&
        !required.containsKey('accountant')) {
      return 'لا يمكن تحديد المحاسب الذي اعتمد هذا السند القديم. افتح السند من حساب المحاسب الذي اعتمده ثم أعد المحاولة.';
    }
    return 'لا يمكن تحديد أصحاب الموافقة لهذا السند.';
  }

  Map<String, dynamic> _amendmentPayload({
    required double amount,
    required String currency,
    required bool? amountMatches,
    required double? cashierAmount,
    required DateTime dateFrom,
    required DateTime dateTo,
    required String notes,
  }) {
    return {
      'amount': amount,
      'currency': currency,
      'amount_matches': amountMatches,
      'cashier_amount': cashierAmount,
      'dateFrom': Timestamp.fromDate(dateFrom),
      'dateTo': Timestamp.fromDate(dateTo),
      'notes': notes,
    };
  }

  // أداة مساعدة لترجمة الحالة للسجل التاريخي
  String _getStatusArabicText(String status) {
    switch (status) {
      case 'reservedForCollection':
        return 'مراجع من المحاسب - بانتظار التحصيل';
      case 'collectionDifferencePendingReview':
        return 'فرق تحصيل بانتظار مراجعة المحاسب';
      case 'reservedCancelled':
        return 'مسودة محجوزة ملغاة';
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
          ..['collection_approval_participants'] = {
            if (actor['role'] == 'collector')
              'collector': _approvalParticipant(actor),
          }
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

  /// Creates the optional accountant-prepared path. It deliberately allocates
  /// from the same branch counter as the direct collector path, in the same
  /// Firestore transaction, so a reserved number can never be duplicated.
  Future<String> reserveReviewedCollectionVoucher({
    required String branchId,
    required double reviewedAmount,
    required String currency,
    required DateTime dateFrom,
    required DateTime dateTo,
    String reference = '',
    String note = '',
  }) async {
    if (reviewedAmount <= 0)
      throw Exception('المبلغ المراجع يجب أن يكون أكبر من صفر.');
    final actor = await _getCurrentActor();
    if (actor['role'] != 'accountant') {
      throw Exception('حجز سند مراجع متاح للمحاسب فقط.');
    }
    final transactionRef = _firestore.collection('transactions').doc();
    final branchRef = _firestore.collection('branches').doc(branchId);
    final counterRef = _firestore
        .collection('branch_transaction_counters')
        .doc(branchId);
    final now = DateTime.now();

    final number = await _firestore.runTransaction((transaction) async {
      final branch = await transaction.get(branchRef);
      if (!branch.exists) throw Exception('الفرع المحدد غير موجود.');
      final code = (branch.data()?['branch_code']?.toString() ?? '')
          .trim()
          .toUpperCase();
      if (code.isEmpty) throw Exception('رمز الفرع غير متوفر.');
      final counter = await transaction.get(counterRef);
      final next = (counter.data()?['next_number'] as num?)?.toInt() ?? 0;
      if (next > 999)
        throw Exception('وصل ترقيم هذا الفرع إلى الحد الأقصى 999.');
      final number = '$code${next.toString().padLeft(3, '0')}';
      final voucher =
          TransactionModel(
              id: transactionRef.id,
              transactionNumber: number,
              branchId: branchId,
              collectorId: '',
              amount: reviewedAmount,
              dateFrom: dateFrom,
              dateTo: dateTo,
              transactionDate: now,
              notes: note.trim(),
              status: TransactionStatus.reservedForCollection,
              timestamp: now,
              currency: currency,
              amountMatches: null,
              history: [],
            ).toJson()
            ..['branch_code'] = code
            ..['collection_workflow'] = 'accountant_reserved'
            ..['reviewed_amount'] = reviewedAmount
            ..['reviewed_by'] = actor['uid']
            ..['reviewed_by_name'] = actor['name']
            ..['reviewed_at'] = FieldValue.serverTimestamp()
            ..['reservation_at'] = FieldValue.serverTimestamp()
            ..['reservation_reference'] = reference.trim()
            ..['physical_collection_completed'] = false
            ..['history'] = [
              _historyEntry(
                action: 'accountant_reserved',
                message:
                    'راجع المحاسب الدخل وحجز السند بانتظار التحصيل الفعلي.',
                actor: actor,
                changes: {
                  'reviewed_amount': reviewedAmount,
                  'reference': reference.trim(),
                },
              ),
            ];
      transaction.set(transactionRef, voucher);
      transaction.set(counterRef, {
        'branch_id': branchId,
        'branch_code': code,
        'next_number': next + 1,
      });
      return number;
    });
    final saved = await transactionRef.get();
    await _notifySafely(
      () => _notificationService.notifyCollectionVoucherReserved(
        transactionId: transactionRef.id,
        transactionData: saved.data()!,
      ),
    );
    return number;
  }

  Future<void> updateReservedCollectionVoucher({
    required String transactionId,
    required double reviewedAmount,
    required String currency,
    required DateTime dateFrom,
    required DateTime dateTo,
    String reference = '',
    String note = '',
  }) async {
    final actor = await _getCurrentActor();
    if (actor['role'] != 'accountant')
      throw Exception('تعديل المسودة متاح للمحاسب فقط.');
    if (reviewedAmount <= 0)
      throw Exception('المبلغ المراجع يجب أن يكون أكبر من صفر.');
    final ref = _firestore.collection('transactions').doc(transactionId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null || data['status'] != 'reservedForCollection') {
        throw Exception('لا يمكن تعديل هذا السند بعد بدء التحصيل.');
      }
      transaction.update(ref, {
        'amount': reviewedAmount,
        'reviewed_amount': reviewedAmount,
        'currency': currency,
        'dateFrom': Timestamp.fromDate(dateFrom),
        'dateTo': Timestamp.fromDate(dateTo),
        'notes': note.trim(),
        'reservation_reference': reference.trim(),
        'reviewed_by': actor['uid'],
        'reviewed_by_name': actor['name'],
        'reviewed_at': FieldValue.serverTimestamp(),
        'last_updated': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([
          _historyEntry(
            action: 'accountant_reservation_updated',
            message: 'حدّث المحاسب معلومات المسودة المحجوزة.',
            actor: actor,
            changes: {
              'reviewed_amount': reviewedAmount,
              'reference': reference.trim(),
            },
          ),
        ]),
      });
    });
  }

  Future<void> cancelReservedCollectionVoucher({
    required String transactionId,
    required String reason,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) throw Exception('سبب إلغاء المسودة مطلوب.');
    final actor = await _getCurrentActor();
    if (actor['role'] != 'accountant')
      throw Exception('إلغاء المسودة متاح للمحاسب فقط.');
    final ref = _firestore.collection('transactions').doc(transactionId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null || data['status'] != 'reservedForCollection') {
        throw Exception('لا يمكن إلغاء هذا السند.');
      }
      transaction.update(ref, {
        'status': 'reservedCancelled',
        'reservation_cancelled_by': actor['uid'],
        'reservation_cancelled_by_name': actor['name'],
        'reservation_cancelled_at': FieldValue.serverTimestamp(),
        'reservation_cancellation_reason': cleanReason,
        'last_updated': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([
          _historyEntry(
            action: 'accountant_reservation_cancelled',
            message: 'ألغى المحاسب المسودة المحجوزة دون إعادة رقمها.',
            actor: actor,
            changes: {'reason': cleanReason},
          ),
        ]),
      });
    });
  }

  /// Records only the physical receipt. A matching amount enters the existing
  /// pending Collection workflow; a mismatch stays visible to the accountant
  /// until a reasoned review authorizes the correction.
  Future<void> collectReservedCollectionVoucher({
    required String transactionId,
    required double physicalAmount,
    required String differenceReason,
  }) async {
    if (physicalAmount <= 0)
      throw Exception('المبلغ المحصل يجب أن يكون أكبر من صفر.');
    final actor = await _getCurrentActor();
    if (actor['role'] != 'collector')
      throw Exception('التحصيل الفعلي متاح للمدير العام فقط.');
    final ref = _firestore.collection('transactions').doc(transactionId);
    var requiresReview = false;
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null || data['status'] != 'reservedForCollection') {
        throw Exception('هذا السند ليس بانتظار التحصيل.');
      }
      final reviewed =
          (data['reviewed_amount'] as num?)?.toDouble() ??
          (data['amount'] as num?)?.toDouble() ??
          0;
      requiresReview = reviewed != physicalAmount;
      final reason = differenceReason.trim();
      if (requiresReview && reason.isEmpty) {
        throw Exception('سبب فرق مبلغ التحصيل مطلوب.');
      }
      transaction.update(ref, {
        'collectorId': actor['uid'],
        'physical_collection_completed': true,
        'physical_collected_by': actor['uid'],
        'physical_collected_by_name': actor['name'],
        'physical_collected_at': FieldValue.serverTimestamp(),
        'physical_collection_amount': physicalAmount,
        'status': requiresReview
            ? 'collectionDifferencePendingReview'
            : 'pending',
        if (requiresReview) ...{
          'collection_difference': physicalAmount - reviewed,
          'collection_difference_reason': reason,
        },
        'last_updated': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([
          _historyEntry(
            action: requiresReview
                ? 'physical_collection_difference'
                : 'physical_collection_completed',
            message: requiresReview
                ? 'سجل المدير العام التحصيل الفعلي مع فرق بانتظار مراجعة المحاسب.'
                : 'سجل المدير العام التحصيل الفعلي وأدخل السند في مسار التحصيل المعتاد.',
            actor: actor,
            changes: {
              'physical_amount': physicalAmount,
              'reviewed_amount': reviewed,
            },
          ),
        ]),
      });
    });
    final saved = await ref.get();
    await _notifySafely(
      () => _notificationService.notifyCollectionVoucherCollected(
        transactionId: transactionId,
        transactionData: saved.data()!,
        differencePendingReview: requiresReview,
      ),
    );
  }

  Future<void> approveReservedCollectionDifference({
    required String transactionId,
    required String note,
  }) async {
    final actor = await _getCurrentActor();
    if (actor['role'] != 'accountant')
      throw Exception('مراجعة فرق التحصيل متاحة للمحاسب فقط.');
    final ref = _firestore.collection('transactions').doc(transactionId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null ||
          data['status'] != 'collectionDifferencePendingReview') {
        throw Exception('لا يوجد فرق تحصيل بانتظار المراجعة.');
      }
      final physical = (data['physical_collection_amount'] as num?)?.toDouble();
      if (physical == null) throw Exception('مبلغ التحصيل الفعلي غير متوفر.');
      transaction.update(ref, {
        'amount': physical,
        'status': 'pending',
        'difference_reviewed_by': actor['uid'],
        'difference_reviewed_by_name': actor['name'],
        'difference_reviewed_at': FieldValue.serverTimestamp(),
        'accountant_notes': note.trim(),
        'last_updated': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([
          _historyEntry(
            action: 'collection_difference_approved',
            message:
                'راجع المحاسب فرق التحصيل وأعاد السند لمسار التحصيل المعتاد.',
            actor: actor,
            changes: {'approved_amount': physical, 'note': note.trim()},
          ),
        ]),
      });
    });
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

      final reference = _firestore
          .collection('transactions')
          .doc(transactionId);
      await _firestore.runTransaction((firestoreTransaction) async {
        final snapshot = await firestoreTransaction.get(reference);
        final currentData = snapshot.data();
        if (currentData == null) throw Exception('السند غير موجود');
        if (_mapValue(currentData['collection_amendment'])['state'] ==
            'pending') {
          throw Exception(
            'لا يمكن تغيير حالة السند أثناء وجود طلب تعديل بانتظار الموافقات.',
          );
        }
        final oldStatus = currentData['status']?.toString() ?? '';
        final historyEntry = _historyEntry(
          action: 'status_update',
          message:
              'تغيرت حالة السند إلى: ${_getStatusArabicText(newStatus)}$noteMsg',
          actor: actor,
          changes: {'from_status': oldStatus, 'to_status': newStatus},
        );

        Map<String, dynamic> updateData = {
          'status': newStatus,
          'last_updated': FieldValue.serverTimestamp(),
          'history': FieldValue.arrayUnion([historyEntry]),
        };

        if (managerNotes != null && managerNotes.isNotEmpty) {
          updateData['manager_notes'] = managerNotes;
        }

        final participantRole = switch (newStatus) {
          'approvedByCollector' => 'collector',
          'approvedByManager' => 'manager',
          'approvedByAccountant' => 'accountant',
          _ => null,
        };
        if (participantRole != null && actor['role'] == participantRole) {
          updateData['collection_approval_participants.$participantRole'] =
              _approvalParticipant(actor);
        }

        firestoreTransaction.update(reference, updateData);
      });
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
    if (newAmount <= 0) throw Exception('المبلغ يجب أن يكون أكبر من صفر.');
    if (newDateTo.isBefore(newDateFrom)) {
      throw Exception(
        'تاريخ النهاية يجب أن يكون بعد أو مساوياً لتاريخ البداية.',
      );
    }

    final actor = await _getCurrentActor();
    final reference = _firestore.collection('transactions').doc(transactionId);
    var wasAppliedDirectly = false;
    var requiresApprovals = <Map<String, dynamic>>[];

    await _firestore.runTransaction((firestoreTransaction) async {
      final snapshot = await firestoreTransaction.get(reference);
      final oldData = snapshot.data();
      if (oldData == null) throw Exception('السند غير موجود أو لم يعد متاحاً.');
      if (_mapValue(oldData['collection_amendment'])['state'] == 'pending') {
        throw Exception(
          'يوجد طلب تعديل معلق لهذا السند. أكمل أو ارفض الطلب الحالي أولاً.',
        );
      }

      final required = _requiredAmendmentParticipants(oldData, actor);
      if (required.isEmpty)
        throw Exception(_missingParticipantMessage(oldData, required));
      if (!required.values.any((item) => item['user_id'] == actor['uid'])) {
        throw Exception(
          'لا يحق إلا لمن شارك في اعتماد السند تقديم تعديل عليه.',
        );
      }

      final proposedData = _amendmentPayload(
        amount: newAmount,
        currency: newCurrency,
        amountMatches: newAmountMatches,
        cashierAmount: newCashierAmount,
        dateFrom: newDateFrom,
        dateTo: newDateTo,
        notes: newNotes,
      );
      final historyChanges = {
        'oldAmount': oldData['amount'],
        'newAmount': newAmount,
        'oldCurrency': oldData['currency'],
        'newCurrency': newCurrency,
        'oldAmountMatches': oldData['amount_matches'],
        'newAmountMatches': newAmountMatches,
        'oldCashierAmount': oldData['cashier_amount'],
        'newCashierAmount': newCashierAmount,
        'oldDateFrom': oldData['dateFrom'],
        'newDateFrom': proposedData['dateFrom'],
        'oldDateTo': oldData['dateTo'],
        'newDateTo': proposedData['dateTo'],
      };

      // Before a second person has approved the voucher, its creator can make
      // a correction directly. This is the only direct-edit case.
      if (required.length == 1 &&
          required.values.first['user_id'] == actor['uid']) {
        firestoreTransaction.update(reference, {
          ...proposedData,
          'last_updated': FieldValue.serverTimestamp(),
          'history': FieldValue.arrayUnion([
            _historyEntry(
              action: 'collection_amendment_applied_directly',
              message: 'تم تعديل السند مباشرة قبل وجود موافقات أخرى عليه.',
              actor: actor,
              changes: historyChanges,
            ),
          ]),
        });
        wasAppliedDirectly = true;
        return;
      }

      final approversByUserId = <String, dynamic>{
        for (final participant in required.values)
          participant['user_id'].toString(): participant,
      };
      requiresApprovals = required.values.toList(growable: false);
      firestoreTransaction.update(reference, {
        // Keep status and the live voucher data intact until every recorded
        // participant gives a fresh approval.
        'collection_amendment': {
          'state': 'pending',
          'requested_by': _approvalParticipant(actor),
          'requested_at': Timestamp.now(),
          'base_status': oldData['status'],
          'proposed_data': proposedData,
          'required_approvers': approversByUserId,
          'approvals': <String, dynamic>{},
        },
        'last_updated': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([
          _historyEntry(
            action: 'collection_amendment_requested',
            message: 'تم تقديم تعديل للسند بانتظار اعتماد المشاركين السابقين.',
            actor: actor,
            changes: historyChanges,
          ),
        ]),
      });
    });

    if (wasAppliedDirectly) return;
    await _notifySafely(
      () => _notificationService.notifyCollectionAmendment(
        transactionId: transactionId,
        approvers: requiresApprovals,
      ),
    );
  }

  // 5. اعتماد التعديلات
  Future<void> approveEditRequest({
    required String transactionId,
    required Map<String, dynamic> pendingData,
  }) async {
    final snapshot = await _firestore
        .collection('transactions')
        .doc(transactionId)
        .get();
    final data = snapshot.data();
    if (data == null) throw Exception('السند غير موجود.');
    if (_mapValue(data['collection_amendment'])['state'] != 'pending') {
      await _migrateLegacyCollectionAmendment(
        transactionId: transactionId,
        legacyPendingData: pendingData,
      );
    }
    await approveCollectionAmendment(transactionId: transactionId);
  }

  /// One-time compatibility bridge for edits submitted by older app versions.
  /// It never applies their pending data directly; instead it converts them to
  /// the current unanimous-approval record before accepting a vote.
  Future<void> _migrateLegacyCollectionAmendment({
    required String transactionId,
    required Map<String, dynamic> legacyPendingData,
  }) async {
    if (legacyPendingData.isEmpty) {
      throw Exception('بيانات التعديل القديمة غير متوفرة.');
    }
    final actor = await _getCurrentActor();
    final reference = _firestore.collection('transactions').doc(transactionId);
    await _firestore.runTransaction((firestoreTransaction) async {
      final snapshot = await firestoreTransaction.get(reference);
      final data = snapshot.data();
      if (data == null) throw Exception('السند غير موجود.');
      if (_mapValue(data['collection_amendment'])['state'] == 'pending') return;
      final required = _requiredAmendmentParticipants(data, actor);
      if (required.isEmpty)
        throw Exception(_missingParticipantMessage(data, required));
      final baseStatus = required.containsKey('accountant')
          ? 'approvedByAccountant'
          : required.containsKey('manager')
          ? 'approvedByManager'
          : 'pending';
      firestoreTransaction.update(reference, {
        'collection_amendment': {
          'state': 'pending',
          'requested_by': {
            'user_id': '',
            'user_name': 'طلب تعديل من إصدار سابق',
            'role': 'legacy',
          },
          'requested_at': Timestamp.now(),
          'base_status': baseStatus,
          'proposed_data': legacyPendingData,
          'required_approvers': {
            for (final participant in required.values)
              participant['user_id'].toString(): participant,
          },
          'approvals': <String, dynamic>{},
        },
        'last_updated': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([
          _historyEntry(
            action: 'collection_amendment_migrated',
            message:
                'تم تحويل طلب تعديل قديم إلى مسار الموافقات الحالي دون تغيير بيانات السند.',
            actor: actor,
          ),
        ]),
      });
    });
  }

  /// Gives the current recorded approver one explicit vote. Data is applied
  /// only by the last required vote; every earlier approval is audit logged.
  Future<void> approveCollectionAmendment({
    required String transactionId,
  }) async {
    final actor = await _getCurrentActor();
    final reference = _firestore.collection('transactions').doc(transactionId);
    var completed = false;
    var participantsToNotify = <Map<String, dynamic>>[];

    await _firestore.runTransaction((firestoreTransaction) async {
      final snapshot = await firestoreTransaction.get(reference);
      final data = snapshot.data();
      if (data == null) throw Exception('السند غير موجود.');
      final amendment = _mapValue(data['collection_amendment']);
      if (amendment['state'] != 'pending') {
        throw Exception('لا يوجد طلب تعديل معلق لهذا السند.');
      }
      final required = _mapValue(amendment['required_approvers']);
      final currentApprover = _mapValue(required[actor['uid']]);
      if (currentApprover.isEmpty) {
        throw Exception(
          'هذه الموافقة مخصصة للمستخدمين الذين اعتمدوا السند سابقاً.',
        );
      }
      final approvals = _mapValue(amendment['approvals']);
      if (approvals.containsKey(actor['uid'])) {
        throw Exception('لقد سجلت موافقتك على هذا التعديل مسبقاً.');
      }
      approvals[actor['uid']!] = {
        ..._approvalParticipant(actor),
        'approved_at': Timestamp.now(),
      };
      final allApproved = required.keys.every(approvals.containsKey);
      participantsToNotify = required.values.map(_mapValue).toList();
      final approvalHistory = _historyEntry(
        action: allApproved
            ? 'collection_amendment_applied'
            : 'collection_amendment_approved',
        message: allApproved
            ? 'اكتملت موافقات التعديل وتم تطبيق البيانات الجديدة على السند.'
            : 'سجل ${actor['name']} موافقته على تعديل السند.',
        actor: actor,
      );

      if (!allApproved) {
        firestoreTransaction.update(reference, {
          'collection_amendment.approvals': approvals,
          'last_updated': FieldValue.serverTimestamp(),
          'history': FieldValue.arrayUnion([approvalHistory]),
        });
        return;
      }

      final proposedData = _mapValue(amendment['proposed_data']);
      if (proposedData.isEmpty) throw Exception('بيانات التعديل غير مكتملة.');
      firestoreTransaction.update(reference, {
        ...proposedData,
        'status': amendment['base_status'] ?? data['status'],
        'collection_amendment': FieldValue.delete(),
        // Clear only the old workflow payload if a voucher was transitioned
        // from an older app version into the current approval process.
        'pending_edit_data': FieldValue.delete(),
        'last_updated': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([approvalHistory]),
      });
      completed = true;
    });

    await _notifySafely(
      () => _notificationService.notifyCollectionAmendmentProgress(
        transactionId: transactionId,
        approvers: participantsToNotify,
        completed: completed,
      ),
    );
  }

  Future<void> rejectCollectionAmendment({
    required String transactionId,
    required String reason,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) throw Exception('سبب رفض التعديل مطلوب.');
    final actor = await _getCurrentActor();
    final reference = _firestore.collection('transactions').doc(transactionId);
    await _firestore.runTransaction((firestoreTransaction) async {
      final snapshot = await firestoreTransaction.get(reference);
      final data = snapshot.data();
      if (data == null) throw Exception('السند غير موجود.');
      final amendment = _mapValue(data['collection_amendment']);
      final required = _mapValue(amendment['required_approvers']);
      if (amendment['state'] != 'pending' ||
          !_mapValue(required[actor['uid']]).isNotEmpty) {
        throw Exception('لا تملك صلاحية رفض هذا التعديل.');
      }
      firestoreTransaction.update(reference, {
        'collection_amendment': FieldValue.delete(),
        'last_updated': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([
          _historyEntry(
            action: 'collection_amendment_rejected',
            message: 'تم رفض تعديل السند. السبب: $cleanReason',
            actor: actor,
            changes: {'reason': cleanReason},
          ),
        ]),
      });
    });
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
      final current = await _firestore
          .collection('transactions')
          .doc(transactionId)
          .get();
      if (current.data() == null) throw Exception('السند غير موجود.');
      if (_mapValue(current.data()!['collection_amendment'])['state'] ==
          'pending') {
        throw Exception(
          'لا يمكن اعتماد السند نهائياً أثناء وجود طلب تعديل بانتظار الموافقات.',
        );
      }
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
        'collection_approval_participants.accountant': _approvalParticipant(
          actor,
        ),
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
