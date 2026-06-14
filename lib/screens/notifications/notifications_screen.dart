import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/screens/transactions/transaction_details_screen.dart';
import 'package:store_collection_app/services/notification_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = NotificationService();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: const Text('الإشعارات'),
          actions: [
            TextButton(
              onPressed: service.markAllAsRead,
              child: const Text(
                'تحديد الكل كمقروء',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: service.getCurrentUserNotifications(),
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
              return const Center(child: Text('لا توجد إشعارات حتى الآن'));
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final doc = notifications[index];
                final data = doc.data();
                final isRead = data['is_read'] == true;
                final createdAt = (data['created_at'] as Timestamp?)?.toDate();
                return Card(
                  color: isRead ? AppTheme.cardColor : Colors.blue.shade50,
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
                      await service.markAsRead(doc.id);
                      final transactionId = data['transaction_id'] as String?;
                      if (transactionId == null) return;
                      final transaction = await FirebaseFirestore.instance
                          .collection('transactions')
                          .doc(transactionId)
                          .get();
                      if (context.mounted && transaction.data() != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TransactionDetailsScreen(
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
    );
  }
}
