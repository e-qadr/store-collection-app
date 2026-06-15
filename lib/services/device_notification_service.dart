import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:store_collection_app/services/app_navigation_service.dart';
import 'package:store_collection_app/services/local_notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await recordDeviceNotificationDelivery(message, state: 'background');
}

Future<void> recordDeviceNotificationDelivery(
  RemoteMessage message, {
  required String state,
}) async {
  final notificationId = message.data['notification_id'];
  if (notificationId == null || notificationId.isEmpty) return;

  try {
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(notificationId)
        .update({
          'device_received_at': FieldValue.serverTimestamp(),
          'device_received_state': state,
          'device_platform': kIsWeb
              ? 'web'
              : defaultTargetPlatform.name.toLowerCase(),
        });
  } catch (_) {
    // لا يجب أن يؤثر فشل تسجيل الاستلام على عرض الإشعار.
  }
}

enum DeviceNotificationPermissionState {
  enabled,
  notDetermined,
  denied,
  unsupported,
}

class DeviceNotificationService {
  static StreamSubscription<String>? _tokenSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  static StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  static String? _registeredUserId;
  static String? _registeredToken;
  static bool _initialized = false;

  bool get supportsAutomaticRequest {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool get supportsDeviceNotifications {
    return kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  Future<void> initializeForSignedInUser() async {
    if (_initialized || !supportsDeviceNotifications) return;
    _initialized = true;

    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
              alert: true,
              badge: true,
              sound: true,
            );
      }
      _tokenSubscription ??= FirebaseMessaging.instance.onTokenRefresh.listen(
        _saveToken,
      );
      _foregroundMessageSubscription ??= FirebaseMessaging.onMessage.listen((
        message,
      ) async {
        await recordDeviceNotificationDelivery(message, state: 'foreground');
        await LocalNotificationService.showForegroundMessage(message);
      });
      _messageOpenedSubscription ??= FirebaseMessaging.onMessageOpenedApp
          .listen((message) {
            recordDeviceNotificationDelivery(message, state: 'opened');
            AppNavigationService.openNotifications();
          });
      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();
      if (initialMessage != null) {
        await recordDeviceNotificationDelivery(
          initialMessage,
          state: 'opened_from_terminated',
        );
        AppNavigationService.openNotifications();
      }
      if (supportsAutomaticRequest) {
        await requestPermission();
      } else {
        await _saveCurrentTokenIfAllowed();
      }
    } catch (_) {
      _initialized = false;
    }
  }

  Future<void> resetForSignedOutUser() async {
    await _removeTokenFromPreviouslyRegisteredUser();
    _initialized = false;
    await _tokenSubscription?.cancel();
    await _foregroundMessageSubscription?.cancel();
    await _messageOpenedSubscription?.cancel();
    _tokenSubscription = null;
    _foregroundMessageSubscription = null;
    _messageOpenedSubscription = null;
  }

  Future<DeviceNotificationPermissionState> getPermissionState() async {
    if (!supportsDeviceNotifications) {
      return DeviceNotificationPermissionState.unsupported;
    }

    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return _mapStatus(settings.authorizationStatus);
    } catch (_) {
      return DeviceNotificationPermissionState.unsupported;
    }
  }

  Future<DeviceNotificationPermissionState> requestPermission() async {
    if (!supportsDeviceNotifications) {
      return DeviceNotificationPermissionState.unsupported;
    }

    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      final state = _mapStatus(settings.authorizationStatus);
      await _updateEnabledState(
        state == DeviceNotificationPermissionState.enabled,
      );
      if (state == DeviceNotificationPermissionState.enabled) {
        await _saveCurrentTokenIfAllowed();
      }
      return state;
    } catch (_) {
      return DeviceNotificationPermissionState.unsupported;
    }
  }

  Future<void> openNotificationSettings() async {
    if (kIsWeb) return;
    await AppSettings.openAppSettings(type: AppSettingsType.notification);
  }

  Future<void> syncCurrentTokenIfAllowed() => _saveCurrentTokenIfAllowed();

  Future<void> _saveCurrentTokenIfAllowed() async {
    if (await getPermissionState() !=
        DeviceNotificationPermissionState.enabled) {
      return;
    }
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) await _saveToken(token);
    } catch (_) {
      // يحتاج الويب إلى إعداد VAPID قبل إمكانية تسجيل رمز Push.
    }
  }

  Future<void> _saveToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_registeredUserId != null && _registeredUserId != uid) {
      await _removeTokenFromPreviouslyRegisteredUser();
    }
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'notification_tokens': FieldValue.arrayUnion([token]),
      'notifications_enabled': true,
      'notification_platform': kIsWeb
          ? 'web'
          : defaultTargetPlatform.name.toLowerCase(),
      'notification_token_updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _registeredUserId = uid;
    _registeredToken = token;
  }

  Future<void> _removeTokenFromPreviouslyRegisteredUser() async {
    final uid = _registeredUserId;
    final token = _registeredToken;
    _registeredUserId = null;
    _registeredToken = null;
    if (uid == null || token == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'notification_tokens': FieldValue.arrayRemove([token]),
        'notification_token_updated_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // قد يكون المستخدم قد فقد الاتصال أثناء تسجيل الخروج.
    }
  }

  Future<void> _updateEnabledState(bool enabled) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'notifications_enabled': enabled,
    }, SetOptions(merge: true));
  }

  DeviceNotificationPermissionState _mapStatus(AuthorizationStatus status) {
    switch (status) {
      case AuthorizationStatus.authorized:
      case AuthorizationStatus.provisional:
        return DeviceNotificationPermissionState.enabled;
      case AuthorizationStatus.notDetermined:
        return DeviceNotificationPermissionState.notDetermined;
      case AuthorizationStatus.denied:
        return DeviceNotificationPermissionState.denied;
    }
  }
}
