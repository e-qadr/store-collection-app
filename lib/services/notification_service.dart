import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
    final branchId = transactionData['branchId'] as String;

    await _send(
      recipients: await _branchManagers(branchId),
      transactionId: transactionId,
      transactionData: transactionData,
      title: 'سند جديد بانتظار الاعتماد',
      message:
          'تم إنشاء السند رقم ${transactionData['transaction_number']} في فرعك.',
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

    final recipients = <String>{};
    String title;
    String body;

    switch (newStatus) {
      case 'pendingApprovalOfEdit':
        recipients.addAll(await _branchManagers(data['branchId']));
        title = 'تعديل سند بانتظار الاعتماد';
        body =
            'تم إرسال تعديل السند رقم ${data['transaction_number']} لاعتمادك.';
        break;
      case 'editRequestedByCollector':
      case 'rejectedByManager':
        recipients.add(data['collectorId']);
        title = newStatus == 'rejectedByManager'
            ? 'تم رفض السند'
            : 'السند يحتاج إلى تعديل';
        body =
            message ?? 'يرجى مراجعة السند رقم ${data['transaction_number']}.';
        break;
      case 'approvedByManager':
        recipients.addAll(await _usersByRole('accountant'));
        title = 'سند جاهز للمراجعة المالية';
        body =
            'اعتمد المدير السند رقم ${data['transaction_number']} وأصبح جاهزًا للمراجعة.';
        break;
      case 'approvedByAccountant':
        recipients.add(data['collectorId']);
        recipients.addAll(await _branchManagers(data['branchId']));
        title = 'تم الاعتماد النهائي للسند';
        body =
            'تم اعتماد السند رقم ${data['transaction_number']} اعتمادًا نهائيًا.';
        break;
      case 'pending':
        recipients.addAll(await _branchManagers(data['branchId']));
        title = 'سند معاد بانتظار الاعتماد';
        body =
            'أعيد السند رقم ${data['transaction_number']} إلى مرحلة اعتماد المدير.';
        break;
      default:
        return;
    }

    await _send(
      recipients: recipients,
      transactionId: transactionId,
      transactionData: data,
      title: title,
      message: body,
    );
  }

  Future<Set<String>> _branchManagers(String branchId) async {
    final recipients = <String>{};
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

  Future<void> _send({
    required Set<String> recipients,
    required String transactionId,
    required Map<String, dynamic> transactionData,
    required String title,
    required String message,
  }) async {
    final senderId = FirebaseAuth.instance.currentUser?.uid;
    recipients.removeWhere((uid) => uid.isEmpty || uid == senderId);
    if (recipients.isEmpty) return;

    final batch = _firestore.batch();
    for (final recipientId in recipients) {
      final ref = _firestore.collection('notifications').doc();
      batch.set(ref, {
        'id': ref.id,
        'recipient_id': recipientId,
        'branch_id': transactionData['branchId'],
        'transaction_id': transactionId,
        'transaction_number': transactionData['transaction_number'],
        'title': title,
        'message': message,
        'is_read': false,
        'push_status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
