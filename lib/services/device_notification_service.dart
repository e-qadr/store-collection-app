import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:store_collection_app/services/app_navigation_service.dart';

enum DeviceNotificationPermissionState {
  enabled,
  notDetermined,
  denied,
  unsupported,
}

class DeviceNotificationService {
  static StreamSubscription<String>? _tokenSubscription;
  static StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
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
      _messageOpenedSubscription ??= FirebaseMessaging.onMessageOpenedApp
          .listen((_) => AppNavigationService.openNotifications());
      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();
      if (initialMessage != null) AppNavigationService.openNotifications();
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
    _initialized = false;
    await _tokenSubscription?.cancel();
    await _messageOpenedSubscription?.cancel();
    _tokenSubscription = null;
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
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'notification_tokens': FieldValue.arrayUnion([token]),
      'notifications_enabled': true,
      'notification_token_updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
