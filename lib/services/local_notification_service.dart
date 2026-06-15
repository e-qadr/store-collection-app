import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:store_collection_app/services/app_navigation_service.dart';

const highImportanceNotificationChannelId = 'high_importance_channel';

@pragma('vm:entry-point')
void localNotificationTapBackground(NotificationResponse response) {
  // يتم فتح شاشة الإشعارات عند عودة المستخدم للتطبيق.
}

class LocalNotificationService {
  LocalNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    const androidSettings = AndroidInitializationSettings('ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (_) =>
          AppNavigationService.openNotifications(),
      onDidReceiveBackgroundNotificationResponse:
          localNotificationTapBackground,
    );

    const channel = AndroidNotificationChannel(
      highImportanceNotificationChannelId,
      'إشعارات المعاملات المهمة',
      description: 'إشعارات الاعتماد والتعديل والأرشفة',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
      showBadge: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    _initialized = true;
  }

  static Future<void> showForegroundMessage(RemoteMessage message) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await initialize();

    final title =
        message.notification?.title ?? message.data['title'] ?? 'إشعار جديد';
    final body = message.notification?.body ?? message.data['message'] ?? '';
    final notificationId = message.data['notification_id'] ?? message.messageId;

    await _plugin.show(
      id: notificationId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          highImportanceNotificationChannelId,
          'إشعارات المعاملات المهمة',
          channelDescription: 'إشعارات الاعتماد والتعديل والأرشفة',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: 'ic_launcher',
        ),
      ),
      payload: message.data['notification_id'],
    );
  }
}
