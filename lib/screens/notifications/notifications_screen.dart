import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/screens/transactions/transaction_details_screen.dart';
import 'package:store_collection_app/services/device_notification_service.dart';
import 'package:store_collection_app/services/notification_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

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

                  return ListView.builder(
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
                            style: const TextStyle(fontWeight: FontWeight.bold),
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
                            final transactionId =
                                data['transaction_id'] as String?;
                            if (transactionId == null) return;
                            final transaction = await FirebaseFirestore.instance
                                .collection('transactions')
                                .doc(transactionId)
                                .get();
                            if (context.mounted && transaction.data() != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      TransactionDetailsScreen(
                                        transactionId: transaction.id,
                                        transactionData: transaction.data()!,
                                      ),
                                ),
                              );
                            }
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
