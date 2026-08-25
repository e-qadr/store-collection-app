import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:store_collection_app/models/consumable_request_model.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/services/notification_service.dart';

class ConsumableRequestService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(ConsumableRequestFields.collection);

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
        .where(ConsumableRequestFields.branchId, isEqualTo: branchId)
        .snapshots();
  }

  Future<void> createRequest({
    required String branchId,
    required String branchName,
    required List<ConsumableRequestItem> items,
    String? notes,
  }) async {
    final requestItems = _normalizeItems(items);
    if (requestItems.isEmpty) {
      throw Exception('أضف منتجاً واحداً على الأقل.');
    }
    if (requestItems.any(
      (item) =>
          item.productId?.trim().isEmpty != false ||
          item.unitId?.trim().isEmpty != false,
    )) {
      throw Exception('يجب اختيار جميع المواد ووحداتها من الكتالوج.');
    }

    final actor = await _getCurrentActor();
    _validateManagerBranch(actor, branchId);

    final doc = _collection.doc();
    final requestNumber = 'CR-${DateTime.now().millisecondsSinceEpoch}';
    await doc.set({
      'id': doc.id,
      ConsumableRequestFields.requestNumber: requestNumber,
      ConsumableRequestFields.branchId: branchId,
      ConsumableRequestFields.branchName: branchName,
      ConsumableRequestFields.items: requestItems
          .map((item) => item.toMap())
          .toList(),
      ConsumableRequestFields.itemName: requestItems.first.name,
      ConsumableRequestFields.unit: requestItems.first.unit,
      ConsumableRequestFields.requestedQuantity:
          requestItems.first.requestedQuantity,
      ConsumableRequestFields.collectorQuantity:
          requestItems.first.collectorQuantity,
      ConsumableRequestFields.status:
          ConsumableRequestStatus.pendingCollectorReview.value,
      if ((notes ?? '').trim().isNotEmpty)
        ConsumableRequestFields.managerNotes: notes!.trim(),
      ConsumableRequestFields.createdBy: actor['uid'],
      ConsumableRequestFields.createdAt: FieldValue.serverTimestamp(),
      ConsumableRequestFields.lastUpdated: FieldValue.serverTimestamp(),
      ConsumableRequestFields.history: [
        _historyEntry(
          action: 'request_created',
          message: 'تم إنشاء طلب استهلاك منتجات للعرض',
          actor: actor,
          note: notes,
          changes: {'items_count': requestItems.length},
        ),
      ],
    });
    final savedRequest = await doc.get();
    final savedData = savedRequest.data();
    if (savedData != null) {
      await _notifySafely(
        () => _notificationService.notifyConsumableRequestCreated(
          requestId: doc.id,
          requestData: savedData,
        ),
      );
    }
  }

  Future<void> submitCollectorReview({
    required String requestId,
    required List<ConsumableRequestItem> reviewedItems,
    String? branchId,
    String? notes,
  }) async {
    final items = _normalizeItems(reviewedItems);
    if (items.isEmpty || items.any((item) => item.collectorQuantity <= 0)) {
      throw Exception('أدخل كمية صحيحة لكل منتج.');
    }

    final actor = await _getCurrentActor();
    _validateRole(
      actor,
      UserRole.collector,
      'قبول أو تعديل الكمية متاح للمدير العام فقط.',
    );
    final docRef = _collection.doc(requestId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final data = _dataOrThrow(snapshot);
      _validateSelectedBranch(data, branchId);
      _ensureNotFinal(data);
      _ensureStatus(
        data,
        ConsumableRequestStatus.pendingCollectorReview,
        'لا يمكن تعديل الطلب بعد إرساله للمحاسب.',
      );

      transaction.update(docRef, {
        ConsumableRequestFields.items: items
            .map((item) => item.toMap())
            .toList(),
        ConsumableRequestFields.collectorQuantity:
            items.first.collectorQuantity,
        ConsumableRequestFields.status:
            ConsumableRequestStatus.pendingAccountingApproval.value,
        if ((notes ?? '').trim().isNotEmpty)
          ConsumableRequestFields.collectorNotes: notes!.trim(),
        ConsumableRequestFields.reviewedBy: actor['uid'],
        ConsumableRequestFields.reviewedAt: FieldValue.serverTimestamp(),
        ConsumableRequestFields.lastUpdated: FieldValue.serverTimestamp(),
        ConsumableRequestFields.history: FieldValue.arrayUnion([
          _historyEntry(
            action: 'collector_reviewed',
            message: _hasQuantityChanges(data, items)
                ? 'راجع المدير العام الطلب وعدل الكميات'
                : 'قبل المدير العام الطلب بالكميات المطلوبة',
            actor: actor,
            note: notes,
            changes: {'items_count': items.length},
          ),
        ]),
      });
    });
    final savedRequest = await docRef.get();
    final savedData = savedRequest.data();
    if (savedData != null) {
      await _notifySafely(
        () => _notificationService.notifyConsumableCollectorReviewed(
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
    if (reference.isEmpty) {
      throw Exception('المرجع المحاسبي مطلوب.');
    }

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
        ConsumableRequestStatus.pendingAccountingApproval,
        'لا يمكن اعتماد الطلب قبل مراجعة المدير العام.',
      );

      transaction.update(docRef, {
        ConsumableRequestFields.status:
            ConsumableRequestStatus.approvedByAccountant.value,
        ConsumableRequestFields.accountingReference: reference,
        if ((notes ?? '').trim().isNotEmpty)
          ConsumableRequestFields.accountantNotes: notes!.trim(),
        ConsumableRequestFields.approvedBy: actor['uid'],
        ConsumableRequestFields.approvedAt: FieldValue.serverTimestamp(),
        ConsumableRequestFields.lastUpdated: FieldValue.serverTimestamp(),
        ConsumableRequestFields.history: FieldValue.arrayUnion([
          _historyEntry(
            action: 'accountant_approved',
            message: 'أدخل المحاسب الطلب في النظام المحاسبي واعتمده نهائياً',
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
        () => _notificationService.notifyConsumableAccountingApproved(
          requestId: requestId,
          requestData: savedData,
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
    if (data == null) throw Exception('طلب المستهلكات غير موجود.');
    return data;
  }

  void _ensureStatus(
    Map<String, dynamic> data,
    ConsumableRequestStatus expected,
    String message,
  ) {
    final current = consumableRequestStatusFromString(
      data[ConsumableRequestFields.status]?.toString(),
    );
    if (current != expected) throw Exception(message);
  }

  void _ensureNotFinal(Map<String, dynamic> data) {
    final status = consumableRequestStatusFromString(
      data[ConsumableRequestFields.status]?.toString(),
    );
    if (status.isFinal) {
      throw Exception('لا يمكن تعديل الطلب بعد اعتماد المحاسب.');
    }
  }

  void _validateManagerBranch(Map<String, String> actor, String branchId) {
    _validateRole(actor, UserRole.manager, 'إنشاء الطلب متاح لمدير الفرع فقط.');
    if (actor['branchId'] != branchId) {
      throw Exception('لا يمكن إنشاء الطلب إلا لفرع المدير الحالي.');
    }
  }

  void _validateRole(Map<String, String> actor, UserRole role, String message) {
    if (actor['role'] == role.name) return;
    throw Exception(message);
  }

  void _validateSelectedBranch(Map<String, dynamic> data, String? branchId) {
    if (branchId == null || branchId.isEmpty) return;
    if (data[ConsumableRequestFields.branchId]?.toString() != branchId) {
      throw Exception('لا يمكن تنفيذ الإجراء إلا على طلبات الفرع المحدد.');
    }
  }

  bool _hasQuantityChanges(
    Map<String, dynamic> existingData,
    List<ConsumableRequestItem> newItems,
  ) {
    final oldItems = ConsumableRequestRead(id: '', data: existingData).items;
    if (oldItems.length != newItems.length) return true;
    for (var index = 0; index < oldItems.length; index++) {
      if (oldItems[index].requestedQuantity !=
          newItems[index].collectorQuantity) {
        return true;
      }
    }
    return false;
  }

  List<ConsumableRequestItem> _normalizeItems(
    List<ConsumableRequestItem> items,
  ) {
    return items
        .where(
          (item) =>
              item.name.trim().isNotEmpty &&
              item.unit.trim().isNotEmpty &&
              item.requestedQuantity > 0,
        )
        .toList();
  }
}
