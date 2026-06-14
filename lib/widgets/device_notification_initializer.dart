import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:store_collection_app/services/device_notification_service.dart';

class DeviceNotificationInitializer extends StatefulWidget {
  final Widget child;

  const DeviceNotificationInitializer({super.key, required this.child});

  @override
  State<DeviceNotificationInitializer> createState() =>
      _DeviceNotificationInitializerState();
}

class _DeviceNotificationInitializerState
    extends State<DeviceNotificationInitializer> {
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        DeviceNotificationService().initializeForSignedInUser();
      } else {
        DeviceNotificationService().resetForSignedOutUser();
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
