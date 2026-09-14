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
    if (role == UserRole.collector) return _collection.snapshots();
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
      BranchRequestFields.createdBy: actor.uid,
      BranchRequestFields.createdByName: actor.name,
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

  Future<void> _transition({
    required String requestId,
    required BranchRequestStatus nextStatus,
    String? completionNote,
  }) async {
    final actor = await _currentActor();
    if (actor.role != UserRole.collector.name) {
      throw StateError('تحديث حالة طلبات الفروع متاح للمدير العام فقط.');
    }
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
      final isStarting = nextStatus == BranchRequestStatus.inProgress;
      transaction.update(ref, {
        BranchRequestFields.status: nextStatus.value,
        if (isStarting) ...{
          BranchRequestFields.startedBy: actor.uid,
          BranchRequestFields.startedByName: actor.name,
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
