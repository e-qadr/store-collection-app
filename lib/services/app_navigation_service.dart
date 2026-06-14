import 'package:flutter/material.dart';
import 'package:store_collection_app/screens/notifications/notifications_screen.dart';

class AppNavigationService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static void openNotifications() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = navigatorKey.currentState;
      if (navigator == null) return;
      navigator.push(
        MaterialPageRoute(builder: (context) => const NotificationsScreen()),
      );
    });
  }
}
