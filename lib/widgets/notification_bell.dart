import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:store_collection_app/screens/notifications/notifications_screen.dart';
import 'package:store_collection_app/services/notification_service.dart';

class NotificationBell extends StatelessWidget {
  final Color color;

  const NotificationBell({super.key, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: NotificationService().getCurrentUserNotifications(),
      builder: (context, snapshot) {
        final unreadCount =
            snapshot.data?.docs
                .where((doc) => doc.data()['is_read'] != true)
                .length ??
            0;
        return IconButton(
          tooltip: 'الإشعارات',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const NotificationsScreen(),
            ),
          ),
          icon: Badge(
            isLabelVisible: unreadCount > 0,
            label: Text(unreadCount > 99 ? '+99' : '$unreadCount'),
            child: Icon(Icons.notifications_rounded, color: color),
          ),
        );
      },
    );
  }
}
