import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/screens/cash_expenses/cash_expense_details_screen.dart';
import 'package:store_collection_app/screens/consumables/consumable_request_details_screen.dart';
import 'package:store_collection_app/screens/inter_branch_invoices/inter_branch_invoice_details_screen.dart';
import 'package:store_collection_app/screens/transactions/transaction_details_screen.dart';
import 'package:store_collection_app/services/device_notification_service.dart';
import 'package:store_collection_app/services/notification_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/firestore_refresh.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  final NotificationService _notificationService = NotificationService();
  final DeviceNotificationService _deviceNotificationService =
      DeviceNotificationService();
  DeviceNotificationPermissionState? _permissionState;
  bool _isRequestingPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPermissionState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadPermissionState();
  }

  Future<void> _loadPermissionState() async {
    final state = await _deviceNotificationService.getPermissionState();
    if (state == DeviceNotificationPermissionState.enabled) {
      await _deviceNotificationService.syncCurrentTokenIfAllowed();
    }
    if (mounted) setState(() => _permissionState = state);
  }

  Future<void> _handlePermissionAction() async {
    final state = _permissionState;
    if (state == DeviceNotificationPermissionState.denied) {
      await _deviceNotificationService.openNotificationSettings();
      return;
    }

    setState(() => _isRequestingPermission = true);
    final result = await _deviceNotificationService.requestPermission();
    if (mounted) {
      setState(() {
        _permissionState = result;
        _isRequestingPermission = false;
      });
      if (result == DeviceNotificationPermissionState.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم حظر إشعارات النظام. يمكنك تفعيلها من إعدادات التطبيق.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: const Text('الإشعارات'),
          actions: [
            TextButton(
              onPressed: _notificationService.markAllAsRead,
              child: const Text(
                'تحديد الكل كمقروء',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            _buildPermissionCard(),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _notificationService.getCurrentUserNotifications(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final notifications = snapshot.data?.docs.toList() ?? [];
                  notifications.sort((a, b) {
                    final aDate =
                        (a.data()['created_at'] as Timestamp?)?.toDate() ??
                        DateTime(2000);
                    final bDate =
                        (b.data()['created_at'] as Timestamp?)?.toDate() ??
                        DateTime(2000);
                    return bDate.compareTo(aDate);
                  });

                  if (notifications.isEmpty) {
                    return const Center(
                      child: Text('لا توجد إشعارات حتى الآن'),
                    );
                  }

                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  return RefreshIndicator(
                    onRefresh: uid == null
                        ? () async {}
                        : () => refreshFirestoreQueries([
                            FirebaseFirestore.instance
                                .collection('notifications')
                                .where('recipient_id', isEqualTo: uid),
                          ]),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: notifications.length,
                      itemBuilder: (context, index) {
                        final doc = notifications[index];
                        final data = doc.data();
                        final isRead = data['is_read'] == true;
                        final createdAt = (data['created_at'] as Timestamp?)
                            ?.toDate();
                        return Card(
                          color: isRead
                              ? AppTheme.cardColor
                              : Colors.blue.shade50,
                          child: ListTile(
                            leading: Icon(
                              isRead
                                  ? Icons.notifications_none_rounded
                                  : Icons.notifications_active_rounded,
                              color: isRead ? AppTheme.textHint : Colors.blue,
                            ),
                            title: Text(
                              data['title'] ?? 'إشعار',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(data['message'] ?? ''),
                                if (createdAt != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    DateFormat(
                                      'yyyy/MM/dd - hh:mm a',
                                    ).format(createdAt),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textHint,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            onTap: () async {
                              await _notificationService.markAsRead(doc.id);
                              if (!mounted) return;
                              await _openNotificationTarget(data);
                            },
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openNotificationTarget(Map<String, dynamic> data) async {
    final module = _string(data, 'module');
    final collection = _string(data, 'entity_collection');

    if (module.isEmpty ||
        module == NotificationService.transactionsModule ||
        collection == 'transactions') {
      await _openTransaction(data);
      return;
    }

    if (module == NotificationService.consumableRequestsModule ||
        collection == NotificationService.consumableRequestsModule) {
      await _openConsumableRequest(data);
      return;
    }

    if (module == NotificationService.cashExpenseRequestsModule ||
        collection == NotificationService.cashExpenseRequestsModule) {
      await _openCashExpenseRequest(data);
      return;
    }

    if (module == NotificationService.interBranchInvoicesModule ||
        collection == NotificationService.interBranchInvoicesModule) {
      await _openInterBranchInvoice(data);
    }
  }

  Future<void> _openTransaction(Map<String, dynamic> data) async {
    final transactionId = _targetId(data, 'transaction_id');
    if (transactionId.isEmpty) return;
    final transaction = await FirebaseFirestore.instance
        .collection('transactions')
        .doc(transactionId)
        .get();
    final transactionData = transaction.data();
    if (!mounted || transactionData == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TransactionDetailsScreen(
          transactionId: transaction.id,
          transactionData: transactionData,
        ),
      ),
    );
  }

  Future<void> _openConsumableRequest(Map<String, dynamic> data) async {
    final requestId = _targetId(data, 'consumable_request_id');
    if (requestId.isEmpty) return;
    final targetContext = await _loadTargetContext(data);
    if (!mounted || targetContext == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConsumableRequestDetailsScreen(
          requestId: requestId,
          role: targetContext.role,
          branchId: targetContext.branchId,
          branchName: targetContext.branchName,
        ),
      ),
    );
  }

  Future<void> _openCashExpenseRequest(Map<String, dynamic> data) async {
    final requestId = _targetId(data, 'cash_expense_request_id');
    if (requestId.isEmpty) return;
    final targetContext = await _loadTargetContext(data);
    if (!mounted || targetContext == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CashExpenseDetailsScreen(
          requestId: requestId,
          role: targetContext.role,
          branchId: targetContext.branchId,
          branchName: targetContext.branchName,
        ),
      ),
    );
  }

  Future<void> _openInterBranchInvoice(Map<String, dynamic> data) async {
    final invoiceId = _targetId(data, 'inter_branch_invoice_id');
    if (invoiceId.isEmpty) return;
    final targetContext = await _loadTargetContext(data);
    if (!mounted || targetContext == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InterBranchInvoiceDetailsScreen(
          invoiceId: invoiceId,
          role: targetContext.role,
          branchId: targetContext.branchId,
          branchName: targetContext.branchName,
        ),
      ),
    );
  }

  Future<_NotificationTargetContext?> _loadTargetContext(
    Map<String, dynamic> notificationData,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final userData = userDoc.data();
    if (userData == null) return null;

    final role = _roleFromString(userData['role']?.toString());
    if (role == null || role == UserRole.admin) return null;

    final userBranchId = userData['branchId']?.toString() ?? '';
    final notificationBranchId = _string(notificationData, 'branch_id');
    final branchId = role == UserRole.manager
        ? userBranchId
        : notificationBranchId.isNotEmpty
        ? notificationBranchId
        : userBranchId;
    final branchName = await _branchName(branchId);

    return _NotificationTargetContext(
      role: role,
      branchId: branchId.isEmpty ? null : branchId,
      branchName: branchName,
    );
  }

  Future<String> _branchName(String branchId) async {
    if (branchId.isEmpty) return 'اختيار النظام';
    final branchDoc = await FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .get();
    return branchDoc.data()?['name']?.toString() ?? 'الفرع غير معروف';
  }

  UserRole? _roleFromString(String? value) {
    for (final role in UserRole.values) {
      if (role.name == value) return role;
    }
    return null;
  }

  String _targetId(Map<String, dynamic> data, String legacyKey) {
    final entityId = _string(data, 'entity_id');
    return entityId.isNotEmpty ? entityId : _string(data, legacyKey);
  }

  String _string(Map<String, dynamic> data, String key) {
    return data[key]?.toString().trim() ?? '';
  }

  Widget _buildPermissionCard() {
    final state = _permissionState;
    if (state == null || state == DeviceNotificationPermissionState.enabled) {
      return const SizedBox.shrink();
    }

    final denied = state == DeviceNotificationPermissionState.denied;
    final unsupported = state == DeviceNotificationPermissionState.unsupported;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_off_rounded, color: Colors.orange.shade800),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'إشعارات الجهاز غير مفعّلة',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 3),
                Text(
                  unsupported
                      ? 'هذه المنصة لا تدعم طلب إشعارات الجهاز من داخل التطبيق.'
                      : denied
                      ? 'تم حظر الإشعارات. افتح إعدادات النظام وفعّلها للتطبيق.'
                      : 'اسمح للتطبيق بإرسال إشعارات الجهاز.',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          if (!unsupported)
            TextButton(
              onPressed: _isRequestingPermission
                  ? null
                  : _handlePermissionAction,
              child: _isRequestingPermission
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(denied ? 'فتح الإعدادات' : 'السماح'),
            ),
        ],
      ),
    );
  }
}

class _NotificationTargetContext {
  final UserRole role;
  final String? branchId;
  final String branchName;

  const _NotificationTargetContext({
    required this.role,
    required this.branchId,
    required this.branchName,
  });
}
