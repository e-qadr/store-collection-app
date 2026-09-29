import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:store_collection_app/models/branch_request_model.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/services/notification_service.dart';

class BranchRequestService {
  final FirebaseFirestore _firestore;
  final NotificationService _notifications;

  BranchRequestService({
    FirebaseFirestore? firestore,
    NotificationService? notifications,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _notifications = notifications ?? NotificationService();

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(BranchRequestFields.collection);

  Stream<QuerySnapshot<Map<String, dynamic>>> watchRequests({
    required UserRole role,
    String? branchId,
  }) {
    if (role == UserRole.collector) {
      final effectiveBranchId = branchId?.trim() ?? '';
      return effectiveBranchId.isEmpty
          ? _collection.snapshots()
          : _collection
                .where(
                  BranchRequestFields.branchId,
                  isEqualTo: effectiveBranchId,
                )
                .snapshots();
    }
    if (role == UserRole.accountant) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      return uid == null
          ? _collection.limit(0).snapshots()
          : _collection
                .where(
                  Filter.or(
                    Filter(BranchRequestFields.createdBy, isEqualTo: uid),
                    Filter(
                      BranchRequestFields.executorRole,
                      isEqualTo: UserRole.accountant.name,
                    ),
                  ),
                )
                .snapshots();
    }
    final effectiveBranchId = branchId?.trim() ?? '';
    if (role != UserRole.manager || effectiveBranchId.isEmpty) {
      return _collection.limit(0).snapshots();
    }
    return _collection
        .where(BranchRequestFields.branchId, isEqualTo: effectiveBranchId)
        .snapshots();
  }

  Future<void> createRequest({
    required String branchId,
    required String branchName,
    required String title,
    required String description,
    required BranchRequestCategory category,
    required BranchRequestPriority priority,
  }) async {
    final cleanTitle = title.trim();
    final cleanDescription = description.trim();
    if (cleanTitle.isEmpty || cleanDescription.isEmpty) {
      throw StateError('العنوان والوصف مطلوبان.');
    }
    if (cleanTitle.length > 120 || cleanDescription.length > 2000) {
      throw StateError('تجاوز الطلب الحد المسموح به.');
    }

    final actor = await _currentActor();
    _requireManagerForBranch(actor, branchId);
    final request = _collection.doc();
    await request.set({
      BranchRequestFields.id: request.id,
      BranchRequestFields.branchId: branchId,
      BranchRequestFields.branchName: branchName.trim(),
      BranchRequestFields.title: cleanTitle,
      BranchRequestFields.description: cleanDescription,
      BranchRequestFields.category: category.value,
      BranchRequestFields.priority: priority.value,
      BranchRequestFields.status: BranchRequestStatus.newRequest.value,
      BranchRequestFields.direction:
          BranchRequestDirection.branchToAdministration.value,
      BranchRequestFields.executorRole: UserRole.collector.name,
      BranchRequestFields.createdBy: actor.uid,
      BranchRequestFields.createdByName: actor.name,
      BranchRequestFields.createdByRole: actor.role,
      BranchRequestFields.createdAt: FieldValue.serverTimestamp(),
      BranchRequestFields.lastUpdated: FieldValue.serverTimestamp(),
      BranchRequestFields.history: [
        _history(
          action: 'created',
          message: 'تم إرسال الطلب إلى المدير العام.',
          actor: actor,
        ),
      ],
    });

    final saved = await request.get();
    if (saved.data() case final data?) {
      await _notifySafely(
        () => _notifications.notifyBranchRequestCreated(
          requestId: request.id,
          requestData: data,
        ),
      );
    }
  }

  Future<void> createTaskForBranch({
    required String branchId,
    required String branchName,
    required String title,
    required String description,
    required BranchRequestCategory category,
    required BranchRequestPriority priority,
  }) async {
    final cleanTitle = title.trim();
    final cleanDescription = description.trim();
    if (cleanTitle.isEmpty || cleanDescription.isEmpty) {
      throw StateError('العنوان والوصف مطلوبان.');
    }
    if (cleanTitle.length > 120 || cleanDescription.length > 2000) {
      throw StateError('تجاوز الطلب الحد المسموح به.');
    }
    final actor = await _currentActor();
    if (actor.role != UserRole.collector.name &&
        actor.role != UserRole.accountant.name) {
      throw StateError('إسناد مهمة إلى فرع متاح للمدير العام أو المحاسب فقط.');
    }

    final request = _collection.doc();
    await request.set({
      BranchRequestFields.id: request.id,
      BranchRequestFields.branchId: branchId.trim(),
      BranchRequestFields.branchName: branchName.trim(),
      BranchRequestFields.title: cleanTitle,
      BranchRequestFields.description: cleanDescription,
      BranchRequestFields.category: category.value,
      BranchRequestFields.priority: priority.value,
      BranchRequestFields.status: BranchRequestStatus.newRequest.value,
      BranchRequestFields.direction:
          BranchRequestDirection.administrationToBranch.value,
      BranchRequestFields.executorRole: UserRole.manager.name,
      BranchRequestFields.createdBy: actor.uid,
      BranchRequestFields.createdByName: actor.name,
      BranchRequestFields.createdByRole: actor.role,
      BranchRequestFields.createdAt: FieldValue.serverTimestamp(),
      BranchRequestFields.lastUpdated: FieldValue.serverTimestamp(),
      BranchRequestFields.history: [
        _history(
          action: 'assigned_to_branch',
          message: 'تم إسناد المهمة إلى الفرع.',
          actor: actor,
        ),
      ],
    });
    final saved = await request.get();
    if (saved.data() case final data?) {
      await _notifySafely(
        () => _notifications.notifyBranchTaskAssigned(
          requestId: request.id,
          requestData: data,
        ),
      );
    }
  }

  Future<void> createAdministrativeTask({
    required String title,
    required String description,
    required BranchRequestCategory category,
    required BranchRequestPriority priority,
  }) async {
    final cleanTitle = title.trim();
    final cleanDescription = description.trim();
    if (cleanTitle.isEmpty || cleanDescription.isEmpty) {
      throw StateError('العنوان والوصف مطلوبان.');
    }
    if (cleanTitle.length > 120 || cleanDescription.length > 2000) {
      throw StateError('تجاوز الطلب الحد المسموح به.');
    }
    final actor = await _currentActor();
    final recipientRole = switch (actor.role) {
      'collector' => UserRole.accountant.name,
      'accountant' => UserRole.collector.name,
      _ => '',
    };
    if (recipientRole.isEmpty) {
      throw StateError(
        'المهام الإدارية المتبادلة متاحة للمدير العام والمحاسب فقط.',
      );
    }

    final request = _collection.doc();
    await request.set({
      BranchRequestFields.id: request.id,
      BranchRequestFields.branchId: BranchRequestFields.administrationScopeId,
      BranchRequestFields.branchName:
          BranchRequestFields.administrationScopeName,
      BranchRequestFields.title: cleanTitle,
      BranchRequestFields.description: cleanDescription,
      BranchRequestFields.category: category.value,
      BranchRequestFields.priority: priority.value,
      BranchRequestFields.status: BranchRequestStatus.newRequest.value,
      BranchRequestFields.direction:
          BranchRequestDirection.administrationToAdministration.value,
      BranchRequestFields.executorRole: recipientRole,
      BranchRequestFields.createdBy: actor.uid,
      BranchRequestFields.createdByName: actor.name,
      BranchRequestFields.createdByRole: actor.role,
      BranchRequestFields.createdAt: FieldValue.serverTimestamp(),
      BranchRequestFields.lastUpdated: FieldValue.serverTimestamp(),
      BranchRequestFields.history: [
        _history(
          action: 'assigned_to_administration',
          message: 'تم توجيه المهمة إلى ${_roleLabel(recipientRole)}.',
          actor: actor,
        ),
      ],
    });
    final saved = await request.get();
    if (saved.data() case final data?) {
      await _notifySafely(
        () => _notifications.notifyAdministrativeTaskAssigned(
          requestId: request.id,
          requestData: data,
        ),
      );
    }
  }

  Future<void> editRequest({
    required String requestId,
    required String title,
    required String description,
    required BranchRequestCategory category,
    required BranchRequestPriority priority,
  }) async {
    final cleanTitle = title.trim();
    final cleanDescription = description.trim();
    if (cleanTitle.isEmpty || cleanDescription.isEmpty) {
      throw StateError('العنوان والوصف مطلوبان.');
    }
    if (cleanTitle.length > 120 || cleanDescription.length > 2000) {
      throw StateError('تجاوز الطلب الحد المسموح به.');
    }
    final actor = await _currentActor();
    final ref = _collection.doc(requestId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null) throw StateError('الطلب غير موجود.');
      final current = branchRequestStatusFromString(
        data[BranchRequestFields.status]?.toString(),
      );
      if (current != BranchRequestStatus.newRequest ||
          data[BranchRequestFields.createdBy]?.toString() != actor.uid) {
        throw StateError('يمكن لصاحب الطلب تعديله قبل بدء التنفيذ فقط.');
      }
      transaction.update(ref, {
        BranchRequestFields.title: cleanTitle,
        BranchRequestFields.description: cleanDescription,
        BranchRequestFields.category: category.value,
        BranchRequestFields.priority: priority.value,
        BranchRequestFields.lastUpdated: FieldValue.serverTimestamp(),
        BranchRequestFields.history: FieldValue.arrayUnion([
          _history(
            action: 'edited',
            message: 'تم تعديل تفاصيل الطلب.',
            actor: actor,
          ),
        ]),
      });
    });
  }

  Future<void> startRequest(String requestId) => _transition(
    requestId: requestId,
    nextStatus: BranchRequestStatus.inProgress,
  );

  Future<void> completeRequest({
    required String requestId,
    String? completionNote,
  }) => _transition(
    requestId: requestId,
    nextStatus: BranchRequestStatus.completed,
    completionNote: completionNote,
  );

  Future<void> rejectRequest({
    required String requestId,
    required String reason,
  }) async {
    final note = reason.trim();
    if (note.isEmpty) throw StateError('سبب الرفض مطلوب.');
    if (note.length > 1000) throw StateError('سبب الرفض طويل جداً.');
    final actor = await _currentActor();
    final ref = _collection.doc(requestId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null) throw StateError('طلب الفرع غير موجود.');
      final current = branchRequestStatusFromString(
        data[BranchRequestFields.status]?.toString(),
      );
      if (!current.isPending || !_actorIsExecutor(actor, data)) {
        throw StateError('لا تملك صلاحية رفض هذا الطلب في مرحلته الحالية.');
      }
      transaction.update(ref, {
        BranchRequestFields.status: BranchRequestStatus.rejected.value,
        BranchRequestFields.rejectedBy: actor.uid,
        BranchRequestFields.rejectedByName: actor.name,
        BranchRequestFields.rejectedByRole: actor.role,
        BranchRequestFields.rejectedAt: FieldValue.serverTimestamp(),
        BranchRequestFields.rejectionReason: note,
        BranchRequestFields.lastUpdated: FieldValue.serverTimestamp(),
        BranchRequestFields.history: FieldValue.arrayUnion([
          _history(
            action: 'rejected',
            message: 'تم رفض الطلب.',
            actor: actor,
            note: note,
          ),
        ]),
      });
    });
    final saved = await ref.get();
    if (saved.data() case final data?) {
      await _notifySafely(
        () => _notifications.notifyBranchRequestRejected(
          requestId: requestId,
          requestData: data,
        ),
      );
    }
  }

  Future<void> _transition({
    required String requestId,
    required BranchRequestStatus nextStatus,
    String? completionNote,
  }) async {
    final actor = await _currentActor();
    final note = completionNote?.trim() ?? '';
    if (note.length > 1000) throw StateError('ملاحظة الإنجاز طويلة جداً.');
    final ref = _collection.doc(requestId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null) throw StateError('طلب الفرع غير موجود.');
      final current = branchRequestStatusFromString(
        data[BranchRequestFields.status]?.toString(),
      );
      if (!BranchRequestWorkflow.canTransition(current, nextStatus)) {
        throw StateError('لا يمكن تحديث حالة الطلب في مرحلته الحالية.');
      }
      if (!_actorIsExecutor(actor, data)) {
        throw StateError('هذا الطلب مخصص لدور آخر للتنفيذ.');
      }
      final isStarting = nextStatus == BranchRequestStatus.inProgress;
      transaction.update(ref, {
        BranchRequestFields.status: nextStatus.value,
        if (isStarting) ...{
          BranchRequestFields.startedBy: actor.uid,
          BranchRequestFields.startedByName: actor.name,
          'started_by_role': actor.role,
          BranchRequestFields.startedAt: FieldValue.serverTimestamp(),
        } else ...{
          BranchRequestFields.completedBy: actor.uid,
          BranchRequestFields.completedByName: actor.name,
          BranchRequestFields.completedAt: FieldValue.serverTimestamp(),
          BranchRequestFields.completionNote: note,
        },
        BranchRequestFields.lastUpdated: FieldValue.serverTimestamp(),
        BranchRequestFields.history: FieldValue.arrayUnion([
          _history(
            action: isStarting ? 'started' : 'completed',
            message: isStarting
                ? 'بدأ المدير العام تنفيذ الطلب.'
                : 'أكمل المدير العام الطلب.',
            actor: actor,
            note: note,
          ),
        ]),
      });
    });

    if (nextStatus == BranchRequestStatus.completed) {
      final saved = await ref.get();
      if (saved.data() case final data?) {
        await _notifySafely(
          () => _notifications.notifyBranchRequestCompleted(
            requestId: requestId,
            requestData: data,
          ),
        );
      }
    }
  }

  Future<_BranchRequestActor> _currentActor() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('يجب تسجيل الدخول أولاً.');
    final profile = await _firestore.collection('users').doc(uid).get();
    final data = profile.data();
    return _BranchRequestActor(
      uid: uid,
      name: data?['name']?.toString().trim() ?? 'مستخدم غير معروف',
      role: data?['role']?.toString().trim() ?? '',
      branchId: data?['branchId']?.toString().trim() ?? '',
    );
  }

  void _requireManagerForBranch(_BranchRequestActor actor, String branchId) {
    if (actor.role != UserRole.manager.name || actor.branchId != branchId) {
      throw StateError('إنشاء طلبات الفروع متاح لمدير الفرع الحالي فقط.');
    }
  }

  bool _actorIsExecutor(_BranchRequestActor actor, Map<String, dynamic> data) {
    final executorRole =
        data[BranchRequestFields.executorRole]?.toString() ??
        (branchRequestDirectionFromString(
                  data[BranchRequestFields.direction]?.toString(),
                ) ==
                BranchRequestDirection.branchToAdministration
            ? UserRole.collector.name
            : UserRole.manager.name);
    if (actor.role != executorRole) return false;
    return executorRole != UserRole.manager.name ||
        actor.branchId == data[BranchRequestFields.branchId]?.toString();
  }

  String _roleLabel(String role) => switch (role) {
    'collector' => 'المدير العام',
    'accountant' => 'المحاسب',
    'manager' => 'مدير الفرع',
    _ => 'الطرف المسؤول',
  };

  Map<String, dynamic> _history({
    required String action,
    required String message,
    required _BranchRequestActor actor,
    String? note,
  }) => {
    'action': action,
    'message': message,
    'actor_id': actor.uid,
    'actor_name': actor.name,
    'actor_role': actor.role,
    'timestamp': Timestamp.now(),
    if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
  };

  Future<void> _notifySafely(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (_) {
      // Notification delivery must never reverse a persisted request update.
    }
  }
}

class _BranchRequestActor {
  final String uid;
  final String name;
  final String role;
  final String branchId;

  const _BranchRequestActor({
    required this.uid,
    required this.name,
    required this.role,
    required this.branchId,
  });
}
